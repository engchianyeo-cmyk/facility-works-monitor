import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { cleanFilename, validateEvidenceFile } from "@/lib/evidence";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

type Context = { params: Promise<{ id: string }> };
const fail = (code: string, message: string, status = 400) => NextResponse.json({ ok: false, code, message }, { status });

/**
 * Lifecycle v2 contractor invoice upload (design §3.5): the assigned Technician uploads the
 * invoice after the Work Order is Completed. PostgreSQL (register_work_order_invoice) checks
 * authority and that the amount equals the approved final cost.
 */
export async function POST(request: NextRequest, { params }: Context) {
  const identity = await getCurrentIdentity();
  if (!identity) return fail("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  if (identity.role !== "technician") return fail("ACCESS_DENIED", "Only the assigned Technician uploads the contractor invoice.", 403);
  const { id } = await params;
  let form: FormData;
  try { form = await request.formData(); } catch { return fail("MALFORMED_UPLOAD", "Upload form is invalid."); }
  const candidate = form.get("file");
  const reference = String(form.get("invoice_reference") ?? "").trim();
  const amountText = String(form.get("invoice_amount") ?? "").trim();
  const amount = Number(amountText);
  if (!(candidate instanceof File) || !reference || reference.length > 100 || amountText === "" || !Number.isFinite(amount) || amount < 0 || Math.round(amount * 100) !== amount * 100) {
    return fail("VALIDATION_ERROR", "Invoice file, invoice number and amount are required.");
  }
  if (!candidate.size || candidate.size > 10 * 1024 * 1024 || !["image/jpeg", "image/png", "image/webp", "application/pdf"].includes(candidate.type)) {
    return fail("INVALID_FILE", "The invoice must be an image or PDF between 1 byte and 10 MB.");
  }
  let supabase: Awaited<ReturnType<typeof createClient>>;
  try {
    supabase = await createClient();
    const { data: order, error } = await supabase.from("work_orders").select("id,status,assigned_technician_id").eq("id", id).maybeSingle();
    if (error) return fail("INVOICE_UNAVAILABLE", "The invoice service is unavailable.", 503);
    if (!order) return fail("NOT_FOUND", "Work Order was not found.", 404);
    if (order.assigned_technician_id !== identity.userId) return fail("ACCESS_DENIED", "Only the assigned Technician uploads the contractor invoice.", 403);
    if (order.status !== "reviewed") return fail("INVALID_TRANSITION", "The invoice is uploaded after the Work Order is Completed.", 409);
  } catch { return fail("INVOICE_UNAVAILABLE", "The invoice service is unavailable.", 503); }
  const bytes = new Uint8Array(await candidate.arrayBuffer());
  const fileError = validateEvidenceFile(candidate, bytes);
  if (fileError) return fail("INVALID_FILE", fileError);
  const safeName = cleanFilename(candidate.name);
  const path = `commercial/work-order/${id}/${crypto.randomUUID()}/${safeName}`;
  let removeNewObject: (() => Promise<{ error: { message: string } | null }>) | null = null;
  async function compensate() {
    if (!removeNewObject) return true;
    try { const result = await removeNewObject(); return !result.error; } catch { return false; }
  }
  try {
    const admin = createAdminClient();
    const uploaded = await admin.storage.from("field-evidence").upload(path, bytes, { contentType: candidate.type, upsert: false });
    if (uploaded.error) return fail("UPLOAD_FAILED", "The invoice could not be uploaded.", 503);
    removeNewObject = () => admin.storage.from("field-evidence").remove([path]);
    const { data, error } = await supabase.rpc("register_work_order_invoice", {
      p_work_order_id: id,
      p_storage_path: path,
      p_original_filename: safeName,
      p_content_type: candidate.type,
      p_byte_size: candidate.size,
      p_invoice_reference: reference,
      p_invoice_amount: amount,
    });
    if (error || !data?.ok) {
      if (!await compensate()) return fail("ORPHANED_STORAGE_OBJECT", "Invoice registration failed and storage recovery is required.", 503);
      const code = String(data?.code ?? "INVOICE_FAILED");
      return fail(code, String(data?.message ?? "The invoice could not be registered."), code === "ACCESS_DENIED" ? 403 : 409);
    }
    return NextResponse.json(data, { status: 201 });
  } catch {
    if (!await compensate()) return fail("ORPHANED_STORAGE_OBJECT", "Invoice registration failed and storage recovery is required.", 503);
    return fail("INVOICE_UNAVAILABLE", "The invoice service is unavailable.", 503);
  }
}
