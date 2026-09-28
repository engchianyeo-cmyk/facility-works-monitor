export const ACTIVE_WORK_STATUSES = new Set(["draft", "submitted", "approved", "assigned", "in_progress"]);
export const OPERATIONAL_WORK_STATUSES = new Set([...ACTIVE_WORK_STATUSES, "completed"]);

export type TechnicianOverviewOrder = {
  id: string;
  work_order_number: string;
  title: string;
  status: string;
  priority: string;
  emergency_work?: boolean;
  due_date: string | null;
  completed_at?: string | null;
  assigned_technician_id?: string | null;
  assigned_vendor_id?: string | null;
  assigned_team_id?: string | null;
  assigned_to?: string | null;
  location?: string;
  site?: string | null;
  created_at: string;
};

export const isUnassigned = (order: TechnicianOverviewOrder) =>
  !order.assigned_technician_id && !order.assigned_vendor_id && !order.assigned_team_id && !order.assigned_to;

export const isOverdue = (order: TechnicianOverviewOrder, today: string) =>
  ACTIVE_WORK_STATUSES.has(order.status) && Boolean(order.due_date && order.due_date < today);

export function technicianCounters(orders: TechnicianOverviewOrder[], actorId: string, today: string) {
  const emergencyCritical = orders.filter((order) => ACTIVE_WORK_STATUSES.has(order.status) && (order.emergency_work || order.priority === "critical"));
  const unassigned = orders.filter((order) => ACTIVE_WORK_STATUSES.has(order.status) && isUnassigned(order));
  const mine = orders.filter((order) => ACTIVE_WORK_STATUSES.has(order.status) && order.assigned_technician_id === actorId);
  const overdue = orders.filter((order) => isOverdue(order, today));
  const awaitingIds = new Set([...emergencyCritical, ...unassigned, ...mine, ...overdue].map((order) => order.id));
  return {
    emergencyCritical: emergencyCritical.length,
    unassigned: unassigned.length,
    myActiveWork: mine.length,
    overdue: overdue.length,
    awaitingAction: awaitingIds.size,
    facilityWorkload: {
      open: orders.filter((order) => ACTIVE_WORK_STATUSES.has(order.status)).length,
      inProgress: orders.filter((order) => order.status === "in_progress").length,
      awaitingApproval: orders.filter((order) => order.status === "submitted").length,
      completedToday: orders.filter((order) => Boolean(order.completed_at?.startsWith(today))).length,
      dueToday: orders.filter((order) => ACTIVE_WORK_STATUSES.has(order.status) && order.due_date === today).length,
    },
  };
}

export function operationalUrgency(order: TechnicianOverviewOrder, today: string) {
  if (order.emergency_work && OPERATIONAL_WORK_STATUSES.has(order.status)) return 0;
  if (order.priority === "critical" && OPERATIONAL_WORK_STATUSES.has(order.status)) return 1;
  if (isOverdue(order, today)) return 2;
  if (isUnassigned(order) && OPERATIONAL_WORK_STATUSES.has(order.status)) return 3;
  if (order.due_date && order.due_date >= today && OPERATIONAL_WORK_STATUSES.has(order.status)) return 4;
  if (OPERATIONAL_WORK_STATUSES.has(order.status)) return 5;
  return 6;
}

export function sortActiveFacilityWork(orders: TechnicianOverviewOrder[], today: string) {
  return orders
    .filter((order) => OPERATIONAL_WORK_STATUSES.has(order.status))
    .toSorted((a, b) => operationalUrgency(a, today) - operationalUrgency(b, today)
      || (a.due_date ?? "9999-12-31").localeCompare(b.due_date ?? "9999-12-31")
      || b.created_at.localeCompare(a.created_at));
}

export function technicianNextAction(order: TechnicianOverviewOrder, actorId: string, today: string) {
  if (order.emergency_work || order.priority === "critical") return "Open Work Order";
  if (isOverdue(order, today) && order.assigned_technician_id === actorId) return "Update Work";
  if (isOverdue(order, today) && order.assigned_technician_id) return "View / Contact Owner";
  if (isUnassigned(order)) return "View / Escalate";
  if (order.status === "submitted") return "View Approval Status";
  if (order.status === "completed") return "View Status";
  return order.assigned_technician_id === actorId ? "Open Work Order" : "View Work Order";
}

export function attentionRequired(orders: TechnicianOverviewOrder[], actorId: string, today: string) {
  return orders
    .filter((order) => order.status === "completed" || ACTIVE_WORK_STATUSES.has(order.status))
    .filter((order) => order.emergency_work || order.priority === "critical" || isOverdue(order, today) || isUnassigned(order) || ["submitted", "completed"].includes(order.status))
    .toSorted((a, b) => operationalUrgency(a, today) - operationalUrgency(b, today))
    .map((order) => ({ ...order, nextAction: technicianNextAction(order, actorId, today) }));
}
