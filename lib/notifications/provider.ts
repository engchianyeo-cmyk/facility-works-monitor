import "server-only";

export type AssignmentNotification = {
  workOrderId: string;
  assigneeId: string;
  assignmentPath: string;
};

export type NotificationCode =
  | "DELIVERED"
  | "NOT_CONFIGURED"
  | "INVALID_DESTINATION"
  | "DELIVERY_FAILED";

export type NotificationResult = {
  delivered: boolean;
  code: NotificationCode;
  provider: string;
  message: string;
  providerReference?: string;
};

export type EmergencyChannel = "sms" | "whatsapp";
export type EmergencyNotification = {
  incidentId: string;
  incidentNumber: string;
  incidentType: string;
  location: string;
  description: string;
  reportedAt: string;
  incidentPath: string;
};
export type ChannelNotification = EmergencyNotification & { destination: string };
export type EmergencyNotificationResult = NotificationResult & { channel: EmergencyChannel };

export interface SmsProvider {
  readonly name: string;
  send(notification: ChannelNotification): Promise<NotificationResult>;
}

export interface WhatsAppProvider {
  readonly name: string;
  send(notification: ChannelNotification): Promise<NotificationResult>;
}

export class NoopSmsProvider implements SmsProvider {
  readonly name = "none";
  async send(notification: ChannelNotification): Promise<NotificationResult> {
    void notification;
    return { delivered: false, code: "NOT_CONFIGURED", provider: this.name, message: "Emergency SMS delivery is not configured." };
  }
}

export class NoopWhatsAppProvider implements WhatsAppProvider {
  readonly name = "none";
  async send(notification: ChannelNotification): Promise<NotificationResult> {
    void notification;
    return { delivered: false, code: "NOT_CONFIGURED", provider: this.name, message: "Emergency WhatsApp delivery is not configured." };
  }
}

export interface NotificationProvider {
  readonly name: string;
  sendAssignment(notification: AssignmentNotification): Promise<NotificationResult>;
  sendEmergencySMS(notification: EmergencyNotification): Promise<EmergencyNotificationResult>;
  sendEmergencyWhatsApp(notification: EmergencyNotification): Promise<EmergencyNotificationResult>;
}

export class NoopNotificationProvider implements NotificationProvider {
  readonly name = "none";
  async sendAssignment(notification: AssignmentNotification): Promise<NotificationResult> {
    void notification;
    return { delivered: false, code: "NOT_CONFIGURED", provider: this.name, message: "Assignment notification delivery is not configured." };
  }
  async sendEmergencySMS(notification: EmergencyNotification): Promise<EmergencyNotificationResult> {
    return { channel: "sms", ...(await new NoopSmsProvider().send({ ...notification, destination: "unconfigured" })) };
  }
  async sendEmergencyWhatsApp(notification: EmergencyNotification): Promise<EmergencyNotificationResult> {
    return { channel: "whatsapp", ...(await new NoopWhatsAppProvider().send({ ...notification, destination: "unconfigured" })) };
  }
}

export function isValidMessageDestination(value: unknown): value is string {
  return typeof value === "string" && /^\+[1-9]\d{7,14}$/.test(value.trim());
}

export async function sendSms(notification: EmergencyNotification, destination: unknown, provider: SmsProvider = new NoopSmsProvider()): Promise<EmergencyNotificationResult> {
  if (!isValidMessageDestination(destination)) return { channel: "sms", delivered: false, code: "INVALID_DESTINATION", provider: provider.name, message: "The SMS destination is invalid." };
  try { return { channel: "sms", ...(await provider.send({ ...notification, destination: destination.trim() })) }; }
  catch { return { channel: "sms", delivered: false, code: "DELIVERY_FAILED", provider: provider.name, message: "Emergency SMS delivery failed." }; }
}

export async function sendWhatsApp(notification: EmergencyNotification, destination: unknown, provider: WhatsAppProvider = new NoopWhatsAppProvider()): Promise<EmergencyNotificationResult> {
  if (!isValidMessageDestination(destination)) return { channel: "whatsapp", delivered: false, code: "INVALID_DESTINATION", provider: provider.name, message: "The WhatsApp destination is invalid." };
  try { return { channel: "whatsapp", ...(await provider.send({ ...notification, destination: destination.trim() })) }; }
  catch { return { channel: "whatsapp", delivered: false, code: "DELIVERY_FAILED", provider: provider.name, message: "Emergency WhatsApp delivery failed." }; }
}

export async function notifyEmergency(notification: EmergencyNotification, provider: NotificationProvider = getNotificationProvider()): Promise<EmergencyNotificationResult[]> {
  const safe = async (channel: EmergencyChannel, operation: () => Promise<EmergencyNotificationResult>) => {
    try { return await operation(); }
    catch { return { channel, delivered: false, code: "DELIVERY_FAILED" as const, provider: provider.name, message: `Emergency ${channel} delivery failed.` }; }
  };
  return Promise.all([safe("sms", () => provider.sendEmergencySMS(notification)), safe("whatsapp", () => provider.sendEmergencyWhatsApp(notification))]);
}

export function getNotificationProvider(): NotificationProvider { return new NoopNotificationProvider(); }

export async function notifyAssignment(notification: AssignmentNotification, provider: NotificationProvider = getNotificationProvider()): Promise<NotificationResult> {
  try { return await provider.sendAssignment(notification); }
  catch { return { delivered: false, code: "DELIVERY_FAILED", provider: provider.name, message: "Assignment notification delivery failed." }; }
}
