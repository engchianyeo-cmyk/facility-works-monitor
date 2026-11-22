import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  createClient: vi.fn(),
  createAdminClient: vi.fn(),
  isAdminConfigured: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getCurrentIdentity: mocks.getCurrentIdentity,
}));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: mocks.createAdminClient,
  isAdminConfigured: mocks.isAdminConfigured,
}));

import { GET } from "@/app/api/admin/users/route";

const profile = {
  id: "22222222-2222-4222-8222-222222222222",
  display_name: "Reviewer One",
  email: "reviewer@example.com",
  department: "Facilities",
  department_id: "33333333-3333-4333-8333-333333333333",
  trade_discipline: null,
  contact_number: null,
  role: "reviewer",
  is_active: true,
  deleted_at: null,
  created_at: "2026-08-01T00:00:00Z",
  updated_at: "2026-08-01T00:00:00Z",
  last_active_at: null,
  last_seen_route: null,
};

function query(result: { data: unknown; error: unknown }, terminal: "order" | "limit") {
  const value = {
    select: vi.fn(),
    order: vi.fn(),
    like: vi.fn(),
    limit: vi.fn(),
    eq: vi.fn(),
    is: vi.fn(),
  };
  value.select.mockReturnValue(value);
  value.like.mockReturnValue(value);
  value.eq.mockReturnValue(value);
  value.is.mockReturnValue(value);
  if (terminal === "order") value.order.mockResolvedValue(result);
  else {
    value.order.mockReturnValue(value);
    value.limit.mockResolvedValue(result);
  }
  return value;
}

function installServer(
  profileResult: { data: unknown; error: unknown } = {
    data: [profile],
    error: null,
  },
) {
  const profiles = query(profileResult, "order");
  const audit = query({ data: [], error: null }, "limit");
  const departments = query(
    {
      data: [{ id: profile.department_id, name: profile.department }],
      error: null,
    },
    "order",
  );
  mocks.createClient.mockResolvedValue({
    from: vi
      .fn()
      .mockReturnValueOnce(profiles)
      .mockReturnValueOnce(audit)
      .mockReturnValueOnce(departments),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue({
    userId: "11111111-1111-4111-8111-111111111111",
    role: "administrator",
  });
  mocks.isAdminConfigured.mockReturnValue(true);
  mocks.createAdminClient.mockReturnValue({
    auth: {
      admin: {
        listUsers: vi.fn().mockResolvedValue({
          data: {
            users: [
              {
                id: profile.id,
                last_sign_in_at: "2026-08-07T00:00:00Z",
                email_confirmed_at: "2026-08-01T00:00:00Z",
              },
            ],
          },
          error: null,
        }),
      },
    },
  });
  installServer();
});

describe("GET /api/admin/users", () => {
  test("denies a request without an Administrator identity", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);
    const response = await GET();
    expect(response.status).toBe(403);
    expect(mocks.createAdminClient).not.toHaveBeenCalled();
  });

  test("loads profile management without privileged Auth configuration", async () => {
    mocks.isAdminConfigured.mockReturnValue(false);
    const response = await GET();
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      provisioning_configured: false,
      auth_directory_available: false,
      users: [{ id: profile.id, department_id: profile.department_id }],
    });
    expect(mocks.createAdminClient).not.toHaveBeenCalled();
  });

  test("merges Auth sign-in state when privileged configuration is available", async () => {
    const response = await GET();
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      provisioning_configured: true,
      auth_directory_available: true,
      users: [
        {
          id: profile.id,
          last_sign_in_at: "2026-08-07T00:00:00Z",
          email_confirmed_at: "2026-08-01T00:00:00Z",
        },
      ],
    });
  });

  test("returns a generic error when profile loading fails", async () => {
    installServer({ data: null, error: { message: "raw database details" } });
    const response = await GET();
    expect(response.status).toBe(503);
    const result = await response.json();
    expect(result.error).toBe("User management data could not be loaded.");
    expect(JSON.stringify(result)).not.toContain("raw database details");
  });
});

describe("UAT 18 Nov 2026: users by facility", () => {
  test("adds each user's facilities and the facility list, and the page filters by them", async () => {
    const { readFileSync } = await import("node:fs");
    const route = readFileSync("app/api/admin/users/route.ts", "utf8");
    // 21 Nov 2026 (D-72): read as the signed-in person; the service key cannot read facility_memberships.
    expect(route).toContain('supabase.rpc("visible_facility_memberships")');
    expect(route).not.toContain('from("facility_memberships")');
    expect(route).toContain("facilities: scope.facilities");
    const page = readFileSync("components/user-management.tsx", "utf8");
    expect(page).toContain('aria-label="Filter users by facility"');
    expect(page).toContain("All facilities");
    expect(page).toContain("Not in any facility");
  });

  test("still lists users if the facility lookup is unavailable", async () => {
    const response = await GET();
    expect(response.status).toBe(200);
    const result = await response.json();
    expect(result.users[0].facilities).toEqual([]);
  });
});
