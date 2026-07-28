export type WorkOrderWithOptionalReference = {
  work_order_no?: unknown;
};

export function getWorkOrderReference(
  workOrder: WorkOrderWithOptionalReference,
): string | null {
  return typeof workOrder.work_order_no === "string" &&
    workOrder.work_order_no.trim()
    ? workOrder.work_order_no.trim()
    : null;
}
