import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";
import { isWorkOrderAction } from "@/lib/work-orders/validation";

type RouteContext = { params: Promise<{ id: string }> };

async function transitionWorkOrder(request: NextRequest, { params }: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  let body: Record<string, unknown>;
  try { body = (await request.json()) as Record<string, unknown>; }
  catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  const action = String(body.action ?? "").toLowerCase();
  if (!isWorkOrderAction(action)) return errorResponse("VALIDATION_ERROR", "Workflow action is invalid.");
  const { id } = await params;
  const payload = { ...body };
  delete payload.action;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("transition_work_order", {
    p_work_order_id: id,
    p_action: action,
    p_payload: payload,
  });
  if (error) return transportFailure("transition");
  return rpcResponse(data as RpcResult<WorkOrderRecord> | null);
}

export async function POST(request: NextRequest, context: RouteContext) {
  try {
    return await transitionWorkOrder(request, context);
  } catch {
    return transportFailure("transition");
  }
}
