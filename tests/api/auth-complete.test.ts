import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({ createClient: vi.fn() }));

vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));

import { GET } from "@/app/auth/complete/route";

function authClient(options: {
  role?: string;
  active?: boolean;
  deletedAt?: string | null;
  missing?: boolean;
  profileError?: unknown;
  user?: boolean;
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
          },
      error: options.profileError ?? null,
    }),
  };
  profileQuery.select.mockReturnValue(profileQuery);
  profileQuery.eq.mockReturnValue(profileQuery);
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
    from: vi.fn().mockReturnValue(profileQuery),
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

  test.each(["reviewer", "initiator", "approver", "technician", "supervisor"])(
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
    expect(response.headers.get("location")).toBe("http://localhost/");
  });

  test.each([
    { name: "inactive", options: { active: false }, message: "inactive" },
    {
      name: "deleted",
      options: { deletedAt: "2026-08-08T00:00:00Z" },
      message: "inactive",
    },
    { name: "missing", options: { missing: true }, message: "profile" },
    {
      name: "query failure",
      options: { profileError: { message: "raw database error" } },
      message: "profile",
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
});
