import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import FacilityLayout from "@/components/facility-layout";
import {
  WorkOrderPriorityBadge,
  WorkOrderStatusBadge,
} from "@/components/work-orders/work-order-badges";
import {
  WORK_ORDER_STATUSES,
  type WorkOrderPriority,
  type WorkOrderStatus,
} from "@/lib/work-orders/types";
import { isWorkOrderPriority, isWorkOrderStatus } from "@/lib/work-orders/validation";

export const revalidate = 0;

type PublicWorkOrder = {
  id: string;
  work_order_number: string;
  title: string;
  location: string;
  site: string | null;
  category_name: string | null;
  priority: WorkOrderPriority;
  status: WorkOrderStatus;
  source: string;
  due_date: string | null;
  created_at: string;
};

const PUBLIC_STATUSES = WORK_ORDER_STATUSES.filter(
  (status): status is Exclude<WorkOrderStatus, "draft"> => status !== "draft",
);
const PRIORITY_ORDER: WorkOrderPriority[] = ["critical", "high", "medium", "low"];

function isPublicWorkOrder(value: unknown): value is PublicWorkOrder {
  if (!value || typeof value !== "object") return false;
  const order = value as Record<string, unknown>;
  return typeof order.id === "string"
    && typeof order.work_order_number === "string"
    && typeof order.title === "string"
    && typeof order.location === "string"
    && (order.site === null || typeof order.site === "string")
    && (order.category_name === null || typeof order.category_name === "string")
    && isWorkOrderPriority(order.priority)
    && isWorkOrderStatus(order.status)
    && order.status !== "draft"
    && typeof order.source === "string"
    && (order.due_date === null || typeof order.due_date === "string")
    && typeof order.created_at === "string";
}

function formatDate(value: string | null) {
  if (!value) return "Not set";
  return new Intl.DateTimeFormat("en-SG", { dateStyle: "medium" }).format(
    new Date(value),
  );
}

export default async function PublicWorksPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; sort?: string }>;
}) {
  const { status: requestedStatus, sort } = await searchParams;
  const status = isWorkOrderStatus(requestedStatus) && requestedStatus !== "draft"
    ? requestedStatus
    : undefined;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("list_public_work_orders");
  const orders = error || !Array.isArray(data) ? [] : data.filter(isPublicWorkOrder);
  const filtered = status ? orders.filter((order) => order.status === status) : orders;
  const displayed = sort === "priority"
    ? [...filtered].sort((first, second) => {
        const priorityDifference = PRIORITY_ORDER.indexOf(first.priority) - PRIORITY_ORDER.indexOf(second.priority);
        return priorityDifference || Date.parse(second.created_at) - Date.parse(first.created_at);
      })
    : filtered;
  const statusCounts = PUBLIC_STATUSES.reduce<Partial<Record<Exclude<WorkOrderStatus, "draft">, number>>>((counts, item) => {
    counts[item] = orders.filter((order) => order.status === item).length;
    return counts;
  }, {});

  return (
    <main className="mx-auto max-w-5xl space-y-6 p-6 lg:p-8">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-900">Work Orders</h1>
          <p className="mt-1 text-sm text-slate-500">
            Public operational overview. Sign in to view details or manage work.
          </p>
        </div>
        <Link href="/login?next=/work-orders" className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white">
          Sign in to manage
        </Link>
      </div>

      <div className="flex flex-wrap items-center gap-2 text-sm">
        <Link href="/works" className={`rounded-full border px-3 py-1.5 font-medium ${!status ? "border-slate-900 bg-slate-900 text-white" : "border-slate-300 bg-white text-slate-700"}`}>
          All ({orders.length})
        </Link>
        {PUBLIC_STATUSES.map((item) => (
          <Link key={item} href={`/works?status=${item}`} className={`rounded-full border px-3 py-1.5 font-medium capitalize ${status === item ? "border-slate-900 bg-slate-900 text-white" : "border-slate-300 bg-white text-slate-700"}`}>
            {item.replaceAll("_", " ")} ({statusCounts[item] ?? 0})
          </Link>
        ))}
        <form action="/works" method="get" className="ml-auto flex gap-2">
          {status && <input type="hidden" name="status" value={status} />}
          <button type="submit" name="sort" value="priority" aria-pressed={sort === "priority"} className="rounded-full border border-slate-300 bg-white px-3 py-1.5 font-medium text-slate-700">Priority</button>
          <button type="submit" name="sort" value="newest" aria-pressed={sort !== "priority"} className="rounded-full border border-slate-300 bg-white px-3 py-1.5 font-medium text-slate-700">Newest</button>
        </form>
      </div>

      {error && <p className="rounded-lg border border-red-300 bg-red-50 p-4 text-sm text-red-700">The public work-order overview could not be loaded.</p>}
      {!error && displayed.length === 0 && <div className="rounded-xl border border-dashed border-slate-300 bg-white p-10 text-center text-slate-500">No public work orders match this view.</div>}
      {!error && displayed.length > 0 && (
        <ul className="divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
          {displayed.map((order) => (
            <li key={order.id} className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
              <div className="min-w-0">
                <p className="text-xs font-bold tracking-wide text-blue-700">{order.work_order_number}</p>
                <h2 className="truncate font-semibold text-slate-900">{order.title}</h2>
                <p className="mt-1 text-sm text-slate-500">{[order.site, order.location, order.category_name].filter(Boolean).join(" · ")}</p>
                <p className="mt-1 text-xs text-slate-400">Due {formatDate(order.due_date)} · {order.source.replaceAll("_", " ")}</p>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <WorkOrderPriorityBadge priority={order.priority} />
                <WorkOrderStatusBadge status={order.status} />
                <Link href={`/works/${order.id}`} className="text-sm font-semibold text-blue-700 hover:underline">Sign in to view</Link>
              </div>
            </li>
          ))}
        </ul>
      )}

      <FacilityLayout />
    </main>
  );
}
