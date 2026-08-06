import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  createAdminClient: vi.fn(),
  createClient: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: mocks.createAdminClient,
}));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));

import { POST } from "@/app/api/admin/departments/route";
import { DELETE, PATCH } from "@/app/api/admin/departments/[id]/route";

const ADMIN_ID = "11111111-1111-4111-8111-111111111111";
const DEPARTMENT_ID = "22222222-2222-4222-8222-222222222222";
const administrator = {
  userId: ADMIN_ID,
  displayName: "Administrator",
  role: "administrator",
};

const validDepartment = {
  code: "OPS",
  name: "Operations",
  description: "Operations team",
  cost_centre: "CC-100",
  manager_id: null,
  parent_department_id: null,
  colour_tag: "#2563EB",
  is_active: true,
};

function request(method: string, body?: unknown) {
  return new Request(`http://localhost/api/admin/departments/${DEPARTMENT_ID}`, {
    method,
    headers: { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

function context() {
  return { params: Promise.resolve({ id: DEPARTMENT_ID }) };
}

function mockRpc(data: unknown, error: unknown = null) {
  const rpc = vi.fn().mockResolvedValue({ data, error });
  mocks.createClient.mockResolvedValue({ rpc });
  return rpc;
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(administrator);
});

describe("department administration authorization and validation", () => {
  test("rejects non-administrators before invoking an RPC", async () => {
    mocks.getCurrentIdentity.mockResolvedValue({
      ...administrator,
      role: "supervisor",
    });
    const response = await POST(request("POST", validDepartment));
    expect(response.status).toBe(403);
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("rejects an invalid colour", async () => {
    const response = await POST(
      request("POST", { ...validDepartment, colour_tag: "blue" }),
    );
    expect(response.status).toBe(400);
    expect((await response.json()).error).toContain("Colour tag must");
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("returns the RPC self-parent rejection", async () => {
    const rpc = mockRpc({
      ok: false,
      code: "self_parent",
      message: "A department cannot be its own parent.",
    });
    const response = await PATCH(
      request("PATCH", {
        ...validDepartment,
        parent_department_id: DEPARTMENT_ID,
      }),
      context(),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "A department cannot be its own parent.",
      code: "self_parent",
    });
    expect(rpc).toHaveBeenCalledWith(
      "update_department",
      expect.objectContaining({
        p_department_id: DEPARTMENT_ID,
        p_parent_department_id: DEPARTMENT_ID,
      }),
    );
  });

  test("returns a duplicate-code conflict from the RPC", async () => {
    mockRpc({
      ok: false,
      code: "duplicate_department",
      message: "An active department already uses that code or name.",
    });
    const response = await POST(request("POST", validDepartment));
    expect(response.status).toBe(409);
    expect((await response.json()).code).toBe("duplicate_department");
  });

  test("returns a clear conflict when active users remain assigned", async () => {
    mockRpc({
      ok: false,
      code: "active_users_assigned",
      message: "Department cannot be archived while active users are assigned.",
      active_user_count: 2,
    });
    const response = await DELETE(request("DELETE"), context());
    expect(response.status).toBe(409);
    expect((await response.json()).error).toContain("2 active users");
  });
});

describe("department RPC mutations", () => {
  test("creates a department successfully", async () => {
    const department = { id: DEPARTMENT_ID, ...validDepartment };
    const rpc = mockRpc({ ok: true, department });
    const response = await POST(request("POST", validDepartment));
    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toEqual({ department });
    expect(rpc).toHaveBeenCalledWith("create_department", {
      p_code: "OPS",
      p_name: "Operations",
      p_description: "Operations team",
      p_cost_centre: "CC-100",
      p_manager_id: null,
      p_parent_department_id: null,
      p_colour_tag: "#2563EB",
      p_is_active: true,
    });
  });

  test("updates a department successfully", async () => {
    const department = {
      id: DEPARTMENT_ID,
      ...validDepartment,
      name: "Facilities Operations",
    };
    const rpc = mockRpc({ ok: true, department });
    const response = await PATCH(
      request("PATCH", { ...validDepartment, name: "Facilities Operations" }),
      context(),
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ department });
    expect(rpc).toHaveBeenCalledWith(
      "update_department",
      expect.objectContaining({
        p_department_id: DEPARTMENT_ID,
        p_name: "Facilities Operations",
      }),
    );
  });

  test("archives a department successfully", async () => {
    const department = {
      id: DEPARTMENT_ID,
      ...validDepartment,
      is_active: false,
      deleted_at: "2026-08-06T00:00:00.000Z",
    };
    const rpc = mockRpc({ ok: true, department });
    const response = await DELETE(request("DELETE"), context());
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      success: true,
      department,
    });
    expect(rpc).toHaveBeenCalledWith("archive_department", {
      p_department_id: DEPARTMENT_ID,
    });
  });

  test("returns a sanitized response when the RPC call fails", async () => {
    mockRpc(null, { message: "sensitive database detail" });
    const response = await POST(request("POST", validDepartment));
    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Department creation failed.",
    });
  });
});
