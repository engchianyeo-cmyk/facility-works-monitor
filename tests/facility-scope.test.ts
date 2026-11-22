import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(path, "utf8");

/** D-82 (22 Nov 2026): one row of facility buttons, remembered across pages, on every page that lists facility work. */
describe("facility buttons on every page", () => {
  it("remembers the choice in the browser and reads memberships as the signed-in person", () => {
    const scope = read("lib/facility-scope-server.ts");
    expect(scope).toContain("FACILITY_COOKIE");
    expect(scope).toContain('rpc("visible_facility_memberships")');
    expect(scope).toContain('identity.role !== "administrator"');
    const buttons = read("components/facility-buttons.tsx");
    expect(buttons).toContain('"All facilities"');
    expect(buttons).toContain("aria-pressed={active}");
    expect(buttons).toContain('next.delete("facility")');
  });
  it.each([
    "app/work-orders/page.tsx", "app/notices/page.tsx", "app/administration/notices/page.tsx", "app/assets/page.tsx",
    "app/maintenance-plan/page.tsx", "app/maintenance/page.tsx", "app/operations/page.tsx",
    "app/administration/contractor-admission/page.tsx", "app/finance/page.tsx",
  ])("%s shows the facility buttons", (path) => {
    const page = read(path);
    expect(page).toContain("facilityScope(supabase,");
    expect(page).toMatch(/<FacilityButtons facilities=\{scope\.facilities\}|<FacilityButtons facilities=\{switchFacilities\}/);
  });
  it("counts unread notices on each facility button", () => {
    expect(read("app/notices/page.tsx")).toContain('counts={unreadByFacility} countLabel="unread"');
    expect(read("app/administration/notices/page.tsx")).toContain("counts={unreadByFacility}");
  });
  it("groups assets by facility", () => {
    expect(read("app/assets/page.tsx")).toContain("groupByFacility(assets");
  });
});

/** M39 (D-81): the on-call roster and incidents belong to a facility. */
describe("on-call per facility", () => {
  it("asks for the facility on the roster and the incident form", () => {
    const roster = read("components/incidents/roster-management.tsx");
    expect(roster).toContain("Choose the facility");
    expect(roster).toContain("No one on call for this facility yet");
    expect(read("components/incidents/incident-form.tsx")).toContain('name="facility_id"');
    expect(read("app/api/incidents/route.ts")).toContain("facility_id: facilityId || null");
  });
  it("is in the release manifest and the release check", () => {
    expect(read("supabase/bootstrap/fresh-install-manifest.txt")).toContain("20261122120000_facility_on_call.sql");
    expect(read("scripts/release-verify.mjs")).toContain('sql("tests/sql/facility_on_call.test.sql")');
  });
});
