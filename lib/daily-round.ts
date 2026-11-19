/** M36 (owner D-67 D-G): the Daily round — shared types and helpers. */
export type RoundItem = { id: string; label: string; unit: string | null; position: number; active: boolean };
export type RoundCheck = { id: string; title: string; equipment: string | null; position: number; active: boolean; items: RoundItem[] };
export type RoundResult = { item_id: string; ok: boolean; reading: string | null; note: string | null; recorded_at: string };
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
