import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export const revalidate = 0;

type Row = { work_order_id: string; work_order_number: string; title: string; vendor_name: string | null; approved_amount: number; completed_at: string | null;
  invoice_reference: string | null; invoice_amount: number | null; invoice_uploaded_at: string | null; invoice_received_at: string | null; payment_due_at: string | null;
  paid_at: string | null; paid_amount: number | null; payment_status: string };

const STATUS: Record<string, { label: string; tone: string }> = {
  awaiting_invoice: { label: "Awaiting invoice", tone: "bg-slate-100 text-slate-800" },
  invoice_uploaded: { label: "Invoice uploaded — confirm receipt", tone: "bg-amber-100 text-amber-900" },
  invoice_received: { label: "Invoice received — payment due", tone: "bg-blue-100 text-blue-900" },
  overdue: { label: "Overdue", tone: "bg-red-100 text-red-900" },
  paid: { label: "Paid", tone: "bg-emerald-100 text-emerald-900" },
};
const money = (value: number | null) => value === null ? "—" : `S$${new Intl.NumberFormat("en-SG", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value))}`;
const day = (value: string | null) => value ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeZone: "Asia/Singapore" }).format(new Date(value)) : "—";

export default async function FinancePage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/finance");
  if (!["finance", "administrator"].includes(identity.role)) return <main className="p-8"><h1 className="text-2xl font-bold">Access denied</h1><p>The payment tracker is available to Finance and the Administrator.</p></main>;
  const { status } = await searchParams;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("work_order_finance_tracker");
  const rows = (error ? [] : (data ?? []) as Row[]);
  const shown = status && STATUS[status] ? rows.filter((row) => row.payment_status === status) : rows;
  const counts = Object.fromEntries(Object.keys(STATUS).map((key) => [key, rows.filter((row) => row.payment_status === key).length]));
  return <main className="mx-auto max-w-7xl space-y-6 p-4 sm:p-8">
    <div>
      <h1 className="text-3xl font-black">Contractor payments</h1>
      <p className="mt-2 text-slate-600">Completed Work Orders with an approved payable. Payment terms run from the date Finance receives the invoice. Open a Work Order to confirm receipt or record payment.</p>
    </div>
    {error && <p role="alert" className="rounded border border-red-300 bg-red-50 p-4 text-red-800">The payment tracker could not be loaded.</p>}
    <nav aria-label="Filter by payment status" className="flex flex-wrap gap-2">
      <Link href="/finance" className={`rounded-full px-4 py-2 text-sm font-bold ${!status ? "bg-slate-900 text-white" : "bg-white border"}`}>All ({rows.length})</Link>
      {Object.entries(STATUS).map(([key, value]) => <Link key={key} href={`/finance?status=${key}`} className={`rounded-full px-4 py-2 text-sm font-bold ${status === key ? "bg-slate-900 text-white" : "bg-white border"}`}>{value.label} ({counts[key]})</Link>)}
    </nav>
    {shown.length === 0 ? <p className="rounded border border-dashed p-6 text-slate-600">Nothing to show.</p> : (
      <div className="overflow-x-auto rounded-xl border bg-white">
        <table className="min-w-full text-sm">
          <thead className="bg-slate-50 text-left"><tr>{["Work Order", "Contractor", "Approved", "Invoice", "Received", "Due", "Paid", "Status"].map((heading) => <th key={heading} className="px-4 py-3 font-bold">{heading}</th>)}</tr></thead>
          <tbody className="divide-y">
            {shown.map((row) => <tr key={row.work_order_id}>
              <td className="px-4 py-3"><Link href={`/work-orders/${row.work_order_id}`} className="font-bold text-blue-700 hover:underline">{row.work_order_number}</Link><p className="text-slate-600">{row.title}</p></td>
              <td className="px-4 py-3">{row.vendor_name ?? "—"}</td>
              <td className="px-4 py-3">{money(row.approved_amount)}</td>
              <td className="px-4 py-3">{row.invoice_reference ? `${row.invoice_reference} · ${money(row.invoice_amount)}` : "—"}</td>
              <td className="px-4 py-3">{day(row.invoice_received_at)}</td>
              <td className="px-4 py-3">{day(row.payment_due_at)}</td>
              <td className="px-4 py-3">{row.paid_at ? `${money(row.paid_amount)} on ${day(row.paid_at)}` : "—"}</td>
              <td className="px-4 py-3"><span className={`rounded-full px-3 py-1 text-xs font-bold ${STATUS[row.payment_status]?.tone ?? ""}`}>{STATUS[row.payment_status]?.label ?? row.payment_status}</span></td>
            </tr>)}
          </tbody>
        </table>
      </div>
    )}
  </main>;
}
