import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";
import { isAssignmentType } from "@/lib/work-orders/validation";
import { notifyAssignment } from "@/lib/notifications/provider";

type RouteContext = { params: Promise<{ id: string }> };
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function POST(request: NextRequest, { params }: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  let body: Record<string, unknown>;
  try { body = (await request.json()) as Record<string, unknown>; }
  catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  const assignmentType = String(body.assignment_type ?? "").toLowerCase();
  const assigneeId = String(body.assignee_id ?? "");
  if (!isAssignmentType(assignmentType) || !UUID_PATTERN.test(assigneeId)) {
    return errorResponse("INVALID_ASSIGNMENT", "Select a valid active assignee.");
  }
  const { id } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("assign_work_order", {
    p_work_order_id: id,
    p_assignment_type: assignmentType,
    p_assignee_id: assigneeId,
  });
  if (error) return transportFailure("assign");
  const result = data as RpcResult<WorkOrderRecord> | null;
  if (result?.ok === true && assignmentType === "technician") {
    const assignmentPath = `/work-orders/${id}`;
    const notification = await notifyAssignment({
      workOrderId: id,
      assigneeId,
      assignmentPath,
    });
    return NextResponse.json({
      ...result,
      data: result.work_order ?? result.data,
      assignment_path: assignmentPath,
      notification,
    });
  }
  return rpcResponse(result);
}
