import { redirect } from "next/navigation";
import OperationsWorkspace, {
  type AttentionItem,
  type OperationsWorkItem,
  type OperationsWorkspaceData,
  type TeamMember,
} from "@/components/operations/OperationsWorkspace";
import { incidentTypeLabel } from "@/lib/product-terminology";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { assetReferenceLabel } from "@/lib/assets/presentation";

export const revalidate = 0;

type RawOrder = {
  id: string;
  work_order_number: string;
  title: string;
  location: string;
  site: string | null;
  asset_id: string | null;
  asset: { asset_tag: string; name: string } | null;
  priority: string;
  status: string;
  assigned_to: string | null;
  assigned_technician_id: string | null;
  assigned_vendor_id: string | null;
  assigned_team_id: string | null;
  due_date: string | null;
  completion_notes: string | null;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
  categories: { name: string } | null;
};

type RawIncident = {
  id: string;
  incident_number: string;
  incident_type: string;
  severity: string;
  status: string;
  location: string;
  assigned_technician_id: string | null;
  assigned_team_id: string | null;
  reported_at: string;
};

const OPEN = new Set(["draft", "submitted", "approved", "assigned", "in_progress", "completed"]);
const day = (date = new Date()) => new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Singapore", year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
const dateLabel = (value: string | null) => value ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeZone: "Asia/Singapore" }).format(new Date(`${value}T00:00:00`)) : "No due date";
const elapsed = (value: string) => {
  const minutes = Math.max(0, Math.floor((Date.now() - Date.parse(value)) / 60000));
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hr`;
  return `${Math.floor(hours / 24)} day${hours < 48 ? "" : "s"}`;
};
const nextAction = (status: string, assigned: boolean) => {
  if (!assigned && ["approved", "assigned"].includes(status)) return "Assign responsible person or team";
  return ({ draft: "Complete and submit request", submitted: "Review authorization", approved: "Allocate resources", assigned: "Accept and start work", in_progress: "Continue work and record completion", completed: "Review completed work", reviewed: "Close work order" })[status] ?? "Review work order";
};

export default async function OperationsPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/operations");

  const supabase = await createClient();
  let orderQuery = supabase.from("work_orders").select("id,work_order_number,title,location,site,asset_id,asset:assets(asset_tag,name),priority,status,assigned_to,assigned_technician_id,assigned_vendor_id,assigned_team_id,due_date,completion_notes,completed_at,created_at,updated_at,categories(name)").order("priority_rank", { ascending: false }).order("due_date", { ascending: true, nullsFirst: false });
  if (identity.role === "technician") orderQuery = orderQuery.eq("assigned_technician_id", identity.userId);

  const teamAllowed = ["approver", "supervisor", "administrator"].includes(identity.role);
  const [orderResult, incidentResult, teamResult, evidenceResult] = await Promise.all([
    orderQuery,
    supabase.from("incidents").select("id,incident_number,incident_type,severity,status,location,assigned_technician_id,assigned_team_id,reported_at").not("status", "in", "(closed,cancelled)").order("reported_at", { ascending: false }),
    teamAllowed ? supabase.from("profiles").select("id,display_name,trade_discipline,department,last_active_at").eq("role", "technician").eq("is_active", true).is("deleted_at", null).order("display_name") : Promise.resolve({ data: [], error: null }),
    supabase.from("evidence_items").select("work_order_id").not("work_order_id", "is", null),
  ]);

  const rawOrders = (orderResult.error ? [] : orderResult.data ?? []) as unknown as RawOrder[];
  const rawIncidents = (incidentResult.error ? [] : incidentResult.data ?? []) as RawIncident[];
  const evidenceCounts = new Map<string, number>();
  if (!evidenceResult.error) for (const row of evidenceResult.data ?? []) if (row.work_order_id) evidenceCounts.set(row.work_order_id, (evidenceCounts.get(row.work_order_id) ?? 0) + 1);
  const today = day();
  const work: OperationsWorkItem[] = rawOrders.map((order) => {
    const assigned = Boolean(order.assigned_technician_id || order.assigned_vendor_id || order.assigned_team_id || order.assigned_to);
    return {
      id: order.id,
      number: order.work_order_number,
      title: order.title,
      location: [order.site, order.location].filter(Boolean).join(" · "),
      system: order.categories?.name ?? null,
      asset: assetReferenceLabel(order.asset_id, order.asset),
      priority: order.priority,
      status: order.status,
      assignee: order.assigned_to,
      age: elapsed(order.created_at),
      due: dateLabel(order.due_date),
      dueDate: order.due_date,
      overdue: Boolean(order.due_date && order.due_date < today && !["completed", "reviewed", "closed", "cancelled"].includes(order.status)),
      dueToday: order.due_date === today,
      completedToday: Boolean(order.completed_at && day(new Date(order.completed_at)) === today),
      nextAction: nextAction(order.status, assigned),
      completionNotes: order.completion_notes,
      evidenceCount: evidenceResult.error ? null : evidenceCounts.get(order.id) ?? 0,
    };
  });

  const attention: AttentionItem[] = [];
  for (const incident of rawIncidents.filter((item) => ["emergency", "critical"].includes(item.severity))) {
    const assigned = Boolean(incident.assigned_technician_id || incident.assigned_team_id);
    attention.push({ id: `incident-${incident.id}`, type: "emergency", title: incidentTypeLabel(incident.incident_type), reference: incident.incident_number, location: incident.location, reason: "Active emergency incident", owner: assigned ? "Assigned responder" : "Unassigned", waiting: elapsed(incident.reported_at), impact: "Emergency response and facility safety may be affected.", nextAction: assigned ? "Confirm response progress and current site condition" : "Assign a responder and confirm acknowledgement", href: `/incidents/${incident.id}` });
  }
  const seen = new Set<string>();
  for (const item of work) {
    if (!OPEN.has(item.status)) continue;
    let type: AttentionItem["type"] | null = null;
    if (item.priority === "critical") type = "critical";
    else if (item.overdue) type = "overdue";
    else if (!item.assignee && ["approved", "assigned"].includes(item.status)) type = "unassigned";
    else if (["submitted", "completed"].includes(item.status)) type = "approval";
    if (!type || seen.has(item.id)) continue;
    seen.add(item.id);
    attention.push({ id: `work-${item.id}`, type, title: item.title.toUpperCase(), reference: item.number, location: item.location, reason: item.nextAction, owner: item.assignee ?? "Unassigned", waiting: item.age, impact: type === "critical" ? "A critical facility requirement remains unresolved." : type === "overdue" ? "Delivery is beyond the recorded due date." : type === "unassigned" ? "Work cannot progress until responsibility is confirmed." : "Work is waiting for an authorized decision.", nextAction: item.nextAction, href: `/work-orders/${item.id}` });
  }

  const profiles = (teamResult.error ? [] : teamResult.data ?? []) as Array<{ id: string; display_name: string; trade_discipline: string | null; department: string | null; last_active_at: string | null }>;
  const team: TeamMember[] = profiles.map((profile) => {
    const assigned = rawOrders.filter((order) => order.assigned_technician_id === profile.id && ["assigned", "in_progress"].includes(order.status));
    return { id: profile.id, name: profile.display_name, discipline: profile.trade_discipline ?? profile.department ?? "Discipline not recorded", lastRecordedActivity: profile.last_active_at ? `${elapsed(profile.last_active_at)} ago` : "Not recorded", workload: assigned.length, currentAssignment: assigned[0] ? `${assigned[0].work_order_number} · ${assigned[0].title}` : null };
  });

  const data: OperationsWorkspaceData = { role: identity.role, name: identity.displayName, work, attention, team, availability: { work: !orderResult.error, incidents: !incidentResult.error, team: !teamResult.error } };
  return <OperationsWorkspace data={data} />;
}
