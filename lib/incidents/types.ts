import type { UserRole } from "@/lib/auth";
import { incidentStatusLabel } from "@/lib/product-terminology";

export const INCIDENT_TYPES = [
  "lift_entrapment", "fire", "flood", "major_water_leak",
  "electrical_failure", "gas_leak", "chemical_spill",
  "medical_emergency", "security", "other",
] as const;
export const INCIDENT_SEVERITIES = ["emergency", "critical", "high", "medium", "low"] as const;
export const INCIDENT_STATUSES = [
  "reported", "acknowledged", "mobilising", "on_site",
  "rescue_in_progress", "safe", "recovery", "closed", "cancelled",
] as const;
export const INCIDENT_ACTIONS = [
  "acknowledge", "mobilise", "arrive", "start_rescue",
  "make_safe", "start_recovery", "close", "cancel",
] as const;

export type IncidentType = (typeof INCIDENT_TYPES)[number];
export type IncidentSeverity = (typeof INCIDENT_SEVERITIES)[number];
export type IncidentStatus = (typeof INCIDENT_STATUSES)[number];
export type IncidentAction = (typeof INCIDENT_ACTIONS)[number];

export type IncidentRecord = {
  id: string; incident_number: string; incident_type: IncidentType;
  severity: IncidentSeverity; status: IncidentStatus; location: string;
  asset_id?: string | null;
  description: string; reported_by: string; reported_at: string;
  incident_commander_id: string | null; assigned_technician_id: string | null;
  assigned_team_id: string | null; acknowledgement_deadline: string;
  acknowledged_at: string | null; mobilising_at: string | null;
  on_site_at: string | null; rescue_started_at: string | null;
  safe_at: string | null; recovery_started_at: string | null;
  closed_at: string | null; created_at: string; updated_at: string;
  [key: string]: unknown;
};

export type IncidentContext = {
  role: UserRole; actorId: string; status: IncidentStatus;
  assignedTechnicianId: string | null; assignedTeamMember?: boolean;
};

export const INCIDENT_STATUS_LABELS: Record<IncidentStatus, string> = {
  reported: incidentStatusLabel("reported"), acknowledged: incidentStatusLabel("acknowledged"), mobilising: incidentStatusLabel("mobilising"),
  on_site: incidentStatusLabel("on_site"), rescue_in_progress: incidentStatusLabel("rescue_in_progress"), safe: incidentStatusLabel("safe"),
  recovery: incidentStatusLabel("recovery"), closed: incidentStatusLabel("closed"), cancelled: incidentStatusLabel("cancelled"),
};
