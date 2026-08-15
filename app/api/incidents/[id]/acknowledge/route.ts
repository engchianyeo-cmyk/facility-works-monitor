import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { incidentRpcResponse, incidentTransportFailure, type IncidentRpcResult } from "@/lib/incidents/api";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";

export async function POST(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  try { const { id } = await params; const supabase = await createClient(); const { data, error } = await supabase.rpc("transition_incident", { p_incident_id: id, p_action: "acknowledge" }); if (error) return incidentTransportFailure("acknowledge"); return incidentRpcResponse(data as IncidentRpcResult | null); }
  catch { return incidentTransportFailure("acknowledge"); }
}

