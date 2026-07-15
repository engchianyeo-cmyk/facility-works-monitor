export type WorkOrderStatus =
  | "submitted"
  | "approved"
  | "in_progress"
  | "done"
  | "rejected";

export type WorkOrderAction = "approve" | "start" | "complete" | "reject";

const TRANSITIONS: Record<WorkOrderAction, { from: WorkOrderStatus[]; to: WorkOrderStatus }> = {
  approve: { from: ["submitted"], to: "approved" },
  start: { from: ["approved"], to: "in_progress" },
  complete: { from: ["in_progress"], to: "done" },
  reject: { from: ["submitted", "approved", "in_progress"], to: "rejected" },
};

export function nextStatus(
  current: WorkOrderStatus,
  action: WorkOrderAction,
): { ok: true; to: WorkOrderStatus } | { ok: false; error: string } {
  const rule = TRANSITIONS[action];
  if (!rule) {
    return { ok: false, error: `Unknown action: ${action}` };
  }
  if (!rule.from.includes(current)) {
    return {
      ok: false,
      error: `Cannot ${action} a work order that is "${current}". Valid from: ${rule.from.join(", ")}`,
    };
  }
  return { ok: true, to: rule.to };
}

export const STATUS_LABEL: Record<WorkOrderStatus, string> = {
  submitted: "Submitted",
  approved: "Approved",
  in_progress: "In Progress",
  done: "Done",
  rejected: "Rejected",
};

export const PRIORITY_LABEL: Record<string, string> = {
  low: "Low",
  medium: "Medium",
  high: "High",
  critical: "Critical",
};
