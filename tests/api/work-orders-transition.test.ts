import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks = vi.hoisted(() => ({ getCurrentIdentity: vi.fn(), createClient: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
import { POST } from "@/app/api/work-orders/[id]/transition/route";
const context = { params: Promise.resolve({ id: "22222222-2222-4222-8222-222222222222" }) };
const request = (body: unknown) => new NextRequest("http://localhost/api/work-orders/id/transition", { method: "POST", body: JSON.stringify(body) });
beforeEach(() => { vi.clearAllMocks(); mocks.getCurrentIdentity.mockResolvedValue({ userId: "actor", role: "approver" }); });

describe("POST transition", () => {
  test.each([
    ["SELF_APPROVAL_DENIED", 409], ["OVERRIDE_REASON_REQUIRED", 400], ["INVALID_TRANSITION", 409],
    ["COMPLETION_DETAILS_REQUIRED", 400], ["TERMINAL_IMMUTABLE", 409], ["ACCESS_DENIED", 403],
  ])("maps %s to a structured response", async (code, status) => { mocks.createClient.mockResolvedValue({ rpc: vi.fn().mockResolvedValue({ data: { ok: false, code, message: "Denied" }, error: null }) }); const response = await POST(request({ action: "approve" }), context); expect(response.status).toBe(status); expect(await response.json()).toMatchObject({ ok: false, code }); });
  test("passes completion evidence to the RPC", async () => { const rpc = vi.fn().mockResolvedValue({ data: { ok: true, work_order: { status: "completed" } }, error: null }); mocks.createClient.mockResolvedValue({ rpc }); const response = await POST(request({ action: "complete", completion_notes: "Replaced bearing", actual_labour_hours: 2.5 }), context); expect(response.status).toBe(200); expect(rpc).toHaveBeenCalledWith("transition_work_order", { p_work_order_id: expect.any(String), p_action: "complete", p_payload: { completion_notes: "Replaced bearing", actual_labour_hours: 2.5 } }); });
  test("hides transport errors", async () => { mocks.createClient.mockResolvedValue({ rpc: vi.fn().mockResolvedValue({ data: null, error: { message: "private SQL" } }) }); const response = await POST(request({ action: "approve" }), context); expect(await response.json()).toMatchObject({ code: "INTERNAL_ERROR", message: "Unable to transition the work order." }); });
});
