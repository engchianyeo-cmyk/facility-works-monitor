import { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import { isUuidLike } from "@/lib/work-orders/decision-header";
import { requireAdministrator, text, unavailable } from "@/lib/administration/facility-admin";
import type { RpcResult } from "@/lib/work-orders/types";

/** D-17: withdraw a facility drawing. The record and file are kept for the audit trail. */
export async function DELETE(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const denied = await requireAdministrator(); if (denied) return denied;
  const { id } = await params;
  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  const reason = text(body?.reason);
  if (!isUuidLike(id) || !reason) return errorResponse("VALIDATION_ERROR", "Give a reason for removing the drawing.", 400);
  const supabase = await createClient();
  const result = await supabase.rpc("admin_remove_facility_drawing", { p_drawing_id: id, p_reason: reason });
  if (result.error) return unavailable("The drawing removal");
  return rpcResponse(result.data as RpcResult);
}
