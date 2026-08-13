import "server-only";

export const PREVIEW_PROJECT_REF = "pvajuywwwypilikgjnvgy";
export const PRODUCTION_PROJECT_REF = "pyapukytcrsuowmgzqzh";
export const PREVIEW_SUPABASE_URL = `https://${PREVIEW_PROJECT_REF}.supabase.co`;
const PREVIEW_AUTH_SETTINGS_URL = `${PREVIEW_SUPABASE_URL}/auth/v1/settings`;

export type UrlClassification = "PREVIEW_MATCH" | "PRODUCTION_UNSAFE" | "UNRECOGNIZED";
export type RoleClassification = "ANON_ROLE_VALID" | "ANON_ROLE_MISMATCH" | "SERVICE_ROLE_VALID" | "SERVICE_ROLE_MISMATCH";
type SafeFetch = (input: string, init: RequestInit) => Promise<Pick<Response, "ok" | "status">>;
type AcceptanceResult = { accepted: boolean; status: number; statusClass: "SUCCESS" | "UNAUTHORIZED" | "FORBIDDEN" | "CLIENT_ERROR" | "SERVER_ERROR" | "NETWORK_ERROR" };

export function classifySupabaseUrl(value: string | undefined): UrlClassification {
  try {
    const hostname = new URL(value ?? "").hostname.toLowerCase();
    if (hostname === `${PREVIEW_PROJECT_REF}.supabase.co`) return "PREVIEW_MATCH";
    if (hostname === `${PRODUCTION_PROJECT_REF}.supabase.co`) return "PRODUCTION_UNSAFE";
    return "UNRECOGNIZED";
  } catch { return "UNRECOGNIZED"; }
}

export function classifyLegacyRole(value: string | undefined, expectedRole: "anon" | "service_role"): RoleClassification {
  try {
    const parts = value?.split(".") ?? [];
    if (parts.length !== 3) throw new Error("invalid key format");
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")) as Record<string, unknown>;
    if (expectedRole === "anon") return payload.role === "anon" ? "ANON_ROLE_VALID" : "ANON_ROLE_MISMATCH";
    return payload.role === "service_role" ? "SERVICE_ROLE_VALID" : "SERVICE_ROLE_MISMATCH";
  } catch {
    return expectedRole === "anon" ? "ANON_ROLE_MISMATCH" : "SERVICE_ROLE_MISMATCH";
  }
}

function statusClass(status: number): AcceptanceResult["statusClass"] {
  if (status >= 200 && status < 300) return "SUCCESS";
  if (status === 401) return "UNAUTHORIZED";
  if (status === 403) return "FORBIDDEN";
  if (status >= 400 && status < 500) return "CLIENT_ERROR";
  if (status >= 500) return "SERVER_ERROR";
  return "NETWORK_ERROR";
}

async function accepted(key: string | undefined, request: SafeFetch): Promise<AcceptanceResult> {
  if (!key) return { accepted: false, status: 0, statusClass: "NETWORK_ERROR" };
  try {
    const response = await request(PREVIEW_AUTH_SETTINGS_URL, {
      method: "GET",
      headers: { apikey: key },
      cache: "no-store",
      redirect: "error",
    });
    return { accepted: response.ok, status: response.status, statusClass: statusClass(response.status) };
  } catch { return { accepted: false, status: 0, statusClass: "NETWORK_ERROR" }; }
}

export async function verifyPreviewIdentity(
  environment: string | undefined,
  runtimeUrl: string | undefined,
  anonKey: string | undefined,
  serviceRoleKey: string | undefined,
  request: SafeFetch = fetch,
) {
  if (environment !== "preview") return null;
  const supabaseUrl = classifySupabaseUrl(runtimeUrl);
  if (supabaseUrl !== "PREVIEW_MATCH") return { environment: "preview" as const, supabaseUrl, overall: "PREVIEW_IDENTITY_FAILED" as const };
  const [anonResult, serviceResult] = await Promise.all([accepted(anonKey, request), accepted(serviceRoleKey, request)]);
  const anonRole = classifyLegacyRole(anonKey, "anon");
  const serviceRole = classifyLegacyRole(serviceRoleKey, "service_role");
  const anonAcceptance = anonResult.accepted ? "ANON_KEY_ACCEPTED" as const : "ANON_KEY_REJECTED" as const;
  const serviceRoleAcceptance = serviceResult.accepted ? "SERVICE_ROLE_KEY_ACCEPTED" as const : "SERVICE_ROLE_KEY_REJECTED" as const;
  return {
    environment: "preview" as const,
    supabaseUrl,
    anonAcceptance,
    anonHttpStatus: anonResult.status,
    anonHttpClass: anonResult.statusClass,
    anonRole,
    serviceRoleAcceptance,
    serviceRoleHttpStatus: serviceResult.status,
    serviceRoleHttpClass: serviceResult.statusClass,
    serviceRole,
    requestImplementation: "REQUEST_IMPLEMENTATION_VALID" as const,
    overall: anonResult.accepted && serviceResult.accepted && anonRole === "ANON_ROLE_VALID" && serviceRole === "SERVICE_ROLE_VALID"
      ? "PREVIEW_IDENTITY_CONFIRMED" as const
      : "PREVIEW_IDENTITY_FAILED" as const,
  };
}
