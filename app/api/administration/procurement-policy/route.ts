import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

export async function POST(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication required.", 401);
  if (!["facility_manager", "administrator"].includes(identity.role)) {
    return errorResponse("ACCESS_DENIED", "Only Facility Manager and Administrator may change procurement policy.", 403);
  }
  const body = await request.json().catch(() => null);
  if (!body || typeof body.threshold !== "number" || !Number.isFinite(body.threshold) || body.threshold <= 0 || body.threshold > 999999999999.99 || Math.abs(body.threshold * 100 - Math.round(body.threshold * 100)) > 0.001 || typeof body.reason !== "string" || !body.reason.trim() || body.reason.trim().length > 1000 || typeof body.expected_version !== "string" || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.expected_version)) {
    return errorResponse("VALIDATION_ERROR", "Enter a positive SGD threshold, a reason, and the current policy version.", 400);
  }
  const supabase = await createClient();
  const result = await supabase.rpc("change_procurement_policy", { p_threshold: body.threshold, p_reason: body.reason.trim(), p_expected_version: body.expected_version });
  if (result.error) return NextResponse.json({ ok: false, message: "Company policy could not be saved." }, { status: 503 });
  return rpcResponse(result.data as RpcResult);
}
