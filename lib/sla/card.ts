/**
 * D-45 (9 Nov 2026): the site's approved SLA targets in plain words, and where a Work Order stands against them.
 */
export type SlaRuleRow = {
  id: string;
  priority_class: string;
  work_order_priority: string;
  acknowledgement_minutes: number | null;
  response_minutes: number | null;
  attendance_minutes: number | null;
  make_safe_minutes: number | null;
  rectification_minutes: number;
  kpi_target_percent: number;
  source_clause: string;
  service_category: { code: string; name: string } | null;
  version: { version_number: number; effective_from: string; effective_to: string | null; agreement: { name: string; counterparty: string | null } | null } | null;
};

export const SLA_STAGES = [
  { key: "acknowledgement", label: "Acknowledge", meaning: "Someone confirms the request has been seen and is being handled." },
  { key: "response", label: "Respond", meaning: "The responsible person contacts the requester with a plan." },
  { key: "attendance", label: "Attend on site", meaning: "A Technician or contractor is at the location." },
  { key: "make_safe", label: "Make safe", meaning: "The danger or damage is contained (isolated, barricaded, leak stopped)." },
  { key: "rectification", label: "Fix", meaning: "The fault is repaired and the asset is back in service." },
] as const;

export type SlaStageKey = (typeof SLA_STAGES)[number]["key"];

const PRIORITY_ORDER: Record<string, number> = { critical: 0, high: 1, medium: 2, low: 3 };

/** "15 min", "2 h", "1 h 30 min", "2 days", "1 day 4 h". */
export function durationLabel(minutes: number | null | undefined): string {
  if (minutes === null || minutes === undefined) return "—";
  const m = Math.max(0, Math.round(minutes));
  const days = Math.floor(m / 1440); const hours = Math.floor((m % 1440) / 60); const mins = m % 60;
  const parts = [days ? `${days} day${days > 1 ? "s" : ""}` : "", hours ? `${hours} h` : "", mins ? `${mins} min` : ""].filter(Boolean);
  return parts.length ? parts.slice(0, 2).join(" ") : "0 min";
}

export function ruleMinutes(rule: SlaRuleRow, stage: SlaStageKey): number | null {
  return stage === "acknowledgement" ? rule.acknowledgement_minutes : stage === "response" ? rule.response_minutes
    : stage === "attendance" ? rule.attendance_minutes : stage === "make_safe" ? rule.make_safe_minutes : rule.rectification_minutes;
}

/** Rules grouped by service category, most urgent priority first. */
export function groupRules(rules: SlaRuleRow[]): Array<{ category: string; rules: SlaRuleRow[] }> {
  const groups = new Map<string, SlaRuleRow[]>();
  for (const rule of rules) {
    const name = rule.service_category?.name ?? "General";
    groups.set(name, [...(groups.get(name) ?? []), rule]);
  }
  return Array.from(groups.entries()).sort(([a], [b]) => a.localeCompare(b))
    .map(([category, list]) => ({ category, rules: list.sort((x, y) => (PRIORITY_ORDER[x.work_order_priority] ?? 9) - (PRIORITY_ORDER[y.work_order_priority] ?? 9)) }));
}

export type SlaClockRow = {
  started_at: string;
  acknowledgement_deadline: string | null; response_deadline: string | null; attendance_deadline: string | null;
  make_safe_deadline: string | null; rectification_deadline: string | null;
  acknowledged_at: string | null; responded_at: string | null; attended_at: string | null; made_safe_at: string | null; rectified_at: string | null;
};

export type StageStatus = { key: SlaStageKey; label: string; deadline: string; doneAt: string | null;
  state: "met" | "missed" | "on_track" | "at_risk" | "breached"; leftMinutes: number };

/** Each stage with a deadline: met or missed once done; otherwise on track, at risk (75% of the time used) or breached. */
export function clockStages(clock: SlaClockRow, now = Date.now()): StageStatus[] {
  const start = new Date(clock.started_at).getTime();
  const done: Record<SlaStageKey, string | null> = { acknowledgement: clock.acknowledged_at, response: clock.responded_at, attendance: clock.attended_at,
    make_safe: clock.made_safe_at, rectification: clock.rectified_at };
  const due: Record<SlaStageKey, string | null> = { acknowledgement: clock.acknowledgement_deadline, response: clock.response_deadline,
    attendance: clock.attendance_deadline, make_safe: clock.make_safe_deadline, rectification: clock.rectification_deadline };
  return SLA_STAGES.flatMap((stage) => {
    const deadline = due[stage.key];
    if (!deadline) return [];
    const end = new Date(deadline).getTime();
    const doneAt = done[stage.key];
    if (doneAt) return [{ key: stage.key, label: stage.label, deadline, doneAt, state: new Date(doneAt).getTime() <= end ? "met" : "missed", leftMinutes: 0 } as StageStatus];
    const left = Math.round((end - now) / 60_000);
    const used = (now - start) / Math.max(1, end - start);
    return [{ key: stage.key, label: stage.label, deadline, doneAt: null, state: left < 0 ? "breached" : used >= 0.75 ? "at_risk" : "on_track", leftMinutes: left } as StageStatus];
  });
}

/** Once the Work Order is finished, open stages stop counting. */
export function clockFinished(status: string) {
  return ["completed", "reviewed", "closed", "cancelled"].includes(status);
}
