import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";
import { scheduleEmailDispatch } from "@/lib/notifications/schedule-email";

// D-36 (6 Nov 2026): record emergency work that has already been carried out, in one step.
export async function POST(request: NextRequest) {
  scheduleEmailDispatch(); // D-42: send any emails this action queued, after the response
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    let payload: unknown;
    try {
      payload = await request.json();
    } catch {
      return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON.");
    }
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) return errorResponse("VALIDATION_ERROR", "Request body must be a JSON object.");
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("record_emergency_work_done", { p_payload: payload });
    if (error) return transportFailure("record emergency work for");
    return rpcResponse(data as RpcResult<WorkOrderRecord> | null, 201);
  } catch {
    return transportFailure("record emergency work for");
  }
}
