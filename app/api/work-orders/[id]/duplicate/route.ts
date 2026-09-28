import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";

type RouteContext = { params: Promise<{ id: string }> };

export async function POST(_request: NextRequest, { params }: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("duplicate_work_order", { p_work_order_id: id });
  if (error) return transportFailure("duplicate");
  return rpcResponse(data as RpcResult<WorkOrderRecord> | null, 201);
}
