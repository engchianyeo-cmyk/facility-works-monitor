import type { WorkOrderAction, WorkOrderStatus } from "@/lib/work-orders/types";

export const WORKFLOW_TRANSITIONS: Record<
  Exclude<WorkOrderAction, "accept" | "cancel">,
  { from: readonly WorkOrderStatus[]; to: WorkOrderStatus }
> = {
  submit: { from: ["draft"], to: "submitted" },
  approve: { from: ["submitted"], to: "approved" },
  start: { from: ["assigned"], to: "in_progress" },
  complete: { from: ["in_progress"], to: "completed" },
  review: { from: ["completed"], to: "reviewed" },
  close: { from: ["reviewed"], to: "closed" },
};

export const CANCELLABLE_STATUSES: readonly WorkOrderStatus[] = [
  "draft",
  "submitted",
  "approved",
  "assigned",
  "in_progress",
  "completed",
  "reviewed",
];

export function getTransition(
  status: WorkOrderStatus,
  action: WorkOrderAction,
): { ok: true; to: WorkOrderStatus } | { ok: false; code: string } {
  if (action === "accept") {
    return status === "assigned"
      ? { ok: true, to: "assigned" }
      : { ok: false, code: "INVALID_TRANSITION" };
  }
  if (action === "cancel") {
    return CANCELLABLE_STATUSES.includes(status)
      ? { ok: true, to: "cancelled" }
      : { ok: false, code: "INVALID_TRANSITION" };
  }

  const transition = WORKFLOW_TRANSITIONS[action];
  if (!transition.from.includes(status)) {
    return { ok: false, code: "INVALID_TRANSITION" };
  }
  return { ok: true, to: transition.to };
}

export const STATUS_LABELS: Record<WorkOrderStatus, string> = {
  draft: "Draft",
  submitted: "Submitted",
  approved: "Approved",
  assigned: "Assigned",
  in_progress: "In Progress",
  completed: "Completed",
  reviewed: "Reviewed",
  closed: "Closed",
  cancelled: "Cancelled",
};
