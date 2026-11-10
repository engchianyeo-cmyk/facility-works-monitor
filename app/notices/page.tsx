import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { currentNoticeIds, noticeText, waitingForReader } from "@/lib/notices";
import { workOrderStatusLabel } from "@/lib/product-terminology";
import NoticesList, { type NoticeItem } from "@/components/notices/notices-list";
import { emailStatusLabel } from "@/lib/notifications/email-rules";
import { scheduleEmailDispatch } from "@/lib/notifications/schedule-email";

export const revalidate = 0;

// D-38 (7 Nov 2026): every notice sent to the signed-in person, newest first, with what is still waiting for them.
export default async function MyNoticesPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/notices");
  scheduleEmailDispatch();
  const supabase = await createClient();
  const { data, error } = await supabase.from("notification_outbox")
    .select("id,work_order_id,event_type,created_at,read_at,delivery_status,result_code")
    .eq("recipient_profile_id", identity.userId).order("created_at", { ascending: false }).limit(300);
  const all = (data ?? []) as Array<{ id: string; work_order_id: string | null; event_type: string; created_at: string; read_at: string | null; delivery_status: string; result_code: string | null }>;
  // D-42: repeats of the same notice for the same Work Order show once, with the latest time (newest rows come first).
  const groups = new Map<string, { row: (typeof all)[number]; ids: string[]; read: boolean }>();
  for (const row of all) {
    const key = row.event_type === "finance_daily_reminder" ? row.id : `${row.work_order_id}|${row.event_type}`;
    const group = groups.get(key);
    if (group) { group.ids.push(row.id); group.read &&= Boolean(row.read_at); } else groups.set(key, { row, ids: [row.id], read: Boolean(row.read_at) });
  }
  const rows = Array.from(groups.values());
  const orderIds = Array.from(new Set(rows.map(({ row }) => row.work_order_id).filter(Boolean))) as string[];
  const { data: orders } = orderIds.length
    ? await supabase.from("work_orders").select("id,work_order_number,title,status,assigned_technician_id,in_house_work,second_technician_id").in("id", orderIds)
    : { data: [] };
  // D-49: review endorsements already given by the reader (the named Technician 2 is then no longer waited for).
  const { data: myEndorsements } = orderIds.length && identity.role === "technician"
    ? await supabase.from("work_order_endorsements").select("work_order_id").eq("endorsed_by", identity.userId).eq("stage", "review").in("work_order_id", orderIds)
    : { data: [] };
  const endorsedByMe = new Set((myEndorsements ?? []).map((row) => (row as { work_order_id: string }).work_order_id));
  const orderOf = new Map((orders ?? []).map((row) => [(row as { id: string }).id, row as { id: string; work_order_number: string | null; title: string; status: string; assigned_technician_id: string | null; in_house_work: boolean | null; second_technician_id: string | null }]));
  // D-43 (9 Nov 2026): the most current notices first; superseded and finished ones under Earlier notices.
  const current = currentNoticeIds(all, (workOrderId) => orderOf.get(workOrderId)?.status);
  const items: NoticeItem[] = rows.map(({ row, ids, read }) => {
    const emailStatus = emailStatusLabel(row.delivery_status, row.result_code);
    if (row.event_type === "finance_daily_reminder") {
      return { id: row.id, ids, repeats: 1, createdAt: row.created_at, read, emailStatus, workOrderId: null, workOrderLabel: "Daily payment reminder",
        text: "invoices to confirm and payments due or overdue", href: "/finance/register", waiting: false, current: current.has(row.id), statusLabel: null };
    }
    const order = row.work_order_id ? orderOf.get(row.work_order_id) : undefined;
    const meaning = noticeText(row.event_type);
    return {
      id: row.id, ids, repeats: ids.length, createdAt: row.created_at, read, emailStatus,
      workOrderId: row.work_order_id, workOrderLabel: order ? `${order.work_order_number ?? ""} ${order.title}`.trim() : "Work Order",
      text: meaning.text, href: row.work_order_id ? `/work-orders/${row.work_order_id}${meaning.href}` : "",
      waiting: waitingForReader(order, { id: identity.userId, role: identity.role }, Boolean(row.work_order_id && endorsedByMe.has(row.work_order_id))),
      current: current.has(row.id),
      statusLabel: order ? workOrderStatusLabel(order.status) : null,
    };
  });
  return (
    <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-8">
      <header>
        <h1 className="text-3xl font-black">My notices</h1>
        <p className="mt-2 text-slate-600">Work Orders waiting for you are at the top, outlined in red; then the latest notice for each open Work Order. Older notices are kept under Earlier notices. Notices that need you to act are also emailed to you (once email is switched on); everything else arrives only here.</p>
        {identity.role === "administrator" && <p className="mt-2 text-sm"><Link href="/administration/notices" className="font-semibold text-blue-700 underline">All notices and delivery status</Link></p>}
      </header>
      {error ? <p role="alert" className="rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950">Notices are not available in this environment yet (database update D-38 not applied).</p>
        : <NoticesList items={items} />}
    </main>
  );
}
