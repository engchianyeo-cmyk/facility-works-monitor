import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";

const read = (path: string) => readFileSync(path, "utf8");

describe("D-64 facility staffing structure", () => {
  it("shows a facility only to its own staff, or the Super-Administrator", () => {
    const lib = read("lib/facility-team.ts");
    expect(lib).toContain('import "server-only"');
    expect(lib).toContain('.eq("profile_id", viewer.userId).eq("active", true)');
    expect(lib).toContain('viewer.role === "administrator" ? await siteQuery : mine.length ? await siteQuery.in("id", mine)');
    expect(lib).not.toMatch(/select\([^)]*email/);
  });

  it("lays out the chain from Facility Administrator to Technicians with Approver and Finance alongside", () => {
    const lib = read("lib/facility-team.ts");
    expect(lib).toContain('const CHAIN = ["facility_administrator", "facility_manager", "supervisor", "technician"]');
    expect(lib).toContain('const SIDE = ["approver", "finance"]');
    const page = read("app/facility-team/page.tsx");
    expect(page).toContain('redirect("/login?next=/facility-team")');
    expect(page).toContain("Alongside");
    expect(read("components/site-header.tsx")).toContain('href="/facility-team"');
  });
});
