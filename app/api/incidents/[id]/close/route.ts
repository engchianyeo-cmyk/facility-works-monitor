import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { incidentRpcResponse, incidentTransportFailure, type IncidentRpcResult } from "@/lib/incidents/api";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  try { const body = await request.json() as Record<string, unknown>; if (body.closure_notes !== undefined && (typeof body.closure_notes !== "string" || !body.closure_notes.trim())) return errorResponse("VALIDATION_ERROR", "Closure notes must be non-empty when provided."); } catch { /* Approved 0014 does not require a body or closure notes. */ }
  try { const { id } = await params; const supabase = await createClient(); const { data, error } = await supabase.rpc("transition_incident", { p_incident_id: id, p_action: "close" }); if (error) return incidentTransportFailure("close"); return incidentRpcResponse(data as IncidentRpcResult | null); }
  catch { return incidentTransportFailure("close"); }
}

