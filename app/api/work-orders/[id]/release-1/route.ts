import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

type Context = { params: Promise<{ id: string }> };

function rpcCollection(value: unknown, key: "quotations" | "rates") {
  if (!value || typeof value !== "object") return [];
  const collection = (value as Record<string, unknown>)[key];
  return Array.isArray(collection) ? collection : [];
}

export async function GET(_: NextRequest, { params }: Context) {
  if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  const supabase = await createClient();
  const [markups, costs, procurement, quotationResult, rateResult, financial, order] = await Promise.all([
    supabase.from("work_order_markups").select("id,source_type,source_reference,drawing_revision,page_number,x_percent,y_percent,annotation_type,geometry,note,created_at,created_by").eq("work_order_id", id).is("deleted_at", null).order("created_at"),
    supabase.from("work_order_cost_lines").select("id,cost_phase,cost_type,description,quantity,unit,unit_rate,amount,worker_name,created_at").eq("work_order_id", id).order("created_at"),
    supabase.from("work_order_procurement_commitments").select("id,purchase_reference,description,currency,committed_amount,status,created_at").eq("work_order_id", id).order("created_at", { ascending: false }),
    supabase.rpc("work_order_contractor_quotations", { p_work_order_id: id }),
    supabase.rpc("work_order_contractor_rate_items", { p_work_order_id: id }),
    supabase.from("work_order_financial_controls").select("currency,estimated_cost,quoted_cost,approved_budget,cost_status,recommended_by,recommended_at,recommendation_note,financial_approved_by,financial_approved_at,financial_approval_note,rule:commercial_approval_rules(rule_code,minimum_quotations,maximum_amount)").eq("work_order_id", id).maybeSingle(),
    supabase.from("work_orders").select("assigned_vendor_id,actual_costs_confirmed_at,contractor:vendors(name)").eq("id", id).maybeSingle(),
  ]);
  const failed = [markups, costs, procurement, quotationResult, rateResult, financial, order].find((item) => item.error);
  if (failed?.error) return transportFailure("load Release 1 workspace for");
  return NextResponse.json({
    ok: true,
    data: {
      markups: markups.data ?? [],
      costs: costs.data ?? [],
      procurement: procurement.data ?? [],
      quotations: rpcCollection(quotationResult.data, "quotations"),
      rates: rpcCollection(rateResult.data, "rates"),
      financial: financial.data,
      contractor: order.data?.contractor ?? null,
      actual_costs_confirmed_at: order.data?.actual_costs_confirmed_at ?? null,
    },
  });
}

export async function POST(request: NextRequest, { params }: Context) {
  if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  const body = await request.json().catch(() => null) as { operation?: string; payload?: Record<string, unknown> } | null;
  if (!body?.operation || !body.payload) return errorResponse("VALIDATION_ERROR", "Operation and payload are required.", 400);
  const payload = body.payload;
  const supabase = await createClient();
  const calls: Record<string, () => PromiseLike<{ data: unknown; error: unknown }>> = {
    markup: () => supabase.rpc("record_work_order_markup", { p_work_order_id: id, p_payload: payload }),
    actual_cost: () => supabase.rpc("manage_work_order_actual_cost", { p_work_order_id: id, p_cost_line_id: null, p_payload: payload }),
    confirm_actual_costs: () => supabase.rpc("manage_work_order_actual_cost", { p_work_order_id: id, p_cost_line_id: null, p_payload: { operation: "confirm" } }),
    procurement: () => supabase.rpc("record_work_order_procurement", { p_work_order_id: id, p_payload: payload }),
    delete_markup: () => supabase.rpc("delete_work_order_markup", { p_work_order_id: id, p_markup_id: payload.markup_id }),
    recommend_cost: () => supabase.rpc("recommend_work_order_cost", { p_work_order_id: id, p_note: payload.note ?? null }),
    approve_financial: () => supabase.rpc("approve_work_order_financial", { p_work_order_id: id, p_approved_budget: payload.approved_budget, p_note: payload.note }),
    quotation: () => supabase.rpc("record_contractor_quotation", {
      p_work_order_id: id,
      p_quotation_ref: String(payload.quotation_ref ?? ""),
      p_quotation_date: String(payload.quotation_date ?? ""),
      p_lines: payload.lines,
      p_source_filename: payload.source_filename ?? null,
      p_source_sha256: payload.source_sha256 ?? null,
    }),
  };
  const call = calls[body.operation];
  if (!call) return errorResponse("VALIDATION_ERROR", "Unsupported Release 1 operation.", 400);
  const result = await call();
  if (result.error) return transportFailure("update Release 1 workspace for");
  return rpcResponse(result.data as RpcResult);
}
