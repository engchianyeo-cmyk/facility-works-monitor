import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildMime } from "@/lib/notifications/smtp";
import { buildFinanceReminder, buildNoticeEmail, emailRule, emailStatusLabel, reminderItems, sgtClock, smtpSettings } from "@/lib/notifications/email-rules";

describe("D-42 email rules: email only when the reader must act", () => {
  it("emails Finance only for an uploaded invoice", () => {
    expect(emailRule("work_order_invoice_uploaded", "finance")).toBe("send");
    expect(emailRule("work_order_completed", "finance")).toBe("in_app");
    expect(emailRule("work_order_closed", "finance")).toBe("in_app");
  });
  it("emails Technicians and approvers for the steps that wait for them", () => {
    expect(emailRule("work_order_approved", "technician")).toBe("send");
    expect(emailRule("work_order_returned_to_draft", "technician")).toBe("send");
    expect(emailRule("work_order_submitted_for_approval", "approver")).toBe("send");
    expect(emailRule("work_order_submitted_for_approval", "facility_manager")).toBe("send");
    expect(emailRule("work_order_submitted_for_approval", "technician")).toBe("in_app");
    expect(emailRule("work_order_invoice_uploaded", "approver")).toBe("in_app");
  });
  it("is off until both Vercel variables are set, and defaults to Yahoo Mail", () => {
    expect(smtpSettings({})).toBeNull();
    expect(smtpSettings({ EMAIL_SMTP_USER: "fmworks.notices@yahoo.com" })).toBeNull();
    expect(smtpSettings({ EMAIL_SMTP_USER: "fmworks.notices@yahoo.com", EMAIL_SMTP_PASSWORD: "abcd efgh ijkl mnop" }))
      .toEqual({ host: "smtp.mail.yahoo.com", port: 465, secure: true, user: "fmworks.notices@yahoo.com", pass: "abcdefghijklmnop", fromName: "FMWorks notices" });
  });
  it("labels the email status plainly", () => {
    expect(emailStatusLabel("pending", "IN_APP_ONLY")).toContain("in app only");
    expect(emailStatusLabel("sent", "SENT")).toBe("sent");
    expect(emailStatusLabel("pending", null)).toBe("not sent");
  });
});

describe("D-42 email content", () => {
  it("tells Finance which invoice to open and links to the payment section", () => {
    const message = buildNoticeEmail({ event: "work_order_invoice_uploaded", recipientName: "EC Yeo", appOrigin: "https://example.test", workOrderId: "w1",
      workOrderNumber: "WO-TEST-007", title: "Solar Inverter Alarm", facility: "FMWorks UAT Facility", contractor: "Sunvane <UAT>", invoiceReference: "SVS-INV-2026-0544",
      invoiceAmount: 565, approvedAmount: 565 });
    expect(message.subject).toBe("[FMWorks] Action needed: WO-TEST-007 — contractor invoice uploaded — confirm receipt and record the payment");
    expect(message.text).toContain("https://example.test/work-orders/w1#payment-heading");
    expect(message.text).toContain("SVS-INV-2026-0544 · S$565.00 before GST");
    expect(message.html).toContain("Sunvane &lt;UAT&gt;");
    expect(message.html).not.toContain("Sunvane <UAT>");
  });
  it("lists overdue first, then invoices to confirm, then payments due within 7 days", () => {
    const now = new Date("2026-11-08T02:00:00Z");
    const base = { title: "t", contractor: "c", invoice_reference: "r", invoice_amount: 1 };
    const items = reminderItems([
      { ...base, work_order_id: "due", work_order_number: "A", invoice_received_at: "2026-11-01T00:00:00Z", payment_due_at: "2026-11-12T00:00:00Z" },
      { ...base, work_order_id: "later", work_order_number: "B", invoice_received_at: "2026-11-01T00:00:00Z", payment_due_at: "2026-12-30T00:00:00Z" },
      { ...base, work_order_id: "confirm", work_order_number: "C", invoice_received_at: null, payment_due_at: null },
      { ...base, work_order_id: "late", work_order_number: "D", invoice_received_at: "2026-10-01T00:00:00Z", payment_due_at: "2026-10-31T00:00:00Z" },
    ], now);
    expect(items.map((item) => [item.workOrderId, item.state])).toEqual([["late", "overdue"], ["confirm", "to_confirm"], ["due", "due_soon"]]);
    expect(buildFinanceReminder({ recipientName: "EC", appOrigin: "https://example.test", items, day: "2026-11-08" }).subject)
      .toBe("[FMWorks] Payments needing Finance today: 1 overdue, 1 to confirm, 1 due within 7 days");
  });
  it("uses Singapore time for the once-a-day reminder", () => {
    expect(sgtClock(new Date("2026-11-07T23:30:00Z"))).toEqual({ day: "2026-11-08", hour: 7 });
    expect(sgtClock(new Date("2026-11-08T00:30:00Z"))).toEqual({ day: "2026-11-08", hour: 8 });
  });
});

describe("D-42 email format", () => {
  it("sends a plain-text and an HTML version with safe headers", () => {
    const mime = buildMime({ fromName: "FMWorks notices", from: "fmworks.notices@yahoo.com", to: "engchian@yahoo.com", subject: "WO-TEST-007 — invoice\r\nBcc: x@y.z", text: "a", html: "<p>a</p>" }, "<id@yahoo.com>");
    expect(mime).toContain('From: "FMWorks notices" <fmworks.notices@yahoo.com>');
    expect(mime).toContain("Subject: =?UTF-8?B?");
    expect(mime).not.toContain("\r\nBcc:");
    expect(mime).toContain("Content-Type: multipart/alternative;");
    expect(() => buildMime({ fromName: "x", from: "fmworks.notices@yahoo.com", to: "bad address", subject: "s", text: "", html: "" }, "<i@y>")).toThrow("Invalid email address");
  });
});

describe("D-42 email sending is wired in", () => {
  it("sends after Work Order actions and page loads, never before the response", () => {
    for (const route of ["transition", "endorsement", "invoice", "release-1", "technician", "assign", "commercial-documents", "in-house"]) {
      expect(readFileSync(`app/api/work-orders/[id]/${route}/route.ts`, "utf8")).toContain("scheduleEmailDispatch();");
    }
    expect(readFileSync("app/api/work-orders/emergency-record/route.ts", "utf8")).toContain("scheduleEmailDispatch();");
    expect(readFileSync("app/finance/page.tsx", "utf8")).toContain("scheduleEmailDispatch();");
    const schedule = readFileSync("lib/notifications/schedule-email.ts", "utf8");
    expect(schedule).toContain("after(async () =>");
    const dispatch = readFileSync("lib/notifications/email-dispatch.ts", "utf8");
    expect(dispatch).toContain('.eq("id", row.id).eq("delivery_status", "pending").select("id")');
    expect(dispatch).toContain("event_key: key");
  });
  it("shows repeat notices once and the email status on My notices", () => {
    const page = readFileSync("app/notices/page.tsx", "utf8");
    expect(page).toContain("`${row.work_order_id}|${row.event_type}`");
    expect(page).toContain("emailStatusLabel(row.delivery_status, row.result_code)");
    expect(readFileSync("components/notices/notices-list.tsx", "utf8")).toContain("markRead(item.ids)");
  });
});
