import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks = vi.hoisted(() => ({ getCurrentIdentity: vi.fn(), createClient: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
import { POST } from "@/app/api/work-orders/[id]/assign/route";
const context = { params: Promise.resolve({ id: "22222222-2222-4222-8222-222222222222" }) };
beforeEach(() => { vi.clearAllMocks(); mocks.getCurrentIdentity.mockResolvedValue({ userId: "actor", role: "supervisor" }); });
describe("POST assignment", () => {
  test.each(["technician", "vendor", "team"])("supports active %s assignment through the RPC", async (assignmentType) => { const rpc = vi.fn().mockResolvedValue({ data: { ok: true, work_order: { status: "assigned" } }, error: null }); mocks.createClient.mockResolvedValue({ rpc }); const response = await POST(new NextRequest("http://localhost/assign", { method: "POST", body: JSON.stringify({ assignment_type: assignmentType, assignee_id: "11111111-1111-4111-8111-111111111111" }) }), context); expect(response.status).toBe(200); expect(rpc).toHaveBeenCalledWith("assign_work_order", expect.objectContaining({ p_assignment_type: assignmentType })); });
  test("surfaces inactive-reference rejection", async () => { mocks.createClient.mockResolvedValue({ rpc: vi.fn().mockResolvedValue({ data: { ok: false, code: "INACTIVE_REFERENCE", message: "Unavailable" }, error: null }) }); const response = await POST(new NextRequest("http://localhost/assign", { method: "POST", body: JSON.stringify({ assignment_type: "vendor", assignee_id: "11111111-1111-4111-8111-111111111111" }) }), context); expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ code: "INACTIVE_REFERENCE" }); });
  test("returns a stable deep link and an honest unconfigured notification result", async () => { mocks.createClient.mockResolvedValue({ rpc: vi.fn().mockResolvedValue({ data: { ok: true, work_order: { status: "assigned" } }, error: null }) }); const response = await POST(new NextRequest("http://localhost/assign", { method: "POST", body: JSON.stringify({ assignment_type: "technician", assignee_id: "11111111-1111-4111-8111-111111111111" }) }), context); expect(response.status).toBe(200); expect(await response.json()).toMatchObject({ ok: true, assignment_path: "/work-orders/22222222-2222-4222-8222-222222222222", notification: { delivered: false, code: "NOT_CONFIGURED", provider: "none" } }); });
});
