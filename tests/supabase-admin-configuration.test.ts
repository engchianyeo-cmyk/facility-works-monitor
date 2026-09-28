import { afterEach, describe, expect, test, vi } from "vitest";

vi.mock("server-only", () => ({}));

import {
  AdminConfigurationError,
  createAdminClient,
  isAdminConfigured,
  isServiceRoleKey,
} from "@/lib/supabase/admin";

const originalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const originalKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

function legacyKey(role: string) {
  const encode = (value: object) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ role })}.signature`;
}

afterEach(() => {
  if (originalUrl === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
  else process.env.NEXT_PUBLIC_SUPABASE_URL = originalUrl;
  if (originalKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  else process.env.SUPABASE_SERVICE_ROLE_KEY = originalKey;
});

describe("privileged Supabase configuration", () => {
  test("rejects nonempty placeholders and anon JWTs", () => {
    expect(isServiceRoleKey("placeholder")).toBe(false);
    expect(isServiceRoleKey(legacyKey("anon"))).toBe(false);
  });

  test("accepts legacy service-role JWTs and current secret keys", () => {
    expect(isServiceRoleKey(legacyKey("service_role"))).toBe(true);
    expect(isServiceRoleKey(`sb_secret_${"a".repeat(24)}`)).toBe(true);
  });

  test("reports placeholder Preview configuration as unavailable", () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "placeholder";
    expect(isAdminConfigured()).toBe(false);
    expect(() => createAdminClient()).toThrow(AdminConfigurationError);
  });
});
