import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { cleanFilename, validateEvidenceFile } from "@/lib/evidence";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

type Context = { params: Promise<{ id: string }> };
const fail = (code: string, message: string, status = 400) => NextResponse.json({ ok: false, code, message }, { status });

export async function POST(request: NextRequest, { params }: Context) {
  const identity = await getCurrentIdentity();
  if (!identity) return fail("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  let form: FormData;
  try { form = await request.formData(); } catch { return fail("MALFORMED_UPLOAD", "Upload form is invalid."); }
  const documentType = String(form.get("document_type") ?? "");
  const recordId = String(form.get("record_id") ?? "");
  const candidate = form.get("file");
  if (!["quotation", "invoice", "final_invoice"].includes(documentType) || !/^[0-9a-f-]{36}$/i.test(recordId) || !(candidate instanceof File)) return fail("VALIDATION_ERROR", "Document type, record and file are required.");
  if (!candidate.size || candidate.size > 10 * 1024 * 1024 || !["image/jpeg", "image/png", "image/webp", "application/pdf"].includes(candidate.type)) return fail("INVALID_FILE", "Commercial documents must be an image or PDF between 1 byte and 10 MB.");
  let supabase: Awaited<ReturnType<typeof createClient>>;
  try {
    supabase = await createClient();
    const { data: order, error } = await supabase.from("work_orders").select("id,status,assigned_technician_id,facility_id").eq("id", id).maybeSingle();
    if (error) return fail("COMMERCIAL_DOCUMENT_UNAVAILABLE", "Commercial document service is unavailable.", 503);
    if (!order) return fail("NOT_FOUND", "Work Order was not found.", 404);
    if (!["technician", "supervisor", "facility_manager", "administrator"].includes(identity.role) || (documentType === "final_invoice" && identity.role !== "technician")) return fail("ACCESS_DENIED", "Commercial document authority is required.", 403);
    if (identity.role === "technician") {
      const membership = await supabase.rpc("technician_facility_read_permitted", { p_facility_id: order.facility_id });
      if (order.assigned_technician_id !== identity.userId || membership.error || membership.data !== true) return fail("ACCESS_DENIED", "Assigned same-facility Technician authority is required.", 403);
    }
    const table = documentType === "quotation" ? "contractor_quotations" : documentType === "invoice" ? "contractor_payment_assessments" : "work_order_final_cost_submissions";
    const record = await supabase.from(table).select("id,status").eq("id", recordId).eq("work_order_id", id).maybeSingle();
    if (record.error) return fail("COMMERCIAL_DOCUMENT_UNAVAILABLE", "Commercial document service is unavailable.", 503);
    if (!record.data) return fail("NOT_FOUND", "Commercial record was not found.", 404);
    if (documentType === "quotation" && !["draft", "returned"].includes(record.data.status)) return fail("APPROVED_DOCUMENT_IMMUTABLE", "Only draft or returned quotations accept documents.", 403);
    if (documentType === "invoice" && !["draft", "awaiting_approval", "approved_for_payment", "returned"].includes(record.data.status)) return fail("FINANCIAL_RECORD_IMMUTABLE", "This final account is read-only.", 403);
    if (documentType === "final_invoice") {
      if (!["assigned", "in_progress", "completed", "reviewed"].includes(order.status)) return fail("ACCESS_DENIED", "Final invoices are read-only after closure.", 403);
      const payment = await supabase.from("contractor_payment_assessments").select("status").eq("work_order_id", id).maybeSingle();
      if (payment.error) return fail("COMMERCIAL_DOCUMENT_UNAVAILABLE", "Commercial document service is unavailable.", 503);
      if (payment.data && ["awaiting_approval", "approved_for_payment", "paid"].includes(payment.data.status)) return fail("FINANCIAL_RECORD_IMMUTABLE", "Submitted payment documents are read-only.", 403);
    }
  } catch { return fail("COMMERCIAL_DOCUMENT_UNAVAILABLE", "Commercial document service is unavailable.", 503); }
  const bytes = new Uint8Array(await candidate.arrayBuffer());
  const fileError = validateEvidenceFile(candidate, bytes);
  if (fileError) return fail("INVALID_FILE", fileError);
  const documentId = crypto.randomUUID();
  const safeName = cleanFilename(candidate.name);
  const path = `commercial/work-order/${id}/${documentId}/${safeName}`;
  let removeNewObject: (() => Promise<{ error: { message: string } | null }>) | null = null;
  async function compensate() {
    if (!removeNewObject) return true;
    try { const result = await removeNewObject(); return !result.error; } catch { return false; }
  }
  try {
    const admin = createAdminClient();
    const uploaded = await admin.storage.from("field-evidence").upload(path, bytes, { contentType: candidate.type, upsert: false });
    if (uploaded.error) return fail("UPLOAD_FAILED", "Commercial document could not be uploaded.", 503);
    removeNewObject = () => admin.storage.from("field-evidence").remove([path]);
    const { data, error } = documentType === "final_invoice" ? await supabase.rpc("register_work_order_final_cost_document", {
      p_work_order_id: id,
      p_submission_id: recordId,
      p_original_filename: safeName,
      p_content_type: candidate.type,
      p_byte_size: candidate.size,
      p_storage_path: path,
    }) : await supabase.rpc("register_work_order_commercial_document", {
      p_work_order_id: id,
      p_document_type: documentType,
      p_record_id: recordId,
      p_original_filename: safeName,
      p_content_type: candidate.type,
      p_byte_size: candidate.size,
      p_storage_path: path,
    });
    if (error || !data?.ok) {
      if (!await compensate()) return fail("ORPHANED_STORAGE_OBJECT", "Commercial document registration failed and storage recovery is required.", 503);
      return fail(String(data?.code ?? "AUDIT_FAILED"), String(data?.message ?? "Commercial document could not be registered."), data?.code === "ACCESS_DENIED" ? 403 : 400);
    }
    return NextResponse.json(data, { status: 201 });
  } catch {
    if (!await compensate()) return fail("ORPHANED_STORAGE_OBJECT", "Commercial document registration failed and storage recovery is required.", 503);
    return fail("COMMERCIAL_DOCUMENT_UNAVAILABLE", "Commercial document service is unavailable.", 503);
  }
}
