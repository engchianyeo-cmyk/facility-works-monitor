import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import WorkOrderDrawings from "@/components/work-order-drawings";
import WorkOrderActions from "@/components/work-orders/work-order-actions";
import WorkOrderAssignment from "@/components/work-orders/work-order-assignment";
import {
  WorkOrderPriorityBadge,
  WorkOrderStatusBadge,
} from "@/components/work-orders/work-order-badges";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { canAct, canAssign, canCreate, canEdit } from "@/lib/work-orders/permissions";
import {
  WORK_ORDER_ACTIONS,
  type WorkOrderAction,
  type WorkOrderPriority,
  type WorkOrderStatus,
} from "@/lib/work-orders/types";

export const revalidate = 0;

const TIMELINE = [
  ["created_at", "Created"],
  ["submitted_at", "Submitted"],
  ["approved_at", "Approved"],
  ["assigned_at", "Assigned"],
  ["accepted_at", "Accepted"],
  ["started_at", "Started"],
  ["completed_at", "Completed"],
  ["reviewed_at", "Reviewed"],
  ["closed_at", "Closed"],
  ["cancelled_at", "Cancelled"],
] as const;

function formatDateTime(value: string | null) {
  if (!value) return "Pending";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Unavailable";
  return new Intl.DateTimeFormat("en-SG", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function display(value: unknown) {
  return value === null || value === undefined || value === "" ? "—" : String(value);
}

function hasValue(value: unknown) {
  return value !== null && value !== undefined && value !== "";
}

function auditNote(value: string | null) {
  if (!value) return null;
  try {
    return JSON.stringify(JSON.parse(value), null, 2);
  } catch {
    return value;
  }
}

function LoadFailure({ message }: { message: string }) {
  return (
    <div className="rounded-lg border border-red-300 bg-red-50 p-4 text-sm text-red-700" role="alert">
      {message}
    </div>
  );
}

export default async function WorkOrderDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const identity = await getCurrentIdentity();
  if (!identity) redirect(`/login?next=/work-orders/${id}`);

  const supabase = await createClient();
  const { data: order, error: orderError } = await supabase
    .from("work_orders")
    .select("*, categories(name), departments(code,name,colour_tag)")
    .eq("id", id)
    .maybeSingle();

  if (orderError) {
    return (
      <main className="mx-auto max-w-5xl space-y-6 p-6 lg:p-8">
        <Link href="/work-orders" className="text-sm font-medium text-blue-700 hover:underline">← All work orders</Link>
        <LoadFailure message="This work order could not be loaded. Please try again." />
      </main>
    );
  }
  if (!order) notFound();

  const status = order.status as WorkOrderStatus;
  const context = {
    role: identity.role,
    actorId: identity.userId,
    requesterId: order.requested_by,
    assignedTechnicianId: order.assigned_technician_id,
    status,
  };
  let allowedActions = WORK_ORDER_ACTIONS.filter((action) => canAct(action, context));
  if (status === "assigned") {
    allowedActions = allowedActions.filter((action) => action !== (order.accepted_at ? "accept" : "start"));
  } else {
    allowedActions = allowedActions.filter((action) => action !== "accept");
  }
  if (["closed", "cancelled"].includes(status)) allowedActions = [];

  const assignmentAllowed = canAssign(identity.role, status);
  let assigneeLoadFailed = false;
  let technicians: Array<{ id: string; name: string; detail: string | null }> = [];
  let vendors: Array<{ id: string; name: string; detail: string | null }> = [];
  let teams: Array<{ id: string; name: string }> = [];

  if (assignmentAllowed) {
    const [technicianResult, vendorResult, teamResult] = await Promise.all([
      supabase.from("profiles").select("id,display_name,trade_discipline,department").eq("role", "technician").eq("is_active", true).is("deleted_at", null).order("display_name"),
      supabase.from("vendors").select("id,name,trade").eq("active", true).is("deleted_at", null).order("name"),
      supabase.from("maintenance_teams").select("id,name").eq("is_active", true).is("deleted_at", null).order("name"),
    ]);
    assigneeLoadFailed = Boolean(technicianResult.error || vendorResult.error || teamResult.error);
    if (!assigneeLoadFailed) {
      technicians = (technicianResult.data ?? []).map((item) => ({
        id: item.id,
        name: item.display_name,
        detail: [item.trade_discipline, item.department].filter(Boolean).join(" · ") || null,
      }));
      vendors = (vendorResult.data ?? []).map((item) => ({ id: item.id, name: item.name, detail: item.trade }));
      teams = (teamResult.data ?? []).map((item) => ({ id: item.id, name: item.name }));
    }
  }

  const { data: activity, error: activityError } = await supabase
    .from("activity_logs")
    .select("id,action,from_status,to_status,actor,note,created_at")
    .eq("work_order_id", id)
    .order("created_at", { ascending: false });

  const predictive = ["condition_based", "predictive"].includes(order.source)
    || order.alert_id
    || order.prediction_reference;
  const overviewFields = [
    ["Source", String(order.source).replaceAll("_", " ")],
    ["Requested by", order.submitted_by],
    ["Due date", order.due_date],
    ["Estimated hours", order.estimated_hours],
    ["Actual labour hours", order.actual_labour_hours],
    ["Contact number", order.contact_number],
    ["Asset ID", order.asset_id],
  ].filter(([, value]) => hasValue(value));
  const assignmentFields = [
    ["Assigned to", order.assigned_to],
    ["Assigned by", order.assigned_by],
    ["Assigned at", order.assigned_at ? formatDateTime(order.assigned_at) : null],
    ["Accepted at", order.accepted_at ? formatDateTime(order.accepted_at) : null],
  ].filter(([, value]) => hasValue(value));
  const noteFields = [
    ["Completion notes", order.completion_notes],
    ["Internal notes", order.internal_notes],
    ["Cancellation reason", order.cancellation_reason],
  ].filter(([, value]) => hasValue(value));
  const predictiveFields = [
    ["Source reference", order.source_reference],
    ["Alert ID", order.alert_id],
    ["Prediction reference", order.prediction_reference],
    ["Health score", order.health_score_at_creation],
    ["Failure probability", order.failure_probability],
    ["Predicted failure", order.predicted_failure_date],
    ["Confidence", order.confidence_score],
    ["Recommended action", order.recommended_action],
  ].filter(([, value]) => hasValue(value));

  return (
    <main className="mx-auto max-w-5xl space-y-8 p-6 lg:p-8">
      <Link href="/work-orders" className="text-sm font-medium text-blue-700 hover:underline">← All work orders</Link>

      <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="text-sm font-bold tracking-wide text-blue-700">{order.work_order_number}</p>
            <h1 className="mt-1 text-3xl font-bold text-slate-900">{order.title}</h1>
            <p className="mt-2 text-slate-500">{[order.site, order.location, order.categories?.name, order.departments?.name].filter(Boolean).join(" · ")}</p>
          </div>
          <div className="flex gap-2">
            <WorkOrderPriorityBadge priority={order.priority as WorkOrderPriority} />
            <WorkOrderStatusBadge status={status} />
          </div>
        </div>
        {order.description && <p className="mt-5 whitespace-pre-wrap text-slate-700">{order.description}</p>}
        {overviewFields.length > 0 && (
          <dl className="mt-6 grid gap-4 border-t border-slate-100 pt-5 text-sm sm:grid-cols-2 lg:grid-cols-4">
            {overviewFields.map(([label, value]) => <div key={String(label)}><dt className="text-slate-400">{label}</dt><dd className="mt-1 font-medium text-slate-800">{display(value)}</dd></div>)}
          </dl>
        )}
      </section>

      {assignmentFields.length > 0 && (
        <section className="rounded-xl border border-slate-200 bg-white p-5">
          <h2 className="font-semibold text-slate-900">Assignment details</h2>
          <dl className="mt-4 grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
            {assignmentFields.map(([label, value]) => <div key={String(label)}><dt className="text-slate-400">{label}</dt><dd className="mt-1 font-medium text-slate-800">{display(value)}</dd></div>)}
          </dl>
        </section>
      )}

      {noteFields.length > 0 && (
        <section className="rounded-xl border border-slate-200 bg-white p-5">
          <h2 className="font-semibold text-slate-900">Work notes</h2>
          <dl className="mt-4 space-y-4">
            {noteFields.map(([label, value]) => <div key={String(label)}><dt className="text-sm font-medium text-slate-500">{label}</dt><dd className="mt-1 whitespace-pre-wrap text-sm text-slate-800">{display(value)}</dd></div>)}
          </dl>
        </section>
      )}

      {predictive && predictiveFields.length > 0 && (
        <section className="rounded-xl border border-purple-200 bg-purple-50 p-5">
          <h2 className="font-semibold text-purple-950">Condition and predictive source context</h2>
          <dl className="mt-4 grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
            {predictiveFields.map(([label, value]) => <div key={String(label)}><dt className="text-purple-600">{label}</dt><dd className="mt-1 text-purple-950">{display(value)}</dd></div>)}
          </dl>
        </section>
      )}

      {assignmentAllowed && (
        <section className="rounded-xl border border-violet-200 bg-violet-50 p-5">
          <h2 className="font-semibold text-violet-950">Primary assignment</h2>
          <p className="mb-4 mt-1 text-sm text-violet-800">Assign one active technician, vendor, or maintenance team. A new assignment replaces the previous primary assignment.</p>
          {assigneeLoadFailed
            ? <LoadFailure message="Assignable personnel could not be loaded. Assignment is temporarily unavailable." />
            : <WorkOrderAssignment workOrderId={id} technicians={technicians} vendors={vendors} teams={teams} />}
        </section>
      )}

      <section className="rounded-xl border border-slate-200 bg-white p-5">
        <h2 className="mb-4 font-semibold">Available actions</h2>
        <WorkOrderActions id={id} status={status} allowedActions={allowedActions as WorkOrderAction[]} canEdit={canEdit(context)} canDuplicate={canCreate(identity.role)} />
      </section>

      <section className="rounded-xl border border-slate-200 bg-white p-5">
        <h2 className="mb-4 font-semibold">Workflow timeline</h2>
        <ol className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          {TIMELINE.map(([field, label]) => (
            <li key={field} className={`rounded-lg border p-3 text-sm ${order[field] ? "border-emerald-200 bg-emerald-50" : "border-slate-200 bg-slate-50"}`}>
              <p className="font-semibold">{label}</p>
              <p className="mt-1 text-xs text-slate-500">{formatDateTime(order[field])}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="rounded-xl border border-slate-200 bg-white p-5">
        <h2 className="mb-4 font-semibold">Audit history</h2>
        {activityError
          ? <LoadFailure message="Audit history could not be loaded. Please try again." />
          : !activity?.length
            ? <p className="text-sm text-slate-500">No audit activity.</p>
            : <ul className="divide-y divide-slate-100">{activity.map((entry) => <li key={entry.id} className="py-4 text-sm"><div className="flex flex-wrap justify-between gap-2"><strong>{entry.actor || "System"} · {entry.action}</strong><time className="text-slate-400">{formatDateTime(entry.created_at)}</time></div>{(entry.from_status || entry.to_status) && <p className="mt-1 text-slate-500">{display(entry.from_status)} → {display(entry.to_status)}</p>}{entry.note && <pre className="mt-2 overflow-auto whitespace-pre-wrap rounded bg-slate-50 p-3 text-xs text-slate-600">{auditNote(entry.note)}</pre>}</li>)}</ul>}
      </section>

      <WorkOrderDrawings />
    </main>
  );
}
