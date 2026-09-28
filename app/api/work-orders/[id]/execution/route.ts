import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";

type RouteContext = { params: Promise<{ id: string }> };

export async function POST(request: NextRequest, { params }: RouteContext) {
  try {
    if (!await getCurrentIdentity()) {
      return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    }
    let payload: Record<string, unknown>;
    try {
      payload = await request.json() as Record<string, unknown>;
    } catch {
      return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON.");
    }
    const { id } = await params;
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("record_work_order_execution", {
      p_work_order_id: id,
      p_payload: payload,
    });
    if (error) return transportFailure("record work for");
    return rpcResponse(data as RpcResult<WorkOrderRecord> | null);
  } catch {
    return transportFailure("record work for");
  }
}
