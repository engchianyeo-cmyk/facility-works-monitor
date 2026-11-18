/** M35 (owner D-67 A): how far a planned date may move either way; mirrors public.pm_window_days. */
export function pmWindowDays(value: number, unit: string): number {
  if (unit === "day") return 0;
  if (unit === "week" && value === 1) return 1;
  if (unit === "month" && value === 1) return 3;
  if (unit === "month" && value === 3) return 7;
  if (unit === "month" && value === 6) return 14;
  if ((unit === "month" && value === 12) || (unit === "year" && value === 1)) return 21;
  const days = value * (unit === "week" ? 7 : unit === "month" ? 30 : unit === "year" ? 365 : 1);
  return Math.min(21, Math.floor(days / 10));
}

export function addDays(iso: string, days: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d + days));
  return date.toISOString().slice(0, 10);
}

export const PM_MODES = [
  { id: "off", label: "Off", help: "No dates, no Work Orders, no reminders. The plan stays on file." },
  { id: "plan_only", label: "Plan only", help: "Dates and reminders are shown; no Work Orders are created and nothing counts as overdue." },
  { id: "full_critical", label: "Full for critical equipment only", help: "Work Orders are created on the day for critical equipment; the rest is shown as a plan." },
  { id: "full", label: "Full", help: "Work Orders are created automatically on the day, already assigned; overdue work is tracked." },
] as const;
export type PmMode = (typeof PM_MODES)[number]["id"];

/** Whether this facility's setting turns a due task into a Work Order (mirrors public.pm_creates_work). */
export function pmCreatesWork(mode: string | null | undefined, criticality: string): boolean {
  return mode === "full" || (mode === "full_critical" && criticality === "critical");
}
