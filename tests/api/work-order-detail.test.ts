import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks = vi.hoisted(() => ({ getCurrentIdentity: vi.fn(), createClient: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
import { DELETE, GET, PATCH } from "@/app/api/work-orders/[id]/route";
const identity = { userId: "11111111-1111-4111-8111-111111111111", email: null, displayName: "Admin", department: null, role: "administrator" as const };
const context = { params: Promise.resolve({ id: "22222222-2222-4222-8222-222222222222" }) };
beforeEach(() => { vi.clearAllMocks(); mocks.getCurrentIdentity.mockResolvedValue(identity); });

describe("/api/work-orders/[id]", () => {
  test("GET returns detail and audit history", async () => {
    const orderQuery: Record<string, ReturnType<typeof vi.fn>> = { select: vi.fn(), eq: vi.fn(), maybeSingle: vi.fn() }; orderQuery.select.mockReturnValue(orderQuery); orderQuery.eq.mockReturnValue(orderQuery); orderQuery.maybeSingle.mockResolvedValue({ data: { id: "order-1" }, error: null });
    const logQuery: Record<string, ReturnType<typeof vi.fn>> = { select: vi.fn(), eq: vi.fn(), order: vi.fn() }; logQuery.select.mockReturnValue(logQuery); logQuery.eq.mockReturnValue(logQuery); logQuery.order.mockResolvedValue({ data: [{ action: "created" }], error: null });
    mocks.createClient.mockResolvedValue({ from: vi.fn().mockReturnValueOnce(orderQuery).mockReturnValueOnce(logQuery) });
    const response = await GET(new NextRequest("http://localhost/api/work-orders/order-1"), context); expect(response.status).toBe(200); expect(await response.json()).toMatchObject({ ok: true, data: { id: "order-1", activity: [{ action: "created" }] } });
  });
  test("GET scopes Technician detail access to their own assignment", async () => {
    mocks.getCurrentIdentity.mockResolvedValue({ ...identity, userId: "technician-id", role: "technician" });
    const orderQuery: Record<string, ReturnType<typeof vi.fn>> = { select: vi.fn(), eq: vi.fn(), maybeSingle: vi.fn() }; orderQuery.select.mockReturnValue(orderQuery); orderQuery.eq.mockReturnValue(orderQuery); orderQuery.maybeSingle.mockResolvedValue({ data: null, error: null });
    mocks.createClient.mockResolvedValue({ from: vi.fn().mockReturnValue(orderQuery) });
    const response = await GET(new NextRequest("http://localhost/api/work-orders/order-1"), context);
    expect(orderQuery.eq).toHaveBeenCalledWith("assigned_technician_id", "technician-id");
    expect(response.status).toBe(404);
  });
  test("PATCH uses update RPC", async () => { const rpc = vi.fn().mockResolvedValue({ data: { ok: true, work_order: { id: "order-1", title: "Updated" } }, error: null }); mocks.createClient.mockResolvedValue({ rpc }); const response = await PATCH(new NextRequest("http://localhost/api/work-orders/order-1", { method: "PATCH", body: JSON.stringify({ title: "Updated" }) }), context); expect(response.status).toBe(200); expect(rpc).toHaveBeenCalledWith("update_work_order", { p_work_order_id: "22222222-2222-4222-8222-222222222222", p_payload: { title: "Updated" } }); });
  test("PATCH rejects malformed JSON", async () => { const response = await PATCH(new NextRequest("http://localhost/api/work-orders/order-1", { method: "PATCH", body: "{" }), context); expect(response.status).toBe(400); expect(await response.json()).toMatchObject({ code: "VALIDATION_ERROR", message: "Request body must be valid JSON." }); });
  test("PATCH rejects unauthenticated callers", async () => { mocks.getCurrentIdentity.mockResolvedValue(null); const response = await PATCH(new NextRequest("http://localhost/api/work-orders/order-1", { method: "PATCH", body: "{}" }), context); expect(response.status).toBe(401); expect(await response.json()).toMatchObject({ code: "AUTHENTICATION_REQUIRED" }); });
  test("PATCH maps not-found RPC results", async () => { mocks.createClient.mockResolvedValue({ rpc: vi.fn().mockResolvedValue({ data: { ok: false, code: "NOT_FOUND", message: "Work order not found." }, error: null }) }); const response = await PATCH(new NextRequest("http://localhost/api/work-orders/order-1", { method: "PATCH", body: JSON.stringify({ title: "Updated" }) }), context); expect(response.status).toBe(404); expect(await response.json()).toMatchObject({ code: "NOT_FOUND" }); });
  test("DELETE is an audited cancellation, never a delete", async () => { const rpc = vi.fn().mockResolvedValue({ data: { ok: true, work_order: { id: "order-1", status: "cancelled" } }, error: null }); mocks.createClient.mockResolvedValue({ rpc }); const response = await DELETE(new NextRequest("http://localhost/api/work-orders/order-1?reason=Duplicate", { method: "DELETE" }), context); expect(response.status).toBe(200); expect(rpc).toHaveBeenCalledWith("transition_work_order", { p_work_order_id: "22222222-2222-4222-8222-222222222222", p_action: "cancel", p_payload: { reason: "Duplicate" } }); });
  test("DELETE rejects unauthenticated callers", async () => { mocks.getCurrentIdentity.mockResolvedValue(null); const response = await DELETE(new NextRequest("http://localhost/api/work-orders/order-1?reason=Duplicate", { method: "DELETE" }), context); expect(response.status).toBe(401); expect(await response.json()).toMatchObject({ code: "AUTHENTICATION_REQUIRED" }); });
  test("returns structured RPC failures", async () => { mocks.createClient.mockResolvedValue({ rpc: vi.fn().mockResolvedValue({ data: { ok: false, code: "TERMINAL_IMMUTABLE", message: "Closed and cancelled work orders are immutable." }, error: null }) }); const response = await PATCH(new NextRequest("http://localhost/api/work-orders/order-1", { method: "PATCH", body: JSON.stringify({ title: "Updated" }) }), context); expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ code: "TERMINAL_IMMUTABLE" }); });
  test("handles unexpected PATCH exceptions safely", async () => { mocks.createClient.mockRejectedValue(new Error("private database detail")); const response = await PATCH(new NextRequest("http://localhost/api/work-orders/order-1", { method: "PATCH", body: JSON.stringify({ title: "Updated" }) }), context); expect(response.status).toBe(500); expect(await response.json()).toEqual({ ok: false, code: "INTERNAL_ERROR", message: "Unable to update the work order.", error: "Unable to update the work order." }); });
});
