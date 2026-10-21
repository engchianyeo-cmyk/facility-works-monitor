import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";

type Context = { params: Promise<{ id: string }> };

/** D-07: declare (or undo) in-house services while Draft. PostgreSQL checks the preparer rule (set_work_order_in_house). */
export async function POST(request: NextRequest, { params }: Context) {
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    const body = await request.json().catch(() => null) as { in_house?: unknown } | null;
    if (typeof body?.in_house !== "boolean") return errorResponse("VALIDATION_ERROR", "Choose in-house or contractor.");
    const { id } = await params;
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("set_work_order_in_house", { p_work_order_id: id, p_in_house: body.in_house });
    if (error) return transportFailure("update");
    return rpcResponse(data as RpcResult<WorkOrderRecord> | null);
  } catch {
    return transportFailure("update");
  }
}
