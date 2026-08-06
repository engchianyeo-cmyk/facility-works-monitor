import { describe, expect, test } from "vitest";
import type { UserRole } from "@/lib/auth";
import { canAct, canAssign, canCreate, canEdit } from "@/lib/work-orders/permissions";
import { getTransition } from "@/lib/work-orders/workflow";
import { WORK_ORDER_ACTIONS, WORK_ORDER_STATUSES, type WorkOrderAction, type WorkOrderStatus } from "@/lib/work-orders/types";

const valid: Array<[WorkOrderStatus, WorkOrderAction, WorkOrderStatus]> = [
  ["draft", "submit", "submitted"], ["submitted", "approve", "approved"],
  ["assigned", "accept", "assigned"], ["assigned", "start", "in_progress"],
  ["in_progress", "complete", "completed"], ["completed", "review", "reviewed"],
  ["reviewed", "close", "closed"],
];

describe("canonical workflow transition matrix", () => {
  test.each(valid)("%s --%s--> %s", (from, action, to) => expect(getTransition(from, action)).toEqual({ ok: true, to }));
  test.each(WORK_ORDER_STATUSES.filter((status) => !["closed", "cancelled"].includes(status)))("%s can be cancelled", (status) => expect(getTransition(status, "cancel")).toEqual({ ok: true, to: "cancelled" }));
  const validKeys = new Set([...valid.map(([from, action]) => `${from}:${action}`), ...WORK_ORDER_STATUSES.filter((status) => !["closed", "cancelled"].includes(status)).map((status) => `${status}:cancel`)]);
  const invalid = WORK_ORDER_STATUSES.flatMap((status) => WORK_ORDER_ACTIONS.map((action) => [status, action] as const)).filter(([status, action]) => !validKeys.has(`${status}:${action}`));
  test.each(invalid)("rejects %s --%s", (status, action) => expect(getTransition(status, action)).toMatchObject({ ok: false, code: "INVALID_TRANSITION" }));
});

describe("canonical workflow authorization", () => {
  const base = { actorId: "actor", requesterId: "requester", assignedTechnicianId: "technician", status: "submitted" as WorkOrderStatus };
  test("reviewer remains requestor-level", () => expect(canAct("approve", { ...base, role: "reviewer" })).toBe(false));
  test("approver can approve another requester's order", () => expect(canAct("approve", { ...base, role: "approver" })).toBe(true));
  test("approver cannot self-approve", () => expect(canAct("approve", { ...base, role: "approver", actorId: "requester" })).toBe(false));
  test("assigned technician can accept, start and complete", () => { for (const action of ["accept", "start", "complete"] as const) expect(canAct(action, { ...base, role: "technician", actorId: "technician", status: action === "complete" ? "in_progress" : "assigned" })).toBe(true); });
  test("only assignment authorities assign", () => { const roles: UserRole[] = ["reviewer", "initiator", "approver", "technician", "supervisor", "administrator"]; expect(roles.filter((role) => canAssign(role, "approved"))).toEqual(["approver", "supervisor", "administrator"]); });
  test("terminal states cannot be edited", () => { expect(canEdit({ ...base, role: "administrator", status: "closed" })).toBe(false); expect(canEdit({ ...base, role: "administrator", status: "cancelled" })).toBe(false); });
  test("technicians cannot create general work orders", () => expect(canCreate("technician")).toBe(false));
});
