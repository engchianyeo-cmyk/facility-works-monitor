import { describe, expect, it } from "vitest";
import { daysLeft, dueNote, registerCsv, type RegisterRow } from "@/lib/finance-register";
import { noticeText, waitingForReader } from "@/lib/notices";

describe("Finance register helpers (D-39)", () => {
  it("counts whole Singapore days to the due date", () => {
    const now = new Date("2026-11-07T02:00:00Z");
    expect(daysLeft("2026-11-14T03:00:00Z", now)).toBe(7);
    expect(daysLeft("2026-11-05T03:00:00Z", now)).toBe(-2);
    expect(dueNote({ register_status: "in_house", payment_due_at: null })).toBeNull();
  });
  it("writes a CSV with GST and quotes commas", () => {
    const row = { work_order_number: "WO-1", title: "Leak, basin", facility_name: "Facility One", in_house_work: false, contractor_name: "Sunvane",
      approved_by_name: "A", completed_at: null, final_amount: 565, invoice_reference: "INV-1", invoice_amount: 565, invoice_received_at: null,
      payment_terms_days: 30, payment_due_at: null, paid_at: null, paid_amount: null, payment_reference: null, register_status: "invoice_uploaded" } as unknown as RegisterRow;
    const csv = registerCsv([row]);
    expect(csv).toContain('"Leak, basin"');
    expect(csv).toContain("565,50.85,615.85");
    expect(csv).toContain("Invoice to confirm");
  });
});

describe("Notices (D-38)", () => {
  it("words each notice and knows when it is still waiting for the reader", () => {
    expect(noticeText("work_order_invoice_uploaded").href).toBe("#payment-heading");
    expect(noticeText("something_new").text).toBe("something new");
    expect(waitingForReader({ status: "reviewed", assigned_technician_id: null, in_house_work: false }, { id: "f", role: "finance" })).toBe(true);
    expect(waitingForReader({ status: "closed", assigned_technician_id: null, in_house_work: false }, { id: "f", role: "finance" })).toBe(false);
    expect(waitingForReader({ status: "submitted", assigned_technician_id: "t", in_house_work: false }, { id: "a", role: "approver" })).toBe(true);
    expect(waitingForReader({ status: "approved", assigned_technician_id: "t", in_house_work: false }, { id: "t", role: "technician" })).toBe(true);
  });
});
