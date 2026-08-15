import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({ createClient: vi.fn() }));

vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));

import { getCurrentIdentity, USER_ROLES } from "@/lib/auth";

function clientFor(options: {
  user?: Record<string, unknown> | null;
  userError?: unknown;
  profile?: Record<string, unknown> | null;
  profileError?: unknown;
}) {
  const maybeSingle = vi.fn().mockResolvedValue({
    data: options.profile ?? null,
    error: options.profileError ?? null,
  });
  const profileQuery = {
    select: vi.fn(),
    eq: vi.fn(),
    maybeSingle,
  };
  profileQuery.select.mockReturnValue(profileQuery);
  profileQuery.eq.mockReturnValue(profileQuery);
  return {
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: options.user ?? null },
        error: options.userError ?? null,
      }),
    },
    from: vi.fn().mockReturnValue(profileQuery),
  };
}

const user = {
  id: "11111111-1111-4111-8111-111111111111",
  email: "person@example.com",
  user_metadata: { display_name: "Metadata name", department: "Legacy" },
};

const activeProfile = {
  display_name: "Profile name",
  email: "person@example.com",
  department: "Facilities",
  role: "reviewer",
  is_active: true,
  deleted_at: null,
  password_change_required: false,
};

beforeEach(() => vi.clearAllMocks());

describe("getCurrentIdentity", () => {
  test.each(USER_ROLES)("loads an active supported %s profile", async (role) => {
    mocks.createClient.mockResolvedValue(
      clientFor({ user, profile: { ...activeProfile, role } }),
    );

    await expect(getCurrentIdentity()).resolves.toEqual({
      userId: user.id,
      email: user.email,
      displayName: activeProfile.display_name,
      department: activeProfile.department,
      role,
      passwordChangeRequired: false,
    });
  });

  test("rejects an inactive profile", async () => {
    mocks.createClient.mockResolvedValue(
      clientFor({ user, profile: { ...activeProfile, is_active: false } }),
    );
    await expect(getCurrentIdentity()).resolves.toBeNull();
  });

  test("rejects a password-pending profile from operational identity", async () => {
    mocks.createClient.mockResolvedValue(
      clientFor({ user, profile: { ...activeProfile, password_change_required: true } }),
    );
    await expect(getCurrentIdentity()).resolves.toBeNull();
  });

  test("rejects a soft-deleted profile", async () => {
    mocks.createClient.mockResolvedValue(
      clientFor({
        user,
        profile: { ...activeProfile, deleted_at: "2026-08-08T00:00:00Z" },
      }),
    );
    await expect(getCurrentIdentity()).resolves.toBeNull();
  });

  test("does not turn a missing profile into a Reviewer identity", async () => {
    mocks.createClient.mockResolvedValue(clientFor({ user, profile: null }));
    await expect(getCurrentIdentity()).resolves.toBeNull();
  });

  test("rejects unsupported profile roles", async () => {
    mocks.createClient.mockResolvedValue(
      clientFor({ user, profile: { ...activeProfile, role: "owner" } }),
    );
    await expect(getCurrentIdentity()).resolves.toBeNull();
  });

  test("fails closed when profile loading fails", async () => {
    mocks.createClient.mockResolvedValue(
      clientFor({ user, profileError: { message: "database unavailable" } }),
    );
    await expect(getCurrentIdentity()).resolves.toBeNull();
  });

  test("fails closed when the Supabase client throws", async () => {
    mocks.createClient.mockRejectedValue(new Error("network details"));
    await expect(getCurrentIdentity()).resolves.toBeNull();
  });
});
