import Link from "next/link";
import type { MissionControlData } from "./MissionControl";
import { attentionRequired, sortActiveFacilityWork, technicianCounters } from "@/lib/work-orders/technician-overview";
import { priorityLabel, workOrderStatusLabel } from "@/lib/product-terminology";

const singaporeDate = () => new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Singapore", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());

export default function TechnicianMissionControl({ data }: { data: MissionControlData }) {
  const today = singaporeDate();
  const counters = technicianCounters(data.orders, data.identity.userId, today);
  const attention = attentionRequired(data.orders, data.identity.userId, today).slice(0, 8);
  const active = sortActiveFacilityWork(data.orders, today).slice(0, 10);
  const primary = [
    ["Emergency / Critical", counters.emergencyCritical, "/work-orders?attention=critical"],
    ["Unassigned", counters.unassigned, "/work-orders?assignment=unassigned"],
    ["My Active Work", counters.myActiveWork, "/work-orders?assignment=mine&active=true"],
    ["Overdue", counters.overdue, "/work-orders?attention=overdue"],
    ["Awaiting Action", counters.awaitingAction, "/work-orders?attention=action"],
  ] as const;
  const workload = [
    ["Open", counters.facilityWorkload.open], ["In Progress", counters.facilityWorkload.inProgress],
    ["Awaiting Approval", counters.facilityWorkload.awaitingApproval], ["Completed Today", counters.facilityWorkload.completedToday],
    ["Due Today", counters.facilityWorkload.dueToday],
  ] as const;
  return <main className="mx-auto max-w-[1500px] space-y-6 p-4 sm:p-6 lg:p-8">
    <header className="rounded-3xl bg-slate-950 px-6 py-7 text-white"><p className="text-xs font-black uppercase tracking-[.22em] text-blue-300">FMWorks Technician</p><h1 className="mt-2 text-3xl font-black">Facility Work · {data.identity.displayName}</h1><p className="mt-2 text-sm text-slate-300">All readable Work Orders in your active Facility membership. Assignment controls actions, not visibility.</p></header>
    <section aria-labelledby="technician-counters"><h2 id="technician-counters" className="text-xl font-black">Operational counters</h2><div className="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-5">{primary.map(([label, value, href]) => <Link key={label} href={href} className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm hover:border-blue-400"><p className="text-sm font-bold text-slate-600">{label}</p><p className="mt-1 text-3xl font-black">{value}</p></Link>)}</div><p className="mt-2 text-xs text-slate-500">Awaiting Action is the unique union of emergency/critical, unassigned, overdue and your active assignments; records are never double-counted.</p></section>
    <section className="rounded-2xl border border-slate-200 bg-white p-5"><h2 className="text-xl font-black">Attention Required</h2><p className="text-sm text-slate-500">Facility work ordered by operational urgency with only Technician-safe actions.</p><ul className="mt-4 divide-y divide-slate-100">{attention.map((order) => <li key={order.id} className="py-3"><Link href={`/work-orders/${order.id}`} className="flex flex-wrap items-center justify-between gap-3 hover:text-blue-700"><div><p className="font-mono text-xs font-black text-blue-700">{order.work_order_number}</p><p className="font-bold">{order.title}</p><p className="text-xs text-slate-500">{priorityLabel(order.priority)} · {workOrderStatusLabel(order.status)} · {order.assigned_to ?? "Unassigned"}</p></div><span className="rounded-lg bg-blue-700 px-3 py-2 text-sm font-bold text-white">{order.nextAction}</span></Link></li>)}{attention.length === 0 && <li className="py-6 text-sm text-slate-500">No Facility Work Orders currently require attention.</li>}</ul></section>
    <section className="rounded-2xl border border-slate-200 bg-white p-5"><div className="flex justify-between gap-3"><div><h2 className="text-xl font-black">Active Facility Work</h2><p className="text-sm text-slate-500">Emergency, critical, overdue, unassigned, due-soon, then other active work.</p></div><Link href="/work-orders" className="text-sm font-bold text-blue-700">All  Work Orders →</Link></div><ul className="mt-4 divide-y divide-slate-100">{active.map((order) => <li key={order.id} className="py-3"><Link href={`/work-orders/${order.id}`} className="flex justify-between gap-3 hover:text-blue-700"><div><p className="font-mono text-xs font-black">{order.work_order_number}</p><p className="font-bold">{order.title}</p><p className="text-xs text-slate-500">{order.location ?? "Location not recorded"} · {order.assigned_to ?? "Unassigned"}</p></div><div className="text-right text-xs"><p className="font-bold">{workOrderStatusLabel(order.status)}</p><p>{order.status === "closed" ? `Original priority: ${priorityLabel(order.priority)}` : priorityLabel(order.priority)}</p></div></Link></li>)}</ul></section>
    <section><h2 className="text-lg font-black">Facility Workload</h2><dl className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-5">{workload.map(([label, value]) => <div key={label} className="rounded-xl bg-slate-100 p-3"><dt className="text-xs font-bold text-slate-600">{label}</dt><dd className="text-2xl font-black">{value}</dd></div>)}</dl></section>
  </main>;
}
