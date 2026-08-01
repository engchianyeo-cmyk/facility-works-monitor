import { describe, expect, test } from "vitest";

import type { UserRole } from "@/lib/auth";
import {
  canAssignWorkOrderPersonnel,
  canCreateWorkOrder,
  canDeleteWorkOrder,
  canEditWorkOrder,
  canPerformWorkOrderAction,
} from "@/lib/permissions";

describe("Create Work Order", () => {
  const permittedRoles: UserRole[] = [
    "reviewer",
    "initiator",
    "approver",
    "supervisor",
    "administrator",
  ];

  test.each(permittedRoles)("%s can create", (role) => {
    expect(canCreateWorkOrder(role)).toBe(true);
  });

  test("technician cannot create", () => {
    expect(canCreateWorkOrder("technician")).toBe(false);
  });
});

describe("Delete Work Order", () => {
  test("administrator can delete", () => {
    expect(canDeleteWorkOrder("administrator")).toBe(true);
  });

  const deniedRoles: UserRole[] = [
    "reviewer",
    "initiator",
    "approver",
    "supervisor",
    "technician",
  ];

  test.each(deniedRoles)("%s cannot delete", (role) => {
    expect(canDeleteWorkOrder(role)).toBe(false);
  });
});

describe("Edit Work Order", () => {
  test("reviewer can edit own submitted order", () => {
    expect(
      canEditWorkOrder({
        role: "reviewer",
        userId: "1",
        ownerId: "1",
        status: "submitted",
      }),
    ).toBe(true);
  });

  test("reviewer cannot edit another user's order", () => {
    expect(
      canEditWorkOrder({
        role: "reviewer",
        userId: "1",
        ownerId: "2",
        status: "submitted",
      }),
    ).toBe(false);
  });

  test("reviewer cannot edit approved order", () => {
    expect(
      canEditWorkOrder({
        role: "reviewer",
        userId: "1",
        ownerId: "1",
        status: "approved",
      }),
    ).toBe(false);
  });

  test("administrator can always edit", () => {
    expect(
      canEditWorkOrder({
        role: "administrator",
        userId: "1",
        ownerId: "2",
        status: "done",
      }),
    ).toBe(true);
  });
});

describe("Assign Personnel", () => {
  test("supervisor can assign approved order", () => {
    expect(
      canAssignWorkOrderPersonnel("supervisor", "approved"),
    ).toBe(true);
  });

  test("supervisor cannot assign submitted order", () => {
    expect(
      canAssignWorkOrderPersonnel("supervisor", "submitted"),
    ).toBe(false);
  });
});

describe("Technician Actions", () => {
  test("assigned technician can start", () => {
    expect(
      canPerformWorkOrderAction("start", {
        role: "technician",
        userId: "100",
        ownerId: "1",
        assignedTechnicianId: "100",
        status: "approved",
      }),
    ).toBe(true);
  });

  test("wrong technician cannot start", () => {
    expect(
      canPerformWorkOrderAction("start", {
        role: "technician",
        userId: "100",
        ownerId: "1",
        assignedTechnicianId: "200",
        status: "approved",
      }),
    ).toBe(false);
  });
});

describe("Approver Actions", () => {
  test.each(["approve", "reject"] as const)(
    "approver can %s",
    (action) => {
      expect(
        canPerformWorkOrderAction(action, {
          role: "approver",
          userId: "approver-1",
          ownerId: "reviewer-1",
          assignedTechnicianId: null,
          status: "submitted",
        }),
      ).toBe(true);
    },
  );

  test.each(["start", "complete"] as const)(
    "approver cannot %s technician work",
    (action) => {
      expect(
        canPerformWorkOrderAction(action, {
          role: "approver",
          userId: "approver-1",
          ownerId: "reviewer-1",
          assignedTechnicianId: "technician-1",
          status: "approved",
        }),
      ).toBe(false);
    },
  );
});

describe("Supervisor and Administrator Actions", () => {
  test.each(["supervisor", "administrator"] as const)(
    "%s can perform controlled workflow actions",
    (role) => {
      expect(
        canPerformWorkOrderAction("approve", {
          role,
          userId: `${role}-1`,
          ownerId: "reviewer-1",
          assignedTechnicianId: null,
          status: "submitted",
        }),
      ).toBe(true);

      expect(
        canPerformWorkOrderAction("complete", {
          role,
          userId: `${role}-1`,
          ownerId: "reviewer-1",
          assignedTechnicianId: "technician-1",
          status: "in_progress",
        }),
      ).toBe(true);
    },
  );
});