import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  createClient: vi.fn(),
  createAdminClient: vi.fn(),
}));

vi.mock("@/lib/auth", async () => {
  const actual = await vi.importActual<typeof import("@/lib/auth")>("@/lib/auth");
  return { ...actual, getCurrentIdentity: mocks.getCurrentIdentity };
});

vi.mock("@/lib/supabase/server", () => ({
  createClient: mocks.createClient,
}));

vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: mocks.createAdminClient,
}));

import { DELETE, PATCH } from "@/app/api/admin/users/[id]/route";

const ADMIN_ID = "11111111-1111-4111-8111-111111111111";
const TARGET_ID = "22222222-2222-4222-8222-222222222222";

const administrator = {
  userId: ADMIN_ID,
  email: "admin@example.com",
  displayName: "Administrator One",
  department: "Facilities",
  role: "administrator" as const,
};

const targetProfile = {
  display_name: "Technician One",
  email: "technician@example.com",
  role: "technician",
  is_active: true,
};

function routeContext(id = TARGET_ID) {
  return { params: Promise.resolve({ id }) };
}

function createRequest(method: "PATCH" | "DELETE", body: unknown): Request {
  return new Request(`http://localhost/api/admin/users/${TARGET_ID}`, {
    method,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function createSingleQuery(result: { data: unknown; error: unknown }) {
  const query = { select: vi.fn(), eq: vi.fn(), single: vi.fn() };
  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.single.mockResolvedValue(result);
  return query;
}

function createUpdateQuery(result: { error: unknown }) {
  const query = { update: vi.fn(), eq: vi.fn() };
  query.update.mockReturnValue(query);
  query.eq.mockResolvedValue(result);
  return query;
}

function createCountQuery(result: { count: number | null; error?: unknown }) {
  const query = {
    select: vi.fn(),
    eq: vi.fn(),
    is: vi.fn(),
    in: vi.fn(),
  };
  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.is.mockResolvedValue({ count: result.count, error: result.error ?? null });
  query.in.mockResolvedValue({ count: result.count, error: result.error ?? null });
  return query;
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(administrator);
});

describe("PATCH /api/admin/users/[id]", () => {
  test("returns 403 when requester is not administrator", async () => {
    mocks.getCurrentIdentity.mockResolvedValue({ ...administrator, role: "supervisor" });
    const response = await PATCH(
      createRequest("PATCH", {
        display_name: "Technician One",
        department: "Facilities",
        role: "technician",
        trade_discipline: "Mechanical",
        is_active: true,
      }),
      routeContext(),
    );
    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({ error: "Access denied." });
  });

  test.each([
    { body: { department: "Facilities", role: "technician", trade_discipline: "Mechanical", is_active: true }, caseName: "missing name" },
    { body: { display_name: "Technician One", role: "technician", trade_discipline: "Mechanical", is_active: true }, caseName: "missing department" },
    { body: { display_name: "Technician One", department: "Facilities", role: "invalid-role", is_active: true }, caseName: "invalid role" },
  ])("returns 400 for $caseName", async ({ body }) => {
    const response = await PATCH(createRequest("PATCH", body), routeContext());
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Name, department/company and a valid role are required.",
    });
  });

  test("requires a trade discipline for technicians", async () => {
    const response = await PATCH(
      createRequest("PATCH", {
        display_name: "Technician One",
        department: "Facilities",
        role: "technician",
        trade_discipline: " ",
        is_active: true,
      }),
      routeContext(),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Trade or technical discipline is required for Technicians.",
    });
  });

  test("prevents current administrator from self-demotion", async () => {
    const response = await PATCH(
      createRequest("PATCH", {
        display_name: "Administrator One",
        department: "Facilities",
        role: "supervisor",
        is_active: true,
      }),
      routeContext(ADMIN_ID),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "You cannot demote or deactivate your current account.",
    });
  });

  test("returns 404 when user profile is not found", async () => {
    const lookup = createSingleQuery({ data: null, error: { message: "No rows" } });
    mocks.createClient.mockResolvedValue({ from: vi.fn().mockReturnValue(lookup) });
    mocks.createAdminClient.mockReturnValue({});
    const response = await PATCH(
      createRequest("PATCH", {
        display_name: "Technician One",
        department: "Facilities",
        role: "technician",
        trade_discipline: "Mechanical",
        is_active: true,
      }),
      routeContext(),
    );
    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({ error: "User not found." });
  });

  test("prevents changing final active administrator", async () => {
    const lookup = createSingleQuery({
      data: { ...targetProfile, role: "administrator" },
      error: null,
    });
    const countQuery = createCountQuery({ count: 1 });
    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValueOnce(lookup).mockReturnValueOnce(countQuery),
    });
    mocks.createAdminClient.mockReturnValue({});
    const response = await PATCH(
      createRequest("PATCH", {
        display_name: "Administrator Two",
        department: "Facilities",
        role: "supervisor",
        is_active: true,
      }),
      routeContext(),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "The final active Administrator cannot be changed.",
    });
  });

  test("updates user profile and writes audit record", async () => {
    const lookup = createSingleQuery({ data: targetProfile, error: null });
    const update = createUpdateQuery({ error: null });
    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValueOnce(lookup).mockReturnValueOnce(update),
    });
    const auditInsert = vi.fn().mockResolvedValue({ error: null });
    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue({ insert: auditInsert }),
    });

    const response = await PATCH(
      createRequest("PATCH", {
        display_name: " Technician Updated ",
        department: " Operations ",
        trade_discipline: " Electrical ",
        contact_number: " 61234567 ",
        role: "technician",
        is_active: true,
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ success: true });
    expect(update.update).toHaveBeenCalledWith({
      display_name: "Technician Updated",
      department: "Operations",
      trade_discipline: "Electrical",
      contact_number: "61234567",
      role: "technician",
      is_active: true,
      deleted_at: null,
    });
    expect(auditInsert).toHaveBeenCalledWith(
      expect.objectContaining({
        user_id: administrator.userId,
        action: "user_admin_profile_updated",
        actor: administrator.displayName,
      }),
    );
  });

  test("returns 400 when profile update fails", async () => {
    const lookup = createSingleQuery({ data: targetProfile, error: null });
    const update = createUpdateQuery({ error: { message: "Profile update failed" } });
    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValueOnce(lookup).mockReturnValueOnce(update),
    });
    mocks.createAdminClient.mockReturnValue({});
    const response = await PATCH(
      createRequest("PATCH", {
        display_name: "Technician One",
        department: "Facilities",
        role: "technician",
        trade_discipline: "Mechanical",
        is_active: true,
      }),
      routeContext(),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({ error: "Profile update failed" });
  });

  test("returns 500 when audit insertion fails", async () => {
    const lookup = createSingleQuery({ data: targetProfile, error: null });
    const update = createUpdateQuery({ error: null });
    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValueOnce(lookup).mockReturnValueOnce(update),
    });
    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue({
        insert: vi.fn().mockResolvedValue({ error: { message: "Audit failed" } }),
      }),
    });
    const response = await PATCH(
      createRequest("PATCH", {
        display_name: "Technician One",
        department: "Facilities",
        role: "technician",
        trade_discipline: "Mechanical",
        is_active: true,
      }),
      routeContext(),
    );
    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "The profile changed, but the audit entry failed.",
    });
  });
});

describe("DELETE /api/admin/users/[id]", () => {
  test("returns 403 when requester is not administrator", async () => {
    mocks.getCurrentIdentity.mockResolvedValue({ ...administrator, role: "reviewer" });
    const response = await DELETE(
      createRequest("DELETE", {
        permanent: false,
        confirmation: targetProfile.email,
      }),
      routeContext(),
    );
    expect(response.status).toBe(403);
  });

  test("prevents deleting current account", async () => {
    const response = await DELETE(
      createRequest("DELETE", {
        permanent: false,
        confirmation: administrator.email,
      }),
      routeContext(ADMIN_ID),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "You cannot delete or archive your current account.",
    });
  });

  test("returns 404 when target user is not found", async () => {
    const lookup = createSingleQuery({ data: null, error: { message: "No rows" } });
    mocks.createClient.mockResolvedValue({ from: vi.fn().mockReturnValue(lookup) });
    mocks.createAdminClient.mockReturnValue({});
    const response = await DELETE(
      createRequest("DELETE", {
        permanent: false,
        confirmation: targetProfile.email,
      }),
      routeContext(),
    );
    expect(response.status).toBe(404);
  });

  test("requires confirmation matching email or display name", async () => {
    const lookup = createSingleQuery({ data: targetProfile, error: null });
    mocks.createClient.mockResolvedValue({ from: vi.fn().mockReturnValue(lookup) });
    mocks.createAdminClient.mockReturnValue({});
    const response = await DELETE(
      createRequest("DELETE", {
        permanent: false,
        confirmation: "wrong confirmation",
      }),
      routeContext(),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Confirmation must exactly match the user email or name.",
    });
  });

  test("returns 409 when user has active assigned work", async () => {
    const lookup = createSingleQuery({ data: targetProfile, error: null });
    const assignmentCount = createCountQuery({ count: 2 });
    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValueOnce(lookup).mockReturnValueOnce(assignmentCount),
    });
    mocks.createAdminClient.mockReturnValue({});
    const response = await DELETE(
      createRequest("DELETE", {
        permanent: false,
        confirmation: targetProfile.email,
      }),
      routeContext(),
    );
    expect(response.status).toBe(409);
  });

  test("archives user after successful audit logging", async () => {
    const lookup = createSingleQuery({ data: targetProfile, error: null });
    const assignmentCount = createCountQuery({ count: 0 });
    const archiveUpdate = createUpdateQuery({ error: null });
    mocks.createClient.mockResolvedValue({
      from: vi.fn()
        .mockReturnValueOnce(lookup)
        .mockReturnValueOnce(assignmentCount)
        .mockReturnValueOnce(archiveUpdate),
    });
    const auditInsert = vi.fn().mockResolvedValue({ error: null });
    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue({ insert: auditInsert }),
    });

    const response = await DELETE(
      createRequest("DELETE", {
        permanent: false,
        confirmation: targetProfile.email.toUpperCase(),
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ success: true });
    expect(auditInsert).toHaveBeenCalledWith(
      expect.objectContaining({ action: "user_admin_archived" }),
    );
    expect(archiveUpdate.update).toHaveBeenCalledWith(
      expect.objectContaining({ is_active: false }),
    );
  });

  test("permanently deletes user after successful audit logging", async () => {
    const lookup = createSingleQuery({ data: targetProfile, error: null });
    const assignmentCount = createCountQuery({ count: 0 });
    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValueOnce(lookup).mockReturnValueOnce(assignmentCount),
    });
    const auditInsert = vi.fn().mockResolvedValue({ error: null });
    const deleteUser = vi.fn().mockResolvedValue({ error: null });
    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue({ insert: auditInsert }),
      auth: { admin: { deleteUser } },
    });

    const response = await DELETE(
      createRequest("DELETE", {
        permanent: true,
        confirmation: targetProfile.display_name,
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);
    expect(deleteUser).toHaveBeenCalledWith(TARGET_ID);
    expect(auditInsert).toHaveBeenCalledWith(
      expect.objectContaining({ action: "user_admin_permanently_deleted" }),
    );
  });

  test("stops deletion when audit logging fails", async () => {
    const lookup = createSingleQuery({ data: targetProfile, error: null });
    const assignmentCount = createCountQuery({ count: 0 });
    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValueOnce(lookup).mockReturnValueOnce(assignmentCount),
    });
    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue({
        insert: vi.fn().mockResolvedValue({ error: { message: "Audit failed" } }),
      }),
    });

    const response = await DELETE(
      createRequest("DELETE", {
        permanent: false,
        confirmation: targetProfile.email,
      }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Deletion was stopped because audit logging failed.",
    });
  });

  test("returns 400 when permanent Auth deletion fails", async () => {
    const lookup = createSingleQuery({ data: targetProfile, error: null });
    const assignmentCount = createCountQuery({ count: 0 });
    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValueOnce(lookup).mockReturnValueOnce(assignmentCount),
    });
    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue({
        insert: vi.fn().mockResolvedValue({ error: null }),
      }),
      auth: {
        admin: {
          deleteUser: vi.fn().mockResolvedValue({
            error: { message: "Auth deletion failed" },
          }),
        },
      },
    });

    const response = await DELETE(
      createRequest("DELETE", {
        permanent: true,
        confirmation: targetProfile.email,
      }),
      routeContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Auth deletion failed",
    });
  });
});
