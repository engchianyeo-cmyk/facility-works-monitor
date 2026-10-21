import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

const ROLES = ["approver", "supervisor", "facility_manager"] as const;
const amountOk = (value: unknown) => typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 999999999999.99 && Math.abs(value * 100 - Math.round(value * 100)) < 0.001;

/** Administrator-only, versioned approval limits (change_work_order_approval_limits). */
export async function POST(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication required.", 401);
  if (identity.role !== "administrator") return errorResponse("ACCESS_DENIED", "Only the Administrator may change approval limits.", 403);
  const body = await request.json().catch(() => null) as { limits?: Record<string, unknown>; reason?: unknown; expected_version?: unknown } | null;
  if (!body?.limits || !ROLES.every((role) => amountOk(body.limits?.[role])) || typeof body.reason !== "string" || !body.reason.trim() || body.reason.length > 1000 || typeof body.expected_version !== "string") {
    return errorResponse("VALIDATION_ERROR", "Enter a non-negative SGD limit for each role, a reason, and the current version.", 400);
  }
  const supabase = await createClient();
  const limits = Object.fromEntries(ROLES.map((role) => [role, body.limits![role]]));
  const result = await supabase.rpc("change_work_order_approval_limits", { p_limits: limits, p_reason: body.reason.trim(), p_expected_version: body.expected_version });
  if (result.error) return NextResponse.json({ ok: false, message: "Approval limits could not be saved." }, { status: 503 });
  return rpcResponse(result.data as RpcResult);
}
