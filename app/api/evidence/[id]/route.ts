import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

const fail = (code: string, message: string, status = 400) => NextResponse.json({ ok: false, code, message }, { status });

type RouteContext = { params: Promise<{ id: string }> };

export async function DELETE(request: NextRequest, { params }: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return fail("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);

  let body: Record<string, unknown> = {};
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return fail("VALIDATION_ERROR", "A deletion reason is required.");
  }

  const reason = String(body.reason ?? "").trim();
  if (!reason) return fail("DELETION_REASON_REQUIRED", "State why this evidence is being removed.");
  if (reason.length > 500) return fail("VALIDATION_ERROR", "Deletion reason must be 500 characters or fewer.");

  const { id } = await params;
  const supabase = await createClient();
  const { data: item, error: itemError } = await supabase
    .from("evidence_items")
    .select("id,work_order_id,incident_id,uploaded_by,category,original_filename,deleted_at")
    .eq("id", id)
    .maybeSingle();

  if (itemError || !item || item.deleted_at) return fail("NOT_FOUND", "Evidence was not found.", 404);

  if (item.work_order_id) {
    const { data: visibleOrder, error } = await supabase
      .from("work_orders")
      .select("id,status,assigned_technician_id")
      .eq("id", item.work_order_id)
      .maybeSingle();
    if (error || !visibleOrder) return fail("NOT_FOUND", "Work Order was not found.", 404);
  } else if (item.incident_id) {
    const { data: visibleIncident, error } = await supabase
      .from("incidents")
      .select("id,status")
      .eq("id", item.incident_id)
      .maybeSingle();
    if (error || !visibleIncident) return fail("NOT_FOUND", "Incident was not found.", 404);
    return fail("ACCESS_DENIED", "Incident evidence removal is not available through this Work Order control.", 403);
  }
  const { data, error } = await supabase.rpc("void_work_order_evidence", { p_evidence_id: item.id, p_reason: reason });
  if (error) return fail("EVIDENCE_DELETE_FAILED", "Evidence could not be removed.", 503);
  if (!data?.ok) return fail(String(data?.code ?? "EVIDENCE_DELETE_FAILED"), String(data?.message ?? "Evidence could not be removed."), data?.code === "AFTER_EVIDENCE_REQUIRED" ? 409 : 403);

  return NextResponse.json({
    ok: true,
    message: "Evidence removed from the active record. The audit history is retained.",
  });
}
