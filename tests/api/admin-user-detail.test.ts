import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  createClient: vi.fn(),
  rpc: vi.fn(),
  isAdminConfigured: vi.fn(),
  createAdminClient: vi.fn(),
  deleteUser: vi.fn(),
  adminRpc: vi.fn(),
}));
vi.mock("@/lib/auth", async () => {
  const actual = await vi.importActual<typeof import("@/lib/auth")>("@/lib/auth");
  return { ...actual, getCurrentIdentity: mocks.getCurrentIdentity };
});
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
vi.mock("@/lib/supabase/admin", () => ({
  isAdminConfigured: mocks.isAdminConfigured,
  createAdminClient: mocks.createAdminClient,
}));

import { DELETE, PATCH } from "@/app/api/admin/users/[id]/route";

const ADMIN_ID = "11111111-1111-4111-8111-111111111111";
const TARGET_ID = "22222222-2222-4222-8222-222222222222";
const DEPARTMENT_ID = "33333333-3333-4333-8333-333333333333";
const administrator = { userId: ADMIN_ID, email: "admin@example.com", displayName: "Administrator", department: "Facilities", role: "administrator" as const };
const context = (id = TARGET_ID) => ({ params: Promise.resolve({ id }) });
const request = (method: "PATCH" | "DELETE", body: unknown) => new Request(`http://localhost/api/admin/users/${TARGET_ID}`, { method, headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
const validUpdate = { display_name: "Technician One", department_id: DEPARTMENT_ID, role: "technician", trade_discipline: "Electrical", contact_number: "61234567", is_active: true };

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(administrator);
  mocks.rpc.mockResolvedValue({ data: { id: TARGET_ID }, error: null });
  mocks.createClient.mockResolvedValue({ rpc: mocks.rpc });
  mocks.isAdminConfigured.mockReturnValue(true);
  mocks.deleteUser.mockResolvedValue({ error: null });
  mocks.adminRpc.mockResolvedValue({ data: { ok: true }, error: null });
  mocks.createAdminClient.mockReturnValue({
    auth: { admin: { deleteUser: mocks.deleteUser } },
    rpc: mocks.adminRpc,
  });
});

describe("Administrator profile mutations", () => {
  test("denies non-Administrators before database mutation", async () => {
    mocks.getCurrentIdentity.mockResolvedValue({ ...administrator, role: "supervisor" });
    const response = await PATCH(request("PATCH", validUpdate), context());
    expect(response.status).toBe(403);
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  test("rejects invalid profile input", async () => {
    const response = await PATCH(request("PATCH", { ...validUpdate, display_name: "" }), context());
    expect(response.status).toBe(400);
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  test("updates profile and audit through one authoritative RPC", async () => {
    const response = await PATCH(request("PATCH", validUpdate), context());
    expect(response.status).toBe(200);
    expect(mocks.rpc).toHaveBeenCalledWith("admin_update_profile", {
      p_target_id: TARGET_ID,
      p_payload: expect.objectContaining({ role: "technician", is_active: true }),
    });
  });

  test("returns a reconciled failure when the atomic RPC rolls back", async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { message: "audit insert failed" } });
    const response = await PATCH(request("PATCH", validUpdate), context());
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toEqual({ error: "The user profile and audit entry were not changed." });
  });

  test("archives profile and audit through one authoritative RPC", async () => {
    const response = await DELETE(request("DELETE", { confirmation: "technician@example.com" }), context());
    expect(response.status).toBe(200);
    expect(mocks.rpc).toHaveBeenCalledWith("admin_archive_profile", { p_target_id: TARGET_ID, p_confirmation: "technician@example.com" });
  });

  test("permanently deletes through preflight, Auth, then service-only result audit", async () => {
    const response = await DELETE(request("DELETE", { permanent: true, confirmation: "technician@example.com" }), context());
    expect(response.status).toBe(200);
    expect(mocks.rpc).toHaveBeenCalledWith("admin_prepare_permanent_profile_deletion", {
      p_target_id: TARGET_ID,
      p_confirmation: "technician@example.com",
    });
    expect(mocks.deleteUser).toHaveBeenCalledWith(TARGET_ID);
    expect(mocks.adminRpc).toHaveBeenCalledWith("admin_record_permanent_delete_result", {
      p_actor_id: ADMIN_ID,
      p_target_id: TARGET_ID,
      p_succeeded: true,
      p_error_code: null,
    });
  });

  test("reports Auth deletion failure without claiming completion", async () => {
    mocks.deleteUser.mockResolvedValue({ error: { code: "foreign_key_violation" } });
    const response = await DELETE(request("DELETE", { permanent: true, confirmation: "technician@example.com" }), context());
    expect(response.status).toBe(422);
    await expect(response.json()).resolves.toMatchObject({ auth_deleted: false, reconciliation_required: false });
    expect(mocks.adminRpc).toHaveBeenCalledWith(
      "admin_record_permanent_delete_result",
      expect.objectContaining({ p_succeeded: false, p_error_code: "foreign_key_violation" }),
    );
  });

  test("reports the exact reconciled state when completion audit fails", async () => {
    mocks.adminRpc.mockResolvedValue({ data: null, error: { message: "audit failed" } });
    const response = await DELETE(request("DELETE", { permanent: true, confirmation: "technician@example.com" }), context());
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toMatchObject({ auth_deleted: true, reconciliation_required: true });
  });

  test("does not start permanent deletion without privileged Auth configuration", async () => {
    mocks.isAdminConfigured.mockReturnValue(false);
    const response = await DELETE(request("DELETE", { permanent: true, confirmation: "technician@example.com" }), context());
    expect(response.status).toBe(503);
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.deleteUser).not.toHaveBeenCalled();
  });
});
