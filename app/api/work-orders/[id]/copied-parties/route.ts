import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import { isUuidLike } from "@/lib/work-orders/decision-header";
import type { RpcResult } from "@/lib/work-orders/types";

type Context = { params: Promise<{ id: string }> };

/** Replace the Work Order's copied parties (set_work_order_copied_parties). */
export async function POST(request: NextRequest, { params }: Context) {
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    const body = await request.json().catch(() => null) as { profile_ids?: unknown } | null;
    const ids = body?.profile_ids;
    if (!Array.isArray(ids) || ids.length > 50 || !ids.every(isUuidLike)) return errorResponse("VALIDATION_ERROR", "Choose up to 50 people.");
    const { id } = await params;
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("set_work_order_copied_parties", { p_work_order_id: id, p_profile_ids: [...new Set(ids)] });
    if (error) return transportFailure("update copied parties on");
    return rpcResponse(data as RpcResult<unknown> | null);
  } catch {
    return transportFailure("update copied parties on");
  }
}
