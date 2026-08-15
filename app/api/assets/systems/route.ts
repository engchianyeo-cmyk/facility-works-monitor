import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { assetRpcResponse, assetTransportFailure } from "@/lib/assets/api";
import { canConfigureAssetSystems, type AssetRpcResult } from "@/lib/assets/types";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";

export async function GET() {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const supabase = await createClient();
  const { data, error } = await supabase.from("asset_systems").select("id,system_code,name,description,site,is_active").order("system_code");
  if (error) return assetTransportFailure("load");
  return NextResponse.json({ ok: true, data: data ?? [] });
}

export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  if (!canConfigureAssetSystems(identity.role)) return errorResponse("ACCESS_DENIED", "Administrator authority is required.", 403);
  let body: Record<string, unknown>; try { body = await request.json() as Record<string, unknown>; } catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  try { const supabase = await createClient(); const { data, error } = await supabase.rpc("create_asset_system", { p_payload: body }); if (error) return assetTransportFailure("create"); return assetRpcResponse(data as AssetRpcResult | null, 201); } catch { return assetTransportFailure("create"); }
}
