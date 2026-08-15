import { describe, expect, test } from "vitest";
import {
  NoopNotificationProvider,
  notifyAssignment,
  notifyEmergency,
  type NotificationProvider,
} from "@/lib/notifications/provider";

const assignment = {
  workOrderId: "work-order-id",
  assigneeId: "technician-id",
  assignmentPath: "/work-orders/work-order-id",
};
const emergency = { incidentId: "incident-id", incidentNumber: "INC-2026-000001", incidentType: "lift_entrapment", location: "Lift lobby", description: "Passenger trapped", reportedAt: "2026-08-10T00:00:00Z", incidentPath: "/incidents/incident-id" };

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
      sendEmergencySMS: async () => { throw new Error("unused"); },
      sendEmergencyWhatsApp: async () => { throw new Error("unused"); },
    };
    await expect(notifyAssignment(assignment, provider)).resolves.toEqual({
      delivered: false,
      code: "DELIVERY_FAILED",
      provider: "future-provider",
      message: "Assignment notification delivery failed.",
    });
  });

  test("reports SMS and WhatsApp independently as not configured", async () => {
    await expect(notifyEmergency(emergency, new NoopNotificationProvider())).resolves.toEqual([
      expect.objectContaining({ channel: "sms", delivered: false, code: "NOT_CONFIGURED", provider: "none" }),
      expect.objectContaining({ channel: "whatsapp", delivered: false, code: "NOT_CONFIGURED", provider: "none" }),
    ]);
  });

  test("contains one channel failure without suppressing the other result", async () => {
    const provider: NotificationProvider = {
      name: "future-provider",
      sendAssignment: async () => ({ delivered: true, code: "DELIVERED", provider: "future-provider", message: "Delivered" }),
      sendEmergencySMS: async () => { throw new Error("private provider failure"); },
      sendEmergencyWhatsApp: async () => ({ channel: "whatsapp", delivered: true, code: "DELIVERED", provider: "future-provider", message: "Delivered" }),
    };
    await expect(notifyEmergency(emergency, provider)).resolves.toEqual([
      expect.objectContaining({ channel: "sms", delivered: false, code: "DELIVERY_FAILED" }),
      expect.objectContaining({ channel: "whatsapp", delivered: true, code: "DELIVERED" }),
    ]);
  });
});
