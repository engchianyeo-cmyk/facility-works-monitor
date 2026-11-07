/** D-39 (7 Nov 2026): Finance's completed work register - row shape, statuses and formatting. */
export type RegisterRow = {
  work_order_id: string; work_order_number: string | null; title: string; facility_name: string | null; status: string;
  in_house_work: boolean; emergency_work: boolean; contractor_name: string | null; technician_name: string | null;
  approved_by_name: string | null; approved_at: string | null; completed_by_name: string | null; completed_at: string | null; closed_at: string | null;
  work_performed: string | null; actual_labour_hours: number | null; actual_work_started_at: string | null; actual_work_ended_at: string | null;
  approved_amount: number | null; final_amount: number | null; invoice_reference: string | null; invoice_amount: number | null;
  invoice_uploaded_at: string | null; invoice_received_at: string | null; payment_due_at: string | null; payment_terms_days: number | null;
  paid_at: string | null; paid_amount: number | null; payment_reference: string | null; register_status: string;
};

export const GST_RATE = 0.09;

export const REGISTER_STATUS: Record<string, { label: string; tone: string; financeAction: boolean }> = {
  invoice_uploaded: { label: "Invoice to confirm", tone: "bg-red-100 text-red-900", financeAction: true },
  overdue: { label: "Overdue", tone: "bg-red-600 text-white", financeAction: true },
  invoice_received: { label: "Awaiting payment", tone: "bg-blue-100 text-blue-900", financeAction: true },
  awaiting_invoice: { label: "Awaiting contractor invoice", tone: "bg-amber-100 text-amber-900", financeAction: false },
  paid: { label: "Paid", tone: "bg-emerald-100 text-emerald-900", financeAction: false },
  in_house: { label: "In-house — no payment", tone: "bg-slate-100 text-slate-800", financeAction: false },
  closed_no_payment: { label: "Closed — no payment recorded", tone: "bg-slate-100 text-slate-800", financeAction: false },
};

export const money = (value: number | null | undefined) => value === null || value === undefined ? "—"
  : `S$${new Intl.NumberFormat("en-SG", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value))}`;
export const day = (value: string | null | undefined) => value ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeZone: "Asia/Singapore" }).format(new Date(value)) : "—";
export const sgtMonth = (value: string | null) => value ? new Intl.DateTimeFormat("sv-SE", { year: "numeric", month: "2-digit", timeZone: "Asia/Singapore" }).format(new Date(value)) : "";

/** Whole days from today (Singapore) to the due date; negative when overdue. */
export function daysLeft(due: string | null, now = new Date()): number | null {
  if (!due) return null;
  const toDay = (value: Date) => new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Singapore" }).format(value);
  return Math.round((Date.parse(toDay(new Date(due))) - Date.parse(toDay(now))) / 86_400_000);
}

export function dueNote(row: Pick<RegisterRow, "register_status" | "payment_due_at">): { text: string; tone: string } | null {
  if (!["invoice_received", "overdue"].includes(row.register_status)) return null;
  const left = daysLeft(row.payment_due_at);
  if (left === null) return null;
  if (left < 0) return { text: `${-left} day${left === -1 ? "" : "s"} overdue`, tone: "font-black text-red-700" };
  if (left === 0) return { text: "due today", tone: "font-black text-red-700" };
  return { text: `${left} day${left === 1 ? "" : "s"} left`, tone: left <= 7 ? "font-bold text-amber-700" : "text-slate-700" };
}

const csvCell = (value: unknown) => {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
};

export function registerCsv(rows: RegisterRow[]): string {
  const header = ["Work Order", "Title", "Facility", "Done by", "Contractor", "Approved by", "Completed", "Final amount before GST", "Invoice", "Invoice amount before GST",
    "GST 9%", "Invoice total", "Invoice received", "Payment terms (days)", "Payment due", "Paid on", "Paid amount", "Payment reference", "Status"];
  const lines = rows.map((row) => {
    const gst = row.invoice_amount === null ? null : Math.round(row.invoice_amount * GST_RATE * 100) / 100;
    return [row.work_order_number, row.title, row.facility_name, row.in_house_work ? "In-house" : "Contractor", row.contractor_name, row.approved_by_name,
      day(row.completed_at), row.final_amount, row.invoice_reference, row.invoice_amount, gst, gst === null ? null : Math.round(((row.invoice_amount ?? 0) + gst) * 100) / 100,
      day(row.invoice_received_at), row.payment_terms_days, day(row.payment_due_at), day(row.paid_at), row.paid_amount, row.payment_reference,
      REGISTER_STATUS[row.register_status]?.label ?? row.register_status].map(csvCell).join(",");
  });
  return [header.map(csvCell).join(","), ...lines].join("\n");
}
