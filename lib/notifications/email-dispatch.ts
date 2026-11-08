import "server-only";

import { applicationOrigin } from "@/lib/app-url";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendSmtp } from "@/lib/notifications/smtp";
import {
  EMAIL_WINDOW_HOURS, MAX_ATTEMPTS, REPEAT_MINUTES, buildFinanceReminder, buildNoticeEmail, emailRule, reminderItems, sgtClock, smtpSettings,
  type EmailMessage, type SmtpSettings,
} from "@/lib/notifications/email-rules";

/**
 * D-42 (7 Nov 2026): sends the queued notices that ask the reader to act, and Finance's daily reminder.
 * Runs after a Work Order action or a Finance / notices page load (there is no scheduler on Preview).
 * Does nothing unless EMAIL_SMTP_USER and EMAIL_SMTP_PASSWORD are set.
 */
type Admin = ReturnType<typeof createAdminClient>;
type Outbox = { id: string; work_order_id: string | null; event_type: string; recipient_profile_id: string | null; recipient_email: string | null; attempts: number; created_at: string };

const safeError = (error: unknown) => (error instanceof Error ? error.message : String(error)).replace(/\s+/g, " ").slice(0, 300);

async function send(settings: SmtpSettings, to: string, message: EmailMessage) {
  return sendSmtp({ host: settings.host, port: settings.port, secure: settings.secure, user: settings.user, pass: settings.pass },
    { fromName: settings.fromName, from: settings.user, to, subject: message.subject, text: message.text, html: message.html });
}

async function noticeDetails(admin: Admin, workOrderId: string) {
  const { data: order } = await admin.from("work_orders").select("id,work_order_number,title,facility_id,assigned_vendor_id").eq("id", workOrderId).maybeSingle();
  if (!order) return null;
  const [{ data: site }, { data: payment }] = await Promise.all([
    order.facility_id ? admin.from("sites").select("name").eq("id", order.facility_id).maybeSingle() : Promise.resolve({ data: null }),
    admin.from("contractor_payment_assessments").select("vendor_id,invoice_reference,invoice_amount,assessed_amount").eq("work_order_id", workOrderId).maybeSingle(),
  ]);
  const vendorId = (payment as { vendor_id?: string } | null)?.vendor_id ?? order.assigned_vendor_id;
  const { data: vendor } = vendorId ? await admin.from("vendors").select("name").eq("id", vendorId).maybeSingle() : { data: null };
  return { order, facility: (site as { name?: string } | null)?.name ?? null, payment: payment as { invoice_reference: string | null; invoice_amount: number | null; assessed_amount: number | null } | null,
    contractor: (vendor as { name?: string } | null)?.name ?? null };
}

export async function dispatchPendingEmails(settings: SmtpSettings, admin: Admin = createAdminClient(), limit = 20): Promise<{ sent: number; inApp: number; failed: number }> {
  // A run cut short (time limit) leaves rows "processing"; after 10 minutes they are tried again.
  await admin.from("notification_outbox").update({ delivery_status: "pending" }).eq("channel", "email").eq("delivery_status", "processing")
    .neq("event_type", "finance_daily_reminder").lt("attempted_at", new Date(Date.now() - 10 * 60_000).toISOString());
  const since = new Date(Date.now() - EMAIL_WINDOW_HOURS * 3_600_000).toISOString();
  const { data, error } = await admin.from("notification_outbox")
    .select("id,work_order_id,event_type,recipient_profile_id,recipient_email,attempts,created_at")
    .eq("channel", "email").eq("delivery_status", "pending").is("result_code", null).not("work_order_id", "is", null)
    .gte("created_at", since).lte("available_at", new Date().toISOString()).order("created_at", { ascending: true }).limit(limit);
  if (error || !data?.length) return { sent: 0, inApp: 0, failed: 0 };
  const rows = data as Outbox[];
  const profileIds = Array.from(new Set(rows.map((row) => row.recipient_profile_id).filter(Boolean))) as string[];
  const { data: people } = await admin.from("profiles").select("id,role,display_name,email,is_active").in("id", profileIds);
  const personOf = new Map(((people ?? []) as Array<{ id: string; role: string; display_name: string | null; email: string | null; is_active: boolean }>).map((p) => [p.id, p]));
  const origin = applicationOrigin();
  const tally = { sent: 0, inApp: 0, failed: 0 };

  for (const row of rows) {
    const person = row.recipient_profile_id ? personOf.get(row.recipient_profile_id) : undefined;
    const to = (row.recipient_email ?? person?.email ?? "").trim();
    if (!person?.is_active || !to || emailRule(row.event_type, person.role) === "in_app") {
      await admin.from("notification_outbox").update({ result_code: "IN_APP_ONLY", provider: "in_app", updated_at: new Date().toISOString() }).eq("id", row.id).eq("delivery_status", "pending");
      tally.inApp += 1; continue;
    }
    // The same notice to the same person shortly before (for example an invoice replaced twice) is not emailed again.
    const repeatSince = new Date(new Date(row.created_at).getTime() - REPEAT_MINUTES * 60_000).toISOString();
    const { data: earlier } = await admin.from("notification_outbox").select("id").eq("work_order_id", row.work_order_id as string).eq("event_type", row.event_type)
      .eq("recipient_profile_id", person.id).eq("delivery_status", "sent").gte("created_at", repeatSince).limit(1);
    if (earlier?.length) {
      await admin.from("notification_outbox").update({ result_code: "REPEAT_SUPPRESSED", provider: "in_app", updated_at: new Date().toISOString() }).eq("id", row.id).eq("delivery_status", "pending");
      tally.inApp += 1; continue;
    }
    // Claim the row so a second run at the same moment does not send it twice.
    const { data: claimed } = await admin.from("notification_outbox").update({ delivery_status: "processing", attempted_at: new Date().toISOString(), provider: "smtp" })
      .eq("id", row.id).eq("delivery_status", "pending").select("id");
    if (!claimed?.length) continue;
    try {
      const details = await noticeDetails(admin, row.work_order_id as string);
      if (!details) throw new Error("Work Order not found");
      const message = buildNoticeEmail({ event: row.event_type, recipientName: person.display_name, appOrigin: origin, workOrderId: details.order.id, workOrderNumber: details.order.work_order_number,
        title: details.order.title, facility: details.facility, contractor: details.contractor, invoiceReference: details.payment?.invoice_reference, invoiceAmount: details.payment?.invoice_amount,
        approvedAmount: details.payment?.assessed_amount });
      const reference = await send(settings, to, message);
      const now = new Date().toISOString();
      await admin.from("notification_outbox").update({ delivery_status: "sent", sent_at: now, result_code: "SENT", provider_reference: reference, attempts: row.attempts + 1, last_error: null, last_error_code: null, updated_at: now }).eq("id", row.id);
      tally.sent += 1;
    } catch (failure) {
      const attempts = row.attempts + 1;
      const last = attempts >= MAX_ATTEMPTS;
      await admin.from("notification_outbox").update({ delivery_status: last ? "failed" : "pending", attempts, retry_count: attempts, last_error: safeError(failure), last_error_code: "SMTP_ERROR",
        available_at: new Date(Date.now() + attempts * 5 * 60_000).toISOString(), updated_at: new Date().toISOString() }).eq("id", row.id);
      tally.failed += 1;
    }
  }
  return tally;
}

/** Once a day from 8 am Singapore time: each active Finance user gets one email listing the payments needing them. */
export async function sendDailyFinanceReminders(settings: SmtpSettings, admin: Admin = createAdminClient(), now = new Date()): Promise<number> {
  const clock = sgtClock(now);
  if (clock.hour < 8) return 0;
  const key = `finance_reminder:${clock.day}`;
  const { data: finance } = await admin.from("profiles").select("id,display_name,email").eq("role", "finance").eq("is_active", true).is("deleted_at", null);
  const people = ((finance ?? []) as Array<{ id: string; display_name: string | null; email: string | null }>).filter((p) => p.email);
  if (!people.length) return 0;
  const { data: already } = await admin.from("notification_outbox").select("recipient_profile_id").eq("event_key", key);
  const done = new Set(((already ?? []) as Array<{ recipient_profile_id: string | null }>).map((row) => row.recipient_profile_id));
  const waiting = people.filter((p) => !done.has(p.id));
  if (!waiting.length) return 0;

  const { data: payments } = await admin.from("contractor_payment_assessments")
    .select("work_order_id,vendor_id,invoice_reference,invoice_amount,invoice_received_at,payment_due_at")
    .eq("status", "approved_for_payment").is("paid_at", null).not("invoice_uploaded_at", "is", null);
  const list = (payments ?? []) as Array<{ work_order_id: string; vendor_id: string | null; invoice_reference: string | null; invoice_amount: number | null; invoice_received_at: string | null; payment_due_at: string | null }>;
  if (!list.length) return 0;
  const { data: testRows, error: testError } = await admin.from("work_order_test_data").select("work_order_id");
  const test = new Set(testError ? [] : ((testRows ?? []) as Array<{ work_order_id: string }>).map((row) => row.work_order_id));
  const live = list.filter((row) => !test.has(row.work_order_id));
  const ids = live.map((row) => row.work_order_id);
  const vendorIds = Array.from(new Set(live.map((row) => row.vendor_id).filter(Boolean))) as string[];
  const [{ data: orders }, { data: vendors }] = await Promise.all([
    ids.length ? admin.from("work_orders").select("id,work_order_number,title,status").in("id", ids) : Promise.resolve({ data: [] }),
    vendorIds.length ? admin.from("vendors").select("id,name").in("id", vendorIds) : Promise.resolve({ data: [] }),
  ]);
  const orderOf = new Map(((orders ?? []) as Array<{ id: string; work_order_number: string | null; title: string; status: string }>).map((o) => [o.id, o]));
  const vendorOf = new Map(((vendors ?? []) as Array<{ id: string; name: string }>).map((v) => [v.id, v.name]));
  const items = reminderItems(live.filter((row) => orderOf.has(row.work_order_id)).map((row) => ({
    work_order_id: row.work_order_id, work_order_number: orderOf.get(row.work_order_id)?.work_order_number ?? null, title: orderOf.get(row.work_order_id)?.title ?? "",
    contractor: row.vendor_id ? vendorOf.get(row.vendor_id) ?? null : null, invoice_reference: row.invoice_reference, invoice_amount: row.invoice_amount,
    invoice_received_at: row.invoice_received_at, payment_due_at: row.payment_due_at })), now);
  if (!items.length) return 0;

  const origin = applicationOrigin();
  let sent = 0;
  for (const person of waiting) {
    // The unique event key per person and day is the claim: a second run the same day inserts nothing.
    const { data: claim, error } = await admin.from("notification_outbox").insert({
      work_order_id: items[0].workOrderId, event_type: "finance_daily_reminder", event_key: key, recipient_user_id: person.id, recipient_profile_id: person.id,
      recipient_email: person.email, channel: "email", provider: "smtp", delivery_status: "processing", attempted_at: new Date().toISOString(),
      payload: { day: clock.day, items: items.map((item) => ({ work_order_id: item.workOrderId, state: item.state })) },
    }).select("id").maybeSingle();
    if (error || !claim) continue;
    try {
      const reference = await send(settings, person.email as string, buildFinanceReminder({ recipientName: person.display_name, appOrigin: origin, items, day: clock.day }));
      const at = new Date().toISOString();
      await admin.from("notification_outbox").update({ delivery_status: "sent", sent_at: at, result_code: "SENT", provider_reference: reference, attempts: 1, updated_at: at }).eq("id", claim.id);
      sent += 1;
    } catch (failure) {
      await admin.from("notification_outbox").update({ delivery_status: "failed", attempts: 1, last_error: safeError(failure), last_error_code: "SMTP_ERROR", updated_at: new Date().toISOString() }).eq("id", claim.id);
    }
  }
  return sent;
}

export async function runEmailDispatch(): Promise<void> {
  const settings = smtpSettings();
  if (!settings) return;
  try {
    const admin = createAdminClient();
    await dispatchPendingEmails(settings, admin);
    await sendDailyFinanceReminders(settings, admin);
  } catch (failure) {
    console.error("[email-dispatch] run failed", safeError(failure));
  }
}
