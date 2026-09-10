import type { UserRole } from "@/lib/auth";
import type {
  WorkOrderAction,
  WorkflowContext,
} from "@/lib/work-orders/types";

const WORK_AUTHORITIES: UserRole[] = ["approver", "supervisor", "facility_manager", "administrator"];
const COMPLETED_WORK_AUTHORITIES: UserRole[] = ["supervisor", "facility_manager", "administrator"];

export function canCreate(role: UserRole): boolean {
  return role !== "technician";
}

export function canEdit(context: WorkflowContext): boolean {
  if (["closed", "cancelled"].includes(context.status)) return false;
  if (["facility_manager", "administrator"].includes(context.role)) return true;
  return (
    ["reviewer", "initiator"].includes(context.role) &&
    context.actorId === context.requesterId &&
    context.status === "draft"
  );
}

export function canAssign(role: UserRole, status: string): boolean {
  return WORK_AUTHORITIES.includes(role) && ["approved", "assigned"].includes(status);
}

export function canAct(
  action: WorkOrderAction,
  context: WorkflowContext,
): boolean {
  if (context.role === "administrator") return true;

  if (action === "submit") {
    return (
      ["reviewer", "initiator", "approver", "supervisor", "facility_manager"].includes(context.role) &&
      context.actorId === context.requesterId
    );
  }
  if (action === "approve") {
    return ["approver", "facility_manager"].includes(context.role) && context.actorId !== context.requesterId;
  }
  if (["review", "return_for_rework", "close"].includes(action)) {
    return COMPLETED_WORK_AUTHORITIES.includes(context.role);
  }
  if (["accept", "start"].includes(action)) {
    return (
      context.role === "technician" &&
      context.actorId === context.assignedTechnicianId
    );
  }
  if (action === "complete") return false;
  if (action === "cancel") {
    return WORK_AUTHORITIES.includes(context.role);
  }
  return false;
}

export function canRecordWork(context: WorkflowContext): boolean {
  if (!["assigned", "in_progress"].includes(context.status)) return false;
  return context.role === "administrator" || (
    context.role === "technician" && context.actorId === context.assignedTechnicianId
  );
}
