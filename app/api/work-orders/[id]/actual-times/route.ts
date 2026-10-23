import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

type Context = { params: Promise<{ id: string }> };

const isTimestamp = (value: unknown): value is string => typeof value === "string" && value.length <= 40 && !Number.isNaN(Date.parse(value));

/** D-11: the assigned Technician enters or corrects the actual start and end of the work (set_work_order_actual_times). */
export async function POST(request: NextRequest, { params }: Context) {
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    const body = await request.json().catch(() => null) as { started_at?: unknown; ended_at?: unknown } | null;
    const ended = body?.ended_at ?? null;
    if (!isTimestamp(body?.started_at) || (ended !== null && !isTimestamp(ended))) return errorResponse("VALIDATION_ERROR", "Enter the start time, and the end time when the work is finished.");
    const { id } = await params;
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("set_work_order_actual_times", {
      p_work_order_id: id, p_started_at: new Date(body!.started_at as string).toISOString(), p_ended_at: ended === null ? null : new Date(ended as string).toISOString(),
    });
    if (error) return transportFailure("record the work times on");
    return rpcResponse(data as RpcResult<unknown> | null);
  } catch {
    return transportFailure("record the work times on");
  }
}
