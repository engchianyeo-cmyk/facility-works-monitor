import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { canMutateWorkOrderEvidence } from "@/lib/evidence";

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
  const admin = createAdminClient();
  const { data: item, error: itemError } = await admin
    .from("evidence_items")
    .select("id,work_order_id,incident_id,uploaded_by,category,original_filename,deleted_at")
    .eq("id", id)
    .maybeSingle();

  if (itemError || !item || item.deleted_at) return fail("NOT_FOUND", "Evidence was not found.", 404);

  let parentStatus: string | null = null;
  if (item.work_order_id) {
    const supabase = await createClient();
    const { data: visibleOrder, error } = await supabase
      .from("work_orders")
      .select("id,status,assigned_technician_id")
      .eq("id", item.work_order_id)
      .maybeSingle();
    if (error || !visibleOrder) return fail("NOT_FOUND", "Work Order was not found.", 404);
    parentStatus = visibleOrder.status;
  } else if (item.incident_id) {
    const supabase = await createClient();
    const { data: visibleIncident, error } = await supabase
      .from("incidents")
      .select("id,status")
      .eq("id", item.incident_id)
      .maybeSingle();
    if (error || !visibleIncident) return fail("NOT_FOUND", "Incident was not found.", 404);
    parentStatus = visibleIncident.status;
  }

  const management = ["supervisor", "facility_manager", "administrator"].includes(identity.role);
  const uploader = item.uploaded_by === identity.userId;
  const verifiedOrTerminal = item.work_order_id && ["completed", "reviewed", "closed", "cancelled"].includes(parentStatus ?? "");

  if (verifiedOrTerminal && identity.role !== "administrator") {
    return fail("ADMINISTRATOR_REQUIRED", "Only an Administrator may void evidence after Completed Work has been verified or the Work Order is terminal.", 403);
  }
  if (item.work_order_id && identity.role !== "administrator") {
    const supabase = await createClient();
    const { data: order } = await supabase.from("work_orders").select("status,assigned_technician_id,facility_id,user_id,requested_by").eq("id", item.work_order_id).maybeSingle();
    const membership = identity.role === "technician" && order ? await supabase.rpc("technician_facility_read_permitted", { p_facility_id: order.facility_id }) : { data: false };
    if (!order || !canMutateWorkOrderEvidence({ role: identity.role, userId: identity.userId, assignedTechnicianId: order.assigned_technician_id, status: order.status, hasActiveFacilityMembership: membership.data === true, creatorId: order.user_id, requesterId: order.requested_by })) return fail("EVIDENCE_READ_ONLY", "Evidence is read-only for this Work Order.", 403);
  }
  if (!verifiedOrTerminal && !management && !uploader) {
    return fail("ACCESS_DENIED", "You are not authorised to remove this evidence.", 403);
  }

  const { error: updateError } = await admin
    .from("evidence_items")
    .update({
      deleted_at: new Date().toISOString(),
      deleted_by: identity.userId,
      deletion_reason: reason,
      category: "other",
    })
    .eq("id", item.id)
    .is("deleted_at", null);

  if (updateError) return fail("EVIDENCE_DELETE_FAILED", "Evidence could not be removed.", 503);

  if (item.work_order_id) {
    await admin.from("activity_logs").insert({
      user_id: identity.userId,
      work_order_id: item.work_order_id,
      action: "evidence_voided",
      from_status: parentStatus,
      to_status: parentStatus,
      actor: identity.displayName,
      note: JSON.stringify({
        evidence_id: item.id,
        filename: item.original_filename,
        original_category: item.category,
        reason,
        voided_by: identity.userId,
        voided_at: new Date().toISOString(),
      }),
    });
  }

  return NextResponse.json({
    ok: true,
    message: "Evidence removed from the active record. The audit history is retained.",
  });
}
