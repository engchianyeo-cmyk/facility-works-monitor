import type { IncidentAction, IncidentContext } from "@/lib/incidents/types";

export function canReportIncident(role: IncidentContext["role"]) { return role !== "technician"; }
export function canManageRoster(role: IncidentContext["role"]) { return role === "administrator" || role === "supervisor"; }
export function canActOnIncident(action: IncidentAction, context: IncidentContext) {
  if (context.role === "administrator") return true;
  if ((action === "close" || action === "cancel") && context.role === "supervisor") return true;
  return context.role === "technician" &&
    (context.actorId === context.assignedTechnicianId || context.assignedTeamMember === true);
}

