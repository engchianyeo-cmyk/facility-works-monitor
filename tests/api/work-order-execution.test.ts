import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({ getCurrentIdentity: vi.fn(), createClient: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
import { POST } from "@/app/api/work-orders/[id]/execution/route";

const context = { params: Promise.resolve({ id: "22222222-2222-4222-8222-222222222222" }) };

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue({ userId: "technician", role: "technician" });
});

describe("POST work-order execution", () => {
  test("delegates work recording without requesting a status transition", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { ok: true, work_order: { status: "in_progress" }, status_unchanged: true }, error: null });
    mocks.createClient.mockResolvedValue({ rpc });
    const response = await POST(new NextRequest("http://localhost/api/work-orders/id/execution", {
      method: "POST",
      body: JSON.stringify({ completion_notes: "Reset pump", actual_labour_hours: 1.5 }),
    }), context);
    expect(response.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith("record_work_order_execution", {
      p_work_order_id: expect.any(String),
      p_payload: { completion_notes: "Reset pump", actual_labour_hours: 1.5 },
    });
    expect(rpc).not.toHaveBeenCalledWith("transition_work_order", expect.anything());
  });

  test("preserves authentication rejection", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);
    const response = await POST(new NextRequest("http://localhost/execution", { method: "POST", body: "{}" }), context);
    expect(response.status).toBe(401);
  });
});
