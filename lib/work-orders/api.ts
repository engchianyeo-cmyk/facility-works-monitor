import { NextResponse } from "next/server";
import type { RpcResult } from "@/lib/work-orders/types";

const HTTP_BY_CODE: Record<string, number> = {
  AUTHENTICATION_REQUIRED: 401,
  ACCESS_DENIED: 403,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  DUPLICATE_WORK_ORDER: 409,
  INVALID_TRANSITION: 409,
  TERMINAL_IMMUTABLE: 409,
  SELF_APPROVAL_DENIED: 409,
  APPROVAL_NOT_READY: 409,
  ACTUAL_COSTING_CONFIRMATION_REQUIRED: 409,
  CONTRACTOR_REQUIRED: 409,
  INVOICE_REQUIRED: 409,
  BEFORE_EVIDENCE_REQUIRED: 409,
  CORRECTION_ALREADY_OPEN: 409,
  CORRECTION_REQUIRED: 409,
  QUOTATION_APPROVAL_REQUIRED: 409,
  QUOTATION_DOCUMENT_REQUIRED: 409,
  REVISION_ALREADY_ACTIVE: 409,
  APPROVED_DOCUMENT_IMMUTABLE: 409,
  APPROVAL_AUTHORITY_EXCEEDED: 403,
  BOARD_APPROVAL_REQUIRED: 409,
  COST_BASIS_LOCKED: 409,
  ASSIGNMENT_CONFLICT: 409,
  INVALID_ASSIGNMENT: 400,
  INACTIVE_REFERENCE: 409,
  VALIDATION_ERROR: 400,
  OVERRIDE_REASON_REQUIRED: 400,
  COMPLETION_DETAILS_REQUIRED: 400,
  AFTER_EVIDENCE_REQUIRED: 400,
  CUMULATIVE_LABOUR_REQUIRED: 400,
  REWORK_REASON_REQUIRED: 400,
  CANCELLATION_REASON_REQUIRED: 400,
  INTERNAL_ERROR: 500,
};

export function errorResponse(
  code: string,
  message: string,
  status = HTTP_BY_CODE[code] ?? 400,
) {
  return NextResponse.json({ ok: false, code, message, error: message }, { status });
}

export function rpcResponse<T>(
  result: RpcResult<T> | null,
  successStatus = 200,
) {
  if (!result || result.ok !== true) {
    const code = String(result?.code ?? "INTERNAL_ERROR").toUpperCase();
    const message = String(result?.message ?? "The work-order operation failed.");
    return errorResponse(code, message);
  }
  return NextResponse.json(
    { ...result, data: result.work_order ?? result.data },
    { status: successStatus },
  );
}

export function transportFailure(operation: string) {
  return errorResponse(
    "INTERNAL_ERROR",
    `Unable to ${operation} the work order.`,
    500,
  );
}
