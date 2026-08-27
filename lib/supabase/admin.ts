import "server-only";

import { createClient } from "@supabase/supabase-js";

export class AdminConfigurationError extends Error {
  readonly code = "ADMIN_NOT_CONFIGURED";

  constructor() {
    super("Privileged Supabase administration is not configured.");
    this.name = "AdminConfigurationError";
  }
}

export function isServiceRoleKey(value: string | undefined): boolean {
  const key = value?.trim();
  if (!key) return false;
  if (/^sb_secret_[A-Za-z0-9_-]{20,}$/.test(key)) return true;

  const parts = key.split(".");
  if (parts.length !== 3) return false;
  try {
    const payload = JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf8"),
    ) as { role?: unknown };
    return payload.role === "service_role";
  } catch {
    return false;
  }
}

export function isAdminConfigured(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL &&
      isServiceRoleKey(process.env.SUPABASE_SERVICE_ROLE_KEY),
  );
}

export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey || !isServiceRoleKey(serviceRoleKey)) {
    throw new AdminConfigurationError();
  }

  return createClient(url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
