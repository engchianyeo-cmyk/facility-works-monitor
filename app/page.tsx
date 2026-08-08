import Link from "next/link";
import { redirect } from "next/navigation";
import {
  WorkOrderPriorityBadge,
  WorkOrderStatusBadge,
} from "@/components/work-orders/work-order-badges";
import { getCurrentIdentity } from "@/lib/auth";
import { canCreate } from "@/lib/work-orders/permissions";
import type {
  WorkOrderPriority,
  WorkOrderStatus,
} from "@/lib/work-orders/types";
import { createClient } from "@/lib/supabase/server";

export const revalidate = 0;

type DashboardWorkOrder = {
  id: string;
  work_order_number: string;
  title: string;
  status: WorkOrderStatus;
  priority: WorkOrderPriority;
  due_date: string | null;
  created_at: string;
};

const OPEN_STATUSES: WorkOrderStatus[] = [
  "draft",
  "submitted",
  "approved",
  "assigned",
  "in_progress",
];
function singaporeDate(date = new Date()) {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Asia/Singapore",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function addDays(date: string, days: number) {
  const value = new Date(`${date}T00:00:00.000Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

function formatDate(value: string | null) {
  if (!value) return "Not set";
  return new Intl.DateTimeFormat("en-SG", { dateStyle: "medium" }).format(
    new Date(`${value}T00:00:00.000Z`),
  );
}

function roleLabel(role: string) {
  return role.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export default async function Home() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("work_orders")
    .select("id,work_order_number,title,status,priority,due_date,created_at")
    .order("created_at", { ascending: false });
  const orders = (error ? [] : (data ?? [])) as DashboardWorkOrder[];
  const today = singaporeDate();
  const dueSoonLimit = addDays(today, 7);
  const isAttention = (order: DashboardWorkOrder) =>
    OPEN_STATUSES.includes(order.status) && Boolean(order.due_date);

  const overdue = orders
    .filter((order) => isAttention(order) && order.due_date! < today)
    .sort((first, second) => first.due_date!.localeCompare(second.due_date!));
  const dueToday = orders.filter(
    (order) => isAttention(order) && order.due_date === today,
  );
  const dueSoon = orders
    .filter(
      (order) =>
        isAttention(order) &&
        order.due_date! > today &&
        order.due_date! <= dueSoonLimit,
    )
    .sort((first, second) => first.due_date!.localeCompare(second.due_date!));
  const attention = [...overdue, ...dueToday, ...dueSoon].slice(0, 8);
  const recent = orders.slice(0, 8);

  const kpis = [
    {
      label: "Open Work Orders",
      value: orders.filter((order) => OPEN_STATUSES.includes(order.status)).length,
      tone: "text-blue-700",
    },
    { label: "Due Today", value: dueToday.length, tone: "text-amber-700" },
    { label: "Overdue", value: overdue.length, tone: "text-red-700" },
    {
      label: "Completed",
      value: orders.filter((order) => order.status === "completed").length,
      tone: "text-emerald-700",
    },
    {
      label: "Pending Approval",
      value: orders.filter((order) => order.status === "submitted").length,
      tone: "text-violet-700",
    },
  ];

  return (
    <main className="mx-auto max-w-7xl space-y-8 p-6 lg:p-8">
      <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
        <p className="text-sm font-semibold text-blue-700">Welcome back</p>
        <div className="mt-1 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="text-3xl font-bold tracking-tight text-slate-900">
              {identity.displayName}
            </h1>
            <p className="mt-1 text-sm text-slate-500">
              {roleLabel(identity.role)}
              {identity.department ? ` · ${identity.department}` : ""}
            </p>
          </div>
          <Link
            href="/work-orders"
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50"
          >
            View all work orders
          </Link>
        </div>
      </section>

      <section aria-labelledby="overview-heading">
        <h2 id="overview-heading" className="text-xl font-bold text-slate-900">
          Operational overview
        </h2>
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          {kpis.map((kpi) => (
            <div key={kpi.label} className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
              <p className="text-sm font-medium text-slate-500">{kpi.label}</p>
              <p className={`mt-2 text-3xl font-bold ${kpi.tone}`}>{kpi.value}</p>
            </div>
          ))}
        </div>
      </section>

      <section aria-labelledby="actions-heading">
        <h2 id="actions-heading" className="text-xl font-bold text-slate-900">
          Quick actions
        </h2>
        <div className="mt-4 flex flex-wrap gap-3">
          {canCreate(identity.role) && (
            <Link href="/work-orders/new" className="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700">
              New Work Order
            </Link>
          )}
          <Link href="/work-orders" className="rounded-lg border border-slate-300 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700 hover:bg-slate-50">
            View Work Orders
          </Link>
          {identity.role === "administrator" && (
            <>
              <Link href="/administration/users" className="rounded-lg border border-slate-300 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700 hover:bg-slate-50">
                Users
              </Link>
              <Link href="/administration/departments" className="rounded-lg border border-slate-300 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700 hover:bg-slate-50">
                Departments
              </Link>
            </>
          )}
        </div>
      </section>

      {error && (
        <p className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700" role="alert">
          Dashboard work-order data could not be loaded. Try again shortly.
        </p>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        <section aria-labelledby="recent-heading" className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
          <div className="border-b border-slate-200 px-5 py-4">
            <h2 id="recent-heading" className="text-lg font-bold text-slate-900">Recent Work Orders</h2>
          </div>
          {!error && recent.length === 0 ? (
            <p className="p-8 text-center text-sm text-slate-500">No work orders are available yet.</p>
          ) : (
            <OrderList orders={recent} today={today} />
          )}
        </section>

        <section aria-labelledby="attention-heading" className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
          <div className="border-b border-slate-200 px-5 py-4">
            <h2 id="attention-heading" className="text-lg font-bold text-slate-900">Due / Attention</h2>
            <p className="mt-1 text-xs text-slate-500">Overdue, due today, then due within seven days.</p>
          </div>
          {!error && attention.length === 0 ? (
            <p className="p-8 text-center text-sm text-slate-500">Nothing requires date-based attention.</p>
          ) : (
            <OrderList orders={attention} today={today} showAttention />
          )}
        </section>
      </div>
    </main>
  );
}

function OrderList({
  orders,
  today,
  showAttention = false,
}: {
  orders: DashboardWorkOrder[];
  today: string;
  showAttention?: boolean;
}) {
  return (
    <ul className="divide-y divide-slate-100">
      {orders.map((order) => {
        const attentionLabel = order.due_date! < today
          ? "Overdue"
          : order.due_date === today
            ? "Due today"
            : "Due soon";
        return (
          <li key={order.id}>
            <Link href={`/work-orders/${order.id}`} className="block p-4 hover:bg-slate-50">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <p className="text-xs font-bold tracking-wide text-blue-700">{order.work_order_number}</p>
                  <p className="mt-1 truncate font-semibold text-slate-900">{order.title}</p>
                  <p className={`mt-2 text-xs ${showAttention && attentionLabel === "Overdue" ? "font-bold text-red-700" : "text-slate-500"}`}>
                    {showAttention ? `${attentionLabel} · ` : "Due "}{formatDate(order.due_date)}
                  </p>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-2">
                  <WorkOrderStatusBadge status={order.status} />
                  <WorkOrderPriorityBadge priority={order.priority} />
                </div>
              </div>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
