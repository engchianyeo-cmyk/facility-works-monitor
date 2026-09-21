import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

type Context = { params: Promise<{ id: string }> };

export async function GET(_: NextRequest, { params }: Context) {
  if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase.from("work_order_document_corrections").select("id,status,reason,original_status,opened_at,opened_by,closed_at,closed_by,closure_note").eq("work_order_id", id).order("opened_at", { ascending: false });
  if (error) return transportFailure("load supporting-document corrections for");
  return NextResponse.json({ ok: true, data: data ?? [] });
}

export async function POST(request: NextRequest, { params }: Context) {
  if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const body = await request.json().catch(() => null) as { operation?: string; reason?: string; note?: string } | null;
  if (!body?.operation) return errorResponse("VALIDATION_ERROR", "Correction operation is required.");
  const { id } = await params;
  const supabase = await createClient();
  const result = body.operation === "withdraw_completion"
    ? await supabase.rpc("withdraw_physical_completion", { p_work_order_id: id, p_reason: body.reason ?? "" })
    : body.operation === "open"
    ? await supabase.rpc("open_work_order_document_correction", { p_work_order_id: id, p_reason: body.reason ?? "" })
    : body.operation === "close"
      ? await supabase.rpc("close_work_order_document_correction", { p_work_order_id: id, p_note: body.note ?? "" })
      : null;
  if (!result) return errorResponse("VALIDATION_ERROR", "Unsupported correction operation.");
  if (result.error) return transportFailure("update supporting-document correction for");
  return rpcResponse(result.data as RpcResult);
}
