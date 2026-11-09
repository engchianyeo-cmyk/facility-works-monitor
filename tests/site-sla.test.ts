import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { clockStages, durationLabel, groupRules, type SlaClockRow, type SlaRuleRow } from "@/lib/sla/card";

describe("D-45 Site SLA (UAT 9 Nov 2026)", () => {
  it("writes times in plain words", () => {
    expect(durationLabel(15)).toBe("15 min");
    expect(durationLabel(120)).toBe("2 h");
    expect(durationLabel(90)).toBe("1 h 30 min");
    expect(durationLabel(2880)).toBe("2 days");
    expect(durationLabel(null)).toBe("—");
  });
  it("lists the most urgent priority first", () => {
    const rule = (id: string, priority: string) => ({ id, work_order_priority: priority, service_category: { code: "GENERAL", name: "General" } }) as unknown as SlaRuleRow;
    expect(groupRules([rule("l", "low"), rule("c", "critical"), rule("h", "high")])[0].rules.map((r) => r.id)).toEqual(["c", "h", "l"]);
  });
  it("shows each step as met, on track, at risk or missed", () => {
    const start = Date.parse("2026-11-09T02:00:00Z");
    const at = (minutes: number) => new Date(start + minutes * 60_000).toISOString();
    const clock: SlaClockRow = { started_at: at(0), acknowledgement_deadline: at(15), response_deadline: null, attendance_deadline: at(60), make_safe_deadline: at(120), rectification_deadline: at(480),
      acknowledged_at: at(10), responded_at: null, attended_at: null, made_safe_at: null, rectified_at: null };
    const stages = clockStages(clock, start + 100 * 60_000);
    expect(stages.map((s) => [s.key, s.state])).toEqual([["acknowledgement", "met"], ["attendance", "breached"], ["make_safe", "at_risk"], ["rectification", "on_track"]]);
    expect(stages[3].leftMinutes).toBe(380);
  });
  it("is on its own page for everyone, on each Work Order, and in the header", () => {
    expect(readFileSync("app/sla/page.tsx", "utf8")).toContain("Site SLA — how fast we must act");
    expect(readFileSync("app/work-orders/[id]/page.tsx", "utf8")).toContain("<SlaCountdown clock={slaClock}");
    expect(readFileSync("components/site-header.tsx", "utf8")).toContain('href="/sla"');
    const management = readFileSync("app/management/sla/page.tsx", "utf8");
    expect(management).toContain("3. Check each clause found");
    expect(management).toContain('replace(/<\\/?DOCUMENT_CONTENT>/g, "")');
  });
});
