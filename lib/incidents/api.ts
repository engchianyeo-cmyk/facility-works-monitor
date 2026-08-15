import { NextResponse } from "next/server";
import type { IncidentRecord } from "@/lib/incidents/types";
import type { RpcResult } from "@/lib/work-orders/types";
import { errorResponse } from "@/lib/work-orders/api";

const HTTP_BY_CODE: Record<string, number> = {
  AUTHENTICATION_REQUIRED: 401,
  ACCESS_DENIED: 403,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  INVALID_TRANSITION: 409,
  INVALID_ASSIGNMENT: 400,
  VALIDATION_ERROR: 400,
  INTERNAL_ERROR: 500,
};

export type IncidentRpcResult = RpcResult<IncidentRecord> & {
  incident?: IncidentRecord;
  assignment_state?: "ASSIGNED" | "UNASSIGNED_EMERGENCY";
};

export function incidentRpcResponse(result: IncidentRpcResult | null, successStatus = 200) {
  if (!result?.ok) {
    const code = String(result?.code ?? "INTERNAL_ERROR").toUpperCase();
    return errorResponse(code, String(result?.message ?? "The incident operation failed."), HTTP_BY_CODE[code]);
  }
  return NextResponse.json({ ...result, data: result.incident ?? result.data }, { status: successStatus });
}

export function incidentTransportFailure(operation: string) {
  return errorResponse("INTERNAL_ERROR", `Unable to ${operation} the emergency incident.`, 500);
}

