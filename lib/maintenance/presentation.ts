import { operationalLabel } from "@/lib/product-terminology";
import type { PmOccurrence, PmRequirement } from "./types";

export type PmExceptionKind = "generation_failed" | "overdue" | "due_soon_critical" | "generated_unassigned" | "repeatedly_deferred" | "decommissioned_asset" | "out_of_service_asset";
export type PmException = { kind: PmExceptionKind; rank: number; label: string; nextAction: string };
const EXCEPTIONS: Record<PmExceptionKind, Omit<PmException, "kind">> = {
  generation_failed: { rank: 1, label: "Generation failed", nextAction: "Review the failure and retry Work Order generation" },
  overdue: { rank: 2, label: "Overdue", nextAction: "Generate or progress the linked Work Order" },
  due_soon_critical: { rank: 3, label: "Due soon · Critical Asset", nextAction: "Confirm timing, access and ownership" },
  generated_unassigned: { rank: 4, label: "Generated · Unassigned", nextAction: "Assign the generated Work Order" },
  repeatedly_deferred: { rank: 5, label: "Repeatedly deferred", nextAction: "Review the recurring access or planning constraint" },
  decommissioned_asset: { rank: 6, label: "Decommissioned Asset conflict", nextAction: "Deactivate the requirement or cancel the occurrence" },
  out_of_service_asset: { rank: 7, label: "Out-of-service Asset decision required", nextAction: "Confirm whether maintenance should proceed" },
};

export function singaporeDate(date = new Date()) { return new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Singapore", year: "numeric", month: "2-digit", day: "2-digit" }).format(date); }
export function addDays(value: string, days: number) { const date = new Date(`${value}T00:00:00Z`); date.setUTCDate(date.getUTCDate() + days); return date.toISOString().slice(0, 10); }
export function formatPmDate(value: string | null | undefined) { if (!value) return "Not scheduled"; const date = new Date(`${value}T00:00:00Z`); return Number.isNaN(date.getTime()) ? "Unavailable" : new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeZone: "UTC" }).format(date); }
export function recurrenceLabel(revision: Pick<PmRequirement["current_revision"], "interval_value" | "interval_unit">) { const unit = operationalLabel(revision.interval_unit).toLowerCase(); return revision.interval_value === 1 ? `Every ${unit}` : `Every ${revision.interval_value} ${unit}s`; }
export function complianceLabel(value: string) { return operationalLabel(value); }
export function classifyPmException(occurrence: PmOccurrence, requirement: PmRequirement, today = singaporeDate()): PmException | null {
  const work = occurrence.work_order; const leadBoundary = addDays(today, requirement.current_revision.lead_time_days || 0);
  let kind: PmExceptionKind | null = null;
  if (occurrence.generation_status === "generation_failed") kind = "generation_failed";
  else if (occurrence.compliance_state === "overdue" || (occurrence.current_due_date < today && !["completed_on_time", "completed_late", "cancelled"].includes(occurrence.compliance_state ?? ""))) kind = "overdue";
  else if (requirement.asset.criticality === "critical" && occurrence.current_due_date >= today && occurrence.current_due_date <= leadBoundary) kind = "due_soon_critical";
  else if (occurrence.generation_status === "generated" && work && !work.assigned_technician_id && !work.assigned_vendor_id && !work.assigned_team_id && !work.assigned_to && !["completed", "reviewed", "closed", "cancelled"].includes(work.status)) kind = "generated_unassigned";
  else if ((occurrence.deferral_count ?? 0) > 1 || occurrence.repeatedly_deferred) kind = "repeatedly_deferred";
  else if (requirement.state === "active" && requirement.asset.lifecycle_status === "decommissioned") kind = "decommissioned_asset";
  else if (requirement.state === "active" && requirement.asset.lifecycle_status === "out_of_service") kind = "out_of_service_asset";
  return kind ? { kind, ...EXCEPTIONS[kind] } : null;
}
export function comparePmExceptions(a: { exception: PmException; occurrence: PmOccurrence }, b: { exception: PmException; occurrence: PmOccurrence }) { return a.exception.rank - b.exception.rank || a.occurrence.current_due_date.localeCompare(b.occurrence.current_due_date); }
