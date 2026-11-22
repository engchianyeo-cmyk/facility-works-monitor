import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(path, "utf8");

/** M41a (owner, 23 Nov 2026): set a temporary password for someone who cannot sign in. */
describe("temporary password set by the Super-Administrator or a Facility Administrator", () => {
  it("checks authority in the database, then sets the password only in the sign-in service", () => {
    const route = read("app/api/admin/users/[id]/route.ts");
    expect(route).toContain('rpc("admin_require_password_change"');
    expect(route).toContain("updateUserById(id, { password })");
    expect(route).toContain('["administrator", "facility_administrator"].includes(caller.role)');
    expect(route).toContain("password.length < 12");
  });
  it("offers the button with the show / hide password box and a reason", () => {
    const page = read("components/user-management.tsx");
    expect(page).toContain("Set temporary password");
    expect(page).toContain("<PasswordInput id={`temp-password-${user.id}`}");
    expect(page).toContain('user.role !== "administrator"');
  });
  it("is in the release manifest and the release check", () => {
    expect(read("supabase/bootstrap/fresh-install-manifest.txt")).toContain("20261123120000_admin_password_reset.sql");
    expect(read("scripts/release-verify.mjs")).toContain('sql("tests/sql/admin_password_reset.test.sql")');
  });
});
