import { UserRole } from "@/lib/auth";
import { WorkOrderAction, WorkOrderStatus } from "@/lib/status";

type PermissionContext = {
  role: UserRole;
  userId: string;
  ownerId: string | null;
  assignedTechnicianId?: string | null;
  status: WorkOrderStatus;
};

export function canCreateWorkOrder(role: UserRole): boolean {
  return [
    "reviewer",
    "initiator",
    "approver",
    "supervisor",
    "administrator",
  ].includes(role);
}

export function canEditWorkOrder(context: PermissionContext): boolean {
  if (["approver", "supervisor", "administrator"].includes(context.role)) {
    return true;
  }
  return (
    ["reviewer", "initiator"].includes(context.role) &&
    context.ownerId === context.userId &&
    context.status === "submitted"
  );
}

export function canDeleteWorkOrder(role: UserRole): boolean {
  return role === "administrator";
}

export function canAssignWorkOrderPersonnel(
  role: UserRole,
  status: WorkOrderStatus,
): boolean {
  return (
    ["approver", "supervisor", "administrator"].includes(role) &&
    status === "approved"
  );
}

export function canPerformWorkOrderAction(
  action: WorkOrderAction,
  context: PermissionContext,
): boolean {
  if (["supervisor", "administrator"].includes(context.role)) return true;

  if (action === "approve" || action === "reject") {
    return context.role === "approver";
  }

  if (action === "start" || action === "complete") {
    return (
      context.role === "technician" &&
      context.assignedTechnicianId === context.userId
    );
  }

  return false;
}
