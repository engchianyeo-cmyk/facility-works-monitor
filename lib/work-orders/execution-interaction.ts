import type { WorkOrderAction, WorkOrderStatus } from "@/lib/work-orders/types";

export const EXECUTION_ACTIONS: Record<WorkOrderStatus, { action: WorkOrderAction; label: string }[]> = {
  draft: [{ action: "submit", label: "Submit for approval" }],
  submitted: [{ action: "approve", label: "Approve Work Order" }],
  approved: [],
  assigned: [{ action: "accept", label: "Accept assignment" }, { action: "start", label: "Start work" }],
  in_progress: [{ action: "complete", label: "Record completion" }],
  completed: [
    { action: "review", label: "Accept completion" },
    { action: "return_for_rework", label: "Return for rework" },
  ],
  reviewed: [{ action: "close", label: "Close Work Order" }],
  closed: [],
  cancelled: [],
};

export const EXECUTION_SUCCESS: Partial<Record<WorkOrderAction, string>> = {
  submit: "The server confirmed that this Work Order is awaiting approval.",
  approve: "The server confirmed that this Work Order is approved.",
  accept: "The server confirmed your assignment acceptance.",
  start: "The server confirmed that work is In Progress.",
  complete: "The server confirmed completion. Supervisor review remains outstanding.",
  review: "The server confirmed that the completion was accepted.",
  return_for_rework: "The server returned this Work Order for rework.",
  close: "The server confirmed that this Work Order is Closed.",
  cancel: "The server confirmed that this Work Order is Cancelled.",
};

export function authorizedExecutionActions(status: string, allowed: readonly WorkOrderAction[]) {
  return (EXECUTION_ACTIONS[status as WorkOrderStatus] ?? []).filter(({ action }) => allowed.includes(action));
}

export function validateCompletionDraft(completionNotes: string, actualHours: string) {
  const notes = completionNotes.trim();
  const hours = Number(actualHours);
  if (!notes) return { ok: false as const, error: "Completion notes are required." };
  if (actualHours === "" || !Number.isFinite(hours) || hours < 0) return { ok: false as const, error: "Labour hours must be zero or greater." };
  return { ok: true as const, payload: { completion_notes: notes, actual_labour_hours: hours } };
}

export function executionResponseMessage(status: number, result: Record<string, unknown>) {
  if (status === 401) return "Your session is no longer active. Sign in again, then retry this action.";
  if (status === 403) return "You are not authorized to perform this action. The Work Order was not changed.";
  const safe = typeof result.message === "string" ? result.message : typeof result.error === "string" ? result.error : null;
  if (status >= 500) return "The workflow service is temporarily unavailable. Nothing was submitted. Retry when the service is available.";
  return safe || "The server rejected this action. Review the information and retry.";
}
