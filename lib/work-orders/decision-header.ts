import {
  incidentStatusLabel,
  operationalLabel,
  priorityLabel,
  workOrderStatusLabel,
} from "@/lib/product-terminology";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TERMINAL_STATUSES = new Set(["done", "reviewed", "verified", "closed", "cancelled", "rejected"]);
const ASSIGNMENT_EXPECTED_STATUSES = new Set(["approved", "assigned", "in_progress", "completion_submitted", "completed"]);
const INCIDENT_ACTIVE_STATUSES = new Set(["reported", "acknowledged", "mobilising", "on_site", "rescue_in_progress", "safe", "recovery"]);
const DUE_SOON_DAYS = 3;

export type OwnershipState = "assigned" | "unassigned" | "unavailable";
export type DueExposureState = "overdue" | "today" | "soon" | "future" | "recorded" | "none" | "unavailable";
export type EvidenceState = "available" | "none" | "unavailable";
export type ExceptionKind = "critical" | "rework" | "overdue" | "unassigned" | "incident" | "unavailable" | "review" | "approval";

export type OwnershipPresentation = {
  state: OwnershipState;
  label: string;
  detail: string;
};

export type DueExposure = {
  state: DueExposureState;
  label: string;
  detail: string;
  actionable: boolean;
};

export type DecisionException = {
  kind: ExceptionKind;
  label: string;
  detail: string;
  rank: number;
};

export type RelatedIncidentPresentation = {
  available: boolean;
  reference: string | null;
  severity: string | null;
  status: string | null;
  active: boolean;
};

export type EvidencePresentation = {
  state: EvidenceState;
  label: string;
};

export type WorkOrderDecisionModel = {
  priority: string;
  status: string;
  ownership: OwnershipPresentation;
  due: DueExposure;
  exceptions: DecisionException[];
  incident: RelatedIncidentPresentation | null;
  evidence: EvidencePresentation;
};

function parseDateOnly(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const milliseconds = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  const parsed = new Date(milliseconds);
  if (parsed.toISOString().slice(0, 10) !== value) return null;
  return milliseconds;
}

function formatDateOnly(value: string) {
  const milliseconds = parseDateOnly(value);
  if (milliseconds === null) return null;
  return new Intl.DateTimeFormat("en-SG", {
    dateStyle: "medium",
    timeZone: "UTC",
  }).format(new Date(milliseconds));
}

export function isUuidLike(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value.trim());
}

export function safeHumanLabel(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const label = value.trim();
  return label && !isUuidLike(label) ? label : null;
}

export function ownershipPresentation(input: {
  assignedTechnicianId?: string | null;
  assignedVendorId?: string | null;
  assignedTeamId?: string | null;
  recordedAssignee?: unknown;
  resolvedAssignee?: unknown;
}): OwnershipPresentation {
  const hasAssignment = Boolean(
    input.assignedTechnicianId
      || input.assignedVendorId
      || input.assignedTeamId
      || (typeof input.recordedAssignee === "string" && input.recordedAssignee.trim()),
  );
  if (!hasAssignment) {
    return { state: "unassigned", label: "Unassigned", detail: "No primary owner is recorded." };
  }
  const assignee = safeHumanLabel(input.resolvedAssignee) ?? safeHumanLabel(input.recordedAssignee);
  if (!assignee) {
    return { state: "unavailable", label: "Assignment unavailable", detail: "A primary assignment exists, but its display name is unavailable." };
  }
  return { state: "assigned", label: "Assigned", detail: assignee };
}

export function dueExposure(input: {
  dueDate: string | null | undefined;
  status: string;
  today: string;
}): DueExposure {
  if (input.dueDate === undefined) {
    return { state: "unavailable", label: "Due date unavailable", detail: "Due-date information could not be determined.", actionable: true };
  }
  if (input.dueDate === null || input.dueDate === "") {
    return { state: "none", label: "No due date", detail: "No due date is recorded.", actionable: false };
  }
  const due = parseDateOnly(input.dueDate);
  const today = parseDateOnly(input.today);
  const formatted = formatDateOnly(input.dueDate);
  if (due === null || today === null || formatted === null) {
    return { state: "unavailable", label: "Due date unavailable", detail: "The recorded due date cannot be interpreted.", actionable: true };
  }
  if (TERMINAL_STATUSES.has(input.status)) {
    return { state: "recorded", label: `Due date was ${formatted}`, detail: "This Work Order is no longer active.", actionable: false };
  }
  const days = Math.round((due - today) / 86_400_000);
  if (days < 0) {
    const unit = Math.abs(days) === 1 ? "day" : "days";
    return { state: "overdue", label: `Overdue by ${Math.abs(days)} ${unit}`, detail: `Due ${formatted}`, actionable: true };
  }
  if (days === 0) return { state: "today", label: "Due today", detail: formatted, actionable: true };
  if (days <= DUE_SOON_DAYS) {
    const unit = days === 1 ? "day" : "days";
    return { state: "soon", label: `Due soon · ${days} ${unit}`, detail: `Due ${formatted}`, actionable: true };
  }
  return { state: "future", label: `Due ${formatted}`, detail: `${days} days remaining`, actionable: false };
}

export function incidentPresentation(input: {
  linked: boolean;
  reference?: unknown;
  severity?: unknown;
  status?: unknown;
}): RelatedIncidentPresentation | null {
  if (!input.linked) return null;
  const reference = safeHumanLabel(input.reference);
  const status = safeHumanLabel(input.status);
  const severity = safeHumanLabel(input.severity);
  return {
    available: Boolean(reference && status),
    reference,
    severity: severity ? operationalLabel(severity) : null,
    status: status ? incidentStatusLabel(status) : null,
    active: Boolean(status && INCIDENT_ACTIVE_STATUSES.has(status.toLowerCase())),
  };
}

export function evidencePresentation(count: number | null | undefined): EvidencePresentation {
  if (count === undefined) return { state: "unavailable", label: "Evidence availability unavailable" };
  if (!count) return { state: "none", label: "No evidence attached" };
  return { state: "available", label: `Evidence available: ${count} ${count === 1 ? "item" : "items"}` };
}

export function decisionExceptions(input: {
  priority: string;
  status: string;
  ownership: OwnershipPresentation;
  due: DueExposure;
  incident: RelatedIncidentPresentation | null;
  evidence: EvidencePresentation;
  reworkReason?: string | null;
}): DecisionException[] {
  const exceptions: DecisionException[] = [];
  if (input.priority.toLowerCase() === "critical" && !TERMINAL_STATUSES.has(input.status)) {
    exceptions.push({ kind: "critical", label: "Critical priority", detail: "This Work Order carries the highest recorded priority.", rank: 10 });
  }
  if (input.status === "in_progress" && input.reworkReason) {
    exceptions.push({ kind: "rework", label: "Returned for rework", detail: input.reworkReason, rank: 15 });
  }
  if (input.due.state === "overdue") {
    exceptions.push({ kind: "overdue", label: input.due.label, detail: input.due.detail, rank: 20 });
  }
  if (input.ownership.state === "unassigned" && ASSIGNMENT_EXPECTED_STATUSES.has(input.status)) {
    exceptions.push({ kind: "unassigned", label: "Unassigned", detail: "No primary owner is recorded.", rank: 30 });
  }
  if (input.incident?.active) {
    exceptions.push({ kind: "incident", label: "Active related incident", detail: input.incident.reference ?? "Incident details unavailable", rank: 40 });
  }
  if (input.ownership.state === "unavailable" || input.due.state === "unavailable" || input.evidence.state === "unavailable" || (input.incident && !input.incident.available)) {
    exceptions.push({ kind: "unavailable", label: "Decision information unavailable", detail: "One or more supporting details could not be verified.", rank: 50 });
  }
  if (["completion_submitted", "completed"].includes(input.status)) {
    exceptions.push({ kind: "review", label: "Awaiting review", detail: "Physical completion is recorded; review remains outstanding.", rank: 60 });
  }
  if (input.status === "submitted") {
    exceptions.push({ kind: "approval", label: "Awaiting approval", detail: "Approval remains outstanding.", rank: 70 });
  }
  return exceptions.sort((left, right) => left.rank - right.rank);
}

export function buildWorkOrderDecisionModel(input: {
  priority: string;
  status: string;
  dueDate: string | null | undefined;
  today: string;
  assignedTechnicianId?: string | null;
  assignedVendorId?: string | null;
  assignedTeamId?: string | null;
  recordedAssignee?: unknown;
  resolvedAssignee?: unknown;
  incidentLinked?: boolean;
  incidentReference?: unknown;
  incidentSeverity?: unknown;
  incidentStatus?: unknown;
  evidenceCount?: number | null;
  reworkReason?: string | null;
}): WorkOrderDecisionModel {
  const ownership = ownershipPresentation(input);
  const due = dueExposure(input);
  const incident = incidentPresentation({
    linked: Boolean(input.incidentLinked),
    reference: input.incidentReference,
    severity: input.incidentSeverity,
    status: input.incidentStatus,
  });
  const evidence = evidencePresentation(input.evidenceCount);
  return {
    priority: priorityLabel(input.priority),
    status: workOrderStatusLabel(input.status),
    ownership,
    due,
    incident,
    evidence,
    exceptions: decisionExceptions({ priority: input.priority, status: input.status, ownership, due, incident, evidence, reworkReason: input.reworkReason }),
  };
}
