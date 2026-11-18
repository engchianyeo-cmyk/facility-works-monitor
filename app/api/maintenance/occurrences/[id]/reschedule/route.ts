import { getCurrentIdentity } from "@/lib/auth";
import { pmRpcResponse, pmTransportFailure } from "@/lib/maintenance/api";
import type { PmRpcResult } from "@/lib/maintenance/types";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";

/** M35: move a planned date inside its window (Supervisor / Facility Manager), or beyond it (Super-Administrator,
 *  Facility Administrator). The database decides who may and records the reason. */
export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  let body: Record<string, unknown>;
  try { body = await request.json() as Record<string, unknown>; } catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  try {
    const { id } = await params;
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("reschedule_pm_occurrence", { p_occurrence_id: id, p_new_date: body.new_date, p_reason: body.reason });
    if (error) return pmTransportFailure("defer");
    return pmRpcResponse(data as PmRpcResult | null);
  } catch { return pmTransportFailure("defer"); }
}
