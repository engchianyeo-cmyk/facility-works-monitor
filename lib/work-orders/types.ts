import type { UserRole } from "@/lib/auth";

export const WORK_ORDER_STATUSES = [
  "draft",
  "submitted",
  "approved",
  "assigned",
  "in_progress",
  "completed",
  "reviewed",
  "closed",
  "cancelled",
] as const;

export const WORK_ORDER_SOURCES = [
  "manual",
  "reactive",
  "preventive",
  "inspection",
  "condition_based",
  "predictive",
] as const;

export const WORK_ORDER_PRIORITIES = [
  "low",
  "medium",
  "high",
  "critical",
] as const;

export const WORK_ORDER_ACTIONS = [
  "submit",
  "approve",
  "accept",
  "start",
  "complete",
  "review",
  "return_for_rework",
  "close",
  "cancel",
] as const;

export const ASSIGNMENT_TYPES = ["technician", "vendor", "team"] as const;

export type WorkOrderStatus = (typeof WORK_ORDER_STATUSES)[number];
export type WorkOrderSource = (typeof WORK_ORDER_SOURCES)[number];
export type WorkOrderPriority = (typeof WORK_ORDER_PRIORITIES)[number];
export type WorkOrderAction = (typeof WORK_ORDER_ACTIONS)[number];
export type AssignmentType = (typeof ASSIGNMENT_TYPES)[number];

export type WorkflowContext = {
  role: UserRole;
  actorId: string;
  requesterId: string | null;
  assignedTechnicianId?: string | null;
  status: WorkOrderStatus;
};

export type RpcResult<T = Record<string, unknown>> = {
  ok: boolean;
  code?: string;
  message?: string;
  work_order?: T;
  [key: string]: unknown;
};

export type WorkOrderRecord = {
  id: string;
  work_order_number: string;
  title: string;
  description: string | null;
  location: string;
  site: string | null;
  category_id: string | null;
  priority: WorkOrderPriority;
  status: WorkOrderStatus;
  source: WorkOrderSource;
  requested_by: string | null;
  submitted_by: string | null;
  department_id: string | null;
  asset_id: string | null;
  assigned_technician_id: string | null;
  assigned_vendor_id: string | null;
  assigned_team_id: string | null;
  assigned_by: string | null;
  assigned_by_user_id: string | null;
  assigned_at: string | null;
  accepted_at: string | null;
  due_date: string | null;
  estimated_hours: number | null;
  actual_labour_hours: number | null;
  completion_notes: string | null;
  internal_notes: string | null;
  cancellation_reason: string | null;
  contact_number: string | null;
  created_at: string;
  updated_at: string;
  [key: string]: unknown;
};
