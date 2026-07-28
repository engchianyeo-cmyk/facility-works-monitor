import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { StatusBadge, PriorityBadge } from "@/components/badges";
import FacilityLayout from "@/components/facility-layout";
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

const PRIORITY_ORDER = ["critical", "high", "medium", "low"] as const;

function timestamp(value: string | null): number {
  const parsed = value ? Date.parse(value) : Number.NaN;
  return Number.isNaN(parsed) ? 0 : parsed;
}

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
  const newestOrders = [...(orders ?? [])].sort(
    (first, second) =>
      timestamp(second.created_at) - timestamp(first.created_at),
  );
  const displayedOrders =
    sort === "priority"
      ? PRIORITY_ORDER.flatMap((priority) =>
          newestOrders.filter(
            (order) => order.priority?.trim().toLowerCase() === priority,
          ),
        ).concat(
          newestOrders.filter(
            (order) =>
              !PRIORITY_ORDER.includes(
                order.priority
                  ?.trim()
                  .toLowerCase() as (typeof PRIORITY_ORDER)[number],
              ),
          ),
        )
      : newestOrders;

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

        <form action="/works" method="get" className="flex items-center gap-2">
          {status && <input type="hidden" name="status" value={status} />}
          <button
            type="submit"
            name="sort"
            value="priority"
            aria-pressed={sort === "priority"}
            data-sort-control="priority"
            className={`rounded-full border px-3 py-1.5 font-medium transition ${
              sort === "priority"
                ? "border-blue-600 bg-blue-50 text-blue-700"
                : "border-slate-300 bg-white text-slate-700 hover:bg-slate-50"
            }`}
          >
            Priority
          </button>
          <button
            type="submit"
            name="sort"
            value="newest"
            aria-pressed={sort !== "priority"}
            data-sort-control="newest"
            className={`rounded-full border px-3 py-1.5 font-medium transition ${
              sort !== "priority"
                ? "border-blue-600 bg-blue-50 text-blue-700"
                : "border-slate-300 bg-white text-slate-700 hover:bg-slate-50"
            }`}
          >
            Newest
          </button>
        </form>
      </div>

      {(error || countError) && (
        <div className="rounded-lg border border-red-300 bg-red-50 p-4 text-sm text-red-700">
          Couldn&apos;t load work orders: {error?.message ?? countError?.message}
        </div>
      )}

      {!error && displayedOrders.length === 0 && (
        <div className="rounded-xl border border-dashed border-slate-300 bg-white p-10 text-center text-slate-400">
          No work orders {status ? `with status "${STATUS_LABELS[status as WorkOrderStatus]}"` : "yet"}.
        </div>
      )}

      {!error && displayedOrders.length > 0 && (
        <ul className="divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
          {displayedOrders.map((o) => (
            <li
              key={o.id}
              data-work-order-card
              data-priority={o.priority?.trim().toLowerCase()}
              data-created-at={o.created_at}
            >
              <Link
                href={`/works/${o.id}`}
                className="flex items-center justify-between gap-4 p-4 transition hover:bg-slate-50"
              >
                <div className="min-w-0">
                  {o.work_order_no && (
                    <div className="text-xs font-semibold tracking-wide text-blue-700">
                      {o.work_order_no}
                    </div>
                  )}
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

      <FacilityLayout />
    </main>
  );
}
