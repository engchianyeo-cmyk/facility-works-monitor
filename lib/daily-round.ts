/** M36 (owner D-67 D-G): the Daily round — shared types and helpers. */
export type RoundItem = { id: string; label: string; unit: string | null; position: number; active: boolean; min?: number | null; max?: number | null; guide?: string | null };
export type RoundCheck = { id: string; title: string; equipment: string | null; position: number; active: boolean; items: RoundItem[] };
export type RoundResult = { item_id: string; ok: boolean; reading: string | null; note: string | null; recorded_at: string; out_of_range?: boolean | null };

/** M38: "7.5", "-20", "−20" or "7,5" → number; anything else → null (same rule as the database). */
export function readingNumber(value: string): number | null {
  const text = value.trim();
  if (!/^[-−+]?\d+([.,]\d+)?$/.test(text)) return null;
  return Number(text.replace("−", "-").replace(",", "."));
}

/** M38: "6 – 8 °C", "at most 500 ppb", "at least 10 Pa"; null without a range. */
export function rangeText(item: Pick<RoundItem, "min" | "max" | "unit">): string | null {
  const unit = item.unit ? ` ${item.unit}` : "";
  if (item.min != null && item.max != null) return `${item.min} – ${item.max}${unit}`;
  if (item.max != null) return `at most ${item.max}${unit}`;
  if (item.min != null) return `at least ${item.min}${unit}`;
  return null;
}

/** M38: where a typed reading sits against the normal range. */
export function readingStatus(item: Pick<RoundItem, "min" | "max">, reading: string): "none" | "not-number" | "in" | "low" | "high" {
  if (item.min == null && item.max == null) return "none";
  if (!reading.trim()) return "none";
  const n = readingNumber(reading);
  if (n == null) return "not-number";
  if (item.min != null && n < item.min) return "low";
  if (item.max != null && n > item.max) return "high";
  return "in";
}
export type RoundSettings = { enabled: boolean; ready: string; due: string; technician_id: string | null; cover_id: string | null };

export const ROUND_EDITOR_ROLES = ["administrator", "facility_administrator", "facility_manager", "supervisor", "approver"] as const;

/** "07:00:00" → "07:00". */
export function hhmm(value: string | null | undefined): string {
  return (value ?? "").slice(0, 5);
}

/** Progress of a round: items recorded out of the active items, and Not OK count. */
export function roundProgress(checks: readonly RoundCheck[], results: readonly RoundResult[]) {
  const active = checks.filter((c) => c.active).flatMap((c) => c.items.filter((i) => i.active));
  const byItem = new Map(results.map((r) => [r.item_id, r]));
  const done = active.filter((i) => byItem.has(i.id)).length;
  const faults = active.filter((i) => byItem.get(i.id)?.ok === false).length;
  return { total: active.length, done, faults, complete: active.length > 0 && done === active.length };
}

/** Is the round late? Singapore time now is past the due time on the round's date and it is not closed. */
export function roundLate(date: string, due: string, status: string, now: Date = new Date()): boolean {
  if (["closed", "cancelled"].includes(status)) return false;
  const dueAt = new Date(`${date}T${hhmm(due) || "10:00"}:00+08:00`);
  return now.getTime() > dueAt.getTime();
}
