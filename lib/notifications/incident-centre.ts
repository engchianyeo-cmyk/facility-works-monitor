import "server-only";
import type { UserRole } from "@/lib/auth";
import {
  NoopSmsProvider,
  NoopWhatsAppProvider,
  sendSms,
  sendWhatsApp,
  type EmergencyNotification,
  type EmergencyNotificationResult,
  type SmsProvider,
  type WhatsAppProvider,
} from "@/lib/notifications/provider";

export type RecipientProfile = {
  id: string;
  role: UserRole;
  active: boolean;
  contactNumber?: string | null;
  whatsappNumber?: string | null;
};

export type RosterRecipient = {
  profileId: string;
  smsEnabled: boolean;
  whatsappEnabled: boolean;
  active: boolean;
};

export type IncidentRecipient = {
  profileId: string;
  smsDestination: string | null;
  whatsappDestination: string | null;
  smsEnabled: boolean;
  whatsappEnabled: boolean;
};

export function incidentPath(incidentId: string): string {
  return `/incidents/${encodeURIComponent(incidentId)}`;
}

export function resolveIncidentRecipients(input: {
  profiles: RecipientProfile[];
  roster: RosterRecipient[];
  assignedProfileIds: string[];
}): IncidentRecipient[] {
  const profileById = new Map(input.profiles.filter(profile => profile.active).map(profile => [profile.id, profile]));
  const selected = new Map<string, { sms: boolean; whatsapp: boolean }>();
  const include = (id: string, sms: boolean, whatsapp: boolean) => {
    if (!profileById.has(id)) return;
    const current = selected.get(id) ?? { sms: false, whatsapp: false };
    selected.set(id, { sms: current.sms || sms, whatsapp: current.whatsapp || whatsapp });
  };
  for (const profile of profileById.values()) if (profile.role === "administrator" || profile.role === "supervisor") include(profile.id, true, true);
  for (const id of input.assignedProfileIds) include(id, true, true);
  for (const recipient of input.roster) if (recipient.active) include(recipient.profileId, recipient.smsEnabled, recipient.whatsappEnabled);
  return [...selected].map(([profileId, channels]) => {
    const profile = profileById.get(profileId)!;
    return { profileId, smsDestination: profile.contactNumber?.trim() || null, whatsappDestination: profile.whatsappNumber?.trim() || null, smsEnabled: channels.sms, whatsappEnabled: channels.whatsapp };
  });
}

export type NotificationAttempt = EmergencyNotificationResult & { profileId: string };

export type OutboxRecipientRow = {
  recipient_profile_id: string | null;
  channel: string | null;
  recipient: { contact_number?: string | null; whatsapp_number?: string | null } | null;
};

export function recipientsFromOutbox(rows: OutboxRecipientRow[]): IncidentRecipient[] {
  const recipients = new Map<string, IncidentRecipient>();
  for (const row of rows) {
    if (!row.recipient_profile_id || (row.channel !== "sms" && row.channel !== "whatsapp")) continue;
    const existing = recipients.get(row.recipient_profile_id) ?? {
      profileId: row.recipient_profile_id,
      smsDestination: row.recipient?.contact_number?.trim() || null,
      whatsappDestination: row.recipient?.whatsapp_number?.trim() || null,
      smsEnabled: false,
      whatsappEnabled: false,
    };
    if (row.channel === "sms") existing.smsEnabled = true;
    if (row.channel === "whatsapp") existing.whatsappEnabled = true;
    recipients.set(row.recipient_profile_id, existing);
  }
  return [...recipients.values()];
}

export async function notifyIncidentRecipients(input: {
  incident: Omit<EmergencyNotification, "incidentPath">;
  recipients: IncidentRecipient[];
  smsProvider?: SmsProvider;
  whatsappProvider?: WhatsAppProvider;
}): Promise<NotificationAttempt[]> {
  const notification = { ...input.incident, incidentPath: incidentPath(input.incident.incidentId) };
  const sms = input.smsProvider ?? new NoopSmsProvider();
  const whatsapp = input.whatsappProvider ?? new NoopWhatsAppProvider();
  const operations: Promise<NotificationAttempt>[] = [];
  for (const recipient of input.recipients) {
    if (recipient.smsEnabled) operations.push(sendSms(notification, recipient.smsDestination, sms).then(result => ({ ...result, profileId: recipient.profileId })));
    if (recipient.whatsappEnabled) operations.push(sendWhatsApp(notification, recipient.whatsappDestination, whatsapp).then(result => ({ ...result, profileId: recipient.profileId })));
  }
  return Promise.all(operations);
}

export type PersistedChannelResult = {
  channel: "sms" | "whatsapp";
  delivered: boolean;
  code: "DELIVERED" | "NOT_CONFIGURED" | "DELIVERY_FAILED";
  provider: string;
};

export function mapOutboxChannelResults(attempts: NotificationAttempt[]): PersistedChannelResult[] {
  return (["sms", "whatsapp"] as const).flatMap(channel => {
    const channelAttempts = attempts.filter(attempt => attempt.channel === channel);
    if (!channelAttempts.length) return [];
    const delivered = channelAttempts.every(attempt => attempt.delivered);
    const notConfigured = channelAttempts.every(attempt => attempt.code === "NOT_CONFIGURED");
    return [{ channel, delivered, code: delivered ? "DELIVERED" : notConfigured ? "NOT_CONFIGURED" : "DELIVERY_FAILED", provider: [...new Set(channelAttempts.map(attempt => attempt.provider))].join(",").slice(0, 100) || "none" }];
  });
}
