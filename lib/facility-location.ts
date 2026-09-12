import { WORK_ORDER_DRAWINGS } from "@/lib/work-order-drawings";

export const FACILITY_LOCATION_AUDIT_EVENT = "facility_area_drawing_location_updated";

export function validNormalizedCoordinate(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 100;
}

export function validDrawingReference(value: unknown): value is string {
  return typeof value === "string" && WORK_ORDER_DRAWINGS.some((drawing) => drawing.code === value);
}
