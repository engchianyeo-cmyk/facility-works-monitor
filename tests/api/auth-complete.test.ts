import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({ createClient: vi.fn(), createAdminClient: vi.fn() }));

vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));
vi.mock("@/lib/supabase/admin", () => ({ createAdminClient: mocks.createAdminClient }));

import { GET } from "@/app/auth/complete/route";

function authClient(options: {
  role?: string;
  active?: boolean;
  deletedAt?: string | null;
  passwordChangeRequired?: boolean;
  missing?: boolean;
  profileError?: unknown;
  user?: boolean;
  operationallyReady?: boolean;
  readinessError?: unknown;
}) {
  const profileQuery = {
    select: vi.fn(),
    eq: vi.fn(),
    maybeSingle: vi.fn().mockResolvedValue({
      data: options.missing
        ? null
        : {
            role: options.role ?? "reviewer",
            is_active: options.active ?? true,
            deleted_at: options.deletedAt ?? null,
            password_change_required: options.passwordChangeRequired ?? false,
          },
      error: options.profileError ?? null,
    }),
  };
  profileQuery.select.mockReturnValue(profileQuery);
  profileQuery.eq.mockReturnValue(profileQuery);
  mocks.createAdminClient.mockReturnValue({
    from: vi.fn().mockReturnValue(profileQuery),
  });
  return {
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: {
          user:
            options.user === false
              ? null
              : { id: "11111111-1111-4111-8111-111111111111" },
        },
      }),
      signOut: vi.fn().mockResolvedValue({ error: null }),
    },
    rpc: vi.fn().mockResolvedValue({
      data: options.operationallyReady ?? true,
      error: options.readinessError ?? null,
    }),
  };
}

beforeEach(() => vi.clearAllMocks());

describe("GET /auth/complete", () => {
  test("preserves Administrator login and a safe requested destination", async () => {
    mocks.createClient.mockResolvedValue(authClient({ role: "administrator" }));
    const response = await GET(
      new Request("http://localhost/auth/complete?next=/administration/users"),
    );
    expect(response.headers.get("location")).toBe(
      "http://localhost/administration/users",
    );
  });

  test.each(["reviewer", "initiator", "approver", "technician", "supervisor", "facility_manager"])(
    "loads an active %s profile at the requested authenticated destination",
    async (role) => {
    mocks.createClient.mockResolvedValue(authClient({ role }));
    const response = await GET(
      new Request("http://localhost/auth/complete?next=/work-orders"),
    );
    expect(response.headers.get("location")).toBe("http://localhost/work-orders");
    },
  );

  test("does not route an active Technician to the legacy public compatibility list", async () => {
    mocks.createClient.mockResolvedValue(authClient({ role: "technician" }));
    const response = await GET(new Request("http://localhost/auth/complete"));
    expect(response.headers.get("location")).toBe("http://localhost/operations");
  });

  test("routes a password-pending account to mandatory password setup", async () => {
    const client = authClient({
      role: "reviewer",
      passwordChangeRequired: true,
      operationallyReady: false,
    });
    mocks.createClient.mockResolvedValue(client);
    const response = await GET(new Request("http://localhost/auth/complete?next=/work-orders"));
    expect(response.headers.get("location")).toBe("http://localhost/account/password?setup=required&next=%2Fwork-orders");
    expect(client.rpc).not.toHaveBeenCalled();
    expect(client.auth.signOut).not.toHaveBeenCalled();
  });

  test.each([
    { name: "inactive", options: { active: false }, message: "inactive" },
    { name: "archived", options: { deletedAt: "2026-08-08T00:00:00Z" }, message: "archived" },
    { name: "missing", options: { missing: true }, message: "missing" },
    {
      name: "query failure",
      options: { profileError: { message: "raw database error" } },
      message: "could not be checked",
    },
    { name: "unsupported role", options: { role: "owner" }, message: "role" },
  ])("signs out a $name profile with a controlled error", async ({ options, message }) => {
    const client = authClient(options);
    mocks.createClient.mockResolvedValue(client);
    const response = await GET(new Request("http://localhost/auth/complete"));
    const location = response.headers.get("location") ?? "";
    expect(location).toContain("/login?error=");
    expect(decodeURIComponent(location).toLowerCase()).toContain(message);
    expect(location).not.toContain("raw%20database%20error");
    expect(client.auth.signOut).toHaveBeenCalledOnce();
  });

  test.each([
    { name: "readiness denial", options: { operationallyReady: false } },
    { name: "readiness check failure", options: { readinessError: { message: "internal detail" } } },
  ])("signs out after a controlled $name", async ({ options }) => {
    const client = authClient(options);
    mocks.createClient.mockResolvedValue(client);
    const response = await GET(new Request("http://localhost/auth/complete"));
    const location = response.headers.get("location") ?? "";
    expect(decodeURIComponent(location)).toContain("account setup is not ready for operational access");
    expect(location).not.toContain("internal%20detail");
    expect(client.auth.signOut).toHaveBeenCalledOnce();
  });
});
