import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { noticeText } from "@/lib/notices";
import { emailStatusLabel } from "@/lib/notifications/email-rules";
import { scheduleEmailDispatch } from "@/lib/notifications/schedule-email";

export const revalidate = 0;

const STATUS: Record<string, string> = { pending: "Queued (not sent)", processing: "Sending", sent: "Sent", delivered: "Delivered", failed: "Failed", suppressed: "Not sent (suppressed)" };
const sgt = (value: string | null) => value ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Singapore" }).format(new Date(value)) : "—";

// D-38 (7 Nov 2026): every notice the app has queued, who it is for, and whether it was delivered or read.
export default async function AllNoticesPage({ searchParams }: { searchParams: Promise<{ status?: string; event?: string }> }) {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/administration/notices");
  if (identity.role !== "administrator") return <main className="p-8"><h1 className="text-2xl font-bold">Access denied</h1><p>This page is for Administrators.</p></main>;
  scheduleEmailDispatch();
  const { status, event } = await searchParams;
  const supabase = await createClient();
  let query = supabase.from("notification_outbox")
    .select("id,work_order_id,event_type,recipient_profile_id,recipient_email,delivery_status,attempts,last_error,created_at,read_at,result_code,sent_at")
    .order("created_at", { ascending: false }).limit(500);
  if (status) query = query.eq("delivery_status", status);
  if (event) query = query.eq("event_type", event);
  const [{ data, error }, { data: all }] = await Promise.all([query, supabase.from("notification_outbox").select("delivery_status,event_type").limit(5000)]);
  const rows = (data ?? []) as Array<{ id: string; work_order_id: string | null; event_type: string; recipient_profile_id: string | null; recipient_email: string | null; delivery_status: string; attempts: number; last_error: string | null; created_at: string; read_at: string | null; result_code: string | null; sent_at: string | null }>;
  const profileIds = Array.from(new Set(rows.map((row) => row.recipient_profile_id).filter(Boolean))) as string[];
  const orderIds = Array.from(new Set(rows.map((row) => row.work_order_id).filter(Boolean))) as string[];
  const [{ data: people }, { data: orders }] = await Promise.all([
    profileIds.length ? supabase.from("profiles").select("id,display_name,role").in("id", profileIds) : Promise.resolve({ data: [] }),
    orderIds.length ? supabase.from("work_orders").select("id,work_order_number").in("id", orderIds) : Promise.resolve({ data: [] }),
  ]);
  const personOf = new Map((people ?? []).map((row) => [(row as { id: string }).id, row as { display_name: string | null; role: string }]));
  const orderOf = new Map((orders ?? []).map((row) => [(row as { id: string }).id, (row as { work_order_number: string | null }).work_order_number]));
  const counts = ((all ?? []) as Array<{ delivery_status: string; event_type: string }>).reduce<Record<string, number>>((acc, row) => { acc[row.delivery_status] = (acc[row.delivery_status] ?? 0) + 1; return acc; }, {});
  const events = Array.from(new Set(((all ?? []) as Array<{ event_type: string }>).map((row) => row.event_type))).sort();
  const chip = (active: boolean) => `rounded-full px-3 py-1.5 text-sm font-bold ${active ? "bg-slate-900 text-white" : "border bg-white"}`;

  return (
    <main className="mx-auto max-w-7xl space-y-5 p-4 sm:p-8">
      <header>
        <p className="text-sm font-black uppercase tracking-widest text-blue-700">Administration</p>
        <h1 className="text-3xl font-black">All notices and delivery status</h1>
        <p className="mt-2 max-w-3xl text-slate-600">Every notice the app has queued. Notices that ask the reader to act are emailed from the app&apos;s mail account once email is switched on (decision D-42); the rest are &quot;in app only&quot;. Notices older than a day when email was switched on stay &quot;Queued&quot;. Each person sees theirs on <Link href="/notices" className="font-semibold text-blue-700 underline">My notices</Link> and the bell in the header.</p>
      </header>
      {error && <p role="alert" className="rounded border border-red-300 bg-red-50 p-4 text-red-800">Notices could not be loaded.</p>}
      <nav aria-label="Filter by delivery status" className="flex flex-wrap gap-2">
        <Link href="/administration/notices" className={chip(!status)}>All</Link>
        {Object.entries(counts).map(([key, count]) => <Link key={key} href={`/administration/notices?status=${key}`} className={chip(status === key)}>{STATUS[key] ?? key} ({count})</Link>)}
      </nav>
      <nav aria-label="Filter by event" className="flex flex-wrap gap-2 text-xs">
        {events.map((key) => <Link key={key} href={`/administration/notices?event=${key}${status ? `&status=${status}` : ""}`} className={chip(event === key)}>{noticeText(key).text}</Link>)}
      </nav>
      <div className="overflow-x-auto rounded-xl border bg-white">
        <table className="min-w-full text-sm">
          <thead className="bg-slate-50 text-left"><tr>{["Queued", "To", "Work Order", "Notice", "Email", "Read in app"].map((heading) => <th key={heading} className="px-3 py-2 font-bold">{heading}</th>)}</tr></thead>
          <tbody className="divide-y">
            {rows.map((row) => {
              const person = row.recipient_profile_id ? personOf.get(row.recipient_profile_id) : undefined;
              const number = row.work_order_id ? orderOf.get(row.work_order_id) : null;
              return (
                <tr key={row.id}>
                  <td className="whitespace-nowrap px-3 py-2">{sgt(row.created_at)}</td>
                  <td className="px-3 py-2">{person?.display_name ?? "—"}<br /><span className="text-xs text-slate-500">{person?.role?.replace("_", " ") ?? ""}{row.recipient_email ? ` · ${row.recipient_email}` : ""}</span></td>
                  <td className="px-3 py-2">{row.work_order_id ? <Link href={`/work-orders/${row.work_order_id}`} className="font-bold text-blue-700 hover:underline">{number ?? "Open"}</Link> : "—"}</td>
                  <td className="px-3 py-2">{row.event_type === "finance_daily_reminder" ? "daily payment reminder" : noticeText(row.event_type).text}</td>
                  <td className="px-3 py-2">{row.result_code && row.result_code !== "SENT" ? emailStatusLabel(row.delivery_status, row.result_code) : STATUS[row.delivery_status] ?? row.delivery_status}{row.sent_at ? ` ${sgt(row.sent_at)}` : ""}{row.attempts ? ` · ${row.attempts} attempt(s)` : ""}{row.last_error ? <><br /><span className="text-xs text-red-700">{row.last_error}</span></> : null}</td>
                  <td className="px-3 py-2">{row.read_at ? sgt(row.read_at) : "Not yet"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </main>
  );
}
