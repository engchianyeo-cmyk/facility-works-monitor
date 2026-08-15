import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { incidentTransportFailure } from "@/lib/incidents/api";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";
import { UUID_PATTERN } from "@/lib/incidents/validation";
import { isWorkOrderPriority } from "@/lib/work-orders/validation";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params; const supabase = await createClient(); const { data, error } = await supabase.from("work_orders").select("id,work_order_number,title,status,priority,due_date,created_at").eq("incident_id", id).order("created_at", { ascending: false });
  if (error) return incidentTransportFailure("load linked work orders for"); return NextResponse.json({ ok: true, data: data ?? [] });
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const identity = await getCurrentIdentity(); if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  let body: Record<string, unknown>; try { body = await request.json() as Record<string, unknown>; } catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  const { id: incidentId } = await params; const existingId = String(body.work_order_id ?? ""); const supabase = await createClient();
  let workOrderId = existingId; let created: WorkOrderRecord | null = null;
  if (existingId && !UUID_PATTERN.test(existingId)) return errorResponse("VALIDATION_ERROR", "Work-order identifier is invalid.");
  if (!existingId) {
    const title = String(body.title ?? "").trim(); const location = String(body.location ?? "").trim(); const priority = String(body.priority ?? "high").toLowerCase();
    if (!title || !location || !isWorkOrderPriority(priority)) return errorResponse("VALIDATION_ERROR", "Title, location, and a valid priority are required to create corrective work.");
    const { data, error } = await supabase.rpc("create_work_order", { p_payload: { title, location, description: String(body.description ?? "").trim() || null, priority, source: "reactive", status: body.submit === true ? "submitted" : "draft" } });
    if (error) return incidentTransportFailure("create corrective work for"); const result = data as RpcResult<WorkOrderRecord> | null;
    if (!result?.ok || !result.work_order) return errorResponse(String(result?.code ?? "INTERNAL_ERROR"), String(result?.message ?? "Corrective work could not be created."));
    created = result.work_order; workOrderId = created.id;
  }
  const { data: linkData, error: linkError } = await supabase.rpc("link_work_order_to_incident", { p_work_order_id: workOrderId, p_incident_id: incidentId });
  if (linkError) return incidentTransportFailure("link corrective work to"); const link = linkData as RpcResult<WorkOrderRecord> | null;
  if (!link?.ok) return errorResponse(String(link?.code ?? "INTERNAL_ERROR"), String(link?.message ?? "Corrective work could not be linked."), link?.code === "ACCESS_DENIED" ? 403 : 400);
  return NextResponse.json({ ...link, data: link.work_order ?? created, created: Boolean(created) }, { status: created ? 201 : 200 });
}
