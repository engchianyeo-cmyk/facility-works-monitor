import { describe, expect, test } from "vitest";
import type { UserRole } from "@/lib/auth";
import { canAct, canAssign, canCreate, canEdit, canRecordWork } from "@/lib/work-orders/permissions";
import { getTransition } from "@/lib/work-orders/workflow";
import { WORK_ORDER_ACTIONS, WORK_ORDER_STATUSES, type WorkOrderAction, type WorkOrderStatus } from "@/lib/work-orders/types";

const valid: Array<[WorkOrderStatus, WorkOrderAction, WorkOrderStatus]> = [
  ["draft", "submit", "submitted"], ["submitted", "approve", "assigned"], ["submitted", "return", "draft"],
  ["approved", "accept_responsibility", "assigned"],
  ["assigned", "accept", "assigned"], ["assigned", "start", "in_progress"],
  ["assigned", "accept_responsibility", "assigned"], ["in_progress", "accept_responsibility", "in_progress"],
  ["assigned", "submit_physical_completion", "completed"], ["in_progress", "submit_physical_completion", "completed"],
  ["in_progress", "complete", "completed"], ["completed", "review", "reviewed"],
  ["completed", "return_for_rework", "in_progress"],
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
  test.each(["approver", "supervisor", "facility_manager", "administrator"] as UserRole[])("%s may approve and return submitted work (limits enforced in PostgreSQL)", (role) => {
    expect(canAct("approve", { ...base, role })).toBe(true);
    expect(canAct("return", { ...base, role })).toBe(true);
  });
  test("the requester cannot approve their own Work Order; an Administrator may with a reason", () => {
    expect(canAct("approve", { ...base, role: "supervisor", actorId: "requester" })).toBe(false);
    expect(canAct("approve", { ...base, role: "administrator", actorId: "requester" })).toBe(true);
  });
  test.each(["approver", "supervisor", "facility_manager", "administrator"] as UserRole[])("%s can review and return completed work", (role) => {
    const completed = { ...base, role, status: "completed" as WorkOrderStatus };
    expect(canAct("review", completed)).toBe(true);
    expect(canAct("return_for_rework", completed)).toBe(true);
  });
  test.each(["reviewer", "initiator", "technician", "finance"] as UserRole[])("%s cannot review or return completed work", (role) => {
    const completed = { ...base, role, status: "completed" as WorkOrderStatus };
    expect(canAct("review", completed)).toBe(false);
    expect(canAct("return_for_rework", completed)).toBe(false);
  });
  test("assigned technician can accept and start but cannot formally complete", () => {
    for (const action of ["accept", "start"] as const) expect(canAct(action, { ...base, role: "technician", actorId: "technician", status: "assigned" })).toBe(true);
    expect(canAct("complete", { ...base, role: "technician", actorId: "technician", status: "in_progress" })).toBe(false);
    expect(canAct("submit_physical_completion", { ...base, role: "technician", actorId: "technician", status: "in_progress" })).toBe(true);
    expect(canRecordWork({ ...base, role: "technician", actorId: "technician", status: "in_progress" })).toBe(true);
  });
  test.each(["reviewer", "approver", "supervisor", "facility_manager"] as UserRole[])("%s cannot formally complete", (role) => expect(canAct("complete", { ...base, role, status: "in_progress" })).toBe(false));
  test("administrator retains formal completion authority", () => expect(canAct("complete", { ...base, role: "administrator", status: "in_progress" })).toBe(true));
  test("only assignment authorities assign", () => { const roles: UserRole[] = ["reviewer", "initiator", "approver", "technician", "supervisor", "administrator"]; expect(roles.filter((role) => canAssign(role, "approved"))).toEqual(["approver", "supervisor", "administrator"]); });
  test("assigned Technician reviewing their own work is denied", () => expect(canAct("review", { ...base, role: "supervisor", actorId: "technician", status: "completed" })).toBe(false));
  test("terminal states cannot be edited", () => { expect(canEdit({ ...base, role: "administrator", status: "closed" })).toBe(false); expect(canEdit({ ...base, role: "administrator", status: "cancelled" })).toBe(false); });
  test("Technicians create Work Orders; superiors may when the Technician is unavailable (D-05.2)", () => {
    const roles: UserRole[] = ["reviewer", "initiator", "approver", "technician", "supervisor", "facility_manager", "administrator", "finance"];
    expect(roles.filter(canCreate)).toEqual(["approver", "technician", "supervisor", "facility_manager", "administrator"]);
  });
  test("only the preparer submits a Draft", () => {
    const draft = { ...base, status: "draft" as WorkOrderStatus };
    expect(canAct("submit", { ...draft, role: "technician", actorId: "technician" })).toBe(true);
    expect(canAct("submit", { ...draft, role: "technician", actorId: "other" })).toBe(false);
    expect(canAct("submit", { ...draft, role: "supervisor", actorId: "requester" })).toBe(true);
    expect(canAct("submit", { ...draft, role: "initiator", actorId: "requester" })).toBe(false);
  });
});
