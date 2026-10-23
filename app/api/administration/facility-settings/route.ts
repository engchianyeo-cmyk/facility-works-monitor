import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import { isUuidLike } from "@/lib/work-orders/decision-header";
import { ENDORSEMENT_STAGES } from "@/lib/facility-settings";
import type { RpcResult } from "@/lib/work-orders/types";

/** D-11: Administrator-only facility settings — designated Approver and second-Technician endorsement stage. */
export async function POST(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication required.", 401);
  if (identity.role !== "administrator") return errorResponse("ACCESS_DENIED", "Only the Administrator may change facility settings.", 403);
  const body = await request.json().catch(() => null) as { facility_id?: unknown; designated_approver_id?: unknown; endorsement_stage?: unknown; reason?: unknown } | null;
  const approver = body?.designated_approver_id ?? null;
  if (!body || !isUuidLike(body.facility_id) || (approver !== null && !isUuidLike(approver))
    || !ENDORSEMENT_STAGES.some((stage) => stage.value === body.endorsement_stage)
    || typeof body.reason !== "string" || !body.reason.trim() || body.reason.length > 1000) {
    return errorResponse("VALIDATION_ERROR", "Choose the facility, when the second Technician endorses, and give a reason.", 400);
  }
  const supabase = await createClient();
  const result = await supabase.rpc("set_facility_settings", {
    p_facility_id: body.facility_id, p_designated_approver_id: approver, p_endorsement_stage: body.endorsement_stage, p_reason: body.reason.trim(),
  });
  if (result.error) return NextResponse.json({ ok: false, message: "Facility settings could not be saved." }, { status: 503 });
  return rpcResponse(result.data as RpcResult);
}
