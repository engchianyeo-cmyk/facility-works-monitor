import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({ getCurrentIdentity: vi.fn(), createClient: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));

import { POST } from "@/app/api/incidents/route";

const identity = { userId: "11111111-1111-4111-8111-111111111111", email: "reporter@example.com", displayName: "Reporter", department: "Facilities", role: "initiator" as const };
const request = (body: unknown) => new Request("http://localhost/api/incidents", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

beforeEach(() => { vi.clearAllMocks(); mocks.getCurrentIdentity.mockResolvedValue(identity); });

describe("POST /api/incidents", () => {
  test("denies unauthenticated callers", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);
    expect((await POST(request({}))).status).toBe(401);
  });

  test("rejects invalid classification", async () => {
    expect((await POST(request({ incident_type: "unknown", severity: "emergency", location: "L1", description: "Help" }))).status).toBe(400);
  });

  test("creates an incident with queued-only notification state", async () => {
    const incident = { id: "incident-id", incident_number: "INC-2026-000001", incident_type: "lift_entrapment", severity: "emergency", status: "reported", location: "Lift lobby", description: "Passenger trapped", reported_at: "2026-08-10T00:00:00Z" };
    const rpc = vi.fn().mockResolvedValueOnce({ data: { ok: true, incident, assignment_state: "UNASSIGNED_EMERGENCY" }, error: null });
    mocks.createClient.mockResolvedValue({ rpc });
    const response = await POST(request({ incident_type: "lift_entrapment", severity: "emergency", location: "Lift lobby", description: "Passenger trapped" }));
    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({ ok: true, assignment_state: "UNASSIGNED_EMERGENCY", notification: { status: "queued", delivery_attempted: false, delivered: false, provider: null } });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith("create_incident_with_asset", expect.objectContaining({ p_payload: expect.objectContaining({ asset_id: null }) }));
  });
});
