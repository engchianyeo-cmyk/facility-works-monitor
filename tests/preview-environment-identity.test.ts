import { afterEach, describe, expect, test } from "vitest";
import { GET } from "@/app/api/internal/preview-environment-check/route";
import { classifyLegacySupabaseKey, classifySupabaseUrl, PREVIEW_PROJECT_REF, previewIdentityResponse } from "@/lib/preview-environment-identity";

const originalEnvironment = process.env.VERCEL_ENV;
afterEach(() => {
  if (originalEnvironment === undefined) delete process.env.VERCEL_ENV;
  else process.env.VERCEL_ENV = originalEnvironment;
});

function jwt(ref: string, role: string) {
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ ref, role })}.test-signature`;
}

describe("Preview runtime identity diagnostic", () => {
  test("classifies the correct Preview URL", () => expect(classifySupabaseUrl(`https://${PREVIEW_PROJECT_REF}.supabase.co`)).toBe("PREVIEW_MATCH"));
  test("rejects the Production URL", () => expect(classifySupabaseUrl("https://pyapukytcrsuowmgzqzh.supabase.co")).toBe("PRODUCTION_UNSAFE"));
  test("rejects an unknown project URL", () => expect(classifySupabaseUrl("https://example.invalid")).toBe("UNRECOGNIZED"));
  test("classifies the correct anon key", () => expect(classifyLegacySupabaseKey(jwt(PREVIEW_PROJECT_REF, "anon"), "anon")).toBe("KEY_MATCH"));
  test("rejects an anon key for another project", () => expect(classifyLegacySupabaseKey(jwt("another-project", "anon"), "anon")).toBe("KEY_PROJECT_MISMATCH"));
  test("rejects an anon key with the wrong role", () => expect(classifyLegacySupabaseKey(jwt(PREVIEW_PROJECT_REF, "service_role"), "anon")).toBe("KEY_ROLE_MISMATCH"));
  test("classifies the correct service-role key", () => expect(classifyLegacySupabaseKey(jwt(PREVIEW_PROJECT_REF, "service_role"), "service_role")).toBe("KEY_MATCH"));
  test("rejects a service key for another project", () => expect(classifyLegacySupabaseKey(jwt("another-project", "service_role"), "service_role")).toBe("KEY_PROJECT_MISMATCH"));
  test("rejects a service key with the wrong role", () => expect(classifyLegacySupabaseKey(jwt(PREVIEW_PROJECT_REF, "anon"), "service_role")).toBe("KEY_ROLE_MISMATCH"));
  test("rejects malformed tokens", () => expect(classifyLegacySupabaseKey("not-a-token", "anon")).toBe("INVALID_KEY_FORMAT"));
  test("refuses requests outside Vercel Preview", async () => { process.env.VERCEL_ENV = "production"; expect((await GET()).status).toBe(404); });
  test("returns classifications only and no secrets", () => {
    const anon = jwt(PREVIEW_PROJECT_REF, "anon"), service = jwt(PREVIEW_PROJECT_REF, "service_role");
    const result = previewIdentityResponse("preview", `https://${PREVIEW_PROJECT_REF}.supabase.co`, anon, service);
    expect(result).toEqual({ environment: "preview", supabaseUrl: "PREVIEW_MATCH", anonKey: "KEY_MATCH", serviceRoleKey: "KEY_MATCH", overall: "PREVIEW_IDENTITY_CONFIRMED" });
    const serialized = JSON.stringify(result);
    expect(serialized).not.toContain(anon);
    expect(serialized).not.toContain(service);
    expect(serialized).not.toContain("https://");
  });
});
