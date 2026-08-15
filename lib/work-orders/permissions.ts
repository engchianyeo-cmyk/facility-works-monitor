import type { UserRole } from "@/lib/auth";
import type {
  WorkOrderAction,
  WorkflowContext,
} from "@/lib/work-orders/types";

export function canCreate(role: UserRole): boolean {
  return role !== "technician";
}

export function canEdit(context: WorkflowContext): boolean {
  if (["closed", "cancelled"].includes(context.status)) return false;
  if (context.role === "administrator") return true;
  return (
    ["reviewer", "initiator"].includes(context.role) &&
    context.actorId === context.requesterId &&
    context.status === "draft"
  );
}

export function canAssign(role: UserRole, status: string): boolean {
  return (
    ["approver", "supervisor", "administrator"].includes(role) &&
    ["approved", "assigned"].includes(status)
  );
}

export function canAct(
  action: WorkOrderAction,
  context: WorkflowContext,
): boolean {
  if (context.role === "administrator") return true;

  if (action === "submit") {
    return (
      ["reviewer", "initiator", "approver", "supervisor"].includes(
        context.role,
      ) && context.actorId === context.requesterId
    );
  }
  if (["approve", "close"].includes(action)) {
    return context.role === "approver" && context.actorId !== context.requesterId;
  }
  if (["review", "return_for_rework"].includes(action)) {
    return ["approver", "supervisor"].includes(context.role);
  }
  if (["accept", "start", "complete"].includes(action)) {
    return (
      context.role === "technician" &&
      context.actorId === context.assignedTechnicianId
    );
  }
  if (action === "cancel") {
    return ["approver", "supervisor"].includes(context.role);
  }
  return false;
}
