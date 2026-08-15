import { getCurrentIdentity } from "@/lib/auth";
import { assetRpcResponse, assetTransportFailure } from "@/lib/assets/api";
import { canConfigureAssetSystems, type AssetRpcResult } from "@/lib/assets/types";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";
type Context = { params: Promise<{ id: string }> };
export async function PATCH(request: Request, { params }: Context) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  if (!canConfigureAssetSystems(identity.role)) return errorResponse("ACCESS_DENIED", "Administrator authority is required.", 403);
  let body: Record<string, unknown>; try { body = await request.json() as Record<string, unknown>; } catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  try { const { id } = await params; const supabase = await createClient(); const { data, error } = await supabase.rpc("update_asset_system", { p_system_id: id, p_payload: body.details ?? body, p_reason: body.reason ?? null }); if (error) return assetTransportFailure("update"); return assetRpcResponse(data as AssetRpcResult | null); } catch { return assetTransportFailure("update"); }
}
