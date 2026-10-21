import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import { isUuidLike } from "@/lib/work-orders/decision-header";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";

type Context = { params: Promise<{ id: string }> };

/** Assign the field-witness Technician while Draft or Awaiting Approval (set_work_order_technician). */
export async function POST(request: NextRequest, { params }: Context) {
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    const body = await request.json().catch(() => null) as { technician_id?: unknown } | null;
    if (!isUuidLike(body?.technician_id)) return errorResponse("VALIDATION_ERROR", "Choose a Technician.");
    const { id } = await params;
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("set_work_order_technician", { p_work_order_id: id, p_technician_id: body.technician_id });
    if (error) return transportFailure("assign a Technician to");
    return rpcResponse(data as RpcResult<WorkOrderRecord> | null);
  } catch {
    return transportFailure("assign a Technician to");
  }
}
