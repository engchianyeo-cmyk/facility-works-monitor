import { describe, expect, test, vi } from "vitest";
import {
  incidentPath,
  mapOutboxChannelResults,
  notifyIncidentRecipients,
  recipientsFromOutbox,
  resolveIncidentRecipients,
} from "@/lib/notifications/incident-centre";
import { NoopSmsProvider, NoopWhatsAppProvider, type SmsProvider, type WhatsAppProvider } from "@/lib/notifications/provider";

const incident = { incidentId: "incident/id", incidentNumber: "INC-2026-000001", incidentType: "fire", location: "Plant room", description: "Smoke detected", reportedAt: "2026-08-10T00:00:00Z" };

describe("Incident Notification Centre", () => {
  test("uses a stable encoded Incident route", () => expect(incidentPath("incident/id")).toBe("/incidents/incident%2Fid"));

  test("includes active administrators, supervisors, assigned and on-call responders once", () => {
    const recipients = resolveIncidentRecipients({
      profiles: [
        { id: "admin", role: "administrator", active: true, contactNumber: "+6591111111" },
        { id: "supervisor", role: "supervisor", active: true, contactNumber: "+6592222222" },
        { id: "assigned", role: "technician", active: true, contactNumber: "+6593333333" },
        { id: "on-call", role: "technician", active: true, whatsappNumber: "+6594444444" },
        { id: "inactive-admin", role: "administrator", active: false, contactNumber: "+6595555555" },
      ],
      assignedProfileIds: ["assigned"],
      roster: [{ profileId: "on-call", smsEnabled: false, whatsappEnabled: true, active: true }, { profileId: "assigned", smsEnabled: true, whatsappEnabled: false, active: true }],
    });
    expect(recipients.map(recipient => recipient.profileId)).toEqual(["admin", "supervisor", "assigned", "on-call"]);
  });

  test("maps pending outbox rows to channel destinations", () => {
    expect(recipientsFromOutbox([{ recipient_profile_id: "admin", channel: "sms", recipient: { contact_number: "+6591111111" } }])).toEqual([expect.objectContaining({ profileId: "admin", smsEnabled: true, whatsappEnabled: false, smsDestination: "+6591111111" })]);
  });

  test("Noop providers report both channels independently without claiming delivery", async () => {
    const results = await notifyIncidentRecipients({ incident, recipients: [{ profileId: "admin", smsDestination: "+6591111111", whatsappDestination: "+6591111111", smsEnabled: true, whatsappEnabled: true }], smsProvider: new NoopSmsProvider(), whatsappProvider: new NoopWhatsAppProvider() });
    expect(results).toEqual([expect.objectContaining({ channel: "sms", code: "NOT_CONFIGURED", delivered: false }), expect.objectContaining({ channel: "whatsapp", code: "NOT_CONFIGURED", delivered: false })]);
  });

  test("rejects invalid destinations without invoking providers", async () => {
    const sendSms = vi.fn(); const sendWhatsApp = vi.fn();
    const results = await notifyIncidentRecipients({ incident, recipients: [{ profileId: "admin", smsDestination: "555", whatsappDestination: null, smsEnabled: true, whatsappEnabled: true }], smsProvider: { name: "sms-test", send: sendSms } as SmsProvider, whatsappProvider: { name: "wa-test", send: sendWhatsApp } as WhatsAppProvider });
    expect(results.map(result => result.code)).toEqual(["INVALID_DESTINATION", "INVALID_DESTINATION"]);
    expect(sendSms).not.toHaveBeenCalled(); expect(sendWhatsApp).not.toHaveBeenCalled();
  });

  test("contains one provider exception while preserving the other channel result", async () => {
    const results = await notifyIncidentRecipients({ incident, recipients: [{ profileId: "assigned", smsDestination: "+6591111111", whatsappDestination: "+6591111111", smsEnabled: true, whatsappEnabled: true }], smsProvider: { name: "sms-test", send: async () => { throw new Error("secret"); } }, whatsappProvider: { name: "wa-test", send: async () => ({ delivered: true, code: "DELIVERED", provider: "wa-test", message: "Delivered", providerReference: "safe-ref" }) } });
    expect(results).toEqual([expect.objectContaining({ channel: "sms", code: "DELIVERY_FAILED" }), expect.objectContaining({ channel: "whatsapp", code: "DELIVERED", providerReference: "safe-ref" })]);
  });

  test("maps per-recipient attempts to the approved channel-level outbox RPC contract", () => {
    expect(mapOutboxChannelResults([{ profileId: "a", channel: "sms", delivered: false, code: "INVALID_DESTINATION", provider: "sms", message: "Invalid" }, { profileId: "b", channel: "sms", delivered: true, code: "DELIVERED", provider: "sms", message: "Sent" }])).toEqual([{ channel: "sms", delivered: false, code: "DELIVERY_FAILED", provider: "sms" }]);
  });
});
