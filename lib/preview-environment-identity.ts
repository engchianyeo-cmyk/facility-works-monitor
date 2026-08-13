import "server-only";
import { lookup } from "node:dns/promises";

export const PREVIEW_PROJECT_REF = "pvajuywwwypjlikqjnvgv";
export const PRODUCTION_PROJECT_REF = "pyapukytcrsuowmgzqzh";
export const PREVIEW_HOSTNAME = `${PREVIEW_PROJECT_REF}.supabase.co`;
export const PREVIEW_SUPABASE_URL = `https://${PREVIEW_HOSTNAME}`;
const PREVIEW_AUTH_SETTINGS_URL = `${PREVIEW_SUPABASE_URL}/auth/v1/settings`;
const GENERAL_HTTPS_URL = "https://example.com";

export type UrlClassification = "PREVIEW_MATCH" | "PRODUCTION_UNSAFE" | "UNRECOGNIZED";
export type RoleClassification = "ANON_ROLE_VALID" | "ANON_ROLE_MISMATCH" | "SERVICE_ROLE_VALID" | "SERVICE_ROLE_MISMATCH";
type NetworkClassification = "DNS_FAILURE" | "CONNECT_TIMEOUT" | "CONNECTION_RESET" | "TLS_FAILURE" | "FETCH_FAILURE" | "HTTP_REACHED";
type SafeFetch = (input: string, init: RequestInit) => Promise<Pick<Response, "ok" | "status">>;
type SafeLookup = (hostname: string) => Promise<unknown>;
type SafeError = { name: string; code: string; causeName: string; causeCode: string; classification: Exclude<NetworkClassification, "HTTP_REACHED"> };

export function classifySupabaseUrl(value: string | undefined): UrlClassification {
  try {
    const hostname = new URL(value ?? "").hostname.toLowerCase();
    if (hostname === PREVIEW_HOSTNAME) return "PREVIEW_MATCH";
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
  } catch { return expectedRole === "anon" ? "ANON_ROLE_MISMATCH" : "SERVICE_ROLE_MISMATCH"; }
}

function safeToken(value: unknown) {
  return typeof value === "string" && /^[A-Za-z0-9_]+$/.test(value) ? value.slice(0, 48) : "UNAVAILABLE";
}
function safeError(error: unknown): SafeError {
  const outer = error && typeof error === "object" ? error as Record<string, unknown> : {};
  const cause = outer.cause && typeof outer.cause === "object" ? outer.cause as Record<string, unknown> : {};
  const name = safeToken(outer.name), code = safeToken(outer.code), causeName = safeToken(cause.name), causeCode = safeToken(cause.code);
  const marker = `${name} ${code} ${causeName} ${causeCode}`;
  const classification: SafeError["classification"] = /ENOTFOUND|EAI_AGAIN/.test(marker) ? "DNS_FAILURE"
    : /TIMEOUT|ETIMEDOUT|AbortError|TimeoutError/i.test(marker) ? "CONNECT_TIMEOUT"
    : /ECONNRESET|UND_ERR_SOCKET/.test(marker) ? "CONNECTION_RESET"
    : /TLS|CERT|SSL|SELF_SIGNED|DEPTH_ZERO/i.test(marker) ? "TLS_FAILURE" : "FETCH_FAILURE";
  return { name, code, causeName, causeCode, classification };
}
async function probe(target: string, request: SafeFetch, headers?: HeadersInit) {
  try {
    const response = await request(target, { method: "GET", ...(headers ? { headers } : {}), cache: "no-store", redirect: "manual", signal: AbortSignal.timeout(8000) });
    return { reached: true as const, status: response.status, classification: "HTTP_REACHED" as const };
  } catch (error) { return { reached: false as const, status: 0, ...safeError(error) }; }
}

export async function diagnosePreviewNetwork(
  environment: string | undefined,
  runtimeUrl: string | undefined,
  anonKey: string | undefined,
  serviceRoleKey: string | undefined,
  request: SafeFetch = fetch,
  resolve: SafeLookup = lookup,
) {
  if (environment !== "preview") return null;
  const supabaseUrl = classifySupabaseUrl(runtimeUrl);
  const hostname = supabaseUrl === "PREVIEW_MATCH" ? "HOSTNAME_MATCH" as const : "HOSTNAME_MISMATCH" as const;
  if (hostname === "HOSTNAME_MISMATCH") return { environment: "preview" as const, supabaseUrl, hostname, dns: "DNS_CHECK_UNAVAILABLE" as const, generalHttps: "NOT_TESTED" as const, previewEndpoint: "NOT_TESTED" as const, networkClassification: "FETCH_FAILURE" as const, anonAcceptance: "NOT_TESTED" as const, serviceRoleAcceptance: "NOT_TESTED" as const, conclusion: "HOSTNAME_CONFIGURATION_ERROR" as const, overall: "BLOCKED" as const };

  const [dnsResult, generalResult] = await Promise.all([
    resolve(PREVIEW_HOSTNAME).then(() => "DNS_RESOLVED" as const).catch(() => "DNS_NOT_RESOLVED" as const),
    probe(GENERAL_HTTPS_URL, request),
  ]);
  const previewResult = await probe(PREVIEW_AUTH_SETTINGS_URL, request);
  if (!previewResult.reached) {
    const conclusion = dnsResult === "DNS_NOT_RESOLVED" ? "DNS_FAILURE" as const
      : !generalResult.reached ? "VERCEL_OUTBOUND_NETWORK_FAILURE" as const
      : previewResult.classification === "TLS_FAILURE" ? "TLS_FAILURE" as const : "SUPABASE_HOST_UNREACHABLE" as const;
    return { environment: "preview" as const, supabaseUrl, hostname, dns: dnsResult, generalHttps: generalResult.reached ? "GENERAL_HTTPS_REACHABLE" as const : "GENERAL_HTTPS_FAILED" as const, generalHttpsError: generalResult.reached ? undefined : generalResult, previewEndpoint: "PREVIEW_ENDPOINT_UNREACHABLE" as const, previewError: previewResult, networkClassification: previewResult.classification, anonAcceptance: "NOT_TESTED" as const, serviceRoleAcceptance: "NOT_TESTED" as const, conclusion, overall: "BLOCKED" as const };
  }

  const [anonResult, serviceResult] = await Promise.all([
    probe(PREVIEW_AUTH_SETTINGS_URL, request, { apikey: anonKey ?? "" }),
    probe(PREVIEW_AUTH_SETTINGS_URL, request, { apikey: serviceRoleKey ?? "" }),
  ]);
  const anonAcceptance = anonResult.reached && anonResult.status >= 200 && anonResult.status < 300 ? "ANON_KEY_ACCEPTED" as const : "ANON_KEY_REJECTED" as const;
  const serviceRoleAcceptance = serviceResult.reached && serviceResult.status >= 200 && serviceResult.status < 300 ? "SERVICE_ROLE_KEY_ACCEPTED" as const : "SERVICE_ROLE_KEY_REJECTED" as const;
  const anonRole = classifyLegacyRole(anonKey, "anon"), serviceRole = classifyLegacyRole(serviceRoleKey, "service_role");
  const confirmed = anonAcceptance === "ANON_KEY_ACCEPTED" && serviceRoleAcceptance === "SERVICE_ROLE_KEY_ACCEPTED" && anonRole === "ANON_ROLE_VALID" && serviceRole === "SERVICE_ROLE_VALID";
  return { environment: "preview" as const, supabaseUrl, hostname, dns: dnsResult, generalHttps: generalResult.reached ? "GENERAL_HTTPS_REACHABLE" as const : "GENERAL_HTTPS_FAILED" as const, previewEndpoint: "PREVIEW_ENDPOINT_REACHABLE" as const, previewHttpStatus: previewResult.status, networkClassification: "HTTP_REACHED" as const, anonAcceptance, anonHttpStatus: anonResult.status, anonRole, serviceRoleAcceptance, serviceRoleHttpStatus: serviceResult.status, serviceRole, conclusion: confirmed ? "PREVIEW_IDENTITY_CONFIRMED" as const : "NETWORK_PATH_CONFIRMED" as const, overall: confirmed ? "PREVIEW_IDENTITY_CONFIRMED" as const : "BLOCKED" as const };
}
