import { GST_RATE, REGISTER_STATUS, day, dueNote, money, type RegisterRow } from "@/lib/finance-register";

const dateTime = (value: string | null) => value ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Singapore" }).format(new Date(value)) : "—";

/** D-39 (7 Nov 2026): what Finance needs from a completed Work Order, in one box at the top of the page. */
export default function FinanceSummary({ row, status }: { row: RegisterRow | null; status: string }) {
  if (!row) {
    return (
      <section aria-label="For Finance" className="rounded-xl border border-slate-200 bg-white p-4 text-sm">
        <h2 className="font-black">For Finance</h2>
        <p className="mt-1 text-slate-700">{status === "cancelled" ? "Cancelled — nothing for Finance." : "Not yet approved as Completed — nothing for Finance yet."}</p>
      </section>
    );
  }
  const meta = REGISTER_STATUS[row.register_status];
  const due = dueNote(row);
  const gst = row.invoice_amount === null ? null : Math.round(row.invoice_amount * GST_RATE * 100) / 100;
  const action = row.register_status === "invoice_uploaded" ? "Confirm the date the invoice was received (this starts the payment terms)."
    : ["invoice_received", "overdue"].includes(row.register_status) ? "Record the payment once made." : null;
  return (
    <section aria-label="For Finance" className={`rounded-xl border-2 bg-white p-4 text-sm ${action ? "border-red-500" : "border-emerald-300"}`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-lg font-black">For Finance</h2>
        <span className={`rounded-full px-3 py-1 text-xs font-bold ${meta?.tone ?? ""}`}>{meta?.label ?? row.register_status}</span>
      </div>
      {action && <p className="mt-2 rounded bg-red-600 px-3 py-2 font-bold text-white">Action needed: {action} <a href="#payment-heading" className="underline">Go to Contractor Invoice and Payment →</a></p>}
      <dl className="mt-3 grid gap-x-6 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
        <div><dt className="font-bold">Work done by</dt><dd>{row.in_house_work ? "In-house team — no invoice and no payment" : `Contractor: ${row.contractor_name ?? "—"}`}{row.emergency_work ? " · emergency work" : ""}</dd></div>
        <div><dt className="font-bold">Approved</dt><dd>{row.approved_by_name ?? "—"} · {dateTime(row.approved_at)}</dd></div>
        <div><dt className="font-bold">Approved as Completed</dt><dd>{row.completed_by_name ?? "—"} · {dateTime(row.completed_at)}</dd></div>
        <div className="sm:col-span-2 lg:col-span-3"><dt className="font-bold">Work performed{row.technician_name ? ` (Technician: ${row.technician_name})` : ""}</dt>
          <dd className="mt-1 whitespace-pre-line rounded border border-slate-200 bg-slate-50 p-2">{row.work_performed?.trim() || "No statement recorded."}</dd>
          <dd className="mt-1 text-slate-600">Labour hours: {row.actual_labour_hours ?? "—"} · Actual start {dateTime(row.actual_work_started_at)} → end {dateTime(row.actual_work_ended_at)}</dd></div>
        <div><dt className="font-bold">Amounts (before GST)</dt><dd>Approved {money(row.approved_amount)} · Final {money(row.final_amount)}</dd></div>
        {!row.in_house_work && <>
          <div><dt className="font-bold">Contractor invoice</dt><dd>{row.invoice_reference
            ? <>{row.invoice_reference} · {money(row.invoice_amount)} + GST {money(gst)} = <b>{money(gst === null ? null : (row.invoice_amount ?? 0) + gst)}</b><br /><span className="text-slate-600">Uploaded {day(row.invoice_uploaded_at)} · received {day(row.invoice_received_at)}</span></>
            : "Not yet uploaded by the Technician"}</dd></div>
          <div><dt className="font-bold">Payment</dt><dd>{row.paid_at ? <>Paid {money(row.paid_amount)} on {day(row.paid_at)}{row.payment_reference ? ` · ref ${row.payment_reference}` : ""}</>
            : row.payment_due_at ? <>Due {day(row.payment_due_at)}{row.payment_terms_days ? ` (${row.payment_terms_days} days)` : ""}{due && <> · <span className={due.tone}>{due.text}</span></>}</> : "Due date set when the invoice receipt is confirmed"}</dd></div>
        </>}
      </dl>
    </section>
  );
}
