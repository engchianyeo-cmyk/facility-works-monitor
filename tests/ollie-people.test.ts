import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { facilitiesNamed, peopleIntent } from "@/lib/help/people";

/** Ollie (owner, 23 Nov 2026): "who are the users in Facility 2?" answered from the facility's staff list. */
describe("Ollie answers who works at a facility", () => {
  it("recognises questions about people, roles and on call", () => {
    expect(peopleIntent("who are the users in Facility 2?")).toEqual({ roles: [], onCall: false });
    expect(peopleIntent("Who is the supervisor at Facility One")).toEqual({ roles: ["supervisor"], onCall: false });
    expect(peopleIntent("list the technicians")).toEqual({ roles: ["technician"], onCall: false });
    expect(peopleIntent("who is on call tonight?")?.onCall).toBe(true);
    expect(peopleIntent("facility manager phone number")?.roles).toEqual(["facility_manager"]);
    expect(peopleIntent("how do I approve a work order")).toBeNull();
    expect(peopleIntent("where is the chiller room")).toBeNull();
  });
  it("finds the facility named, or all", () => {
    const facilities = [{ name: "Facility One", code: "UAT-FAC-001" }, { name: "Facility 2 — Pharma Warehouse", code: "F2-PW" }];
    expect(facilitiesNamed("who are the users in Facility 2?", facilities).map((f) => f.code)).toEqual(["F2-PW"]);
    expect(facilitiesNamed("staff at facility 1", facilities).map((f) => f.code)).toEqual(["UAT-FAC-001"]);
    expect(facilitiesNamed("who is the supervisor", facilities)).toHaveLength(2);
  });
  it("reads the staff list as the signed-in person and shows it in the help panel", () => {
    const route = readFileSync("app/api/assistant/people/route.ts", "utf8");
    expect(route).toContain('rpc("visible_facility_memberships")');
    expect(route).toContain("facilityScope(supabase, identity)");
    expect(readFileSync("components/help/help-panel.tsx", "utf8")).toContain('data-testid="ollie-people"');
  });
});
