import { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import { isUuidLike } from "@/lib/work-orders/decision-header";
import { requireAdministrator, text, unavailable } from "@/lib/administration/facility-admin";
import type { RpcResult } from "@/lib/work-orders/types";

/** D-17: add a new facility (with the standard area list) or change an existing facility's details. */
export async function POST(request: NextRequest) {
  const denied = await requireAdministrator(); if (denied) return denied;
  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  const id = body?.facility_id ?? null;
  const code = text(body?.code, 20); const name = text(body?.name, 120); const reason = text(body?.reason);
  const address = typeof body?.address === "string" ? body.address.trim().slice(0, 500) : "";
  if (!body || (id !== null && !isUuidLike(id)) || !code || !name || !reason || (id !== null && typeof body.active !== "boolean")) {
    return errorResponse("VALIDATION_ERROR", "Enter the facility code, name and a reason.", 400);
  }
  const supabase = await createClient();
  const result = await supabase.rpc("admin_save_facility", {
    p_facility_id: id, p_code: code, p_name: name, p_address: address, p_active: id === null ? true : body.active,
    p_seed_standard_areas: id === null ? body.seed_standard_areas !== false : false, p_reason: reason,
  });
  if (result.error) return unavailable("The facility");
  return rpcResponse(result.data as RpcResult, id === null ? 201 : 200);
}
