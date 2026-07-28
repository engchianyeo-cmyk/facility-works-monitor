import { createClient } from "@/lib/supabase/server";

export const USER_ROLES = [
  "reviewer",
  "initiator",
  "approver",
  "technician",
  "supervisor",
  "administrator",
] as const;

export type UserRole = (typeof USER_ROLES)[number];

export type AuthIdentity = {
  userId: string;
  email: string | null;
  displayName: string;
  department: string | null;
  role: UserRole;
};

function isUserRole(value: unknown): value is UserRole {
  return USER_ROLES.includes(value as UserRole);
}

export async function getCurrentIdentity(): Promise<AuthIdentity | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name, email, department, role, is_active")
    .eq("id", user.id)
    .maybeSingle();

  if (profile && profile.is_active === false) return null;

  const metadataName =
    typeof user.user_metadata?.display_name === "string"
      ? user.user_metadata.display_name.trim()
      : "";
  const email = profile?.email ?? user.email ?? null;
  const emailName = email?.split("@")[0] ?? "";

  return {
    userId: user.id,
    email,
    displayName:
      profile?.display_name?.trim() || metadataName || emailName || "Unknown user",
    department:
      profile?.department ??
      (typeof user.user_metadata?.department === "string"
        ? user.user_metadata.department
        : null),
    role: isUserRole(profile?.role) ? profile.role : "reviewer",
  };
}
