import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  createClient: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));

import { GET } from "@/app/api/exports/[register]/route";

const identity = {
  userId: "11111111-1111-4111-8111-111111111111",
  email: "manager@example.test",
  displayName: "Manager",
  department: "Facilities",
  role: "approver" as const,
  passwordChangeRequired: false,
};

const context = (register: string) => ({ params: Promise.resolve({ register }) });

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(identity);
});

describe("authenticated customer CSV exports", () => {
  test("denies anonymous access before creating a database client", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);
    const response = await GET(new Request("http://localhost/api/exports/work-orders"), context("work-orders"));
    expect(response.status).toBe(401);
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("denies a Technician whose normal visibility is narrower", async () => {
    mocks.getCurrentIdentity.mockResolvedValue({ ...identity, role: "technician" });
    const response = await GET(new Request("http://localhost/api/exports/work-orders"), context("work-orders"));
    expect(response.status).toBe(403);
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("uses the authenticated RLS client and returns a controlled Work Order register", async () => {
    const order = vi.fn().mockResolvedValue({ data: [], error: null });
    const select = vi.fn().mockReturnValue({ order });
    const from = vi.fn().mockReturnValue({ select });
    mocks.createClient.mockResolvedValue({ from });

    const response = await GET(new Request("http://localhost/api/exports/work-orders"), context("work-orders"));
    expect(response.status).toBe(200);
    expect(mocks.createClient).toHaveBeenCalledTimes(1);
    expect(from).toHaveBeenCalledWith("work_orders");
    expect(response.headers.get("cache-control")).toContain("no-store");
    expect(response.headers.get("content-type")).toContain("text/csv; charset=utf-8");
    const csv = await response.text();
    expect(csv).toContain('"assignee_name"');
    expect(csv).toContain('"reviewed_at"');
    expect(csv).toContain('"closed_at"');
    expect(csv).not.toContain('"target_profile_id"');
  });
});
