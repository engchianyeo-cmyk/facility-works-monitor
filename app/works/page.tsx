import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { StatusBadge, PriorityBadge } from "@/components/badges";
import { WorkOrderStatus } from "@/lib/status";

export const revalidate = 0;

const STATUSES: WorkOrderStatus[] = [
  "submitted",
  "approved",
  "in_progress",
  "done",
  "rejected",
];

const STATUS_LABELS: Record<WorkOrderStatus, string> = {
  submitted: "Submitted",
  approved: "Approved",
  in_progress: "In Progress",
  done: "Done",
  rejected: "Rejected",
};

const PRIORITY_RANK: Record<string, number> = {
  critical: 0,
  high: 1,
  medium: 2,
  low: 3,
};

function formatLoggedAt(value: string | null): string {
  if (!value) return "Date unavailable";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Date unavailable";
  return new Intl.DateTimeFormat("en-SG", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

export default async function WorksPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; sort?: string }>;
}) {
  const { status, sort } = await searchParams;
  const supabase = await createClient();

  const { data: allOrders, error: countError } = await supabase
    .from("work_orders")
    .select("status");

  const statusCounts: Record<string, number> = {
    all: allOrders?.length ?? 0,
    submitted: 0,
    approved: 0,
    in_progress: 0,
    done: 0,
    rejected: 0,
  };

  allOrders?.forEach((order) => {
    if (order.status && order.status in statusCounts) {
      statusCounts[order.status] += 1;
    }
  });

  let query = supabase.from("work_orders").select("*, categories(name)");

  if (status && STATUSES.includes(status as WorkOrderStatus)) {
    query = query.eq("status", status);
  }

  query = query.order("created_at", { ascending: false });

  const { data: orders, error } = await query;

  if (sort === "priority" && orders) {
    orders.sort((first, second) => {
      const priorityDifference =
        (PRIORITY_RANK[first.priority] ?? Number.MAX_SAFE_INTEGER) -
        (PRIORITY_RANK[second.priority] ?? Number.MAX_SAFE_INTEGER);
      if (priorityDifference !== 0) return priorityDifference;
      return (
        new Date(second.created_at).getTime() -
        new Date(first.created_at).getTime()
      );
    });
  }

  return (
    <main className="mx-auto max-w-5xl space-y-6 p-8">
      <div>
        <h1 className="text-3xl font-bold tracking-tight text-slate-900">
          Work Orders
        </h1>
        <p className="mt-1 text-sm text-slate-500">
          Track, prioritise and manage maintenance requests.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-2 text-sm">
        <Link
          href="/works"
          className={`rounded-full border px-3 py-1.5 font-medium transition ${
            !status
              ? "border-slate-900 bg-slate-900 text-white"
              : "border-slate-300 bg-white text-slate-700 hover:bg-slate-50"
          }`}
        >
          All ({statusCounts.all})
        </Link>

        {STATUSES.map((s) => (
          <Link
            key={s}
            href={`/works?status=${s}`}
            className={`rounded-full border px-3 py-1.5 font-medium transition ${
              status === s
                ? "border-slate-900 bg-slate-900 text-white"
                : "border-slate-300 bg-white text-slate-700 hover:bg-slate-50"
            }`}
          >
            {STATUS_LABELS[s]} ({statusCounts[s]})
          </Link>
        ))}

        <span className="mx-2 hidden text-slate-300 sm:inline">|</span>

        <Link
          href={`/works${status ? `?status=${status}&` : "?"}sort=priority`}
          className={`rounded-full border px-3 py-1.5 font-medium transition ${
            sort === "priority"
              ? "border-blue-600 bg-blue-50 text-blue-700"
              : "border-slate-300 bg-white text-slate-700 hover:bg-slate-50"
          }`}
        >
          Priority
        </Link>

        {sort === "priority" && (
          <Link
            href={`/works${status ? `?status=${status}` : ""}`}
            className="rounded-full border border-slate-300 bg-white px-3 py-1.5 font-medium text-slate-700 transition hover:bg-slate-50"
          >
            Newest
          </Link>
        )}
      </div>

      {(error || countError) && (
        <div className="rounded-lg border border-red-300 bg-red-50 p-4 text-sm text-red-700">
          Couldn&apos;t load work orders: {error?.message ?? countError?.message}
        </div>
      )}

      {!error && orders?.length === 0 && (
        <div className="rounded-xl border border-dashed border-slate-300 bg-white p-10 text-center text-slate-400">
          No work orders {status ? `with status "${STATUS_LABELS[status as WorkOrderStatus]}"` : "yet"}.
        </div>
      )}

      {!error && orders && orders.length > 0 && (
        <ul className="divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
          {orders.map((o) => (
            <li key={o.id}>
              <Link
                href={`/works/${o.id}`}
                className="flex items-center justify-between gap-4 p-4 transition hover:bg-slate-50"
              >
                <div className="min-w-0">
                  <div className="font-medium text-slate-900">{o.title}</div>
                  <div className="mt-1 text-sm text-slate-500">
                    {o.location}
                    {o.categories?.name ? ` · ${o.categories.name}` : ""}
                  </div>
                  <div className="mt-1 text-xs text-slate-400">
                    Logged by {o.submitted_by?.trim() || "Unknown"} ·{" "}
                    {formatLoggedAt(o.created_at)}
                  </div>
                </div>

                <div className="flex shrink-0 items-center gap-2">
                  <PriorityBadge priority={o.priority} />
                  <StatusBadge status={o.status as WorkOrderStatus} />
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
