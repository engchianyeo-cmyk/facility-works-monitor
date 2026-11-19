import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { hhmm, roundLate, roundProgress, type RoundCheck } from "@/lib/daily-round";

const read = (p: string) => readFileSync(p, "utf8");
const checks: RoundCheck[] = [
  { id: "c1", title: "Cold room 1", equipment: null, position: 10, active: true, items: [
    { id: "i1", label: "Temperature", unit: "°C", position: 10, active: true },
    { id: "i2", label: "Alarms clear", unit: null, position: 20, active: true },
    { id: "i3", label: "Old item", unit: null, position: 30, active: false },
  ] },
  { id: "c2", title: "Out of use", equipment: null, position: 20, active: false, items: [{ id: "i4", label: "x", unit: null, position: 10, active: true }] },
];

describe("M36 Daily round (owner D-67 D-G)", () => {
  it("counts only items in use, and Not OK", () => {
    expect(roundProgress(checks, [])).toEqual({ total: 2, done: 0, faults: 0, complete: false });
    expect(roundProgress(checks, [{ item_id: "i1", ok: true, reading: "5", note: null, recorded_at: "" }, { item_id: "i2", ok: false, reading: null, note: "alarm", recorded_at: "" }]))
      .toEqual({ total: 2, done: 2, faults: 1, complete: true });
  });

  it("is late after the due time in Singapore, unless closed", () => {
    expect(hhmm("07:00:00")).toBe("07:00");
    expect(roundLate("2026-11-19", "10:00:00", "approved", new Date("2026-11-19T02:30:00Z"))).toBe(true);
    expect(roundLate("2026-11-19", "10:00:00", "approved", new Date("2026-11-19T01:30:00Z"))).toBe(false);
    expect(roundLate("2026-11-19", "10:00:00", "closed", new Date("2026-11-19T05:00:00Z"))).toBe(false);
  });

  it("leaves every decision to the database and links the pages", () => {
    for (const [file, rpc] of [["record", "record_daily_round_item"], ["complete", "complete_daily_round"], ["start", "create_daily_round"], ["settings", "set_daily_round_settings"], ["check", "save_daily_round_check"], ["item", "save_daily_round_item"]]) {
      const route = read(`app/api/daily-round/${file}/route.ts`);
      expect(route).toContain(`rpc("${rpc}"`);
      expect(route).not.toContain("createAdminClient");
    }
    expect(read("components/site-header.tsx")).toContain('href="/daily-round"');
    expect(read("app/work-orders/[id]/page.tsx")).toContain("order.daily_round_date &&");
    expect(read("app/daily-round/setup/page.tsx")).toContain('rpc("daily_round_editor"');
  });
});
