import Link from "next/link";
import { OperationsCard } from "@/components/operations/operations-board";
import { SlaIndicator } from "@/components/operations/sla-indicator";
import { StatusIndicator } from "@/components/operations/status-indicator";
import { INCIDENT_STATUS_LABELS, type IncidentRecord } from "@/lib/incidents/types";
import { incidentTypeLabel, operationalLabel } from "@/lib/product-terminology";

type Related = { display_name?: string } | { name?: string } | null;
type IncidentCardRecord = IncidentRecord & { assigned_technician?: Related; assigned_team?: Related; incident_commander?: Related; linked_work_orders?: { count: number }[] };
export type NotificationState = Record<string, { sent: number; failed: number; pending: number }>;
const name = (value: Related, fallback: string) => {
  if (!value) return fallback;
  const record = value as { display_name?: string; name?: string };
  return record.display_name || record.name || fallback;
};
const notifyLabel = (state?: { sent: number; failed: number; pending: number }) => !state ? "Unavailable" : state.failed ? "Failed" : state.pending ? "Queued" : state.sent ? "Delivered" : "Not Configured";

export function IncidentCard({ incident, notifications = {} }: { incident: IncidentCardRecord; notifications?: NotificationState }) {
  const active = !["closed", "cancelled"].includes(incident.status); const emergency = active && incident.severity === "emergency";
  const unassigned = !incident.assigned_technician_id && !incident.assigned_team_id;
  const responder = incident.assigned_technician_id ? name(incident.assigned_technician ?? null, "Assigned technician") : incident.assigned_team_id ? name(incident.assigned_team ?? null, "Assigned team") : "Unassigned";
  return <OperationsCard emergency={emergency}><Link href={`/incidents/${incident.id}`} className="block p-5 outline-none focus-visible:ring-4 focus-visible:ring-blue-500"><div className="flex flex-wrap items-start justify-between gap-3"><div><p className={`font-mono text-sm font-black ${emergency ? "text-red-800" : "text-slate-700"}`}>{incident.incident_number}</p><h2 className="mt-1 text-xl font-black">{incidentTypeLabel(incident.incident_type)}</h2><p className="mt-1 text-base font-semibold text-slate-700">{incident.location}</p></div><div className="flex flex-wrap justify-end gap-2"><StatusIndicator tone={emergency ? "danger" : incident.severity === "critical" ? "warning" : "neutral"}>{operationalLabel(incident.severity)}</StatusIndicator><StatusIndicator tone={active ? "info" : "neutral"}>{INCIDENT_STATUS_LABELS[incident.status]}</StatusIndicator></div></div>{emergency && <p className="mt-4 border-l-4 border-red-600 pl-3 text-sm font-black uppercase tracking-wide text-red-800">Emergency response active</p>}<dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2"><div><dt className="text-slate-500">Responder</dt><dd className="font-semibold">{responder}</dd></div><div><dt className="text-slate-500">Incident Commander</dt><dd className="font-semibold">{name(incident.incident_commander ?? null, incident.incident_commander_id ? "Assigned" : "Unassigned")}</dd></div></dl>{unassigned && active && <div className="mt-4"><StatusIndicator tone="danger">Unassigned emergency</StatusIndicator></div>}<div className="mt-4 rounded-lg bg-white/80 p-3"><SlaIndicator reportedAt={incident.reported_at} deadline={incident.acknowledgement_deadline} acknowledgedAt={incident.acknowledged_at} compact /></div><div className="mt-4 flex flex-wrap gap-2 text-xs"><StatusIndicator>SMS: {notifyLabel(notifications.sms)}</StatusIndicator><StatusIndicator>WhatsApp: {notifyLabel(notifications.whatsapp)}</StatusIndicator><StatusIndicator>{incident.linked_work_orders?.[0]?.count ?? 0} linked Work Order{incident.linked_work_orders?.[0]?.count === 1 ? "" : "s"}</StatusIndicator></div></Link></OperationsCard>;
}
