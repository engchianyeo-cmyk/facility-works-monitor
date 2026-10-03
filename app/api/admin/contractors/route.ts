import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

export async function POST(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication required.", 401);
  if (!["supervisor", "facility_manager", "administrator"].includes(identity.role)) return errorResponse("ACCESS_DENIED", "Contractor administration authority is required.", 403);
  const body = await request.json().catch(() => null);
  if (!body || !["vendor", "rate"].includes(body.kind)) return errorResponse("VALIDATION_ERROR", "Unsupported contractor administration action.", 400);
  const supabase = await createClient();
  const result = await supabase.rpc("create_contractor_master", { p_payload: body });
  if (result.error) return NextResponse.json({ ok: false, message: "Contractor details could not be saved." }, { status: 503 });
  return rpcResponse(result.data as RpcResult);
}
