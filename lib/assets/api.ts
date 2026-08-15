import { NextResponse } from "next/server";
import type { AssetRpcResult } from "@/lib/assets/types";
import { errorResponse } from "@/lib/work-orders/api";

const STATUS: Record<string, number> = {
  ACCESS_DENIED: 403,
  NOT_FOUND: 404,
  DUPLICATE_ASSET_TAG: 409,
  DUPLICATE_SYSTEM_CODE: 409,
  TERMINAL_IMMUTABLE: 409,
  INVALID_REFERENCE: 400,
  REASON_REQUIRED: 400,
  VALIDATION_ERROR: 400,
  INTERNAL_ERROR: 500,
};

export function assetRpcResponse(result: AssetRpcResult | null, status = 200) {
  if (!result?.ok) {
    const code = String(result?.code ?? "INTERNAL_ERROR");
    return errorResponse(code, String(result?.message ?? "The Asset operation failed."), STATUS[code] ?? 400);
  }
  return NextResponse.json({ ok: true, code: result.code, data: result.asset ?? result.asset_system ?? result.work_order ?? result.incident }, { status });
}

export function assetTransportFailure(action: string) {
  return errorResponse("INTERNAL_ERROR", `Unable to ${action} the Asset Registry.`, 500);
}
