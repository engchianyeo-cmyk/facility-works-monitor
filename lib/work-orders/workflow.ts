import type { WorkOrderAction, WorkOrderStatus } from "@/lib/work-orders/types";
import { workOrderStatusLabel } from "@/lib/product-terminology";

export const WORKFLOW_TRANSITIONS: Record<
  Exclude<WorkOrderAction, "accept" | "cancel">,
  { from: readonly WorkOrderStatus[]; to: WorkOrderStatus }
> = {
  submit: { from: ["draft"], to: "submitted" },
  approve: { from: ["submitted"], to: "approved" },
  start: { from: ["assigned"], to: "in_progress" },
  complete: { from: ["in_progress"], to: "completed" },
  review: { from: ["completed"], to: "reviewed" },
  return_for_rework: { from: ["completed"], to: "in_progress" },
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
  draft: workOrderStatusLabel("draft"),
  submitted: workOrderStatusLabel("submitted"),
  approved: workOrderStatusLabel("approved"),
  assigned: workOrderStatusLabel("assigned"),
  in_progress: workOrderStatusLabel("in_progress"),
  completed: workOrderStatusLabel("completed"),
  reviewed: workOrderStatusLabel("reviewed"),
  closed: workOrderStatusLabel("closed"),
  cancelled: workOrderStatusLabel("cancelled"),
};
