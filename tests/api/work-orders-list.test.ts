import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks = vi.hoisted(() => ({ getCurrentIdentity: vi.fn(), createClient: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
import { GET } from "@/app/api/work-orders/route";

function query(result = { data: [{ id: "order-1" }], error: null, count: 41 }) {
  const chain: Record<string, ReturnType<typeof vi.fn>> = {};
  for (const method of ["select", "or", "eq", "is", "not", "gte", "lte", "order"]) chain[method] = vi.fn().mockReturnValue(chain);
  chain.range = vi.fn().mockResolvedValue(result);
  return chain;
}

beforeEach(() => { vi.clearAllMocks(); mocks.getCurrentIdentity.mockResolvedValue({ userId: "11111111-1111-4111-8111-111111111111", role: "technician" }); });
describe("GET /api/work-orders", () => {
  test("applies filters, allow-listed sorting and pagination", async () => {
    const chain = query(); mocks.createClient.mockResolvedValue({ from: vi.fn().mockReturnValue(chain) });
    const response = await GET(new NextRequest("http://localhost/api/work-orders?search=AHU&status=assigned&priority=high&department=dept-1&source=predictive&assignment=mine&date_from=2026-08-01&date_to=2026-08-31&sort=due_date&page=2&page_size=10"));
    expect(response.status).toBe(200); expect(chain.or).toHaveBeenCalled(); expect(chain.eq).toHaveBeenCalledWith("status", "assigned"); expect(chain.eq).toHaveBeenCalledWith("priority", "high"); expect(chain.eq).toHaveBeenCalledWith("department_id", "dept-1"); expect(chain.eq).toHaveBeenCalledWith("source", "predictive"); expect(chain.eq).toHaveBeenCalledWith("assigned_technician_id", "11111111-1111-4111-8111-111111111111"); expect(chain.order).toHaveBeenCalledWith("due_date", { ascending: false, nullsFirst: false }); expect(chain.range).toHaveBeenCalledWith(10, 19); expect(await response.json()).toMatchObject({ pagination: { page: 2, page_size: 10, total: 41, total_pages: 5 } });
  });
  test("rejects unsupported filters", async () => { const response = await GET(new NextRequest("http://localhost/api/work-orders?status=deleted")); expect(response.status).toBe(400); expect(await response.json()).toMatchObject({ code: "VALIDATION_ERROR" }); expect(mocks.createClient).not.toHaveBeenCalled(); });
  test("caps page size", async () => { const chain = query({ data: [], error: null, count: 0 }); mocks.createClient.mockResolvedValue({ from: vi.fn().mockReturnValue(chain) }); await GET(new NextRequest("http://localhost/api/work-orders?page_size=500")); expect(chain.range).toHaveBeenCalledWith(0, 99); });
});
