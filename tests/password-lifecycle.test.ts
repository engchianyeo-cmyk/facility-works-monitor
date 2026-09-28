import { describe, expect, test } from "vitest";
import { MINIMUM_PASSWORD_LENGTH, validatePasswordChange } from "@/lib/auth/password";

describe("password lifecycle validation", () => {
  test("rejects short and mismatched passwords", () => {
    expect(validatePasswordChange("short", "short")).toMatchObject({ ok: false });
    expect(validatePasswordChange("long-enough-password", "different-password")).toMatchObject({ ok: false });
  });

  test("accepts a matching password at the minimum length", () => {
    const password = "x".repeat(MINIMUM_PASSWORD_LENGTH);
    expect(validatePasswordChange(password, password)).toEqual({ ok: true, password });
  });
});
