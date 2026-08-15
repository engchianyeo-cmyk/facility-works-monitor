import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { incidentRpcResponse, incidentTransportFailure, type IncidentRpcResult } from "@/lib/incidents/api";
import { INCIDENT_PHASE_ACTIONS, isIncidentPhase } from "@/lib/incidents/validation";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  let body: Record<string, unknown>; try { body = await request.json() as Record<string, unknown>; } catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  const phase = String(body.phase ?? "").toLowerCase(); if (!isIncidentPhase(phase)) return errorResponse("VALIDATION_ERROR", "Emergency phase is invalid.");
  try { const { id } = await params; const supabase = await createClient(); const { data, error } = await supabase.rpc("transition_incident", { p_incident_id: id, p_action: INCIDENT_PHASE_ACTIONS[phase] }); if (error) return incidentTransportFailure("update"); return incidentRpcResponse(data as IncidentRpcResult | null); }
  catch { return incidentTransportFailure("update"); }
}

