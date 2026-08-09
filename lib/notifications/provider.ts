import "server-only";

export type AssignmentNotification = {
  workOrderId: string;
  assigneeId: string;
  assignmentPath: string;
};

export type NotificationResult = {
  delivered: boolean;
  code: "DELIVERED" | "NOT_CONFIGURED" | "DELIVERY_FAILED";
  provider: string;
  message: string;
};

export interface NotificationProvider {
  readonly name: string;
  sendAssignment(
    notification: AssignmentNotification,
  ): Promise<NotificationResult>;
}

export class NoopNotificationProvider implements NotificationProvider {
  readonly name = "none";

  async sendAssignment(
    notification: AssignmentNotification,
  ): Promise<NotificationResult> {
    void notification;
    return {
      delivered: false,
      code: "NOT_CONFIGURED",
      provider: this.name,
      message: "Assignment notification delivery is not configured.",
    };
  }
}

export function getNotificationProvider(): NotificationProvider {
  return new NoopNotificationProvider();
}

export async function notifyAssignment(
  notification: AssignmentNotification,
  provider: NotificationProvider = getNotificationProvider(),
): Promise<NotificationResult> {
  try {
    return await provider.sendAssignment(notification);
  } catch {
    return {
      delivered: false,
      code: "DELIVERY_FAILED",
      provider: provider.name,
      message: "Assignment notification delivery failed.",
    };
  }
}
