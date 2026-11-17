import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { toCell, toMinutes } from "@/components/sla/sla-times-editor";
import { groupRules, ruleScope, type SlaRuleRow } from "@/lib/sla/card";

describe("M32 SLA times page and asset download", () => {
  it("shows stored minutes in the largest whole unit and converts back", () => {
    expect(toCell(240)).toEqual({ value: "4", unit: "h" });
    expect(toCell(1440)).toEqual({ value: "1", unit: "days" });
    expect(toCell(15)).toEqual({ value: "15", unit: "min" });
    expect(toCell(null)).toEqual({ value: "", unit: "min" });
    expect(toMinutes({ value: "3", unit: "days" })).toBe(4320);
    expect(toMinutes({ value: "1.5", unit: "h" })).toBe(90);
    expect(toMinutes({ value: "", unit: "h" })).toBeNull();
  });

  it("groups Site SLA as the standard first, then each facility's own", () => {
    const rule = (id: string, facility: string | null) => ({ id, work_order_priority: "critical", service_category: { code: "GENERAL", name: "General" },
      version: { version_number: 1, effective_from: "2026-11-17", effective_to: null, agreement: { name: "x", counterparty: null, facility_id: facility, facility: facility ? { name: "Facility 2" } : null } } }) as unknown as SlaRuleRow;
    expect(ruleScope(rule("a", null))).toBe("Standard SLA — all facilities");
    const groups = groupRules([rule("f", "f2"), rule("s", null)]);
    expect(groups.map((group) => group.category)).toEqual(["Standard SLA — all facilities", "Facility 2 — its own SLA"]);
  });

  it("lets only the Super-Administrator set SLA times, and downloads assets for signed-in people", () => {
    expect(readFileSync("app/api/administration/sla-times/route.ts", "utf8")).toContain('identity.role !== "administrator"');
    const exportRoute = readFileSync("app/api/assets/export/route.ts", "utf8");
    expect(exportRoute).toContain("createCsv(HEADERS, rows)");
    expect(exportRoute).not.toContain("createAdminClient");
    expect(readFileSync("app/assets/page.tsx", "utf8")).toContain("Download asset list (Excel)");
  });
});
