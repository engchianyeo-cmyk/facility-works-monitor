import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { StatusBadge, PriorityBadge } from "@/components/badges";
import ActionButtons from "@/components/action-buttons";
import { WorkOrderStatus } from "@/lib/status";

export const revalidate = 0;

export default async function WorkOrderDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: order } = await supabase
    .from("work_orders")
    .select("*, categories(name)")
    .eq("id", id)
    .single();

  if (!order) notFound();

  const { data: activity } = await supabase
    .from("activity_logs")
    .select("*")
    .eq("work_order_id", id)
    .order("created_at", { ascending: true });

  return (
    <main className="max-w-3xl mx-auto p-8 space-y-8">
      <Link href="/works" className="text-sm text-neutral-500 hover:underline">
        ← All work orders
      </Link>

      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <StatusBadge status={order.status as WorkOrderStatus} />
          <PriorityBadge priority={order.priority} />
        </div>
        <h1 className="text-2xl font-bold tracking-tight">{order.title}</h1>
        <p className="text-neutral-500">
          {order.location} {order.categories?.name ? `· ${order.categories.name}` : ""}
        </p>
        {order.description && <p className="text-neutral-700">{order.description}</p>}
        <dl className="grid grid-cols-2 gap-3 text-sm text-neutral-500 pt-2">
          <div>
            <dt className="text-neutral-400">Submitted by</dt>
            <dd>{order.submitted_by ?? "—"}</dd>
          </div>
          <div>
            <dt className="text-neutral-400">Assigned to</dt>
            <dd>{order.assigned_to ?? "Unassigned"}</dd>
          </div>
          <div>
            <dt className="text-neutral-400">Created</dt>
            <dd>{new Date(order.created_at).toLocaleString()}</dd>
          </div>
          <div>
            <dt className="text-neutral-400">Last updated</dt>
            <dd>{new Date(order.updated_at).toLocaleString()}</dd>
          </div>
        </dl>
      </div>

      <div className="border-t border-neutral-200 pt-6">
        <h2 className="text-sm font-semibold text-neutral-500 mb-3">Actions</h2>
        <ActionButtons id={order.id} status={order.status as WorkOrderStatus} />
      </div>

      <div className="border-t border-neutral-200 pt-6">
        <h2 className="text-sm font-semibold text-neutral-500 mb-3">Activity log</h2>
        {!activity || activity.length === 0 ? (
          <p className="text-neutral-400 text-sm">No activity yet.</p>
        ) : (
          <ul className="space-y-4">
            {activity.map((a) => (
              <li key={a.id} className="text-sm">
                <div className="flex items-center gap-2">
                  <span className="font-medium">{a.actor}</span>
                  <span className="text-neutral-400">
                    {new Date(a.created_at).toLocaleString()}
                  </span>
                </div>
                <p className="text-neutral-600">
                  {a.action === "created"
                    ? "Submitted this work order."
                    : `Moved from ${a.from_status} → ${a.to_status}`}
                  {a.note ? ` — "${a.note}"` : ""}
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </main>
  );
}
