import { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import { isUuidLike } from "@/lib/work-orders/decision-header";
import { requireAdministrator, text, unavailable } from "@/lib/administration/facility-admin";
import type { RpcResult } from "@/lib/work-orders/types";

/** D-17: add an area to one facility. */
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const denied = await requireAdministrator(); if (denied) return denied;
  const { id } = await params;
  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  const code = text(body?.area_code, 20); const name = text(body?.name, 120);
  const level = typeof body?.level === "string" ? body.level.trim().slice(0, 40) : "";
  if (!isUuidLike(id) || !code || !name) return errorResponse("VALIDATION_ERROR", "Enter the area code and area name.", 400);
  const supabase = await createClient();
  const result = await supabase.rpc("admin_add_facility_area", { p_facility_id: id, p_area_code: code, p_name: name, p_level: level });
  if (result.error) return unavailable("The area");
  return rpcResponse(result.data as RpcResult, 201);
}
