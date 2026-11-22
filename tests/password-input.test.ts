import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

/** Owner, 10 Nov 2026: an eye button on the right of the password boxes shows or hides what was typed. */
describe("password boxes with show / hide", () => {
  const component = readFileSync("components/password-input.tsx", "utf8");
  it("switches between hidden and visible text with an accessible toggle that does not reuse the word password", () => {
    expect(component).toContain('type={visible ? "text" : "password"}');
    expect(component).toContain("aria-pressed={visible}");
    expect(component).toContain('"Show the characters typed"');
    expect(component).not.toMatch(/aria-label=\{[^}]*[Pp]assword/);
  });
  it("is used on the sign-in and change-password forms", () => {
    expect(readFileSync("components/auth-form.tsx", "utf8")).toContain("<PasswordInput id=\"password\"");
    const change = readFileSync("components/password-change-form.tsx", "utf8");
    expect(change).toContain("<PasswordInput id=\"password\"");
    expect(change).toContain("<PasswordInput id=\"confirmation\"");
  });
  it("is used for the temporary password when creating a user, and no plain password box is left (21 Nov 2026)", () => {
    expect(readFileSync("components/direct-user-provisioning.tsx", "utf8")).toContain('id="temporary-password"');
    for (const file of ["components/direct-user-provisioning.tsx", "components/auth-form.tsx", "components/password-change-form.tsx", "components/user-management.tsx"]) {
      expect(readFileSync(file, "utf8")).not.toContain('type="password"');
    }
  });
});
