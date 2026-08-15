"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import type { UserRole } from "@/lib/auth";
import { operationalLabel, workOrderStatusLabel } from "@/lib/product-terminology";

export type OperationsWorkItem = {
  id: string;
  number: string;
  title: string;
  location: string;
  system: string | null;
  asset: string | null;
  priority: string;
  status: string;
  assignee: string | null;
  age: string;
  due: string;
  dueDate: string | null;
  overdue: boolean;
  dueToday: boolean;
  completedToday: boolean;
  nextAction: string;
  completionNotes: string | null;
  evidenceCount: number | null;
};

export type AttentionItem = {
  id: string;
  type: "emergency" | "critical" | "overdue" | "unassigned" | "approval";
  title: string;
  reference: string;
  location: string;
  reason: string;
  owner: string;
  waiting: string;
  impact: string;
  nextAction: string;
  href: string;
};

export type TeamMember = {
  id: string;
  name: string;
  discipline: string;
  lastRecordedActivity: string;
  workload: number;
  currentAssignment: string | null;
};

export type OperationsWorkspaceData = {
  role: UserRole;
  name: string;
  work: OperationsWorkItem[];
  attention: AttentionItem[];
  team: TeamMember[];
  availability: { work: boolean; incidents: boolean; team: boolean };
};

type View = "today" | "work" | "approvals" | "team" | "schedule" | "exceptions";
const MANAGER_ROLES: UserRole[] = ["approver", "supervisor", "administrator"];
const VIEWS: Array<{ id: View; label: string }> = [
  { id: "today", label: "Today" },
  { id: "work", label: "Work Queue" },
  { id: "approvals", label: "Approvals" },
  { id: "team", label: "Team" },
  { id: "schedule", label: "Schedule" },
  { id: "exceptions", label: "Exceptions" },
];

const attentionTone = {
  emergency: "border-red-600 bg-white text-red-800",
  critical: "border-red-500 bg-white text-red-800",
  overdue: "border-amber-500 bg-white text-amber-900",
  unassigned: "border-orange-500 bg-white text-orange-900",
  approval: "border-violet-500 bg-white text-violet-900",
};

function WorkRow({ item, technician = false }: { item: OperationsWorkItem; technician?: boolean }) {
  return (
    <li className="border-b border-slate-100 last:border-0">
      <Link href={`/work-orders/${item.id}`} className={`grid gap-3 p-4 hover:bg-slate-50 ${technician ? "min-h-32" : "lg:grid-cols-[minmax(0,1.4fr)_repeat(4,minmax(7rem,.6fr))] lg:items-center"}`}>
        <div className="min-w-0">
          <p className="font-mono text-xs font-black text-blue-700">{item.number}</p>
          <h3 className="mt-1 font-black text-slate-950">{item.title}</h3>
          <p className="mt-1 text-sm text-slate-600">{item.location}{item.system ? ` · ${item.system}` : ""}</p>
          {item.asset && <p className="mt-1 text-xs text-slate-500">Asset: {item.asset}</p>}
        </div>
        <div><p className="text-xs font-bold text-slate-500">Status</p><p className="mt-1 text-sm font-bold text-slate-800">{workOrderStatusLabel(item.status)}</p></div>
        <div><p className="text-xs font-bold text-slate-500">Owner</p><p className="mt-1 text-sm text-slate-800">{item.assignee ?? "Unassigned"}</p></div>
        <div><p className="text-xs font-bold text-slate-500">Age / Due</p><p className={`mt-1 text-sm ${item.overdue ? "font-black text-red-700" : "text-slate-800"}`}>{item.age} · {item.due}</p></div>
        <div><p className="text-xs font-bold text-slate-500">Next action</p><p className="mt-1 text-sm font-semibold text-blue-800">{item.nextAction}</p></div>
      </Link>
    </li>
  );
}

function AttentionQueue({ items }: { items: AttentionItem[] }) {
  return items.length ? (
    <ol className="overflow-hidden rounded-xl border border-slate-200 bg-white">
      {items.map((item) => (
        <li key={item.id} className="border-b border-slate-100 last:border-0">
          <Link href={item.href} className={`block border-l-4 px-4 py-3 hover:bg-slate-50 ${attentionTone[item.type]}`}>
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div><p className="text-xs font-black uppercase tracking-wide">{operationalLabel(item.type)}</p><h3 className="mt-1 text-lg font-black text-slate-950">{item.title}</h3><p className="text-sm text-slate-600">{item.reference} · {item.location}</p></div>
              <span className="rounded-full bg-white/80 px-2.5 py-1 text-xs font-black">{item.owner} · {item.waiting}</span>
            </div>
            <dl className="mt-2 grid gap-2 text-sm md:grid-cols-2">
              <div className="hidden sm:block"><dt className="font-black text-slate-700">Why it matters</dt><dd className="text-slate-600">{item.impact}</dd></div>
              <div><dt className="font-black text-slate-700">Next action</dt><dd className="font-semibold text-slate-800">{item.nextAction}</dd></div>
            </dl>
          </Link>
        </li>
      ))}
    </ol>
  ) : <div className="rounded-xl border border-dashed border-emerald-300 bg-emerald-50 p-8 text-center"><p className="font-black text-emerald-900">No immediate exceptions</p><p className="mt-1 text-sm text-emerald-800">Routine operations can continue.</p></div>;
}

function ApprovalCard({ item, canReview, expanded }: { item: OperationsWorkItem; canReview: boolean; expanded: boolean }) {
  return <article className={`rounded-xl border bg-white ${expanded ? "border-amber-300 p-5" : "border-slate-200 p-4"}`}><div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-mono text-xs font-black text-violet-700">{item.number}</p><h3 className="font-black">{item.title}</h3><p className="text-sm text-slate-600">{item.location} · {item.assignee ?? "No owner recorded"}</p></div>{expanded && <span className="rounded-full bg-amber-100 px-2.5 py-1 text-xs font-black text-amber-900">Review required</span>}</div><dl className="mt-3 grid gap-2 text-sm sm:grid-cols-2"><div><dt className="font-bold">Physical status</dt><dd>{item.status === "completed" ? "Work completed on site" : "Work not recorded as complete"}</dd></div><div><dt className="font-bold">Documentation status</dt><dd>{item.status === "completed" ? "Awaiting completion review" : "Awaiting authorization"}</dd></div><div><dt className="font-bold">What was done</dt><dd>{item.completionNotes ?? (item.status === "completed" ? "Completion statement not recorded" : "Work has not started")}</dd></div><div><dt className="font-bold">Decision required</dt><dd>{item.status === "completed" ? "Review completion and recorded exceptions" : "Review scope and authorize or return"}</dd></div></dl>{expanded && <p className="mt-3 text-sm text-amber-900"><span className="font-bold">Exception:</span> {item.priority === "critical" ? "Critical work requires additional review." : !item.assignee && item.status === "completed" ? "Responsible person is not recorded." : "Required completion information is incomplete."}</p>}<p className="mt-3 text-sm font-bold text-slate-700">{item.evidenceCount === null ? "Evidence availability is unknown" : item.evidenceCount === 0 ? "No evidence attached" : `Evidence available: ${item.evidenceCount} item${item.evidenceCount === 1 ? "" : "s"}`}</p><Link href={`/work-orders/${item.id}`} className="mt-3 inline-flex min-h-11 items-center rounded-lg bg-violet-700 px-4 text-sm font-black text-white">{canReview ? "Review decision" : "View work order"}</Link></article>;
}

export default function OperationsWorkspace({ data }: { data: OperationsWorkspaceData }) {
  const technician = data.role === "technician";
  const canReview = ["approver", "supervisor", "administrator"].includes(data.role);
  const approvalFirst = canReview;
  const visibleViews = technician
    ? VIEWS.filter((view) => ["today", "work", "schedule"].includes(view.id))
    : VIEWS.filter((view) => {
        if (view.id === "approvals") return canReview;
        if (view.id === "team") return MANAGER_ROLES.includes(data.role);
        return true;
      });
  const [view, setView] = useState<View>(technician ? "work" : approvalFirst ? "approvals" : "today");
  const [filter, setFilter] = useState("active");
  const filteredWork = useMemo(() => data.work.filter((item) => filter === "all" || (filter === "active" && ["submitted", "approved", "assigned", "in_progress"].includes(item.status)) || (filter === "critical" && item.priority === "critical") || (filter === "today" && item.dueToday) || (filter === "overdue" && item.overdue) || (filter === "waiting" && item.status === "submitted") || (filter === "unassigned" && !item.assignee && ["approved", "assigned"].includes(item.status)) || (filter === "completed" && item.completedToday)), [data.work, filter]);
  const approvals = data.work.filter((item) => ["submitted", "completed"].includes(item.status));
  const approvalNeedsReview = (item: OperationsWorkItem) => item.priority === "critical" || (item.status === "completed" && (!item.assignee || !item.completionNotes));
  const normalApprovals = approvals.filter((item) => !approvalNeedsReview(item));
  const reviewApprovals = approvals.filter(approvalNeedsReview);
  const topAttention = data.attention.slice(0, 5);
  const attentionGroups = [
    { label: "Immediate", description: "Critical safety or service-impact items", items: topAttention.filter((item) => ["emergency", "critical"].includes(item.type)) },
    { label: "Decision Required", description: "Approvals or escalation decisions", items: topAttention.filter((item) => item.type === "approval") },
    { label: "Assignment Required", description: "Work without recorded ownership", items: topAttention.filter((item) => item.type === "unassigned") },
    { label: "Watch", description: "Important exposure requiring monitoring", items: topAttention.filter((item) => item.type === "overdue") },
  ];
  const exceptions = data.attention.filter((item) => item.type === "overdue" || item.type === "unassigned" || item.type === "critical" || (item.type === "emergency" && item.owner === "Unassigned"));
  const degradedForView = !data.availability.work || (["today", "exceptions"].includes(view) && !data.availability.incidents) || (view === "team" && !data.availability.team);
  const today = data.work.filter((item) => item.dueToday);
  const tomorrow = data.work.filter((item) => item.dueDate && new Date(`${item.dueDate}T00:00:00`).toDateString() === new Date(Date.now() + 86400000).toDateString());
  const upcoming = data.work.filter((item) => item.dueDate && !item.dueToday && !item.overdue && !tomorrow.includes(item)).slice(0, 8);

  return (
    <main className="mx-auto max-w-[1500px] space-y-6 p-4 sm:p-6 lg:p-8">
      <header className="rounded-3xl bg-slate-950 px-6 py-7 text-white sm:px-8">
        <p className="text-xs font-black uppercase tracking-[.22em] text-blue-300">FMWorks Operations</p>
        <div className="mt-2 flex flex-wrap items-end justify-between gap-4"><div><h1 className="text-3xl font-black tracking-tight sm:text-4xl">{technician ? `My Work · ${data.name}` : "Operations Workspace"}</h1><p className="mt-2 text-sm text-slate-300">{technician ? "Your current assignment, location and next required action." : "Attention, work ownership and decisions for today’s operation."}</p></div><Link href="/" className="rounded-lg border border-slate-600 px-4 py-2 text-sm font-bold hover:bg-slate-800">← Mission Control</Link></div>
      </header>

      {degradedForView && <div role="status" className="rounded-lg border border-amber-200 bg-amber-50/70 px-4 py-2 text-xs text-amber-900">Some information needed for this view is temporarily unavailable. Available work remains accessible.</div>}

      <nav aria-label="Operations views" className="flex gap-2 overflow-x-auto border-b border-slate-200 pb-2">
        {visibleViews.map((item) => <button key={item.id} type="button" onClick={() => setView(item.id)} aria-pressed={view === item.id} className={`min-h-11 shrink-0 rounded-lg px-4 py-2 text-sm font-black ${view === item.id ? "bg-slate-950 text-white" : "text-slate-600 hover:bg-slate-100"}`}>{technician && item.id === "work" ? "My Work" : technician && item.id === "today" ? "Emergency" : item.label}</button>)}
      </nav>

      {view === "today" && <section className="space-y-5"><div><p className="text-xs font-black uppercase tracking-widest text-red-700">What needs attention now</p><h2 className="text-2xl font-black text-slate-950">Manage by priority</h2><p className="mt-1 text-sm text-slate-600">The five highest-priority visible items, grouped by the action required.</p></div>{attentionGroups.map((group) => group.items.length > 0 && <section key={group.label}><div className="mb-2 flex items-end justify-between gap-3"><div><h3 className="font-black uppercase tracking-wide text-slate-900">{group.label}</h3><p className="text-xs text-slate-500">{group.description}</p></div><span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-black text-slate-700">{group.items.length}</span></div><AttentionQueue items={group.items} /></section>)}{topAttention.length === 0 && <AttentionQueue items={[]} />}</section>}

      {view === "work" && <section><div className="flex flex-wrap items-end justify-between gap-3"><div><p className="text-xs font-black uppercase tracking-widest text-blue-700">Operational work</p><h2 className="text-2xl font-black">{technician ? "My Work" : "Work Queue"}</h2></div>{!technician && <select aria-label="Filter work queue" value={filter} onChange={(event) => setFilter(event.target.value)} className="min-h-11 rounded-lg border border-slate-300 bg-white px-3 text-sm font-bold"><option value="active">Active</option><option value="critical">Critical</option><option value="today">Due Today</option><option value="overdue">Overdue</option><option value="unassigned">Unassigned</option><option value="waiting">Awaiting Approval</option><option value="completed">Completed Today</option><option value="all">All</option></select>}</div><ul className="mt-4 overflow-hidden rounded-xl border border-slate-200 bg-white">{filteredWork.length ? filteredWork.map((item) => <WorkRow key={item.id} item={item} technician={technician} />) : <li className="p-8 text-center text-sm text-slate-500">No work matches this view.</li>}</ul></section>}

      {view === "approvals" && <section><p className="text-xs font-black uppercase tracking-widest text-violet-700">Decision required</p><h2 className="text-2xl font-black">Approval Centre</h2><p className="mt-1 text-sm text-slate-600">Healthy approvals stay compact; incomplete or critical records are elevated for review.</p>{approvals.length ? <div className="mt-5 space-y-6">{reviewApprovals.length > 0 && <section><div className="mb-3 flex items-center justify-between"><h3 className="font-black uppercase tracking-wide text-amber-900">Review Required</h3><span className="rounded-full bg-amber-100 px-2.5 py-1 text-xs font-black text-amber-900">{reviewApprovals.length}</span></div><div className="grid gap-4 lg:grid-cols-2">{reviewApprovals.map((item) => <ApprovalCard key={item.id} item={item} canReview={canReview} expanded />)}</div></section>}{normalApprovals.length > 0 && <section><div className="mb-3 flex items-center justify-between"><h3 className="font-black uppercase tracking-wide text-slate-700">Normal Approval</h3><span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-black text-slate-700">{normalApprovals.length}</span></div><div className="grid gap-3 lg:grid-cols-2">{normalApprovals.map((item) => <ApprovalCard key={item.id} item={item} canReview={canReview} expanded={false} />)}</div></section>}</div> : <div className="mt-4 rounded-xl border border-dashed border-slate-300 p-8 text-center text-slate-500">No work is waiting for a decision.</div>}</section>}

      {view === "team" && <section><p className="text-xs font-black uppercase tracking-widest text-blue-700">Resource coordination</p><h2 className="text-2xl font-black">Team Operations</h2><p className="mt-1 text-sm text-slate-600">Recorded assignments, workload and activity; this is not live availability and does not imply a person is free.</p><div className="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-3">{data.team.length ? data.team.map((member) => <article key={member.id} className="rounded-xl border border-slate-200 bg-white p-4"><div className="flex justify-between gap-3"><div><h3 className="font-black">{member.name}</h3><p className="text-sm text-slate-500">{member.discipline}</p></div><span className="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-black text-blue-800">Recorded workload: {member.workload}</span></div><p className="mt-3 text-sm"><span className="font-bold">Current known work:</span> {member.currentAssignment ?? "No active assignment recorded"}</p><p className="mt-2 text-xs text-slate-500">Last recorded activity: {member.lastRecordedActivity}</p></article>) : <div className="rounded-xl border border-dashed border-slate-300 p-8 text-center"><p className="font-black text-slate-800">No team workload records are available</p><p className="mt-1 text-sm text-slate-500">Work assignments remain visible in the Work Queue. Future resource planning may add roster capacity and shift context.</p></div>}</div></section>}

      {view === "schedule" && <section><div className="flex flex-wrap items-end justify-between gap-3"><div><p className="text-xs font-black uppercase tracking-widest text-blue-700">Operational coordination</p><h2 className="text-2xl font-black">Schedule</h2></div>{!technician&&<Link href="/maintenance?view=upcoming" className="inline-flex min-h-11 items-center rounded-lg border border-teal-200 bg-teal-50 px-4 text-sm font-black text-teal-800">Upcoming Maintenance →</Link>}</div><div className="mt-4 grid gap-4 lg:grid-cols-3">{[["Today",today],["Tomorrow",tomorrow],["Upcoming",upcoming]].map(([label,items]) => <div key={label as string} className="rounded-xl border border-slate-200 bg-white p-4"><h3 className="font-black">{label as string}</h3><ul className="mt-3 space-y-3">{(items as OperationsWorkItem[]).length ? (items as OperationsWorkItem[]).map((item) => <li key={item.id}><Link href={`/work-orders/${item.id}`} className="block rounded-lg bg-slate-50 p-3 hover:bg-slate-100"><p className="font-mono text-xs font-black text-blue-700">{item.number}</p><p className="font-bold">{item.title}</p><p className="text-xs text-slate-500">{item.location} · {item.assignee ?? "Unassigned"}</p></Link></li>) : <li className="rounded-lg bg-slate-50 p-4 text-sm text-slate-600"><p>No planned work is scheduled for {(label as string).toLowerCase()}.</p><button type="button" onClick={() => setView("work")} className="mt-2 min-h-11 font-bold text-blue-700">View active Work Queue →</button></li>}</ul></div>)}</div><p className="mt-4 text-sm text-slate-500">Generated PM Work Orders appear here as normal work. Maintenance planning remains in the PM workspace.</p></section>}

      {view === "exceptions" && <section><div className="flex flex-wrap items-end justify-between gap-3"><div><p className="text-xs font-black uppercase tracking-widest text-amber-700">Barriers to normal workflow</p><h2 className="text-2xl font-black">Exceptions</h2><p className="mt-1 text-sm text-slate-600">Conditions creating operational exposure or preventing work from progressing normally.</p></div>{!technician&&<Link href="/maintenance?view=exceptions" className="inline-flex min-h-11 items-center rounded-lg border border-teal-200 bg-teal-50 px-4 text-sm font-black text-teal-800">PM Exceptions →</Link>}</div><div className="mt-4"><AttentionQueue items={exceptions} /></div><p className="mt-4 text-sm text-slate-500">Generated PM Work Orders appear once in the Work Queue; planning exceptions remain in Preventive Maintenance.</p></section>}
    </main>
  );
}
