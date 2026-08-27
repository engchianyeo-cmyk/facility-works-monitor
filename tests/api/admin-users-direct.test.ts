import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(), createClient: vi.fn(), createAdminClient: vi.fn(), isAdminConfigured: vi.fn(),
  rpc: vi.fn(), createUser: vi.fn(), updateUserById: vi.fn(), deleteUser: vi.fn(), listUsers: vi.fn(),
  departmentResult: { data: null as unknown, error: null as unknown },
  profileResult: { data: null as unknown, error: null as unknown },
  invitationResult: { data: { id: "invite-1" } as unknown, error: null as unknown },
  departmentListResult: { data: [] as unknown[], error: null as unknown },
}));

vi.mock("@/lib/auth", async () => {
  const actual = await vi.importActual<typeof import("@/lib/auth")>("@/lib/auth");
  return { ...actual, getCurrentIdentity: mocks.getCurrentIdentity };
});
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
vi.mock("@/lib/supabase/admin", () => ({ createAdminClient: mocks.createAdminClient, isAdminConfigured: mocks.isAdminConfigured }));

import { GET, POST } from "@/app/api/admin/users/direct/route";

const ADMIN_ID = "11111111-1111-4111-8111-111111111111";
const USER_ID = "22222222-2222-4222-8222-222222222222";
const DEPARTMENT_ID = "33333333-3333-4333-8333-333333333333";
const administrator = { userId: ADMIN_ID, email: "admin@example.com", displayName: "Administrator", department: "Facilities", role: "administrator" as const };
const validBody = { mode: "create", display_name: "Reviewer One", email: "reviewer@example.com", department_id: DEPARTMENT_ID, role: "reviewer", trade_discipline: "", contact_number: "61234567", temporary_password: "Temporary-1234", is_active: true };
const request = (body: unknown = validBody) => new Request("http://localhost/api/admin/users/direct", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

function chain(methods: string[]) {
  const query: Record<string, ReturnType<typeof vi.fn>> = {};
  for (const method of methods) query[method] = vi.fn().mockReturnValue(query);
  return query;
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(administrator);
  mocks.isAdminConfigured.mockReturnValue(true);
  mocks.departmentResult.data = { id: DEPARTMENT_ID, name: "Facilities" };
  mocks.departmentResult.error = null;
  mocks.profileResult.data = null;
  mocks.profileResult.error = null;
  mocks.invitationResult.data = { id: "invite-1" };
  mocks.invitationResult.error = null;
  mocks.departmentListResult.data = [{ id: DEPARTMENT_ID, name: "Facilities" }];
  mocks.departmentListResult.error = null;
  mocks.rpc.mockResolvedValue({ data: { id: USER_ID, password_change_required: true }, error: null });
  mocks.createUser.mockResolvedValue({ data: { user: { id: USER_ID } }, error: null });
  mocks.updateUserById.mockResolvedValue({ error: null });
  mocks.deleteUser.mockResolvedValue({ error: null });
  mocks.listUsers.mockResolvedValue({ data: { users: [] }, error: null });

  const department = chain(["select", "eq", "is", "order", "maybeSingle"]);
  department.maybeSingle.mockResolvedValue(mocks.departmentResult);
  department.order.mockImplementation(() => Promise.resolve(mocks.departmentListResult));
  mocks.createClient.mockResolvedValue({ from: vi.fn().mockReturnValue(department), rpc: mocks.rpc });

  const profile = chain(["select", "ilike", "maybeSingle"]);
  profile.maybeSingle.mockResolvedValue(mocks.profileResult);
  const invitation = chain(["insert", "select", "single", "update", "eq"]);
  invitation.single.mockResolvedValue(mocks.invitationResult);
  invitation.eq.mockResolvedValue({ error: null });
  mocks.createAdminClient.mockReturnValue({
    auth: { admin: { listUsers: mocks.listUsers, createUser: mocks.createUser, updateUserById: mocks.updateUserById, deleteUser: mocks.deleteUser } },
    from: vi.fn((table: string) => table === "profiles" ? profile : invitation),
  });
});

describe("administrator direct user provisioning", () => {
  test("denies unauthenticated and non-Administrator callers", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);
    expect((await POST(request())).status).toBe(401);
    mocks.getCurrentIdentity.mockResolvedValue({ ...administrator, role: "supervisor" });
    expect((await POST(request())).status).toBe(403);
    expect(mocks.createUser).not.toHaveBeenCalled();
  });

  test("reports whether provisioning is configured", async () => {
    const response = await GET();
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      success: true,
      provisioning_configured: true,
      department_setup_required: false,
      departments: [{ id: DEPARTMENT_ID, name: "Facilities" }],
    });
  });

  test("reports the empty-bootstrap department prerequisite without inventing master data", async () => {
    mocks.departmentListResult.data = [];
    const response = await GET();
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      success: true,
      department_setup_required: true,
      departments: [],
    });
  });

  test("rejects weak temporary passwords", async () => {
    const response = await POST(request({ ...validBody, temporary_password: "short" }));
    expect(response.status).toBe(400);
    expect(mocks.createUser).not.toHaveBeenCalled();
  });

  test("creates Auth then atomically finalizes profile and audit", async () => {
    const response = await POST(request());
    expect(response.status).toBe(200);
    expect(mocks.createUser).toHaveBeenCalledWith(expect.objectContaining({ email_confirm: true, user_metadata: expect.objectContaining({ administrator_invitation_token: expect.any(String) }) }));
    expect(mocks.rpc).toHaveBeenCalledWith("admin_finalize_provisioned_profile", {
      p_target_id: USER_ID,
      p_payload: expect.objectContaining({ role: "reviewer", is_active: true }),
      p_event: "user_admin_direct_created",
    });
    await expect(response.json()).resolves.toMatchObject({ success: true, user_id: USER_ID });
  });

  test("removes a newly created Auth user if Postgres reconciliation fails", async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { message: "audit failed" } });
    const response = await POST(request());
    expect(response.status).toBe(500);
    expect(mocks.deleteUser).toHaveBeenCalledWith(USER_ID);
    await expect(response.json()).resolves.toMatchObject({ code: "PROFILE_PROVISION_FAILED_ROLLED_BACK" });
  });

  test("keeps an existing pending account locked when reconciliation fails", async () => {
    mocks.listUsers.mockResolvedValue({ data: { users: [{ id: USER_ID, email: validBody.email, email_confirmed_at: null }] }, error: null });
    mocks.rpc.mockResolvedValue({ data: null, error: { message: "audit failed" } });
    const response = await POST(request({ ...validBody, mode: "activate_pending" }));
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toMatchObject({ code: "PROFILE_ACTIVATION_FAILED_RECONCILIATION_REQUIRED" });
    expect(mocks.deleteUser).not.toHaveBeenCalled();
  });
});
