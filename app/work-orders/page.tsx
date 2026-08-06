import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentIdentity } from "@/lib/auth";
import WorkOrderFilters from "@/components/work-orders/work-order-filters";
import { WorkOrderPriorityBadge, WorkOrderStatusBadge } from "@/components/work-orders/work-order-badges";
import { isWorkOrderPriority, isWorkOrderSource, isWorkOrderStatus } from "@/lib/work-orders/validation";
import type { WorkOrderPriority, WorkOrderStatus } from "@/lib/work-orders/types";

export const revalidate = 0;
type Search = Record<string, string | string[] | undefined>;
const one = (value: string | string[] | undefined) => Array.isArray(value) ? value[0] : value;
const SORT: Record<string, { column: string; ascending: boolean }> = {
  newest: { column: "created_at", ascending: false }, oldest: { column: "created_at", ascending: true },
  due_date: { column: "due_date", ascending: true }, priority: { column: "priority_rank", ascending: false }, updated: { column: "updated_at", ascending: false },
};

function formatDate(value: string | null) {
  if (!value) return "Not set";
  return new Intl.DateTimeFormat("en-SG", { dateStyle: "medium" }).format(new Date(value));
}

export default async function WorkOrdersPage({ searchParams }: { searchParams: Promise<Search> }) {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/work-orders");
  const raw = await searchParams;
  const values = Object.fromEntries(Object.entries(raw).map(([key, value]) => [key, one(value)])) as Record<string, string | undefined>;
  const page = Math.max(1, Number.parseInt(values.page ?? "1", 10) || 1);
  const pageSize = 20; const from = (page - 1) * pageSize; const to = from + pageSize - 1;
  const supabase = await createClient();
  const { data: departments } = await supabase.from("departments").select("id,code,name").eq("is_active", true).is("deleted_at", null).order("name");
  let query = supabase.from("work_orders").select("*, categories(name), departments(code,name,colour_tag)", { count: "exact" });
  if (values.search?.trim()) {
    const search = values.search.replaceAll(/[,%()]/g, " ").trim();
    if (search) query = query.or(`work_order_number.ilike.%${search}%,title.ilike.%${search}%,description.ilike.%${search}%,location.ilike.%${search}%`);
  }
  if (isWorkOrderStatus(values.status)) query = query.eq("status", values.status);
  if (isWorkOrderPriority(values.priority)) query = query.eq("priority", values.priority);
  if (isWorkOrderSource(values.source)) query = query.eq("source", values.source);
  if (values.department) query = query.eq("department_id", values.department);
  if (values.assignment === "mine") query = query.eq("assigned_technician_id", identity.userId);
  else if (values.assignment === "unassigned") query = query.is("assigned_technician_id", null).is("assigned_vendor_id", null).is("assigned_team_id", null);
  else if (values.assignment === "technician") query = query.not("assigned_technician_id", "is", null);
  else if (values.assignment === "vendor") query = query.not("assigned_vendor_id", "is", null);
  else if (values.assignment === "team") query = query.not("assigned_team_id", "is", null);
  if (values.date_from) query = query.gte("created_at", `${values.date_from}T00:00:00.000Z`);
  if (values.date_to) query = query.lte("created_at", `${values.date_to}T23:59:59.999Z`);
  const sorting = SORT[values.sort ?? "newest"] ?? SORT.newest;
  const { data: orders, error, count } = await query.order(sorting.column, { ascending: sorting.ascending, nullsFirst: false }).range(from, to);
  const totalPages = Math.max(1, Math.ceil((count ?? 0) / pageSize));
  const pageHref = (target: number) => { const params = new URLSearchParams(); Object.entries(values).forEach(([key, value]) => { if (value && key !== "page") params.set(key, value); }); params.set("page", String(target)); return `/work-orders?${params}`; };

  return (
    <main className="mx-auto max-w-6xl space-y-6 p-6 lg:p-8">
      <div className="flex flex-wrap items-end justify-between gap-4"><div><h1 className="text-3xl font-bold tracking-tight text-slate-900">Work Orders</h1><p className="mt-1 text-sm text-slate-500">Plan, authorize, assign, execute, review, and close maintenance work.</p></div>{identity.role !== "technician" && <Link href="/work-orders/new" className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white">New work order</Link>}</div>
      <WorkOrderFilters values={values} departments={departments ?? []} />
      {error && <p className="rounded-lg border border-red-300 bg-red-50 p-4 text-sm text-red-700">Work orders could not be loaded.</p>}
      {!error && (orders ?? []).length === 0 && <div className="rounded-xl border border-dashed border-slate-300 bg-white p-10 text-center text-slate-500">No matching work orders.</div>}
      {!error && (orders ?? []).length > 0 && <ul className="divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">{orders?.map((order) => {
        const overdue = order.due_date && !["closed", "cancelled", "completed", "reviewed"].includes(order.status) && new Date(`${order.due_date}T23:59:59`).getTime() < Date.now();
        return <li key={order.id}><Link href={`/work-orders/${order.id}`} className="flex flex-col gap-3 p-4 hover:bg-slate-50 sm:flex-row sm:items-center sm:justify-between"><div className="min-w-0"><p className="text-xs font-bold tracking-wide text-blue-700">{order.work_order_number}</p><h2 className="truncate font-semibold text-slate-900">{order.title}</h2><p className="mt-1 text-sm text-slate-500">{[order.site, order.location, order.categories?.name, order.departments?.name].filter(Boolean).join(" · ")}</p><p className={`mt-1 text-xs ${overdue ? "font-bold text-red-700" : "text-slate-400"}`}>{overdue ? "Overdue · " : ""}Due {formatDate(order.due_date)} · {String(order.source).replaceAll("_", " ")}</p></div><div className="flex shrink-0 gap-2"><WorkOrderPriorityBadge priority={order.priority as WorkOrderPriority} /><WorkOrderStatusBadge status={order.status as WorkOrderStatus} /></div></Link></li>;
      })}</ul>}
      <div className="flex items-center justify-between text-sm"><span className="text-slate-500">Page {page} of {totalPages} · {count ?? 0} records</span><div className="flex gap-2">{page > 1 && <Link className="rounded border px-3 py-1.5" href={pageHref(page - 1)}>Previous</Link>}{page < totalPages && <Link className="rounded border px-3 py-1.5" href={pageHref(page + 1)}>Next</Link>}</div></div>
    </main>
  );
}
