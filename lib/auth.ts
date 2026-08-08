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

export function isUserRole(value: unknown): value is UserRole {
  return USER_ROLES.includes(value as UserRole);
}

async function loadCurrentIdentity(): Promise<AuthIdentity | null> {
  const supabase = await createClient();
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) return null;

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("display_name, email, department, role, is_active, deleted_at")
    .eq("id", user.id)
    .maybeSingle();

  if (
    profileError ||
    !profile ||
    profile.is_active !== true ||
    profile.deleted_at ||
    !isUserRole(profile.role)
  ) {
    return null;
  }

  const metadataName =
    typeof user.user_metadata?.display_name === "string"
      ? user.user_metadata.display_name.trim()
      : "";
  const email = profile.email ?? user.email ?? null;
  const emailName = email?.split("@")[0] ?? "";

  return {
    userId: user.id,
    email,
    displayName:
      profile.display_name?.trim() || metadataName || emailName || "Unknown user",
    department: profile.department,
    role: profile.role,
  };
}

export async function getCurrentIdentity(): Promise<AuthIdentity | null> {
  try {
    return await loadCurrentIdentity();
  } catch {
    return null;
  }
}
