import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks = vi.hoisted(() => ({ getCurrentIdentity: vi.fn(), createClient: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
import { POST } from "@/app/api/work-orders/[id]/duplicate/route";
const context = { params: Promise.resolve({ id: "22222222-2222-4222-8222-222222222222" }) };
beforeEach(() => { vi.clearAllMocks(); mocks.getCurrentIdentity.mockResolvedValue({ userId: "actor", role: "reviewer" }); });
describe("POST duplicate", () => {
  test("returns a new draft with provenance", async () => { const rpc = vi.fn().mockResolvedValue({ data: { ok: true, work_order: { id: "new", status: "draft", duplicated_from_id: "source" } }, error: null }); mocks.createClient.mockResolvedValue({ rpc }); const response = await POST(new NextRequest("http://localhost/duplicate", { method: "POST" }), context); expect(response.status).toBe(201); expect(await response.json()).toMatchObject({ data: { status: "draft", duplicated_from_id: "source" } }); });
});
