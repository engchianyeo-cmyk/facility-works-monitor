import { describe, expect, test } from "vitest";
import {
  NoopNotificationProvider,
  notifyAssignment,
  type NotificationProvider,
} from "@/lib/notifications/provider";

const assignment = {
  workOrderId: "work-order-id",
  assigneeId: "technician-id",
  assignmentPath: "/work-orders/work-order-id",
};

describe("assignment notification provider", () => {
  test("reports that delivery is not configured without claiming success", async () => {
    await expect(
      notifyAssignment(assignment, new NoopNotificationProvider()),
    ).resolves.toEqual({
      delivered: false,
      code: "NOT_CONFIGURED",
      provider: "none",
      message: "Assignment notification delivery is not configured.",
    });
  });

  test("contains provider failures without failing assignment business logic", async () => {
    const provider: NotificationProvider = {
      name: "future-provider",
      sendAssignment: async () => {
        throw new Error("private provider failure");
      },
    };
    await expect(notifyAssignment(assignment, provider)).resolves.toEqual({
      delivered: false,
      code: "DELIVERY_FAILED",
      provider: "future-provider",
      message: "Assignment notification delivery failed.",
    });
  });
});
