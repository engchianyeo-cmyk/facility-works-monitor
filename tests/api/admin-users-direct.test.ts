import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  createClient: vi.fn(),
  createAdminClient: vi.fn(),
  isAdminConfigured: vi.fn(),
  departmentResult: { data: null as unknown, error: null as unknown },
  profileLookupResult: { data: null as unknown, error: null as unknown },
  authUsers: [] as Array<{
    id: string;
    email?: string;
    email_confirmed_at?: string | null;
  }>,
  listUsersError: null as unknown,
  invitationInsert: vi.fn(),
  invitationResult: { data: { id: "invite-1" } as unknown, error: null as unknown },
  invitationUpdate: vi.fn(),
  invitationCleanupError: null as unknown,
  createUser: vi.fn(),
  updateUserById: vi.fn(),
  profileUpsert: vi.fn(),
  auditInsert: vi.fn(),
  deleteUser: vi.fn(),
}));

vi.mock("@/lib/auth", async () => {
  const actual = await vi.importActual<typeof import("@/lib/auth")>("@/lib/auth");
  return { ...actual, getCurrentIdentity: mocks.getCurrentIdentity };
});

vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: mocks.createAdminClient,
  isAdminConfigured: mocks.isAdminConfigured,
}));

import { GET, POST } from "@/app/api/admin/users/direct/route";

const ADMIN_ID = "11111111-1111-4111-8111-111111111111";
const USER_ID = "22222222-2222-4222-8222-222222222222";
const DEPARTMENT_ID = "33333333-3333-4333-8333-333333333333";
const administrator = {
  userId: ADMIN_ID,
  email: "admin@example.com",
  displayName: "Administrator",
  department: "Facilities",
  role: "administrator" as const,
};

const validBody = {
  mode: "create",
  display_name: "Reviewer One",
  email: "reviewer@example.com",
  department_id: DEPARTMENT_ID,
  role: "reviewer",
  trade_discipline: "",
  contact_number: "61234567",
  temporary_password: "Temporary-1234",
  is_active: true,
};

function request(body: unknown = validBody) {
  return new Request("http://localhost/api/admin/users/direct", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function chain<T extends Record<string, ReturnType<typeof vi.fn>>>(value: T): T {
  for (const method of Object.values(value)) method.mockReturnValue(value);
  return value;
}

function installClients() {
  const departmentQuery = chain({
    select: vi.fn(),
    eq: vi.fn(),
    is: vi.fn(),
    order: vi.fn(),
    maybeSingle: vi.fn(),
  });
  departmentQuery.maybeSingle.mockResolvedValue(mocks.departmentResult);
  departmentQuery.order.mockResolvedValue(mocks.departmentResult);
  mocks.createClient.mockResolvedValue({
    from: vi.fn().mockReturnValue(departmentQuery),
  });

  const profileLookup = chain({
    select: vi.fn(),
    ilike: vi.fn(),
    maybeSingle: vi.fn(),
  });
  profileLookup.maybeSingle.mockResolvedValue(mocks.profileLookupResult);

  const invitation = chain({
    insert: mocks.invitationInsert,
    select: vi.fn(),
    single: vi.fn(),
    update: mocks.invitationUpdate,
    eq: vi.fn(),
  });
  invitation.single.mockResolvedValue(mocks.invitationResult);
  invitation.eq.mockResolvedValue({ error: mocks.invitationCleanupError });

  let profilesCalls = 0;
  mocks.createAdminClient.mockReturnValue({
    auth: {
      admin: {
        listUsers: vi.fn().mockImplementation(() =>
          Promise.resolve({
            data: { users: mocks.authUsers },
            error: mocks.listUsersError,
          }),
        ),
        createUser: mocks.createUser,
        updateUserById: mocks.updateUserById,
        deleteUser: mocks.deleteUser,
      },
    },
    from: vi.fn().mockImplementation((table: string) => {
      if (table === "profiles") {
        profilesCalls += 1;
        return profilesCalls === 1
          ? profileLookup
          : { upsert: mocks.profileUpsert };
      }
      if (table === "account_invitations") return invitation;
      if (table === "activity_logs") return { insert: mocks.auditInsert };
      throw new Error(`Unexpected table ${table}`);
    }),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(administrator);
  mocks.isAdminConfigured.mockReturnValue(true);
  mocks.departmentResult.data = { id: DEPARTMENT_ID, name: "Facilities" };
  mocks.departmentResult.error = null;
  mocks.profileLookupResult.data = null;
  mocks.profileLookupResult.error = null;
  mocks.authUsers.length = 0;
  mocks.listUsersError = null;
  mocks.invitationResult.data = { id: "invite-1" };
  mocks.invitationResult.error = null;
  mocks.invitationCleanupError = null;
  mocks.createUser.mockResolvedValue({
    data: { user: { id: USER_ID } },
    error: null,
  });
  mocks.updateUserById.mockResolvedValue({ error: null });
  mocks.profileUpsert.mockResolvedValue({ error: null });
  mocks.auditInsert.mockResolvedValue({ error: null });
  mocks.deleteUser.mockResolvedValue({ error: null });
  installClients();
});

describe("administrator direct user provisioning", () => {
  test("denies an unauthenticated request", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);
    const response = await POST(request());
    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      code: "AUTH_REQUIRED",
    });
  });

  test("denies a non-Administrator request", async () => {
    mocks.getCurrentIdentity.mockResolvedValue({
      ...administrator,
      role: "reviewer",
    });
    const response = await POST(request());
    expect(response.status).toBe(403);
    expect(mocks.createAdminClient).not.toHaveBeenCalled();
  });

  test("returns a safe structured error when admin configuration is missing", async () => {
    mocks.isAdminConfigured.mockReturnValue(false);
    const response = await POST(request());
    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      success: false,
      code: "PROVISIONING_NOT_CONFIGURED",
      error: "User provisioning is not configured for this deployment.",
    });
  });

  test("rejects malformed email addresses", async () => {
    const response = await POST(request({ ...validBody, email: "bad@address" }));
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ code: "INVALID_EMAIL" });
  });

  test("rejects missing required fields", async () => {
    const response = await POST(request({ ...validBody, display_name: "" }));
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ code: "NAME_REQUIRED" });
  });

  test("rejects a temporary password shorter than twelve characters", async () => {
    const response = await POST(
      request({ ...validBody, temporary_password: "Too-short1" }),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({
      code: "INVALID_TEMPORARY_PASSWORD",
    });
  });

  test("rejects unsupported roles", async () => {
    const response = await POST(request({ ...validBody, role: "owner" }));
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ code: "INVALID_ROLE" });
  });

  test("rejects an inactive or missing department", async () => {
    mocks.departmentResult.data = null;
    const response = await POST(request());
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toEqual({
      success: false,
      code: "INACTIVE_DEPARTMENT",
      error: "Department is inactive.",
    });
  });

  test("rejects a duplicate Auth email without ambiguity", async () => {
    mocks.authUsers.push({ id: USER_ID, email: validBody.email });
    const response = await POST(request());
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toMatchObject({
      code: "DUPLICATE_EMAIL",
      error: "User email is already registered.",
    });
  });

  test("does not treat a confirmed account as pending activation", async () => {
    mocks.authUsers.push({
      id: USER_ID,
      email: validBody.email,
      email_confirmed_at: "2026-08-08T00:00:00Z",
    });
    const response = await POST(
      request({ ...validBody, mode: "activate_pending" }),
    );
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toMatchObject({
      code: "ACCOUNT_ALREADY_ACTIVE",
    });
    expect(mocks.updateUserById).not.toHaveBeenCalled();
  });

  test("creates an Auth user through the trigger ticket and completes its profile", async () => {
    const response = await POST(request());
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      success: true,
      user_id: USER_ID,
    });
    expect(mocks.invitationInsert).toHaveBeenCalledWith(
      expect.objectContaining({
        email: validBody.email,
        assigned_role: "reviewer",
        department: "Facilities",
        created_by: ADMIN_ID,
      }),
    );
    expect(mocks.createUser).toHaveBeenCalledWith(
      expect.objectContaining({
        email: validBody.email,
        email_confirm: true,
        user_metadata: expect.objectContaining({
          administrator_invitation_token: expect.any(String),
        }),
      }),
    );
    expect(mocks.profileUpsert).toHaveBeenCalledWith(
      expect.objectContaining({
        id: USER_ID,
        department_id: DEPARTMENT_ID,
        department: "Facilities",
        role: "reviewer",
        is_active: true,
      }),
      { onConflict: "id" },
    );
    expect(mocks.auditInsert).toHaveBeenCalledOnce();
  });

  test.each(["initiator", "technician", "approver", "supervisor"])(
    "creates an active canonical %s profile with the Auth user ID",
    async (role) => {
      const response = await POST(request({
        ...validBody,
        role,
        trade_discipline: role === "technician" ? "Electrical" : "",
      }));
      expect(response.status).toBe(200);
      expect(mocks.profileUpsert).toHaveBeenCalledWith(
        expect.objectContaining({ id: USER_ID, role, is_active: true }),
        { onConflict: "id" },
      );
    },
  );

  test("activates one existing pending Approver without creating a duplicate Auth user", async () => {
    mocks.authUsers.push({ id: USER_ID, email: validBody.email, email_confirmed_at: null });
    mocks.profileLookupResult.data = { id: USER_ID };
    const response = await POST(request({ ...validBody, mode: "activate_pending", role: "approver" }));
    expect(response.status).toBe(200);
    expect(mocks.createUser).not.toHaveBeenCalled();
    expect(mocks.updateUserById).toHaveBeenCalledWith(USER_ID, expect.objectContaining({ email_confirm: true }));
    expect(mocks.profileUpsert).toHaveBeenCalledWith(expect.objectContaining({ id: USER_ID, role: "approver", is_active: true }), { onConflict: "id" });
  });

  test("can provision an initially inactive profile", async () => {
    const response = await POST(request({ ...validBody, is_active: false }));
    expect(response.status).toBe(200);
    expect(mocks.invitationInsert).toHaveBeenCalledWith(
      expect.objectContaining({ is_active: false }),
    );
    expect(mocks.profileUpsert).toHaveBeenCalledWith(
      expect.objectContaining({ is_active: false }),
      { onConflict: "id" },
    );
  });

  test("removes a newly-created Auth user when profile completion fails", async () => {
    mocks.profileUpsert.mockResolvedValue({ error: { message: "raw error" } });
    const response = await POST(request());
    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toMatchObject({
      code: "PROFILE_PROVISION_FAILED_ROLLED_BACK",
    });
    expect(mocks.deleteUser).toHaveBeenCalledWith(USER_ID);
  });

  test("loads active departments while safely reporting deployment configuration", async () => {
    mocks.isAdminConfigured.mockReturnValue(false);
    mocks.departmentResult.data = [{ id: DEPARTMENT_ID, name: "Facilities" }];
    const response = await GET();
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      success: true,
      provisioning_configured: false,
      departments: [{ id: DEPARTMENT_ID, name: "Facilities" }],
    });
  });
});
