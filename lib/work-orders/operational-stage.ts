import type { WorkOrderStatus } from "@/lib/work-orders/types";

export type CompletionReadiness = {
  workRecordReceived: boolean;
  labourHoursRecorded: boolean;
  activeAfterEvidence: boolean;
  ready: boolean;
};

export type OperationalStage = {
  label: string;
  nextAction: string | null;
  completion: CompletionReadiness;
};

export function deriveWorkOrderOperationalStage(input: {
  status: WorkOrderStatus;
  startedAt?: string | null;
  completionNotes?: string | null;
  actualLabourHours?: number | null;
  evidence?: Array<{ category: string | null; deleted_at: string | null }>;
}): OperationalStage {
  const workRecordReceived = Boolean(input.completionNotes?.trim());
  const labourHoursRecorded = input.actualLabourHours !== null
    && input.actualLabourHours !== undefined
    && Number(input.actualLabourHours) >= 0;
  const activeAfterEvidence = (input.evidence ?? []).some(
    (item) => item.category === "after" && !item.deleted_at,
  );
  const completion = {
    workRecordReceived,
    labourHoursRecorded,
    activeAfterEvidence,
    ready: workRecordReceived && labourHoursRecorded && activeAfterEvidence,
  };

  if (input.status === "closed" || input.status === "cancelled") {
    return { label: input.status === "closed" ? "Closed" : "Cancelled", nextAction: null, completion };
  }
  if (input.status === "reviewed") {
    return { label: "Completed — Verified", nextAction: null, completion };
  }
  if (input.status === "completed") {
    return { label: "Awaiting Verification", nextAction: "Verify Completed Work", completion };
  }
  if (input.status === "assigned" || input.status === "in_progress") {
    if (workRecordReceived && labourHoursRecorded) {
      return completion.ready
        ? { label: "Ready for Administrator Completion", nextAction: "Mark Completed", completion }
        : { label: "Awaiting After Evidence", nextAction: "Add After Evidence", completion };
    }
    if (workRecordReceived || labourHoursRecorded) {
      return { label: "Work Record Submitted", nextAction: "Complete Work Record", completion };
    }
    if (input.status === "in_progress" || input.startedAt) {
      return { label: "Work In Progress", nextAction: "Record Work Done", completion };
    }
    return { label: "Assigned — Not Started", nextAction: "Start Work", completion };
  }

  return { label: input.status.replaceAll("_", " "), nextAction: null, completion };
}
