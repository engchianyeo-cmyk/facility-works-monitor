/**
 * D-42 (7 Nov 2026): which notices go out by email, and what the emails say.
 * Emails go out at once only when the reader must act; information-only notices stay on My notices.
 * Pure functions so they can be tested without a mail server.
 */
import { noticeText } from "@/lib/notices";

const APPROVERS = ["approver", "supervisor", "facility_manager", "administrator"];

/** Events that ask the reader to act, by the reader's role. Everything else is in-app only. */
export const ACTION_EVENTS: Record<string, string[]> = {
  finance: ["work_order_invoice_uploaded"],
  technician: ["work_order_approved", "work_order_technician_assigned", "work_order_returned_to_draft", "work_order_second_technician_named", "work_order_endorsement_due"],
  approver: ["work_order_submitted_for_approval", "work_order_emergency_started", "work_order_endorsed"],
};

export function emailRule(event: string, role: string | null | undefined): "send" | "in_app" {
  const key = role && APPROVERS.includes(role) ? "approver" : role ?? "";
  return (ACTION_EVENTS[key] ?? []).includes(event) ? "send" : "in_app";
}

/** Notices older than this when the sender first sees them are not emailed (no backlog blast). */
export const EMAIL_WINDOW_HOURS = 24;
/** A repeat of the same notice to the same person within this many minutes is not emailed again. */
export const REPEAT_MINUTES = 30;
export const MAX_ATTEMPTS = 3;

export type SmtpSettings = { host: string; port: number; secure: boolean; user: string; pass: string; fromName: string };

/** Sending is on only when both Vercel variables exist. Yahoo Mail by default; host and port can be changed. */
export function smtpSettings(env: Record<string, string | undefined> = process.env): SmtpSettings | null {
  const user = env.EMAIL_SMTP_USER?.trim();
  const pass = env.EMAIL_SMTP_PASSWORD?.replace(/\s+/g, "");
  if (!user || !pass) return null;
  const port = Number(env.EMAIL_SMTP_PORT ?? 465) || 465;
  return { host: env.EMAIL_SMTP_HOST?.trim() || "smtp.mail.yahoo.com", port, secure: port === 465, user, pass, fromName: env.EMAIL_FROM_NAME?.trim() || "FMWorks notices" };
}

/** What My notices and the Administrator page show for a notice's email. */
export function emailStatusLabel(status: string, resultCode: string | null | undefined): string {
  if (resultCode === "IN_APP_ONLY") return "in app only (no action needed, so no email)";
  if (resultCode === "REPEAT_SUPPRESSED") return "in app only (same notice emailed shortly before)";
  if (status === "sent") return "sent";
  if (status === "processing") return "sending";
  if (status === "failed") return "failed";
  return "not sent";
}

const escape = (value: string) => value.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
const money = (value: number | null | undefined) => value === null || value === undefined ? "—" : `S$${new Intl.NumberFormat("en-SG", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value))}`;
const sgtDay = (value: string | null | undefined) => value ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeZone: "Asia/Singapore" }).format(new Date(value)) : "—";

export type EmailMessage = { subject: string; text: string; html: string };

const FOOTER = "This is an automatic notice from FMWorks (UAT test system). Please do not reply to this email.";

function layout(heading: string, paragraphs: string[], rows: Array<[string, string]>, button: { label: string; href: string }): string {
  return `<!doctype html><html><body style="margin:0;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif;color:#0f172a">
<div style="max-width:560px;margin:0 auto;padding:24px">
<div style="background:#ffffff;border:2px solid #dc2626;border-radius:12px;padding:24px">
<p style="margin:0 0 4px;font-size:12px;font-weight:bold;letter-spacing:2px;color:#dc2626;text-transform:uppercase">Action needed</p>
<h1 style="margin:0 0 16px;font-size:20px">${escape(heading)}</h1>
${paragraphs.map((p) => `<p style="margin:0 0 12px;line-height:1.5">${escape(p)}</p>`).join("")}
${rows.length ? `<table style="width:100%;border-collapse:collapse;margin:8px 0 16px;font-size:14px">${rows.map(([k, v]) => `<tr><td style="padding:6px 8px;border-bottom:1px solid #e2e8f0;font-weight:bold;width:40%">${escape(k)}</td><td style="padding:6px 8px;border-bottom:1px solid #e2e8f0">${escape(v)}</td></tr>`).join("")}</table>` : ""}
<a href="${escape(button.href)}" style="display:inline-block;background:#dc2626;color:#ffffff;text-decoration:none;font-weight:bold;padding:12px 20px;border-radius:8px">${escape(button.label)}</a>
</div>
<p style="margin:16px 0 0;font-size:12px;color:#64748b">${escape(FOOTER)}</p>
</div></body></html>`;
}

export type NoticeEmailInput = {
  event: string; recipientName: string | null; appOrigin: string; workOrderId: string; workOrderNumber: string | null; title: string;
  facility: string | null; contractor?: string | null; invoiceReference?: string | null; invoiceAmount?: number | null; approvedAmount?: number | null;
};

export function buildNoticeEmail(input: NoticeEmailInput): EmailMessage {
  const meaning = noticeText(input.event);
  const number = input.workOrderNumber ?? "Work Order";
  const href = `${input.appOrigin}/work-orders/${input.workOrderId}${meaning.href}`;
  const subject = `[FMWorks] Action needed: ${number} — ${meaning.text}`;
  const greeting = `Hello ${input.recipientName?.trim() || "there"},`;
  const what = `${number} ${input.title}: ${meaning.text}.`;
  const rows: Array<[string, string]> = [["Work Order", `${number} ${input.title}`], ["Facility", input.facility ?? "—"]];
  if (input.event === "work_order_invoice_uploaded") {
    rows.push(["Contractor", input.contractor ?? "—"], ["Invoice", `${input.invoiceReference ?? "—"} · ${money(input.invoiceAmount)} before GST`], ["Approved amount", `${money(input.approvedAmount)} before GST`]);
  }
  const next = input.event === "work_order_invoice_uploaded"
    ? "Please open the invoice in FMWorks, check it against the approved amount and confirm the date you received it. The payment terms start from that date."
    : "Please open the Work Order in FMWorks; the section waiting for you is outlined in red.";
  const button = { label: `Open ${number} in FMWorks`, href };
  const text = [greeting, "", what, "", ...rows.map(([k, v]) => `${k}: ${v}`), "", next, "", `Open: ${href}`, "", FOOTER].join("\n");
  return { subject, text, html: layout(`${number} — ${meaning.text}`, [greeting, next], rows, button) };
}

export type ReminderItem = { workOrderId: string; workOrderNumber: string | null; title: string; contractor: string | null; invoiceReference: string | null;
  invoiceAmount: number | null; state: "to_confirm" | "due_soon" | "overdue"; dueAt: string | null };

const STATE_TEXT: Record<ReminderItem["state"], string> = { to_confirm: "Invoice receipt not yet confirmed", due_soon: "Payment due within 7 days", overdue: "Payment overdue" };

/** Daily reminder for Finance: invoices not yet confirmed, payments due within 7 days and overdue payments. */
export function reminderItems(rows: Array<{ work_order_id: string; work_order_number: string | null; title: string; contractor: string | null; invoice_reference: string | null;
  invoice_amount: number | null; invoice_received_at: string | null; payment_due_at: string | null }>, now = new Date()): ReminderItem[] {
  const week = now.getTime() + 7 * 86_400_000;
  const items = rows.flatMap((row): ReminderItem[] => {
    const base = { workOrderId: row.work_order_id, workOrderNumber: row.work_order_number, title: row.title, contractor: row.contractor, invoiceReference: row.invoice_reference, invoiceAmount: row.invoice_amount, dueAt: row.payment_due_at };
    if (!row.invoice_received_at) return [{ ...base, state: "to_confirm" }];
    if (!row.payment_due_at) return [];
    const due = new Date(row.payment_due_at).getTime();
    if (due < now.getTime()) return [{ ...base, state: "overdue" }];
    if (due <= week) return [{ ...base, state: "due_soon" }];
    return [];
  });
  const order = { overdue: 0, to_confirm: 1, due_soon: 2 };
  return items.sort((a, b) => order[a.state] - order[b.state] || (a.dueAt ?? "").localeCompare(b.dueAt ?? ""));
}

export function buildFinanceReminder(input: { recipientName: string | null; appOrigin: string; items: ReminderItem[]; day: string }): EmailMessage {
  const counts = (state: ReminderItem["state"]) => input.items.filter((item) => item.state === state).length;
  const summary = [counts("overdue") && `${counts("overdue")} overdue`, counts("to_confirm") && `${counts("to_confirm")} to confirm`, counts("due_soon") && `${counts("due_soon")} due within 7 days`].filter(Boolean).join(", ");
  const subject = `[FMWorks] Payments needing Finance today: ${summary}`;
  const greeting = `Hello ${input.recipientName?.trim() || "there"},`;
  const intro = `These contractor invoices need Finance (${input.day}):`;
  const rows: Array<[string, string]> = input.items.map((item) => [`${item.workOrderNumber ?? "Work Order"} ${item.title}`,
    `${STATE_TEXT[item.state]}${item.dueAt && item.state !== "to_confirm" ? ` (due ${sgtDay(item.dueAt)})` : ""} · ${item.contractor ?? "—"} · ${item.invoiceReference ?? "—"} ${money(item.invoiceAmount)}`]);
  const href = `${input.appOrigin}/finance/register`;
  const text = [greeting, "", intro, "", ...rows.map(([k, v]) => `- ${k}: ${v}`), "", `Completed work register: ${href}`, "", FOOTER].join("\n");
  return { subject, text, html: layout("Payments needing Finance today", [greeting, intro], rows, { label: "Open the Completed work register", href }) };
}

/** Today's date in Singapore (YYYY-MM-DD) and the hour, for the once-a-day reminder from 8 am. */
export function sgtClock(now = new Date()): { day: string; hour: number } {
  const day = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Singapore" }).format(now);
  const hour = Number(new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Singapore", hour: "2-digit", hourCycle: "h23" }).format(now));
  return { day, hour };
}
