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
};

export default function OperationsSummary({ orders }: { orders: MissionWorkOrder[] }) {
  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5">
      <SectionTitle title="Recent operations" action={<Link href="/work-orders" className="text-sm font-bold text-blue-700 hover:underline">All work orders →</Link>} />
      <div className="mt-4">
        {!orders.length ? (
          <EmptyState title="No work orders available" description="New operational work will appear here." />
        ) : (
          <ul className="divide-y divide-slate-100">
            {orders.slice(0, 6).map((order) => (
              <li key={order.id} className="py-3">
                <Link href={`/work-orders/${order.id}`} className="flex items-start justify-between gap-3 hover:text-blue-700">
                  <div>
                    <p className="font-mono text-xs font-bold text-slate-500">{order.work_order_number}</p>
                    <p className="font-bold">{order.title}</p>
                    <p className="text-xs text-slate-500">Due {order.due_date || "not set"}</p>
                  </div>
                  <div className="flex flex-wrap justify-end gap-1">
                    <StatusChip tone={order.priority === "critical" ? "danger" : order.priority === "high" ? "warning" : "neutral"}>{priorityLabel(order.priority)}</StatusChip>
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
