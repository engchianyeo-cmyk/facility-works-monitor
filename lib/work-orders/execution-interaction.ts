import type { WorkOrderAction, WorkOrderStatus } from "@/lib/work-orders/types";

export const EXECUTION_ACTIONS: Record<WorkOrderStatus, { action: WorkOrderAction; label: string }[]> = {
  draft: [{ action: "submit", label: "Submit for approval" }],
  submitted: [
    { action: "approve", label: "Approve Work and Quotation" },
    { action: "return", label: "Return to Draft" },
  ],
  approved: [{ action: "accept_responsibility", label: "Accept Work / Take Responsibility" }],
  assigned: [
    { action: "submit_physical_completion", label: "Submit Physical Completion" },
    { action: "start", label: "Start work" },
    { action: "accept", label: "Accept assignment" },
  ],
  in_progress: [{ action: "submit_physical_completion", label: "Submit Physical Completion" }],
  completed: [
    { action: "review", label: "Approve as Completed" },
    { action: "return_for_rework", label: "Reject & Reopen" },
  ],
  reviewed: [{ action: "close", label: "Close Work Order" }],
  closed: [],
  cancelled: [],
};

export const EXECUTION_SUCCESS: Partial<Record<WorkOrderAction, string>> = {
  submit: "The server confirmed that this Work Order was submitted. Emergency work starts immediately; other work awaits approval.",
  approve: "The server confirmed the approval. The contractor may proceed.",
  return: "The server returned this Work Order to Draft for the preparer to revise.",
  accept_responsibility: "The server confirmed your field responsibility.",
  accept: "The server confirmed your assignment acceptance.",
  start: "The server confirmed that work is In Progress.",
  complete: "The server confirmed the Work Order was submitted for review.",
  review: "The server confirmed the work, final cost and documents are approved. The Work Order is Completed.",
  return_for_rework: "The server rejected the Completed Work and reopened this Work Order for rework.",
  close: "The server confirmed that this Work Order is Closed.",
  cancel: "The server confirmed that this Work Order is Cancelled.",
};

export const WORK_RECORD_SUCCESS = "Work record saved. Awaiting authorised completion.";

export function authorizedExecutionActions(status: string, allowed: readonly WorkOrderAction[]) {
  return (EXECUTION_ACTIONS[status as WorkOrderStatus] ?? []).filter(({ action }) => allowed.includes(action));
}

export function validateWorkRecordDraft(completionNotes: string, actualHours: string) {
  const notes = completionNotes.trim();
  const hours = Number(actualHours);
  if (!notes) return { ok: false as const, error: "Work performed statement is required." };
  if (actualHours === "" || !Number.isFinite(hours) || hours < 0) return { ok: false as const, error: "Labour hours must be zero or greater." };
  return { ok: true as const, payload: { completion_notes: notes, actual_labour_hours: hours } };
}

export const validateCompletionDraft = validateWorkRecordDraft;

export function executionResponseMessage(status: number, result: Record<string, unknown>) {
  if (status === 401) return "Your session is no longer active. Sign in again, then retry this action.";
  if (status === 403) {
    const code = typeof result.code === "string" ? result.code : "";
    if (["APPROVAL_AUTHORITY_EXCEEDED", "SELF_APPROVAL_DENIED", "SELF_REVIEW_DENIED"].includes(code) && typeof result.message === "string") {
      return `${result.message} The Work Order was not changed.`;
    }
    return "You are not authorized to perform this action. The Work Order was not changed.";
  }
  const safe = typeof result.message === "string" ? result.message : typeof result.error === "string" ? result.error : null;
  if (status >= 500) return "The workflow service is temporarily unavailable. Nothing was submitted. Retry when the service is available.";
  return safe || "The server rejected this action. Review the information and retry.";
}
