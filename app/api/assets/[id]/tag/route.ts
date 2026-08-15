import { getCurrentIdentity } from "@/lib/auth";
import { assetRpcResponse, assetTransportFailure } from "@/lib/assets/api";
import { canCorrectAssetTag, type AssetRpcResult } from "@/lib/assets/types";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";

type Context = { params: Promise<{ id: string }> };
export async function POST(request: Request, { params }: Context) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  if (!canCorrectAssetTag(identity.role)) return errorResponse("ACCESS_DENIED", "Administrator authority is required.", 403);
  let body: Record<string, unknown>; try { body = await request.json() as Record<string, unknown>; } catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  try { const { id } = await params; const supabase = await createClient(); const { data, error } = await supabase.rpc("change_asset_tag", { p_asset_id: id, p_asset_tag: body.asset_tag, p_reason: body.reason }); if (error) return assetTransportFailure("correct the tag in"); return assetRpcResponse(data as AssetRpcResult | null); } catch { return assetTransportFailure("correct the tag in"); }
}
