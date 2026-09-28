import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import CorrectiveWorkOrderForm from "@/components/incidents/corrective-work-order-form";
import EvidencePanel from "@/components/evidence/evidence-panel";
import IncidentAssignment from "@/components/incidents/incident-assignment";
import IncidentActions from "@/components/incidents/incident-actions";
import AssetLinkControl from "@/components/assets/asset-link-control";
import { SlaIndicator } from "@/components/operations/sla-indicator";
import { StatusIndicator } from "@/components/operations/status-indicator";
import { getCurrentIdentity } from "@/lib/auth";
import { assetReferenceLabel } from "@/lib/assets/presentation";
import { canLinkIncidentAsset, type AssetSummary } from "@/lib/assets/types";
import { canActOnIncident } from "@/lib/incidents/permissions";
import { INCIDENT_ACTIONS, INCIDENT_STATUS_LABELS, type IncidentAction, type IncidentRecord } from "@/lib/incidents/types";
import { canTransitionFrom } from "@/lib/incidents/workflow";
import { incidentTypeLabel, operationalLabel, priorityLabel, workOrderStatusLabel } from "@/lib/product-terminology";
import { createClient } from "@/lib/supabase/server";

type NamedProfile = { display_name?: string } | null; type NamedTeam = { name?: string } | null;
type DetailedIncident = IncidentRecord & { assigned_technician?: NamedProfile; assigned_team?: NamedTeam; incident_commander?: NamedProfile; asset?: AssetSummary | null };
type Log = { id: string; action: string; actor: string | null; note: string | null; created_at: string; from_status: string | null; to_status: string | null };
type Notification = { id: string; channel: string | null; provider: string; result_code: string | null; delivery_status: string; attempted_at: string | null };
type WorkOrder = { id: string; work_order_number: string | null; title: string; status: string; priority: string };
const fmt = (value: string | null) => value ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Pending";
const channelSummary = (rows: Notification[], channel: string) => { const selected = rows.filter(row => row.channel === channel); if (!selected.length) return "Unavailable"; if (selected.some(row => row.delivery_status === "failed")) return "Failed"; if (selected.some(row => row.delivery_status === "pending" || row.delivery_status === "processing")) return "Queued"; return selected.every(row => row.delivery_status === "sent") ? "Delivered" : "Not Configured"; };

export default async function IncidentDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params; const identity = await getCurrentIdentity(); if (!identity) redirect(`/login?next=/incidents/${id}`);
  const supabase = await createClient();
  const { data } = await supabase.from("incidents").select("*,assigned_technician:profiles!incidents_assigned_technician_id_fkey(display_name),assigned_team:maintenance_teams!incidents_assigned_team_id_fkey(name),incident_commander:profiles!incidents_incident_commander_id_fkey(display_name),asset:assets(asset_tag,name,asset_type,criticality,lifecycle_status,site,location,system:asset_systems(name,system_code))").eq("id", id).maybeSingle();
  if (!data) notFound(); const incident = data as unknown as DetailedIncident;
  let teamMember = false;
  if (incident.assigned_team_id && identity.role === "technician") { const { data: member } = await supabase.from("maintenance_team_members").select("team_id").eq("team_id", incident.assigned_team_id).eq("profile_id", identity.userId).eq("is_active", true).maybeSingle(); teamMember = Boolean(member); }
  const context = { role: identity.role, actorId: identity.userId, status: incident.status, assignedTechnicianId: incident.assigned_technician_id, assignedTeamMember: teamMember };
  const actions = INCIDENT_ACTIONS.filter(action => action !== "cancel" && canTransitionFrom(incident.status, action) && canActOnIncident(action, context));
  const [logResult, notificationResult, workResult, projectionResult, optionResult] = await Promise.all([
    supabase.from("activity_logs").select("id,action,actor,note,created_at,from_status,to_status").eq("incident_id", id).order("created_at", { ascending: true }),
    supabase.from("notification_outbox").select("id,channel,provider,result_code,delivery_status,attempted_at").eq("incident_id", id).order("created_at", { ascending: false }),
    supabase.from("work_orders").select("id,work_order_number,title,status,priority").eq("incident_id", id).order("created_at", { ascending: false }),
    supabase.rpc("get_incident_operations", { p_incident_id: id }),
    ["supervisor", "administrator"].includes(identity.role) ? supabase.rpc("get_emergency_response_options") : Promise.resolve({ data: [], error: null }),
  ]);
  const projection = (projectionResult.data as { responder_display_name?: string; team_name?: string; commander_display_name?: string; sms_status?: string; whatsapp_status?: string }[] | null)?.[0];
  if (projection?.commander_display_name) incident.incident_commander = { display_name: projection.commander_display_name };
  const fallbackNotifications = (["sms", "whatsapp"] as const).map(channel => { const value = projection?.[`${channel}_status`]; return { id: `safe-${channel}`, channel, provider: "hidden", result_code: value === "not_configured" ? "NOT_CONFIGURED" : null, delivery_status: value === "delivered" ? "sent" : value === "pending" ? "pending" : value === "unavailable" ? "unavailable" : "failed", attempted_at: null }; });
  const logs = (logResult.data ?? []) as Log[]; const notifications = (notificationResult.error ? fallbackNotifications : notificationResult.data ?? []) as Notification[]; const workOrders = (workResult.data ?? []) as WorkOrder[];
  const active = !["closed", "cancelled"].includes(incident.status); const emergency = active && incident.severity === "emergency";
  const assignmentOptions = (optionResult.data ?? []) as { target_type: string; target_id: string; display_name: string }[];
  const responderName = projection?.responder_display_name ?? projection?.team_name ?? incident.assigned_technician?.display_name ?? incident.assigned_team?.name ?? (incident.assigned_technician_id ? "Assigned technician" : incident.assigned_team_id ? "Assigned team" : "Unassigned");
  const responder = <>{responderName}{assignmentOptions.length > 0 && active && <div className="mt-4 rounded-xl border border-blue-200 bg-blue-50 p-4"><IncidentAssignment incidentId={id} options={assignmentOptions} /></div>}</>;
  const canCreateCorrective = ["safe", "recovery"].includes(incident.status) && ["approver", "supervisor", "administrator"].includes(identity.role);
  const assetLinkAllowed = active && canLinkIncidentAsset(identity.role);
  const assetOptionResult = assetLinkAllowed ? await supabase.from("assets").select("id,asset_tag,name,asset_type,criticality,lifecycle_status,site,location,system:asset_systems(name,system_code)").neq("lifecycle_status", "decommissioned").order("asset_tag") : { data: [], error: null };
  const assetOptions = (assetOptionResult.error ? [] : assetOptionResult.data ?? []) as unknown as AssetSummary[];
  const assetLabel = assetReferenceLabel(incident.asset_id, incident.asset);
  return (
    <main className="mx-auto max-w-6xl space-y-6 p-4 pb-24 sm:p-6 lg:p-8">
      <Link href="/incidents" className="inline-flex min-h-11 items-center text-sm font-semibold text-slate-700 hover:underline">← Incident Operations Board</Link>
      {emergency && <div role="status" className="rounded-2xl border-2 border-red-900 bg-red-700 p-5 text-white shadow-lg"><p className="text-xs font-black uppercase tracking-[.22em]">Emergency Response Active</p><h1 className="mt-1 font-mono text-3xl font-black">{incident.incident_number}</h1><p className="mt-2 text-lg font-bold">{incident.location}</p></div>}
      <div className="grid gap-6 lg:grid-cols-[minmax(0,1.4fr)_minmax(19rem,.6fr)]">
        <div className="space-y-6">
          <section className="rounded-2xl border bg-white p-5 sm:p-6">
            <div className="flex flex-wrap justify-between gap-4"><div>{!emergency && <h1 className="font-mono text-2xl font-black">{incident.incident_number}</h1>}<h2 className="mt-1 text-2xl font-black">{incidentTypeLabel(incident.incident_type)}</h2><p className="mt-1 text-lg font-semibold text-slate-700">{incident.location}</p></div><div className="flex h-fit gap-2"><StatusIndicator tone={emergency ? "danger" : "warning"}>{operationalLabel(incident.severity)}</StatusIndicator><StatusIndicator tone={active ? "info" : "neutral"}>{INCIDENT_STATUS_LABELS[incident.status]}</StatusIndicator></div></div>
            <p className="mt-5 whitespace-pre-wrap text-slate-800">{incident.description}</p>
            <dl className="mt-6 grid gap-4 border-t pt-5 text-sm sm:grid-cols-2"><div><dt className="text-slate-500">Current phase</dt><dd className="font-bold">{INCIDENT_STATUS_LABELS[incident.status]}</dd></div><div><dt className="text-slate-500">Responder</dt><dd className="font-bold">{responder}</dd></div><div><dt className="text-slate-500">Incident Commander</dt><dd className="font-bold">{incident.incident_commander?.display_name ?? (incident.incident_commander_id ? "Assigned" : "Unassigned")}</dd></div><div><dt className="text-slate-500">Acknowledgement deadline</dt><dd className="font-bold">{fmt(incident.acknowledgement_deadline)}</dd></div></dl>
            <div className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4"><SlaIndicator reportedAt={incident.reported_at} deadline={incident.acknowledgement_deadline} acknowledgedAt={incident.acknowledged_at} /><p className="mt-1 text-xs text-slate-600">Elapsed from report; countdown stops when acknowledged.</p></div>
          </section>
          {actions.length > 0 && <section aria-labelledby="response-actions" className="sticky bottom-3 z-10 rounded-2xl border-2 border-red-300 bg-red-50 p-5 shadow-xl lg:static"><h2 id="response-actions" className="mb-3 text-lg font-black">Response action</h2><IncidentActions id={id} actions={actions as IncidentAction[]} /></section>}
          <section className="rounded-2xl border bg-white p-5"><h2 className="text-xl font-black">Response timeline</h2>{logResult.error ? <p role="alert" className="mt-3 text-red-700">The response timeline is temporarily unavailable. Incident details and available response actions remain accessible.</p> : logs.length ? <ol className="mt-4 border-l-2 border-slate-200 pl-5">{logs.map(log => <li key={log.id} className="relative pb-6 before:absolute before:-left-[1.55rem] before:top-1 before:h-3 before:w-3 before:rounded-full before:bg-blue-600"><div className="flex flex-wrap justify-between gap-2"><strong>{operationalLabel(log.action)}</strong><time dateTime={log.created_at} className="text-xs text-slate-500">{fmt(log.created_at)}</time></div><p className="text-sm text-slate-600">{log.actor || "System"}{log.from_status || log.to_status ? ` · ${operationalLabel(log.from_status ?? "start")} → ${log.to_status ? operationalLabel(log.to_status) : "Not recorded"}` : ""}</p></li>)}</ol> : <p className="mt-3 text-slate-600">No response activity has been recorded.</p>}</section>
          <section className="rounded-2xl border border-emerald-200 bg-emerald-50 p-5"><p className="text-xs font-black uppercase tracking-widest text-emerald-800">Primary affected Asset</p>{assetLabel ? incident.asset ? <Link href={`/assets/${incident.asset_id}`} className="mt-1 inline-block text-lg font-black text-emerald-950 hover:underline">{assetLabel}</Link> : <p className="mt-1 text-lg font-black text-amber-900">Asset unavailable</p> : <p className="mt-1 font-bold">No Asset linked</p>}<p className="mt-1 text-sm text-emerald-800">Incident location remains the authoritative event-location context.</p>{assetLinkAllowed && <div className="mt-4 border-t border-emerald-200 pt-4"><AssetLinkControl parent="incidents" parentId={id} assets={assetOptions} currentAssetId={incident.asset_id ?? null} unavailable={Boolean(incident.asset_id && !incident.asset)} /></div>}</section>
          <EvidencePanel parentType="incident" parentId={id} />
        </div>
        <aside className="space-y-6">
          <section className="rounded-2xl border bg-white p-5"><h2 className="font-black">Notification delivery</h2><dl className="mt-4 space-y-3 text-sm"><div className="flex justify-between gap-3"><dt>SMS</dt><dd className="font-bold">{channelSummary(notifications, "sms")}</dd></div><div className="flex justify-between gap-3"><dt>WhatsApp</dt><dd className="font-bold">{channelSummary(notifications, "whatsapp")}</dd></div></dl>{notificationResult.error && <p className="mt-3 text-xs text-slate-500">Delivery details are unavailable for this role. This does not confirm that a notification was delivered.</p>}</section>
          <section className="rounded-2xl border bg-white p-5"><div className="flex items-center justify-between gap-3"><h2 className="font-black">Corrective Work</h2><StatusIndicator>{workOrders.length} linked</StatusIndicator></div>{workResult.error ? <p className="mt-3 text-red-700">Linked Corrective Work is temporarily unavailable. The Incident remains accessible.</p> : workOrders.length ? <ul className="mt-4 divide-y">{workOrders.map(work => <li key={work.id} className="py-3"><Link href={`/work-orders/${work.id}`} className="font-bold text-blue-700 hover:underline">{work.work_order_number || "Work Order"}</Link><p className="text-sm text-slate-700">{work.title}</p><p className="text-xs text-slate-500">{workOrderStatusLabel(work.status)} · {priorityLabel(work.priority)} Priority</p></li>)}</ul> : <p className="mt-3 text-sm text-slate-600">No Corrective Work is linked to this Incident.</p>}{canCreateCorrective && <div className="mt-5 border-t pt-5"><CorrectiveWorkOrderForm incidentId={id} location={incident.location} /></div>}</section>
        </aside>
      </div>
    </main>
  );
}
