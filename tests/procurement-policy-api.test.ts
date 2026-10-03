import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ identity: vi.fn(), rpc: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.identity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: async () => ({ rpc: mocks.rpc }) }));
import { POST } from "@/app/api/administration/procurement-policy/route";
const payload = { threshold: 2000, reason: "Company policy updated", expected_version: "10000000-0000-4000-8000-000000000001" };
const request = (body: unknown) => new NextRequest("http://localhost/api/administration/procurement-policy", { method: "POST", body: JSON.stringify(body) });
beforeEach(() => { vi.clearAllMocks(); mocks.identity.mockResolvedValue({ role: "administrator" }); mocks.rpc.mockResolvedValue({ data: { ok: true }, error: null }); });
describe("company procurement policy API", () => {
  it("requires authentication", async () => { mocks.identity.mockResolvedValue(null); expect((await POST(request(payload))).status).toBe(401); expect(mocks.rpc).not.toHaveBeenCalled(); });
  it.each(["reviewer", "initiator", "approver", "technician", "supervisor"])("denies %s", async role => { mocks.identity.mockResolvedValue({ role }); expect((await POST(request(payload))).status).toBe(403); expect(mocks.rpc).not.toHaveBeenCalled(); });
  it.each(["facility_manager", "administrator"])("passes %s changes to the authenticated RPC", async role => { mocks.identity.mockResolvedValue({ role }); expect((await POST(request(payload))).status).toBe(200); expect(mocks.rpc).toHaveBeenCalledWith("change_procurement_policy", { p_threshold: 2000, p_reason: payload.reason, p_expected_version: payload.expected_version }); });
  it.each([{ ...payload, threshold: 0 }, { ...payload, threshold: 1.001 }, { ...payload, threshold: "2000" }, { ...payload, reason: " " }, { ...payload, expected_version: "wrong" }])("rejects malformed changes", async body => { expect((await POST(request(body))).status).toBe(400); expect(mocks.rpc).not.toHaveBeenCalled(); });
  it("returns stale policy edits as HTTP 409", async () => { mocks.rpc.mockResolvedValue({ data: { ok: false, code: "POLICY_CONFLICT", message: "Refresh policy" }, error: null }); expect((await POST(request(payload))).status).toBe(409); });
  it("returns a safe service failure", async () => { mocks.rpc.mockResolvedValue({ data: null, error: { message: "private database details" } }); const response = await POST(request(payload)); expect(response.status).toBe(503); expect(JSON.stringify(await response.json())).not.toContain("private database details"); });
});
