import { getCurrentIdentity } from "@/lib/auth";
import { pmRpcResponse, pmTransportFailure } from "@/lib/maintenance/api";
import { approvedPmPayload, canManagePm, type PmRpcResult } from "@/lib/maintenance/types";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";

export async function POST(request: Request) {
  const identity = await getCurrentIdentity(); if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401); if (!canManagePm(identity.role)) return errorResponse("ACCESS_DENIED", "Supervisor or Administrator authority is required.", 403);
  let body: Record<string, unknown>; try { body = await request.json() as Record<string, unknown>; } catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  try { const supabase = await createClient(); const { data, error } = await supabase.rpc("create_pm_requirement", { p_payload: approvedPmPayload(body) }); if (error) return pmTransportFailure("create"); return pmRpcResponse(data as PmRpcResult | null, 201); } catch { return pmTransportFailure("create"); }
}
