import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import { isUuidLike } from "@/lib/work-orders/decision-header";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";
import { scheduleEmailDispatch } from "@/lib/notifications/schedule-email";

type Context = { params: Promise<{ id: string }> };

/** D-49 (10 Nov 2026): name or change Technician 2, the independent checker (set_work_order_second_technician). */
export async function POST(request: NextRequest, { params }: Context) {
  scheduleEmailDispatch(); // D-42: send any emails this action queued, after the response
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    const body = await request.json().catch(() => null) as { technician_id?: unknown } | null;
    if (!isUuidLike(body?.technician_id)) return errorResponse("VALIDATION_ERROR", "Choose Technician 2.");
    const { id } = await params;
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("set_work_order_second_technician", { p_work_order_id: id, p_technician_id: body.technician_id });
    if (error) return transportFailure("name Technician 2 on");
    return rpcResponse(data as RpcResult<WorkOrderRecord> | null);
  } catch {
    return transportFailure("name Technician 2 on");
  }
}
