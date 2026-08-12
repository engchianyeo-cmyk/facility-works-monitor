import "server-only";

export const PREVIEW_PROJECT_REF = "pvajuywwwypilikgjnvgy";
export const PRODUCTION_PROJECT_REF = "pyapukytcrsuowmgzqzh";

export type UrlClassification = "PREVIEW_MATCH" | "PRODUCTION_UNSAFE" | "UNRECOGNIZED";
export type KeyClassification = "KEY_MATCH" | "KEY_PROJECT_MISMATCH" | "KEY_ROLE_MISMATCH" | "INVALID_KEY_FORMAT";

export function classifySupabaseUrl(value: string | undefined): UrlClassification {
  try {
    const hostname = new URL(value ?? "").hostname.toLowerCase();
    if (hostname === `${PREVIEW_PROJECT_REF}.supabase.co`) return "PREVIEW_MATCH";
    if (hostname === `${PRODUCTION_PROJECT_REF}.supabase.co`) return "PRODUCTION_UNSAFE";
    return "UNRECOGNIZED";
  } catch {
    return "UNRECOGNIZED";
  }
}

export function classifyLegacySupabaseKey(value: string | undefined, expectedRole: "anon" | "service_role"): KeyClassification {
  try {
    const parts = value?.split(".") ?? [];
    if (parts.length !== 3) return "INVALID_KEY_FORMAT";
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")) as Record<string, unknown>;
    if (payload.ref !== PREVIEW_PROJECT_REF) return "KEY_PROJECT_MISMATCH";
    if (payload.role !== expectedRole) return "KEY_ROLE_MISMATCH";
    return "KEY_MATCH";
  } catch {
    return "INVALID_KEY_FORMAT";
  }
}

export function previewIdentityResponse(environment: string | undefined, url: string | undefined, anonKey: string | undefined, serviceRoleKey: string | undefined) {
  if (environment !== "preview") return null;
  const supabaseUrl = classifySupabaseUrl(url);
  const anonKeyResult = classifyLegacySupabaseKey(anonKey, "anon");
  const serviceRoleKeyResult = classifyLegacySupabaseKey(serviceRoleKey, "service_role");
  return {
    environment: "preview" as const,
    supabaseUrl,
    anonKey: anonKeyResult,
    serviceRoleKey: serviceRoleKeyResult,
    overall: supabaseUrl === "PREVIEW_MATCH" && anonKeyResult === "KEY_MATCH" && serviceRoleKeyResult === "KEY_MATCH"
      ? "PREVIEW_IDENTITY_CONFIRMED" as const
      : "PREVIEW_IDENTITY_FAILED" as const,
  };
}
