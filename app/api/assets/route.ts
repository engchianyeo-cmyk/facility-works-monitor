import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { assetRpcResponse, assetTransportFailure } from "@/lib/assets/api";
import { canCreateAsset, type AssetRpcResult } from "@/lib/assets/types";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";

export async function GET(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const params = request.nextUrl.searchParams;
  const supabase = await createClient();
  let query = supabase.from("assets").select("id,asset_tag,name,asset_type,criticality,lifecycle_status,site,location,system:asset_systems(name,system_code)");
  const search = params.get("search")?.replaceAll(/[,%()]/g, " ").trim();
  if (search) query = query.or(`asset_tag.ilike.%${search}%,name.ilike.%${search}%,asset_type.ilike.%${search}%,location.ilike.%${search}%,site.ilike.%${search}%`);
  for (const [parameter, column] of [["system", "system_id"], ["criticality", "criticality"], ["status", "lifecycle_status"], ["site", "site"], ["type", "asset_type"]] as const) {
    const value = params.get(parameter)?.trim();
    if (value) query = query.eq(column, value);
  }
  const { data, error } = await query.order("asset_tag").limit(200);
  if (error) return assetTransportFailure("load");
  return NextResponse.json({ ok: true, data: data ?? [] });
}

export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  if (!canCreateAsset(identity.role)) return errorResponse("ACCESS_DENIED", "Supervisor or Administrator authority is required.", 403);
  let body: Record<string, unknown>;
  try { body = await request.json() as Record<string, unknown>; }
  catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  try {
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("create_asset", { p_payload: body });
    if (error) return assetTransportFailure("create");
    return assetRpcResponse(data as AssetRpcResult | null, 201);
  } catch { return assetTransportFailure("create"); }
}
