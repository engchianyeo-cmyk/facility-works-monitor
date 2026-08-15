import type { UserRole } from "@/lib/auth";

export const PM_INTERVAL_UNITS = ["day", "week", "month", "year"] as const;
export const PM_MAINTENANCE_TYPES = ["preventive", "inspection"] as const;

export type PmAsset = { id: string; asset_tag: string; name: string; criticality: string; lifecycle_status: string; site: string; location: string; system?: { system_code: string; name: string } | null };
export type PmRevision = { id: string; revision_number: number; title: string; scope: string; maintenance_type: string; interval_value: number; interval_unit: string; first_due_date: string; lead_time_days: number; default_priority: string; estimated_hours: number | null; evidence_guidance: string | null; instructions: string | null; procedure_reference: string | null; effective_date: string; created_at?: string; department_id?: string | null; responsible_team_id?: string | null; department?: { code: string; name: string } | null; responsible_team?: { name: string } | null };
export type PmWorkOrder = { id: string; work_order_number: string; title?: string; status: string; due_date?: string | null; assigned_technician_id?: string | null; assigned_vendor_id?: string | null; assigned_team_id?: string | null; assigned_to?: string | null };
export type PmOccurrence = { id: string; requirement_id: string; requirement_revision_id: string; occurrence_number: number; original_due_date: string; current_due_date: string; generation_status: string; generation_attempts: number; last_generation_error_code: string | null; cancellation_reason?: string | null; cancelled_at?: string | null; compliance_state?: string; deferral_count?: number; deferred?: boolean; repeatedly_deferred?: boolean; work_order?: PmWorkOrder | null; asset?: PmAsset; requirement?: { requirement_number: string; state: string; current_revision?: PmRevision | null } };
export type PmRequirement = { id: string; requirement_number: string; state: string; current_revision_id: string; asset: PmAsset; current_revision: PmRevision };
export type PmDeferral = { id: string; sequence_number: number; previous_due_date: string; revised_due_date: string; reason: string; deferred_at: string; deferred_by?: string };
export type PmRpcResult = { ok: boolean; code?: string; message?: string; requirement?: Record<string, unknown>; revision?: Record<string, unknown>; occurrence?: Record<string, unknown>; deferral?: Record<string, unknown>; work_order?: Record<string, unknown>; created_occurrences?: number; generated?: number; failed?: number; cancelled_occurrences?: number };

export function canManagePm(role: UserRole) { return role === "supervisor" || role === "administrator"; }
export function canCancelPm(role: UserRole) { return role === "administrator"; }

const APPROVED_PAYLOAD_FIELDS = ["asset_id", "title", "scope", "maintenance_type", "interval_value", "interval_unit", "first_due_date", "effective_date", "lead_time_days", "default_priority", "department_id", "responsible_team_id", "estimated_hours", "instructions", "evidence_guidance", "procedure_reference"] as const;
export function approvedPmPayload(input: Record<string, unknown>) {
  return Object.fromEntries(APPROVED_PAYLOAD_FIELDS.filter((key) => Object.hasOwn(input, key)).map((key) => [key, input[key]]));
}
