import { NextResponse } from "next/server";
import { errorResponse } from "@/lib/work-orders/api";
import type { PmRpcResult } from "./types";

const STATUS: Record<string, number> = { ACCESS_DENIED: 403, NOT_FOUND: 404, INVALID_ASSET: 409, OCCURRENCE_CANCELLED: 409, WORK_ALREADY_STARTED: 409, WORK_ORDER_CANCELLATION_REQUIRED: 409, REASON_REQUIRED: 400, INVALID_HORIZON: 400, INVALID_REFERENCE: 400, VALIDATION_ERROR: 400, INTERNAL_ERROR: 500, WORK_ORDER_GENERATION_FAILED: 500 };
export function pmRpcResponse(result: PmRpcResult | null, status = 200) {
  if (!result?.ok) { const code = String(result?.code ?? "INTERNAL_ERROR"); return errorResponse(code, String(result?.message ?? "The preventive-maintenance operation failed."), STATUS[code] ?? 400); }
  return NextResponse.json({ ...result, data: result.requirement ?? result.occurrence ?? result.work_order ?? result }, { status });
}
export function pmTransportFailure(action: string) { return errorResponse("INTERNAL_ERROR", `Unable to ${action} preventive maintenance.`, 500); }
