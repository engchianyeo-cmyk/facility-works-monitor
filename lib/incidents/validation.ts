import { INCIDENT_ACTIONS, INCIDENT_SEVERITIES, INCIDENT_STATUSES, INCIDENT_TYPES, type IncidentAction, type IncidentSeverity, type IncidentStatus, type IncidentType } from "@/lib/incidents/types";

export const isIncidentType = (value: unknown): value is IncidentType => INCIDENT_TYPES.includes(value as IncidentType);
export const isIncidentSeverity = (value: unknown): value is IncidentSeverity => INCIDENT_SEVERITIES.includes(value as IncidentSeverity);
export const isIncidentStatus = (value: unknown): value is IncidentStatus => INCIDENT_STATUSES.includes(value as IncidentStatus);
export const isIncidentAction = (value: unknown): value is IncidentAction => INCIDENT_ACTIONS.includes(value as IncidentAction);

export const INCIDENT_PHASE_ACTIONS = {
  mobilising: "mobilise",
  on_site: "arrive",
  rescue_in_progress: "start_rescue",
  safe: "make_safe",
  recovery: "start_recovery",
} as const;

export type IncidentPhase = keyof typeof INCIDENT_PHASE_ACTIONS;
export const isIncidentPhase = (value: unknown): value is IncidentPhase =>
  typeof value === "string" && value in INCIDENT_PHASE_ACTIONS;

export const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
