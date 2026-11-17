import Link from "next/link";
import EmptyState from "@/components/ui/EmptyState";
import SectionTitle from "@/components/ui/SectionTitle";
import StatusChip from "@/components/ui/StatusChip";
import { priorityLabel, workOrderStatusLabel } from "@/lib/product-terminology";

export type MissionWorkOrder = {
  id: string;
  work_order_number: string;
  title: string;
  status: string;
  priority: string;
  due_date: string | null;
  completed_at?: string | null;
  created_at: string;
  emergency_work?: boolean;
  assigned_technician_id?: string | null;
  assigned_vendor_id?: string | null;
  assigned_team_id?: string | null;
  assigned_to?: string | null;
  location?: string;
  site?: string | null;
  facility?: { name: string } | Array<{ name: string }> | null;
};

/** UAT 16 Nov 2026: the home list shows open work only, and names each Work Order's facility. */
const FINISHED = new Set(["closed", "cancelled"]);
function facilityName(order: MissionWorkOrder): string | null {
  const facility = Array.isArray(order.facility) ? order.facility[0] : order.facility;
  return facility?.name ?? null;
}

export default function OperationsSummary({ orders: allOrders }: { orders: MissionWorkOrder[] }) {
  const orders = allOrders.filter((order) => !FINISHED.has(order.status));
  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5">
      <SectionTitle title="Active facility work" action={<Link href="/work-orders" className="text-sm font-bold text-blue-700 hover:underline">All work orders →</Link>} />
      <div className="mt-4">
        {!orders.length ? (
          <EmptyState title="No open work orders" description="New operational work will appear here. Closed and Cancelled ones are in the Work Orders list." />
        ) : (
          <ul className="divide-y divide-slate-100">
            {orders.slice(0, 6).map((order) => (
              <li key={order.id} className="py-3">
                <Link href={`/work-orders/${order.id}`} className="flex items-start justify-between gap-3 hover:text-blue-700">
                  <div>
                    <p className="font-mono text-xs font-bold text-slate-500">{order.work_order_number}</p>
                    <p className="font-bold">{order.title}</p>
                    <p className="text-xs text-slate-500">{facilityName(order) ? <span className="font-semibold text-slate-700">{facilityName(order)} · </span> : null}Due {order.due_date || "not set"}</p>
                  </div>
                  <div className="flex flex-wrap justify-end gap-1">
                    <StatusChip tone={order.status === "closed" ? "neutral" : order.priority === "critical" ? "danger" : order.priority === "high" ? "warning" : "neutral"}>{order.status === "closed" ? `Original priority: ${priorityLabel(order.priority)}` : priorityLabel(order.priority)}</StatusChip>
                    <StatusChip tone="info">{workOrderStatusLabel(order.status)}</StatusChip>
                  </div>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
