import "server-only";

import { createClient } from "@supabase/supabase-js";

export class AdminConfigurationError extends Error {
  readonly code = "ADMIN_NOT_CONFIGURED";

  constructor() {
    super("Privileged Supabase administration is not configured.");
    this.name = "AdminConfigurationError";
  }
}

export function isAdminConfigured(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL &&
      process.env.SUPABASE_SERVICE_ROLE_KEY,
  );
}

export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) throw new AdminConfigurationError();

  return createClient(url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
