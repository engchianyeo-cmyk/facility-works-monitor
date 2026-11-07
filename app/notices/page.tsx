import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { noticeText, waitingForReader } from "@/lib/notices";
import NoticesList, { type NoticeItem } from "@/components/notices/notices-list";

export const revalidate = 0;

// D-38 (7 Nov 2026): every notice sent to the signed-in person, newest first, with what is still waiting for them.
export default async function MyNoticesPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/notices");
  const supabase = await createClient();
  const { data, error } = await supabase.from("notification_outbox")
    .select("id,work_order_id,event_type,created_at,read_at,delivery_status")
    .eq("recipient_profile_id", identity.userId).order("created_at", { ascending: false }).limit(300);
  const rows = (data ?? []) as Array<{ id: string; work_order_id: string | null; event_type: string; created_at: string; read_at: string | null; delivery_status: string }>;
  const orderIds = Array.from(new Set(rows.map((row) => row.work_order_id).filter(Boolean))) as string[];
  const { data: orders } = orderIds.length
    ? await supabase.from("work_orders").select("id,work_order_number,title,status,assigned_technician_id,in_house_work").in("id", orderIds)
    : { data: [] };
  const orderOf = new Map((orders ?? []).map((row) => [(row as { id: string }).id, row as { id: string; work_order_number: string | null; title: string; status: string; assigned_technician_id: string | null; in_house_work: boolean | null }]));
  const items: NoticeItem[] = rows.map((row) => {
    const order = row.work_order_id ? orderOf.get(row.work_order_id) : undefined;
    const meaning = noticeText(row.event_type);
    return {
      id: row.id, createdAt: row.created_at, read: Boolean(row.read_at), emailStatus: row.delivery_status,
      workOrderId: row.work_order_id, workOrderLabel: order ? `${order.work_order_number ?? ""} ${order.title}`.trim() : "Work Order",
      text: meaning.text, href: row.work_order_id ? `/work-orders/${row.work_order_id}${meaning.href}` : "",
      waiting: waitingForReader(order, { id: identity.userId, role: identity.role }),
    };
  });
  return (
    <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-8">
      <header>
        <h1 className="text-3xl font-black">My notices</h1>
        <p className="mt-2 text-slate-600">Everything the app has sent you, newest first. Work Orders still waiting for you are at the top, outlined in red. Email delivery is not connected yet, so this page is where notices arrive.</p>
        {identity.role === "administrator" && <p className="mt-2 text-sm"><Link href="/administration/notices" className="font-semibold text-blue-700 underline">All notices and delivery status</Link></p>}
      </header>
      {error ? <p role="alert" className="rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950">Notices are not available in this environment yet (database update D-38 not applied).</p>
        : <NoticesList items={items} />}
    </main>
  );
}
