import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({ createClient: vi.fn(), createAdminClient: vi.fn(), updateUserById: vi.fn(), rpc: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
vi.mock("@/lib/supabase/admin", () => ({ createAdminClient: mocks.createAdminClient }));

import { POST } from "@/app/api/auth/password/change/route";

function profileQuery(profile: unknown) {
  const query = { select: vi.fn(), eq: vi.fn(), maybeSingle: vi.fn() };
  query.select.mockReturnValue(query); query.eq.mockReturnValue(query);
  query.maybeSingle.mockResolvedValue({ data: profile, error: null });
  return query;
}
const request = (body: unknown) => new Request("http://localhost/api/auth/password/change", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

beforeEach(() => {
  vi.clearAllMocks();
  mocks.createClient.mockResolvedValue({
    auth: { getUser: vi.fn().mockResolvedValue({ data: { user: { id: "user-1" } } }) },
    from: vi.fn().mockReturnValue(profileQuery({ role: "reviewer", is_active: true, deleted_at: null })),
  });
  mocks.updateUserById.mockResolvedValue({ error: null });
  mocks.rpc.mockResolvedValue({ data: { ok: true }, error: null });
  mocks.createAdminClient.mockReturnValue({ auth: { admin: { updateUserById: mocks.updateUserById } }, rpc: mocks.rpc });
});

describe("POST /api/auth/password/change", () => {
  test("denies an unauthenticated caller", async () => {
    mocks.createClient.mockResolvedValue({ auth: { getUser: vi.fn().mockResolvedValue({ data: { user: null } }) } });
    expect((await POST(request({ password: "long-enough-password", confirmation: "long-enough-password" }))).status).toBe(401);
    expect(mocks.updateUserById).not.toHaveBeenCalled();
  });

  test("denies inactive profiles", async () => {
    mocks.createClient.mockResolvedValue({
      auth: { getUser: vi.fn().mockResolvedValue({ data: { user: { id: "user-1" } } }) },
      from: vi.fn().mockReturnValue(profileQuery({ role: "reviewer", is_active: false, deleted_at: null })),
    });
    expect((await POST(request({ password: "long-enough-password", confirmation: "long-enough-password" }))).status).toBe(403);
  });

  test("updates Auth before trusted database reconciliation", async () => {
    const response = await POST(request({ password: "long-enough-password", confirmation: "long-enough-password", next: "/work-orders" }));
    expect(response.status).toBe(200);
    expect(mocks.updateUserById).toHaveBeenCalledWith("user-1", { password: "long-enough-password" });
    expect(mocks.rpc).toHaveBeenCalledWith("complete_password_change_trusted", { p_user_id: "user-1" });
  });

  test("returns success when trusted reconciliation reports an already-ready profile", async () => {
    mocks.rpc.mockResolvedValue({ data: { ok: true, was_required: false }, error: null });
    const response = await POST(request({ password: "long-enough-password", confirmation: "long-enough-password" }));
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ ok: true });
  });

  test("reports a locked reconciliation state without claiming failure to change Auth", async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { message: "database unavailable" } });
    const response = await POST(request({ password: "long-enough-password", confirmation: "long-enough-password" }));
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toMatchObject({ reconciliation_required: true });
  });
});
