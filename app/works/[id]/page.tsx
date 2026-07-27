import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { StatusBadge, PriorityBadge } from "@/components/badges";
import ActionButtons from "@/components/action-buttons";
import { WorkOrderStatus } from "@/lib/status";
import DeleteWorkOrderButton from "@/components/delete-work-order-button";

export const revalidate = 0;

function formatDateTime(value: string | null): string {
  if (!value) return "Date unavailable";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Date unavailable";
  return new Intl.DateTimeFormat("en-SG", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function displayValue(value: string | null): string {
  return value?.trim() || "—";
}

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
    .order("created_at", { ascending: false });

  return (
    <main className="mx-auto max-w-3xl space-y-8 p-8">
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
          {order.location}
          {order.categories?.name ? ` · ${order.categories.name}` : ""}
        </p>
        {order.description && (
          <p className="text-neutral-700">{order.description}</p>
        )}
        <dl className="grid grid-cols-2 gap-3 pt-2 text-sm text-neutral-500">
          <div>
            <dt className="text-neutral-400">Logged by</dt>
            <dd>{order.submitted_by?.trim() || "Unknown"}</dd>
          </div>
          <div>
            <dt className="text-neutral-400">Assigned to</dt>
            <dd>{order.assigned_to ?? "Unassigned"}</dd>
          </div>
          <div>
            <dt className="text-neutral-400">Logged at</dt>
            <dd>{formatDateTime(order.created_at)}</dd>
          </div>
          <div>
            <dt className="text-neutral-400">Last updated</dt>
            <dd>{formatDateTime(order.updated_at)}</dd>
          </div>
        </dl>
      </div>

      <div className="border-t border-neutral-200 pt-6">
        <h2 className="mb-3 text-sm font-semibold text-neutral-500">Actions</h2>
        <ActionButtons id={order.id} status={order.status as WorkOrderStatus} />
      </div>

      <section className="border-t border-neutral-200 pt-6">
        <h2 className="mb-3 text-sm font-semibold text-neutral-500">
          Work activity history
        </h2>
        {!activity || activity.length === 0 ? (
          <p className="text-sm text-neutral-400">No activity yet.</p>
        ) : (
          <ul className="divide-y divide-neutral-100 overflow-hidden rounded-lg border border-neutral-200">
            {activity.map((entry) => (
              <li key={entry.id} className="p-4 text-sm">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <span className="font-medium text-neutral-900">
                    {displayValue(entry.actor)}
                  </span>
                  <time
                    className="text-neutral-400"
                    dateTime={entry.created_at}
                  >
                    {formatDateTime(entry.created_at)}
                  </time>
                </div>
                <dl className="mt-2 grid gap-x-4 gap-y-1 text-neutral-600 sm:grid-cols-3">
                  <div>
                    <dt className="text-xs uppercase tracking-wide text-neutral-400">
                      Action
                    </dt>
                    <dd>{displayValue(entry.action)}</dd>
                  </div>
                  <div>
                    <dt className="text-xs uppercase tracking-wide text-neutral-400">
                      From
                    </dt>
                    <dd>{displayValue(entry.from_status)}</dd>
                  </div>
                  <div>
                    <dt className="text-xs uppercase tracking-wide text-neutral-400">
                      To
                    </dt>
                    <dd>{displayValue(entry.to_status)}</dd>
                  </div>
                </dl>
                {entry.note && (
                  <p className="mt-2 rounded-md bg-neutral-50 px-3 py-2 text-neutral-600">
                    {entry.note}
                  </p>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      <div className="border-t border-red-200 pt-6">
        <h2 className="mb-2 text-sm font-semibold text-red-700">
          Administrator
        </h2>

        <p className="mb-4 text-sm text-neutral-500">
          Permanently remove this work order. Use this only for test, duplicate
          or invalid records.
        </p>

        <DeleteWorkOrderButton id={order.id} title={order.title} />
      </div>
    </main>
  );
}
