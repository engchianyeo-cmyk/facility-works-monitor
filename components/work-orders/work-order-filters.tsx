import type { WorkOrderStatus } from "@/lib/work-orders/types";
import { WORK_ORDER_SOURCES, WORK_ORDER_STATUSES } from "@/lib/work-orders/types";
import { STATUS_LABELS } from "@/lib/work-orders/workflow";
import Link from "next/link";

type Department = { id: string; code: string; name: string };

export default function WorkOrderFilters({
  values,
  departments,
}: {
  values: Record<string, string | undefined>;
  departments: Department[];
}) {
  const input = "rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm";
  return (
    <form method="get" action="/work-orders" className="grid gap-3 rounded-xl border border-slate-200 bg-white p-4 md:grid-cols-4">
      <input className={`${input} md:col-span-2`} name="search" defaultValue={values.search} placeholder="Search number, title, location…" />
      <select className={input} name="status" defaultValue={values.status ?? ""}>
        <option value="">All statuses</option>
        {WORK_ORDER_STATUSES.map((status) => <option key={status} value={status}>{STATUS_LABELS[status as WorkOrderStatus]}</option>)}
      </select>
      <select className={input} name="priority" defaultValue={values.priority ?? ""}>
        <option value="">All priorities</option><option value="critical">Critical</option><option value="high">High</option><option value="medium">Medium</option><option value="low">Low</option>
      </select>
      <select className={input} name="department" defaultValue={values.department ?? ""}>
        <option value="">All departments</option>
        {departments.map((department) => <option key={department.id} value={department.id}>{department.code} — {department.name}</option>)}
      </select>
      <select className={input} name="source" defaultValue={values.source ?? ""}>
        <option value="">All sources</option>
        {WORK_ORDER_SOURCES.map((source) => <option key={source} value={source}>{source.replaceAll("_", " ")}</option>)}
      </select>
      <select className={input} name="assignment" defaultValue={values.assignment ?? ""}>
        <option value="">All assignments</option><option value="mine">Assigned to me</option><option value="unassigned">Unassigned</option><option value="technician">Technician</option><option value="vendor">Vendor</option><option value="team">Team</option>
      </select>
      <select className={input} name="sort" defaultValue={values.sort ?? "newest"}>
        <option value="newest">Newest</option><option value="oldest">Oldest</option><option value="due_date">Due date</option><option value="priority">Priority</option><option value="updated">Recently updated</option>
      </select>
      <input className={input} type="date" name="date_from" defaultValue={values.date_from} aria-label="Created from" />
      <input className={input} type="date" name="date_to" defaultValue={values.date_to} aria-label="Created to" />
      <div className="flex gap-2 md:col-span-2">
        <button className="rounded-lg bg-slate-900 px-4 py-2 text-sm font-semibold text-white" type="submit">Apply filters</button>
        <Link className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700" href="/work-orders">Clear</Link>
      </div>
    </form>
  );
}
