import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";
import { validateContactNumber, validatePredictiveRanges } from "@/lib/work-orders/validation";

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(_request: NextRequest, { params }: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("work_orders")
    .select("*, categories(name), departments(code,name,colour_tag)")
    .eq("id", id)
    .maybeSingle();
  if (error) return transportFailure("load");
  if (!data) return errorResponse("NOT_FOUND", "Work order not found.", 404);

  const { data: activity, error: activityError } = await supabase
    .from("activity_logs")
    .select("id,action,from_status,to_status,actor,note,created_at,user_id")
    .eq("work_order_id", id)
    .order("created_at", { ascending: true });
  if (activityError) return transportFailure("load");
  return NextResponse.json({ ok: true, data: { ...data, activity: activity ?? [] } });
}

async function updateWorkOrder(request: NextRequest, { params }: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  let body: Record<string, unknown>;
  try { body = (await request.json()) as Record<string, unknown>; }
  catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  const contactError = validateContactNumber(body.contact_number);
  if (contactError) return errorResponse("VALIDATION_ERROR", contactError);
  const rangeError = validatePredictiveRanges(body);
  if (rangeError) return errorResponse("VALIDATION_ERROR", rangeError);
  const { id } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("update_work_order", { p_work_order_id: id, p_payload: body });
  if (error) return transportFailure("update");
  return rpcResponse(data as RpcResult<WorkOrderRecord> | null);
}

export async function PATCH(request: NextRequest, context: RouteContext) {
  try {
    return await updateWorkOrder(request, context);
  } catch {
    return transportFailure("update");
  }
}

async function cancelWorkOrder(request: NextRequest, { params }: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  let reason = request.nextUrl.searchParams.get("reason")?.trim() ?? "";
  if (!reason) {
    try {
      const body = (await request.json()) as { reason?: unknown };
      reason = String(body.reason ?? "").trim();
    } catch { /* A body is optional; the RPC returns the stable reason error. */ }
  }
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("transition_work_order", {
    p_work_order_id: id,
    p_action: "cancel",
    p_payload: { reason },
  });
  if (error) return transportFailure("cancel");
  return rpcResponse(data as RpcResult<WorkOrderRecord> | null);
}

export async function DELETE(request: NextRequest, context: RouteContext) {
  try {
    return await cancelWorkOrder(request, context);
  } catch {
    return transportFailure("cancel");
  }
}
