import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { currentNoticeIds } from "@/lib/notices";

const now = Date.parse("2026-11-09T11:00:00Z");
const row = (id: string, wo: string | null, at: string, event = "work_order_submitted_for_approval") => ({ id, work_order_id: wo, event_type: event, created_at: at });

describe("D-43 current notices (UAT 9 Nov 2026)", () => {
  it("keeps only the newest notice of each open Work Order as current", () => {
    const status: Record<string, string> = { open: "in_progress", done: "closed" };
    const ids = currentNoticeIds([
      row("old-open", "open", "2026-10-27T08:00:00Z"),
      row("new-open", "open", "2026-10-30T08:00:00Z", "work_order_approved"),
      row("done", "done", "2026-10-30T08:00:00Z", "work_order_closed"),
    ], (id) => status[id], now);
    expect([...ids]).toEqual(["new-open"]);
  });
  it("shows a closed Work Order's notice for two days, and today's payment reminder", () => {
    const ids = currentNoticeIds([
      row("just-closed", "done", "2026-11-08T12:00:00Z", "work_order_closed"),
      row("reminder-today", null, "2026-11-09T01:00:00Z", "finance_daily_reminder"),
      row("reminder-old", null, "2026-11-08T01:00:00Z", "finance_daily_reminder"),
    ], () => "closed", now);
    expect(ids.has("just-closed")).toBe(true);
    expect(ids.has("reminder-today")).toBe(true);
    expect(ids.has("reminder-old")).toBe(false);
  });
  it("puts the rest under Earlier notices and counts only current ones on the bell", () => {
    const list = readFileSync("components/notices/notices-list.tsx", "utf8");
    expect(list).toContain("Earlier notices (");
    expect(list).toContain("<details");
    expect(readFileSync("app/notices/page.tsx", "utf8")).toContain("currentNoticeIds(all,");
    expect(readFileSync("components/site-header.tsx", "utf8")).toContain("current.has(row.id)).length");
  });
});
