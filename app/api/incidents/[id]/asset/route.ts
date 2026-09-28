import { getCurrentIdentity } from "@/lib/auth";
import { assetRpcResponse, assetTransportFailure } from "@/lib/assets/api";
import { canLinkIncidentAsset, type AssetRpcResult } from "@/lib/assets/types";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";
type Context = { params: Promise<{ id: string }> };
export async function POST(request: Request, { params }: Context) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  if (!canLinkIncidentAsset(identity.role)) return errorResponse("ACCESS_DENIED", "Incident Asset-link management is not permitted.", 403);
  let body: Record<string, unknown>; try { body = await request.json() as Record<string, unknown>; } catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  try { const { id } = await params; const supabase = await createClient(); const { data, error } = await supabase.rpc("set_incident_asset", { p_incident_id: id, p_asset_id: body.asset_id || null, p_reason: body.reason ?? null }); if (error) return assetTransportFailure("update"); return assetRpcResponse(data as AssetRpcResult | null); } catch { return assetTransportFailure("update"); }
}
