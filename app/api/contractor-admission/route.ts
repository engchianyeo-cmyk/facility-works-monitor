import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

// D-37 (6 Nov 2026): each step of contractor admission goes to its own database function, which checks who may do it.
type Body = Record<string, unknown>;
const text = (value: unknown) => (typeof value === "string" ? value : "");
const idOrNull = (value: unknown) => (typeof value === "string" && value ? value : null);

export async function POST(request: NextRequest) {
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    let body: Body;
    try {
      body = await request.json() as Body;
    } catch {
      return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON.");
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) return errorResponse("VALIDATION_ERROR", "Request body must be a JSON object.");
    const supabase = await createClient();
    const admission = idOrNull(body.admission_id);
    const call = (() => {
      switch (body.action) {
        case "designate": return supabase.rpc("designate_procurement_manager", { p_profile_id: idOrNull(body.profile_id), p_facility_id: idOrNull(body.facility_id), p_active: body.active !== false });
        case "request": return supabase.rpc("raise_contractor_request", { p_work_order_id: idOrNull(body.work_order_id), p_service: text(body.service), p_reason: text(body.reason) });
        case "recommend": return supabase.rpc("recommend_contractor", { p_payload: body.payload ?? {} });
        case "prequalify": return supabase.rpc("prequalify_contractor", { p_admission_id: admission, p_note: text(body.note) });
        case "owner_approval": return supabase.rpc("record_contractor_owner_approval", { p_admission_id: admission, p_note: text(body.note) });
        case "score": return supabase.rpc("score_contractor_trial_job", { p_work_order_id: idOrNull(body.work_order_id), p_scores: body.scores ?? {} });
        case "admit": return supabase.rpc("admit_contractor", { p_admission_id: admission, p_note: text(body.note) });
        case "reject": return supabase.rpc("reject_contractor", { p_admission_id: admission, p_reason: text(body.reason) });
        default: return null;
      }
    })();
    if (!call) return errorResponse("VALIDATION_ERROR", "Unknown contractor admission step.");
    const { data, error } = await call;
    if (error) return transportFailure("update contractor admission for");
    return rpcResponse(data as RpcResult<unknown> | null);
  } catch {
    return transportFailure("update contractor admission for");
  }
}
