const ENUM_LABELS: Readonly<Record<string, string>> = {
  draft: "Draft",
  submitted: "Awaiting Approval",
  approved: "Approved",
  assigned: "Assigned",
  accepted: "Accepted",
  in_progress: "In Progress",
  completion_submitted: "Completed — Awaiting Review",
  completed: "Completed — Awaiting Review",
  done: "Completed",
  reviewed: "Reviewed",
  verified: "Verified",
  closed: "Closed",
  cancelled: "Cancelled",
  rejected: "Rejected",
  blocked: "Blocked",
  overdue: "Overdue",
  due: "Due",
  critical: "Critical",
  low: "Low",
  medium: "Medium",
  high: "High",
  emergency: "Emergency",
  reported: "Reported",
  acknowledged: "Acknowledged",
  mobilising: "Mobilising",
  on_site: "On Site",
  rescue_in_progress: "Rescue In Progress",
  safe: "Safe",
  recovery: "Recovery",
  queued: "Queued",
  delivered: "Delivered",
  failed: "Failed",
  unavailable: "Unavailable",
  not_configured: "Not Configured",
  active: "Active",
  inactive: "Inactive",
  preventive: "Preventive",
  inspection: "Inspection",
  generation_failed: "Generation Failed",
  generated: "Generated",
  scheduled: "Scheduled",
  deferred: "Deferred",
  completed_on_time: "Completed On Time",
  completed_late: "Completed Late",
  out_of_service: "Out of Service",
  decommissioned: "Decommissioned",
  administrator: "Administrator",
  approver: "Approver",
  supervisor: "Supervisor",
  technician: "Technician",
  initiator: "Initiator",
  reviewer: "Reviewer",
};

/** Convert a stored enum or audit action into restrained, user-facing text. */
export function operationalLabel(value: string | null | undefined): string {
  if (!value) return "Not recorded";
  const normalized = value.trim().toLowerCase();
  if (ENUM_LABELS[normalized]) return ENUM_LABELS[normalized];
  const words = normalized.replaceAll("_", " ").replace(/\s+/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function workOrderStatusLabel(status: string): string {
  return operationalLabel(status);
}

export function priorityLabel(priority: string): string {
  return operationalLabel(priority);
}

export function incidentStatusLabel(status: string): string {
  return operationalLabel(status);
}

export function incidentTypeLabel(type: string): string {
  return operationalLabel(type);
}

export function roleLabel(role: string): string {
  return operationalLabel(role);
}
