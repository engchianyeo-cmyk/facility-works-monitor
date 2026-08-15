export type CompletionSnapshot = {
  cycle: number;
  reason: string;
  actor: string;
  returnedAt: string;
  completionNotes: string | null;
  cumulativeLabourHours: number | null;
  completedAt: string | null;
  evidenceIds: string[];
};

type ActivityRow = {
  action?: unknown;
  actor?: unknown;
  note?: unknown;
  created_at?: unknown;
};

function objectValue(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) return value as Record<string, unknown>;
  if (typeof value !== "string") return null;
  try {
    const parsed: unknown = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

export function reworkHistory(activity: readonly ActivityRow[]): CompletionSnapshot[] {
  return activity.flatMap((row) => {
    if (row.action !== "work_order_returned_for_rework") return [];
    const note = objectValue(row.note);
    const previous = objectValue(note?.previous_completion);
    const reason = stringValue(note?.reason);
    if (!note || !reason) return [];
    return [{
      cycle: numberValue(note.cycle) ?? 1,
      reason,
      actor: stringValue(row.actor) ?? "Reviewer unavailable",
      returnedAt: stringValue(row.created_at) ?? "",
      completionNotes: stringValue(previous?.completion_notes),
      cumulativeLabourHours: numberValue(previous?.cumulative_labour_hours),
      completedAt: stringValue(previous?.completed_at),
      evidenceIds: Array.isArray(previous?.evidence_ids)
        ? previous.evidence_ids.filter((value): value is string => typeof value === "string")
        : [],
    }];
  }).sort((left, right) => right.cycle - left.cycle);
}

export function activeReworkContext(
  status: string,
  activity: readonly ActivityRow[],
): CompletionSnapshot | null {
  if (status !== "in_progress") return null;
  const latestLifecycle = activity.find((row) => [
    "work_order_returned_for_rework",
    "work_order_completed",
    "work_order_completion_reviewed",
  ].includes(String(row.action)));
  if (latestLifecycle?.action !== "work_order_returned_for_rework") return null;
  return reworkHistory([latestLifecycle])[0] ?? null;
}
