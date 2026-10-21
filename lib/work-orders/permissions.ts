import type { UserRole } from "@/lib/auth";
import type {
  WorkOrderAction,
  WorkflowContext,
} from "@/lib/work-orders/types";

/**
 * Work Order Lifecycle v2 presentation rules (docs/design/WORK_ORDER_LIFECYCLE_V2.md §4).
 * These decide which controls are shown. PostgreSQL enforces the same rules, including
 * facility membership and monetary limits, and remains the authority.
 */

/** Approver, Supervisor, Facility Manager and Administrator approve, assign, review and cancel. */
export const APPROVAL_AUTHORITIES: readonly UserRole[] = ["approver", "supervisor", "facility_manager", "administrator"];
/** A superior may create a Work Order when the Technician is unavailable (D-05.2 amended). */
export const SUPERIOR_CREATORS: readonly UserRole[] = APPROVAL_AUTHORITIES;
/** Assigned field owners (migration 0040). */
export const FIELD_EXECUTION_ROLES: readonly UserRole[] = ["technician", "supervisor", "facility_manager", "administrator"];

export function isApprovalAuthority(role: UserRole): boolean {
  return APPROVAL_AUTHORITIES.includes(role);
}

/** Technicians create Work Orders; superiors may when the Technician is unavailable. */
export function canCreate(role: UserRole): boolean {
  return role === "technician" || SUPERIOR_CREATORS.includes(role);
}

/** The preparer: the assigned Technician, or the superior who created it while Draft/Awaiting Approval. */
export function isPreparer(context: WorkflowContext): boolean {
  if (context.role === "technician") return context.actorId === context.assignedTechnicianId;
  return SUPERIOR_CREATORS.includes(context.role)
    && context.actorId === context.requesterId
    && ["draft", "submitted"].includes(context.status);
}

export function canEdit(context: WorkflowContext): boolean {
  if (["closed", "cancelled"].includes(context.status)) return false;
  if (["facility_manager", "administrator"].includes(context.role)) return true;
  return context.status === "draft" && isPreparer(context);
}

export function canAssign(role: UserRole, status: string): boolean {
  return isApprovalAuthority(role) && ["approved", "assigned"].includes(status);
}

/** Choose the field-witness Technician while Draft or Awaiting Approval. */
export function canSetTechnician(role: UserRole, status: string): boolean {
  return isApprovalAuthority(role) && ["draft", "submitted"].includes(status);
}

function independent(context: WorkflowContext): boolean {
  return context.role === "administrator"
    || (context.actorId !== context.requesterId && context.actorId !== context.assignedTechnicianId);
}

export function canAct(
  action: WorkOrderAction,
  context: WorkflowContext,
): boolean {
  if (["accept", "accept_responsibility"].includes(action)) {
    return FIELD_EXECUTION_ROLES.includes(context.role)
      && (!context.assignedTechnicianId || context.actorId === context.assignedTechnicianId)
      && ["approved", "assigned", "in_progress"].includes(context.status);
  }
  if (action === "submit_physical_completion") {
    return FIELD_EXECUTION_ROLES.includes(context.role) && context.actorId === context.assignedTechnicianId && ["assigned", "in_progress"].includes(context.status);
  }
  if (action === "start") {
    return FIELD_EXECUTION_ROLES.includes(context.role) && context.actorId === context.assignedTechnicianId;
  }
  if (action === "submit") return context.status === "draft" && isPreparer(context);
  if (action === "approve" || action === "return") {
    return context.status === "submitted" && isApprovalAuthority(context.role) && independent(context);
  }
  if (action === "review") {
    return context.status === "completed" && isApprovalAuthority(context.role) && independent(context);
  }
  if (action === "return_for_rework" || action === "close" || action === "cancel") {
    return isApprovalAuthority(context.role);
  }
  if (action === "complete") return context.role === "administrator";
  return false;
}

export function canRecordWork(context: WorkflowContext): boolean {
  if (!["assigned", "in_progress"].includes(context.status)) return false;
  return FIELD_EXECUTION_ROLES.includes(context.role) && context.actorId === context.assignedTechnicianId;
}

/** Contractor invoice upload: the assigned Technician, after the Work Order is Completed. */
export function canUploadInvoice(context: WorkflowContext): boolean {
  return context.role === "technician" && context.actorId === context.assignedTechnicianId && context.status === "reviewed";
}

export function isFinance(role: UserRole): boolean {
  return role === "finance";
}
