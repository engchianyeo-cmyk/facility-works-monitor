import type { IncidentAction, IncidentStatus } from "@/lib/incidents/types";

export const INCIDENT_TRANSITIONS: Record<IncidentAction, { from: readonly IncidentStatus[]; to: IncidentStatus }> = {
  acknowledge: { from: ["reported"], to: "acknowledged" },
  mobilise: { from: ["acknowledged"], to: "mobilising" },
  arrive: { from: ["mobilising"], to: "on_site" },
  start_rescue: { from: ["on_site"], to: "rescue_in_progress" },
  make_safe: { from: ["rescue_in_progress"], to: "safe" },
  start_recovery: { from: ["safe"], to: "recovery" },
  close: { from: ["recovery"], to: "closed" },
  cancel: { from: ["reported", "acknowledged", "mobilising", "on_site", "rescue_in_progress", "safe", "recovery"], to: "cancelled" },
};

export function canTransitionFrom(status: IncidentStatus, action: IncidentAction) {
  return INCIDENT_TRANSITIONS[action].from.includes(status);
}

