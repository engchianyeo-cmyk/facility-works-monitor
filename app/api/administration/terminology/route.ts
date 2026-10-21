import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

/** Administrator renames a role or Work Order stage; a blank label restores the default (set_terminology_label). */
export async function POST(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication required.", 401);
  if (identity.role !== "administrator") return errorResponse("ACCESS_DENIED", "Only the Administrator may rename roles and stages.", 403);
  const body = await request.json().catch(() => null) as { code?: unknown; label?: unknown } | null;
  if (typeof body?.code !== "string" || !/^(role|status):[a-z_]+$/.test(body.code) || typeof body.label !== "string" || body.label.length > 60) {
    return errorResponse("VALIDATION_ERROR", "Choose a role or stage and enter a label of up to 60 characters.", 400);
  }
  const supabase = await createClient();
  const result = await supabase.rpc("set_terminology_label", { p_code: body.code, p_label: body.label });
  if (result.error) return NextResponse.json({ ok: false, message: "The label could not be saved." }, { status: 503 });
  return rpcResponse(result.data as RpcResult);
}
