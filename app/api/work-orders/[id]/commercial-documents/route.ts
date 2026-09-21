import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { cleanFilename, validateEvidenceFile } from "@/lib/evidence";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

type Context = { params: Promise<{ id: string }> };
const fail = (code: string, message: string, status = 400) => NextResponse.json({ ok: false, code, message }, { status });

export async function POST(request: NextRequest, { params }: Context) {
  if (!await getCurrentIdentity()) return fail("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  let form: FormData;
  try { form = await request.formData(); } catch { return fail("MALFORMED_UPLOAD", "Upload form is invalid."); }
  const documentType = String(form.get("document_type") ?? "");
  const recordId = String(form.get("record_id") ?? "");
  const candidate = form.get("file");
  if (!["quotation", "invoice", "final_invoice"].includes(documentType) || !/^[0-9a-f-]{36}$/i.test(recordId) || !(candidate instanceof File)) return fail("VALIDATION_ERROR", "Document type, record and file are required.");
  const bytes = new Uint8Array(await candidate.arrayBuffer());
  const fileError = validateEvidenceFile(candidate, bytes);
  if (fileError) return fail("INVALID_FILE", fileError);
  const documentId = crypto.randomUUID();
  const safeName = cleanFilename(candidate.name);
  const path = `commercial/work-order/${id}/${documentId}/${safeName}`;
  const admin = createAdminClient();
  const uploaded = await admin.storage.from("field-evidence").upload(path, bytes, { contentType: candidate.type, upsert: false });
  if (uploaded.error) return fail("UPLOAD_FAILED", "Commercial document could not be uploaded.", 503);
  try {
    const supabase = await createClient();
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
      await admin.storage.from("field-evidence").remove([path]);
      return fail(String(data?.code ?? "AUDIT_FAILED"), String(data?.message ?? "Commercial document could not be registered."), data?.code === "ACCESS_DENIED" ? 403 : 400);
    }
    return NextResponse.json(data, { status: 201 });
  } catch {
    await admin.storage.from("field-evidence").remove([path]);
    return fail("COMMERCIAL_DOCUMENT_UNAVAILABLE", "Commercial document service is unavailable.", 503);
  }
}
