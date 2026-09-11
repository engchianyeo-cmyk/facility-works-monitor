import { describe, expect, test } from "vitest";
import { attentionRequired, sortActiveFacilityWork, technicianCounters, technicianNextAction, type TechnicianOverviewOrder } from "@/lib/work-orders/technician-overview";

const today = "2026-09-11";
const technician = "tech-1";
const order = (n: number, changes: Partial<TechnicianOverviewOrder> = {}): TechnicianOverviewOrder => ({ id: `order-${n}`, work_order_number: `WO-TEST-${String(n).padStart(3, "0")}`, title: `Work ${n}`, status: "approved", priority: "medium", due_date: "2026-09-20", created_at: `2026-09-${String(n).padStart(2, "0")}T00:00:00Z`, assigned_technician_id: "other-tech", assigned_to: "Other Technician", ...changes });

describe("Technician facility workflow", () => {
  test("uses all 15 facility-readable records and unique action counts", () => {
    const orders = Array.from({ length: 15 }, (_, index) => order(index + 1));
    orders[0] = order(1, { emergency_work: true }); orders[1] = order(2, { priority: "critical" });
    orders[2] = order(3, { assigned_technician_id: null, assigned_to: null });
    orders[3] = order(4, { assigned_technician_id: technician, assigned_to: "Yang Ying Zhang" });
    orders[4] = order(5, { due_date: "2026-09-10" });
    expect(orders).toHaveLength(15);
    expect(technicianCounters(orders, technician, today)).toMatchObject({ emergencyCritical: 2, unassigned: 1, myActiveWork: 1, overdue: 1, awaitingAction: 5 });
  });
  test("sorts active urgency and excludes closed critical alarms", () => {
    const sorted = sortActiveFacilityWork([order(1, { status: "closed", priority: "critical" }), order(2), order(3, { due_date: "2026-09-10" }), order(4, { priority: "critical" }), order(5, { emergency_work: true })], today);
    expect(sorted.map((item) => item.work_order_number)).toEqual(["WO-TEST-005", "WO-TEST-004", "WO-TEST-003", "WO-TEST-002"]);
  });
  test("offers only Technician-safe attention actions", () => {
    expect(technicianNextAction(order(1, { assigned_technician_id: null, assigned_to: null }), technician, today)).toBe("View / Escalate");
    expect(technicianNextAction(order(2, { due_date: "2026-09-10", assigned_technician_id: technician }), technician, today)).toBe("Update Work");
    expect(technicianNextAction(order(3, { due_date: "2026-09-10" }), technician, today)).toBe("View / Contact Owner");
    expect(attentionRequired([order(4, { status: "completed" })], technician, today)[0]?.nextAction).toBe("View Status");
  });
});
