import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

type Context = { params: Promise<{ id: string }> };

/** D-11: a second Technician of the facility endorses the Work Order as authentic (endorse_work_order). */
export async function POST(request: NextRequest, { params }: Context) {
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    const body = await request.json().catch(() => null) as { statement?: unknown; checklist?: unknown } | null;
    const statement = typeof body?.statement === "string" ? body.statement.trim() : "";
    if (statement.length < 10 || statement.length > 1000) return errorResponse("VALIDATION_ERROR", "State what you checked (10 to 1,000 characters).");
    const { id } = await params;
    const supabase = await createClient();
    const checklist = body?.checklist && typeof body.checklist === "object" && !Array.isArray(body.checklist) ? body.checklist : {};
    const { data, error } = await supabase.rpc("endorse_work_order", { p_work_order_id: id, p_statement: statement, p_checklist: checklist });
    if (error) return transportFailure("endorse");
    return rpcResponse(data as RpcResult<unknown> | null);
  } catch {
    return transportFailure("endorse");
  }
}
