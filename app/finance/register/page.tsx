import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { GST_RATE, REGISTER_STATUS, day, daysLeft, dueNote, money, registerCsv, sgtMonth, type RegisterRow } from "@/lib/finance-register";

export const revalidate = 0;

type Filters = { status?: string; by?: string; month?: string; facility?: string };

// D-39 (7 Nov 2026): every Work Order approved as Completed - in-house or contractor - with payment due dates.
export default async function CompletedWorkRegisterPage({ searchParams }: { searchParams: Promise<Filters> }) {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/finance/register");
  if (!["finance", "administrator"].includes(identity.role)) return <main className="p-8"><h1 className="text-2xl font-bold">Access denied</h1><p>The completed work register is for Finance and the Administrator.</p></main>;
  const filters = await searchParams;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("finance_completed_work_register");
  const rows = (error ? [] : (data ?? []) as RegisterRow[]);
  const shown = rows.filter((row) =>
    (!filters.status || row.register_status === filters.status)
    && (!filters.by || (filters.by === "in_house" ? row.in_house_work : !row.in_house_work))
    && (!filters.month || sgtMonth(row.completed_at) === filters.month)
    && (!filters.facility || row.facility_name === filters.facility));

  const outstanding = rows.filter((row) => ["invoice_uploaded", "invoice_received", "overdue"].includes(row.register_status));
  const sum = (list: RegisterRow[]) => list.reduce((total, row) => total + Number(row.invoice_amount ?? row.final_amount ?? 0), 0);
  const dueSoon = rows.filter((row) => row.register_status === "invoice_received" && (daysLeft(row.payment_due_at) ?? 99) <= 7);
  const overdue = rows.filter((row) => row.register_status === "overdue");
  const thisMonth = sgtMonth(new Date().toISOString());
  const paidThisMonth = rows.filter((row) => row.register_status === "paid" && sgtMonth(row.paid_at) === thisMonth);
  const months = Array.from(new Set(rows.map((row) => sgtMonth(row.completed_at)).filter(Boolean))).sort().reverse();
  const facilities = Array.from(new Set(rows.map((row) => row.facility_name).filter(Boolean))) as string[];
  const link = (change: Filters) => {
    const next = { ...filters, ...change };
    const query = Object.entries(next).filter(([, value]) => value).map(([key, value]) => `${key}=${encodeURIComponent(String(value))}`).join("&");
    return `/finance/register${query ? `?${query}` : ""}`;
  };
  const chip = (active: boolean) => `rounded-full px-3 py-1.5 text-sm font-bold ${active ? "bg-slate-900 text-white" : "border bg-white"}`;
  const csvHref = `data:text/csv;charset=utf-8,${encodeURIComponent(registerCsv(shown))}`;

  return (
    <main className="mx-auto max-w-[96rem] space-y-5 p-4 sm:p-8">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-sm font-black uppercase tracking-widest text-emerald-700"><Link href="/finance" className="hover:underline">Finance</Link></p>
          <h1 className="text-3xl font-black">Completed work register</h1>
          <p className="mt-2 max-w-3xl text-slate-600">Every Work Order approved as Completed, in-house or by a contractor. Payment is due a number of days after Finance confirms the invoice was received (standard terms until each facility&apos;s own terms are set). Rows needing Finance are outlined in red.</p>
        </div>
        <a href={csvHref} download={`completed-work-register-${new Date().toISOString().slice(0, 10)}.csv`} className="rounded-lg border border-slate-300 bg-white px-4 py-2 text-sm font-bold">Download as spreadsheet (CSV)</a>
      </header>
      {error && <p role="alert" className="rounded border border-amber-300 bg-amber-50 p-4 text-amber-950">The register is not available in this environment yet (database update D-39 not applied).</p>}

      <section aria-label="Totals" className="grid gap-3 sm:grid-cols-4">
        {[
          { label: "Outstanding (before GST)", value: money(sum(outstanding)), note: `${outstanding.length} invoice(s)`, tone: "border-slate-200" },
          { label: "Due in the next 7 days", value: money(sum(dueSoon)), note: `${dueSoon.length} invoice(s)`, tone: dueSoon.length ? "border-amber-400" : "border-slate-200" },
          { label: "Overdue", value: money(sum(overdue)), note: `${overdue.length} invoice(s)`, tone: overdue.length ? "border-red-500" : "border-slate-200" },
          { label: "Paid this month", value: money(paidThisMonth.reduce((total, row) => total + Number(row.paid_amount ?? 0), 0)), note: `${paidThisMonth.length} payment(s)`, tone: "border-slate-200" },
        ].map((tile) => <div key={tile.label} className={`rounded-xl border-2 bg-white p-4 ${tile.tone}`}><p className="text-sm font-bold text-slate-600">{tile.label}</p><p className="text-2xl font-black">{tile.value}</p><p className="text-xs text-slate-500">{tile.note}</p></div>)}
      </section>

      <nav aria-label="Filter the register" className="space-y-2">
        <div className="flex flex-wrap gap-2">
          <Link href={link({ status: undefined })} className={chip(!filters.status)}>All statuses</Link>
          {Object.entries(REGISTER_STATUS).map(([key, value]) => <Link key={key} href={link({ status: key })} className={chip(filters.status === key)}>{value.label} ({rows.filter((row) => row.register_status === key).length})</Link>)}
        </div>
        <div className="flex flex-wrap gap-2">
          <Link href={link({ by: undefined })} className={chip(!filters.by)}>In-house and contractor</Link>
          <Link href={link({ by: "in_house" })} className={chip(filters.by === "in_house")}>In-house only</Link>
          <Link href={link({ by: "contractor" })} className={chip(filters.by === "contractor")}>Contractor only</Link>
          <span className="mx-1 self-center text-slate-300">|</span>
          <Link href={link({ month: undefined })} className={chip(!filters.month)}>All months</Link>
          {months.map((month) => <Link key={month} href={link({ month })} className={chip(filters.month === month)}>{month}</Link>)}
          {facilities.length > 1 && <>
            <span className="mx-1 self-center text-slate-300">|</span>
            <Link href={link({ facility: undefined })} className={chip(!filters.facility)}>All facilities</Link>
            {facilities.map((facility) => <Link key={facility} href={link({ facility })} className={chip(filters.facility === facility)}>{facility}</Link>)}
          </>}
        </div>
      </nav>

      {shown.length === 0 ? <p className="rounded border border-dashed p-6 text-slate-600">Nothing to show.</p> : (
        <div className="overflow-x-auto rounded-xl border bg-white">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50 text-left"><tr>{["Work Order", "Facility", "Done by", "Approved by", "Completed", "Invoice (before GST · with GST)", "Received", "Payment due", "Paid", "Status"].map((heading) => <th key={heading} className="px-3 py-2 font-bold">{heading}</th>)}</tr></thead>
            <tbody className="divide-y">
              {shown.map((row) => {
                const meta = REGISTER_STATUS[row.register_status];
                const due = dueNote(row);
                const withGst = row.invoice_amount === null ? null : row.invoice_amount * (1 + GST_RATE);
                return (
                  <tr key={row.work_order_id} className={meta?.financeAction ? "outline outline-2 -outline-offset-2 outline-red-400" : ""}>
                    <td className="px-3 py-2"><Link href={`/work-orders/${row.work_order_id}`} className="font-bold text-blue-700 hover:underline">{row.work_order_number}</Link><p className="text-slate-600">{row.title}</p></td>
                    <td className="px-3 py-2">{row.facility_name ?? "—"}</td>
                    <td className="px-3 py-2">{row.in_house_work ? <b>In-house</b> : <><b>Contractor</b><br />{row.contractor_name ?? "—"}</>}{row.emergency_work && <span className="ml-1 rounded bg-red-100 px-1.5 text-xs font-bold text-red-800">Emergency</span>}</td>
                    <td className="px-3 py-2">{row.approved_by_name ?? "—"}<br /><span className="text-xs text-slate-500">{day(row.approved_at)}</span></td>
                    <td className="px-3 py-2">{day(row.completed_at)}<br /><span className="text-xs text-slate-500">{row.completed_by_name ?? ""}</span></td>
                    <td className="px-3 py-2">{row.in_house_work ? <span className="text-slate-500">No invoice{row.final_amount ? ` · cost ${money(row.final_amount)}` : ""}</span>
                      : row.invoice_reference ? <>{row.invoice_reference}<br />{money(row.invoice_amount)} · {money(withGst)}</> : <span className="text-slate-500">Not yet{row.final_amount ? ` · final ${money(row.final_amount)}` : ""}</span>}</td>
                    <td className="px-3 py-2">{day(row.invoice_received_at)}</td>
                    <td className="px-3 py-2">{row.in_house_work ? "—" : <>{day(row.payment_due_at)}{row.payment_terms_days ? <span className="text-xs text-slate-500"> ({row.payment_terms_days} days)</span> : null}{due && <><br /><span className={due.tone}>{due.text}</span></>}</>}</td>
                    <td className="px-3 py-2">{row.paid_at ? <>{money(row.paid_amount)}<br /><span className="text-xs text-slate-500">{day(row.paid_at)}{row.payment_reference ? ` · ${row.payment_reference}` : ""}</span></> : "—"}</td>
                    <td className="px-3 py-2"><span className={`rounded-full px-3 py-1 text-xs font-bold ${meta?.tone ?? ""}`}>{meta?.label ?? row.register_status}</span></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </main>
  );
}
