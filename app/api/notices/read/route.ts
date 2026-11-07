import { NextRequest } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult } from "@/lib/work-orders/types";

// D-38 (7 Nov 2026): mark your own notices read (all of them when no ids are given).
export async function POST(request: NextRequest) {
  try {
    if (!await getCurrentIdentity()) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
    const body = await request.json().catch(() => ({})) as { ids?: unknown };
    const ids = Array.isArray(body.ids) ? body.ids.filter((id): id is string => typeof id === "string") : null;
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("mark_my_notices_read", { p_notice_ids: ids });
    if (error) return transportFailure("mark notices read for");
    return rpcResponse(data as RpcResult<unknown> | null);
  } catch {
    return transportFailure("mark notices read for");
  }
}
