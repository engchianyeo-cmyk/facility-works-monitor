import { createHash } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { parseContractorActualCsv } from "@/lib/work-orders/contractor-csv";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

type RouteContext = { params: Promise<{ id: string }> };
type RateRow = { id: string; item_code: string | null };

const MAX_CSV_BYTES = 1024 * 1024;
const VALID_KINDS = new Set(["personnel", "materials", "equipment_services", "mixed"]);

export async function POST(request: NextRequest, { params }: RouteContext) {
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    const form = await request.formData();
    const file = form.get("file");
    const mode = String(form.get("mode") ?? "preview");
    const importKind = String(form.get("import_kind") ?? "mixed");
    if (!(file instanceof File)) return errorResponse("VALIDATION_ERROR", "Choose a contractor CSV file.");
    if (file.size <= 0 || file.size > MAX_CSV_BYTES) return errorResponse("VALIDATION_ERROR", "CSV file must be between 1 byte and 1 MB.");
    if (!file.name.toLowerCase().endsWith(".csv")) return errorResponse("VALIDATION_ERROR", "Use a CSV file.");
    if (mode !== "preview" && mode !== "confirm") return errorResponse("VALIDATION_ERROR", "Import mode must be preview or confirm.");
    if (!VALID_KINDS.has(importKind)) return errorResponse("VALIDATION_ERROR", "Import kind is invalid.");

    const bytes = new Uint8Array(await file.arrayBuffer());
    const parsed = parseContractorActualCsv(new TextDecoder().decode(bytes));
    if (parsed.errors.length) return NextResponse.json({ ok: false, code: "VALIDATION_ERROR", message: "CSV validation failed.", errors: parsed.errors }, { status: 400 });
    if (!parsed.rows.length) return errorResponse("VALIDATION_ERROR", "CSV contains no usable cost rows.");

    const { id } = await params;
    const supabase = await createClient();
    const { data: order, error: orderError } = await supabase.from("work_orders").select("work_order_number").eq("id", id).maybeSingle();
    if (orderError || !order) return errorResponse("NOT_FOUND", "Work Order was not found.", 404);
    const wrongOrder = parsed.rows.find((row) => row.workOrderNumber !== order.work_order_number);
    if (wrongOrder) return errorResponse("VALIDATION_ERROR", `CSV contains Work Order ${wrongOrder.workOrderNumber}; expected ${order.work_order_number}.`);

    const { data: rateResult, error: rateError } = await supabase.rpc("work_order_contractor_rate_items", { p_work_order_id: id });
    if (rateError) return transportFailure("load contractor rates for");
    if (!rateResult?.ok) return rpcResponse(rateResult as RpcResult<unknown> | null);
    const rateRows = (rateResult.rates ?? []) as RateRow[];
    const byCode = new Map<string, RateRow>();
    rateRows.forEach((rate) => {
      if (!rate.item_code) return;
      byCode.set(rate.item_code.toUpperCase(), rate);
      if (rate.item_code.toUpperCase().startsWith("UAT-")) byCode.set(rate.item_code.slice(4).toUpperCase(), rate);
    });

    const unresolved = [...new Set(parsed.rows.map((row) => row.rateCode).filter((code) => !byCode.has(code.toUpperCase())))];
    if (unresolved.length) return NextResponse.json({ ok: false, code: "VALIDATION_ERROR", message: "CSV contains rate codes not found in the assigned contractor's effective rate schedule.", rate_codes: unresolved }, { status: 400 });

    const lines = parsed.rows.map((row) => ({
      rate_item_id: byCode.get(row.rateCode.toUpperCase())!.id,
      quantity: row.quantity,
      actual_unit_rate: row.actualUnitRate,
      worker_name: row.workerName,
      worker_id: row.workerId,
      work_date: row.workDate,
      exception_reason: row.exceptionReason,
      remarks: row.remarks,
    }));

    if (mode === "preview") {
      const { data, error } = await supabase.rpc("preview_contractor_actual_import", { p_work_order_id: id, p_lines: lines });
      if (error) return transportFailure("preview contractor actuals for");
      return rpcResponse(data as RpcResult<unknown> | null);
    }

    const sourceHash = createHash("sha256").update(bytes).digest("hex");
    const { data, error } = await supabase.rpc("confirm_contractor_actual_import", {
      p_work_order_id: id,
      p_import_kind: importKind,
      p_source_filename: file.name,
      p_source_sha256: sourceHash,
      p_lines: lines,
    });
    if (error) return transportFailure("confirm contractor actuals for");
    return rpcResponse(data as RpcResult<unknown> | null, 201);
  } catch {
    return transportFailure("import contractor actuals for");
  }
}
