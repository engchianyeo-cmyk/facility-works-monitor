import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { incidentSla } from "@/lib/incidents/sla";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";
import { incidentTransportFailure } from "@/lib/incidents/api";

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(_request: NextRequest, { params }: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  const supabase = await createClient();
  const { data: incident, error } = await supabase.from("incidents")
    .select("*,assigned_technician:profiles!incidents_assigned_technician_id_fkey(id,display_name,role),assigned_team:maintenance_teams!incidents_assigned_team_id_fkey(id,name)")
    .eq("id", id).maybeSingle();
  if (error) return incidentTransportFailure("load");
  if (!incident) return errorResponse("NOT_FOUND", "Emergency incident not found.", 404);

  const [activityResult, workOrdersResult, notificationResult] = await Promise.all([
    supabase.from("activity_logs").select("id,action,from_status,to_status,actor,note,created_at,user_id").eq("incident_id", id).order("created_at", { ascending: true }),
    supabase.from("work_orders").select("id,work_order_number,title,status,priority,due_date,created_at").eq("incident_id", id).order("created_at", { ascending: false }),
    supabase.from("notification_outbox").select("id,channel,provider,delivery_status,result_code,attempted_at,delivered_at,created_at").eq("incident_id", id).order("created_at", { ascending: false }),
  ]);
  if (activityResult.error || workOrdersResult.error) return incidentTransportFailure("load");
  const notifications = notificationResult.error ? [] : (notificationResult.data ?? []);
  const summary = notifications.reduce<Record<string, { total: number; delivered: number; failed: number; pending: number }>>((acc, item) => {
    const channel = String(item.channel ?? "unknown"); const entry = acc[channel] ?? { total: 0, delivered: 0, failed: 0, pending: 0 };
    entry.total += 1; if (item.delivery_status === "sent") entry.delivered += 1; else if (item.delivery_status === "failed") entry.failed += 1; else entry.pending += 1; acc[channel] = entry; return acc;
  }, {});
  return NextResponse.json({ ok: true, data: { incident, responder: { technician: incident.assigned_technician ?? null, team: incident.assigned_team ?? null }, acknowledgement_deadline: incident.acknowledgement_deadline, sla: incidentSla(incident.reported_at, incident.acknowledgement_deadline, incident.acknowledged_at), activity: activityResult.data ?? [], linked_work_orders: workOrdersResult.data ?? [], notifications, notification_summary: summary } });
}

