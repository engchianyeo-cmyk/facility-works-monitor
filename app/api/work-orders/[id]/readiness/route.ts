import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(_: Request, { params }: RouteContext) {
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    const { id } = await params;
    const supabase = await createClient();
    const [approval, verification] = await Promise.all([
      supabase.rpc("work_order_approval_readiness", { p_work_order_id: id }),
      supabase.rpc("work_order_verification_readiness", { p_work_order_id: id }),
    ]);
    if (approval.error || verification.error) return transportFailure("load readiness for");
    return rpcResponse({ ok: true, data: { approval: approval.data, verification: verification.data } } as RpcResult);
  } catch {
    return transportFailure("load readiness for");
  }
}
