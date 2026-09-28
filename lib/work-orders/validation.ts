import {
  ASSIGNMENT_TYPES,
  WORK_ORDER_ACTIONS,
  WORK_ORDER_PRIORITIES,
  WORK_ORDER_SOURCES,
  WORK_ORDER_STATUSES,
  type AssignmentType,
  type WorkOrderAction,
  type WorkOrderPriority,
  type WorkOrderSource,
  type WorkOrderStatus,
} from "@/lib/work-orders/types";

export function isWorkOrderStatus(value: unknown): value is WorkOrderStatus {
  return WORK_ORDER_STATUSES.includes(value as WorkOrderStatus);
}

export function isWorkOrderSource(value: unknown): value is WorkOrderSource {
  return WORK_ORDER_SOURCES.includes(value as WorkOrderSource);
}

export function isWorkOrderPriority(value: unknown): value is WorkOrderPriority {
  return WORK_ORDER_PRIORITIES.includes(value as WorkOrderPriority);
}

export function isWorkOrderAction(value: unknown): value is WorkOrderAction {
  return WORK_ORDER_ACTIONS.includes(value as WorkOrderAction);
}

export function isAssignmentType(value: unknown): value is AssignmentType {
  return ASSIGNMENT_TYPES.includes(value as AssignmentType);
}

export function parseFiniteNumber(value: unknown): number | null | undefined {
  if (value === null || value === "") return null;
  if (value === undefined) return undefined;
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : undefined;
}

export function validatePredictiveRanges(payload: Record<string, unknown>): string | null {
  const health = parseFiniteNumber(payload.health_score_at_creation);
  if (health !== undefined && health !== null && (health < 0 || health > 100)) {
    return "Health score must be between 0 and 100.";
  }
  for (const field of ["failure_probability", "confidence_score"] as const) {
    const value = parseFiniteNumber(payload[field]);
    if (value !== undefined && value !== null && (value < 0 || value > 1)) {
      return `${field === "failure_probability" ? "Failure probability" : "Confidence score"} must be between 0 and 1.`;
    }
  }
  return null;
}

export function validateContactNumber(value: unknown): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") return "Contact number must be text.";
  if (value.trim().length > 255) return "Contact number must be 255 characters or fewer.";
  return null;
}
