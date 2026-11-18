import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { addDays, pmCreatesWork, pmWindowDays, PM_MODES } from "@/lib/maintenance/window";

const read = (p: string) => readFileSync(p, "utf8");

describe("M35 planned maintenance runs by itself (owner D-67)", () => {
  it("uses the agreed windows", () => {
    expect([pmWindowDays(1, "week"), pmWindowDays(1, "month"), pmWindowDays(3, "month"), pmWindowDays(6, "month"), pmWindowDays(1, "year"), pmWindowDays(12, "month"), pmWindowDays(1, "day")]).toEqual([1, 3, 7, 14, 21, 21, 0]);
    expect(addDays("2026-11-30", 3)).toBe("2026-12-03");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
  });

  it("creates Work Orders only where the facility's setting allows", () => {
    expect(PM_MODES.map((m) => m.id)).toEqual(["off", "plan_only", "full_critical", "full"]);
    expect(pmCreatesWork("full", "low")).toBe(true);
    expect(pmCreatesWork("full_critical", "critical")).toBe(true);
    expect(pmCreatesWork("full_critical", "high")).toBe(false);
    expect(pmCreatesWork("plan_only", "critical")).toBe(false);
    expect(pmCreatesWork(undefined, "critical")).toBe(false);
  });

  it("runs once a day for a caller holding the secret only", () => {
    const route = read("app/api/cron/pm-daily/route.ts");
    expect(route).toContain('request.headers.get("authorization") !== `Bearer ${secret}`');
    expect(route).toContain('rpc("pm_daily_run")');
    const vercel = JSON.parse(read("vercel.json")) as { crons: Array<{ path: string; schedule: string }> };
    expect(vercel.crons).toEqual([{ path: "/api/cron/pm-daily", schedule: "0 22 * * *" }]);
  });

  it("leaves date moves and the setting to the database", () => {
    expect(read("app/api/maintenance/occurrences/[id]/reschedule/route.ts")).toContain('rpc("reschedule_pm_occurrence"');
    expect(read("app/api/maintenance/pm-mode/route.ts")).toContain('rpc("admin_set_pm_mode"');
    const page = read("app/maintenance/page.tsx");
    expect(page).toContain("<RescheduleControl");
    expect(page).toContain("if(!tracked(requirement.asset.id))return[];");
  });
});
