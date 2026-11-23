import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(path, "utf8");

/** M41b (owner, 23 Nov 2026): the Facility Manager's management views, one-line assets, notices explained. */
describe("Facility Manager management views", () => {
  it.each(["app/management/sla/page.tsx", "app/exports/page.tsx", "app/api/exports/[register]/route.ts", "app/sla/page.tsx", "components/operations/OperationsWorkspace.tsx"])("%s lets the Facility Manager in", (path) => {
    expect(read(path)).toMatch(/"approver", ?"supervisor", ?"facility_manager", ?"administrator"/);
  });
  it("hides the retiring Staffing link", () => {
    expect(read("components/site-header.tsx")).not.toContain('href="/management/staffing"');
  });
  it("shows one line per asset and explains what each role receives as notices", () => {
    expect(read("app/assets/page.tsx")).toContain("<details className=\"group\">");
    const notices = read("app/notices/page.tsx");
    expect(notices).toContain("Payment matters go to Finance, not here.");
    expect(notices).toContain("Nothing here means nothing is waiting for you.");
  });
});
