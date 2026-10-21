const ENUM_LABELS: Readonly<Record<string, string>> = {
  draft: "Draft",
  submitted: "Awaiting Approval",
  approved: "Approved",
  assigned: "Assigned",
  accepted: "Accepted",
  in_progress: "In Progress",
  completion_submitted: "Submitted for Review",
  completed: "Completed",
  done: "Completed",
  reviewed: "Completed",
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
  facility_manager: "Facility Manager",
  approver: "Approver",
  supervisor: "Supervisor",
  technician: "Technician",
  initiator: "Initiator",
  reviewer: "Reviewer",
  finance: "Finance",
};

const ROLE_CODES = new Set(["reviewer", "initiator", "approver", "technician", "supervisor", "facility_manager", "administrator", "finance"]);

/** Lifecycle v2 Work Order stage names (design §2). Stored status codes never change. */
const WORK_ORDER_STATUS_LABELS: Readonly<Record<string, string>> = {
  draft: "Draft",
  submitted: "Awaiting Approval",
  approved: "Approved",
  assigned: "Approved — Contractor to Proceed",
  in_progress: "Work in Progress",
  completed: "Submitted for Review",
  reviewed: "Completed",
  closed: "Closed",
  cancelled: "Cancelled",
};

/**
 * Company terminology chosen by the Administrator (table terminology_labels), keyed as
 * "role:<code>" or "status:<code>". Applied on the server by the root layout and on the
 * client by TerminologyBootstrap. One customer per deployment (PILOT_BOUNDARY.md).
 */
let terminologyOverrides: Readonly<Record<string, string>> = {};
export function applyTerminologyOverrides(labels: Record<string, string> | null | undefined) {
  terminologyOverrides = Object.freeze({ ...(labels ?? {}) });
}
export function terminologyOverride(code: string): string | undefined {
  return terminologyOverrides[code];
}
export function defaultWorkOrderStatusLabel(status: string): string {
  return WORK_ORDER_STATUS_LABELS[status] ?? operationalLabel(status);
}
export function defaultRoleLabel(role: string): string {
  return ENUM_LABELS[role] ?? operationalLabel(role);
}

/** Convert a stored enum or audit action into restrained, user-facing text. */
export function operationalLabel(value: string | null | undefined): string {
  if (!value) return "Not recorded";
  const normalized = value.trim().toLowerCase();
  if (ROLE_CODES.has(normalized) && terminologyOverrides[`role:${normalized}`]) return terminologyOverrides[`role:${normalized}`];
  if (ENUM_LABELS[normalized]) return ENUM_LABELS[normalized];
  const words = normalized.replaceAll("_", " ").replace(/\s+/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function workOrderStatusLabel(status: string): string {
  const normalized = status.trim().toLowerCase();
  return terminologyOverrides[`status:${normalized}`] ?? defaultWorkOrderStatusLabel(normalized);
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

export const TERMINOLOGY_ROLE_CODES = [...ROLE_CODES];
export const TERMINOLOGY_STATUS_CODES = Object.keys(WORK_ORDER_STATUS_LABELS);
