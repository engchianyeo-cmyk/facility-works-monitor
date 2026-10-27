import { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import { isUuidLike } from "@/lib/work-orders/decision-header";
import { requireAdministrator, text, unavailable } from "@/lib/administration/facility-admin";
import type { RpcResult } from "@/lib/work-orders/types";

/** D-17: add a staff member to, or remove them from, one facility. */
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const denied = await requireAdministrator(); if (denied) return denied;
  const { id } = await params;
  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  const reason = text(body?.reason);
  if (!isUuidLike(id) || !isUuidLike(body?.profile_id) || typeof body?.active !== "boolean" || !reason) {
    return errorResponse("VALIDATION_ERROR", "Choose the staff member and give a reason.", 400);
  }
  const supabase = await createClient();
  const result = await supabase.rpc("admin_set_facility_membership", { p_facility_id: id, p_profile_id: body.profile_id, p_active: body.active, p_reason: reason });
  if (result.error) return unavailable("The staff change");
  return rpcResponse(result.data as RpcResult);
}
