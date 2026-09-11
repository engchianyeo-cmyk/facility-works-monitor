import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { canMutateWorkOrderEvidence, cleanFilename, compensateEvidenceRegistrationFailure, validCategory, validParent, validateEvidenceFile } from "@/lib/evidence";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

const fail = (code: string, message: string, status = 400) => NextResponse.json({ ok: false, code, message }, { status });

async function parentVisible(type: string, id: string) {
  const supabase = await createClient();
  const table = type === "work_order" ? "work_orders" : "incidents";
  const { data, error } = await supabase.from(table).select("id").eq("id", id).maybeSingle();
  return !error && Boolean(data);
}

function usableDisplayName(value: string | null | undefined, email: string | null | undefined) {
  const name = value?.trim() ?? "";
  if (name && name.toLowerCase() !== "pending preserved user") return name;
  const local = email?.split("@")[0]?.trim();
  return local || "Recorded user";
}

export async function GET(request: NextRequest) {
  if (!await getCurrentIdentity()) return fail("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const type = request.nextUrl.searchParams.get("parent_type");
  const id = request.nextUrl.searchParams.get("parent_id");
  if (!validParent(type, id)) return fail("VALIDATION_ERROR", "Evidence parent is invalid.");
  const parentId = id as string;
  if (!await parentVisible(type, parentId)) return fail("NOT_FOUND", "Parent record was not found.", 404);

  const supabase = await createClient();
  const column = type === "work_order" ? "work_order_id" : "incident_id";
  const { data, error } = await supabase
    .from("evidence_items")
    .select("id,parent_type,work_order_id,incident_id,uploaded_by,original_filename,content_type,byte_size,category,description,uploaded_at")
    .eq(column, parentId)
    .is("deleted_at", null)
    .order("uploaded_at", { ascending: false });
  if (error) return fail("EVIDENCE_UNAVAILABLE", "Evidence is temporarily unavailable.", 503);

  const uploaderIds = [...new Set((data ?? []).map((item) => item.uploaded_by))];
  const admin = createAdminClient();
  const { data: profiles } = uploaderIds.length
    ? await admin.from("profiles").select("id,display_name,email").in("id", uploaderIds)
    : { data: [] };
  const names = new Map((profiles ?? []).map((profile) => [profile.id, usableDisplayName(profile.display_name, profile.email)]));

  return NextResponse.json({
    ok: true,
    data: (data ?? []).map((item) => ({ ...item, uploader_name: names.get(item.uploaded_by) ?? "Recorded user" })),
  });
}

export async function POST(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return fail("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return fail("MALFORMED_UPLOAD", "Upload form is invalid.");
  }

  const type = form.get("parent_type");
  const id = form.get("parent_id");
  const category = form.get("category");
  const description = String(form.get("description") ?? "").trim();
  const candidate = form.get("file");
  if (!validParent(type, id) || !validCategory(category)) return fail("VALIDATION_ERROR", "Parent or evidence category is invalid.");
  const parentId = id as string;
  if (description.length > 500) return fail("VALIDATION_ERROR", "Description must be 500 characters or fewer.");
  if (!(candidate instanceof File)) return fail("VALIDATION_ERROR", "Choose a file to upload.");
  if (!await parentVisible(type, parentId)) return fail("NOT_FOUND", "Parent record was not found.", 404);
  if (type === "work_order") {
    const supabase = await createClient();
    const { data: order, error } = await supabase.from("work_orders").select("status,assigned_technician_id,facility_id,user_id,requested_by").eq("id", parentId).maybeSingle();
    if (error || !order) return fail("NOT_FOUND", "Work Order was not found.", 404);
    const membership = identity.role === "technician" ? await supabase.rpc("technician_facility_read_permitted", { p_facility_id: order.facility_id }) : { data: false };
    if (!canMutateWorkOrderEvidence({ role: identity.role, userId: identity.userId, assignedTechnicianId: order.assigned_technician_id, status: order.status, hasActiveFacilityMembership: membership.data === true, creatorId: order.user_id, requesterId: order.requested_by })) {
      return fail("EVIDENCE_READ_ONLY", "Evidence is read-only unless you are authorised to record field evidence for this active assignment.", 403);
    }
  }

  const bytes = new Uint8Array(await candidate.arrayBuffer());
  const fileError = validateEvidenceFile(candidate, bytes);
  if (fileError) return fail("INVALID_FILE", fileError);

  const evidenceId = crypto.randomUUID();
  const safeName = cleanFilename(candidate.name);
  const path = `evidence/${type.replace("_", "-")}/${parentId}/${evidenceId}/${safeName}`;
  let removeNewObject: (() => Promise<{ error: { message: string } | null }>) | null = null;

  try {
    const admin = createAdminClient();
    const { error: uploadError } = await admin.storage.from("field-evidence").upload(path, bytes, { contentType: candidate.type, upsert: false });
    if (uploadError) return fail("UPLOAD_FAILED", "Evidence could not be uploaded.", 503);
    removeNewObject = () => admin.storage.from("field-evidence").remove([path]);

    const supabase = await createClient();
    const { data, error } = await supabase.rpc("register_evidence_item", {
      p_parent_type: type,
      p_parent_id: parentId,
      p_original_filename: safeName,
      p_content_type: candidate.type,
      p_byte_size: candidate.size,
      p_category: category,
      p_description: description,
      p_storage_path: path,
    });

    if (error || !data?.ok) {
      const registrationCode = data?.code ?? "AUDIT_FAILED";
      const cleanup = await compensateEvidenceRegistrationFailure(removeNewObject, { evidenceId, parentType: type, parentId, registrationCode });
      if (cleanup.orphaned) return fail("ORPHANED_STORAGE_OBJECT", "Evidence registration failed and storage recovery is required.", 503);
      return fail(registrationCode, "Evidence could not be registered.", 503);
    }

    return NextResponse.json(data, { status: 201 });
  } catch {
    if (removeNewObject) {
      const cleanup = await compensateEvidenceRegistrationFailure(removeNewObject, { evidenceId, parentType: type, parentId, registrationCode: "REGISTRATION_EXCEPTION" });
      if (cleanup.orphaned) return fail("ORPHANED_STORAGE_OBJECT", "Evidence registration failed and storage recovery is required.", 503);
    }
    return fail("EVIDENCE_UNAVAILABLE", "Evidence service is unavailable.", 503);
  }
}
