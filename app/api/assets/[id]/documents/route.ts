import { randomUUID } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

/** M34: file a document (first of all the O&M manual) with an asset. Stored privately; the database decides who may file. */
const TYPES = ["application/pdf", "image/png", "image/jpeg", "image/webp"];
const MAX = 50 * 1024 * 1024;
const safe = (name: string) => name.replace(/[^A-Za-z0-9._-]+/g, "_").slice(-120) || "document";

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) return NextResponse.json({ error: "Asset not found." }, { status: 404 });
  const supabase = await createClient();
  const { data: allowed } = await supabase.rpc("asset_document_editor", { p_asset_id: id });
  if (allowed !== true) return NextResponse.json({ error: "A Supervisor, Facility Manager or Facility Administrator of this facility, or the Super-Administrator, files asset documents." }, { status: 403 });
  const form = await request.formData().catch(() => null);
  const file = form?.get("file");
  const kind = typeof form?.get("kind") === "string" ? String(form?.get("kind")) : "om_manual";
  const title = String(form?.get("title") ?? "").trim().slice(0, 200) || "O&M manual";
  if (!(file instanceof File) || !TYPES.includes(file.type) || file.size <= 0 || file.size > MAX) {
    return NextResponse.json({ error: "Choose a PDF or image of up to 50 MB." }, { status: 400 });
  }
  const path = `asset-documents/${id}/${randomUUID()}-${safe(file.name)}`;
  let admin;
  try { admin = createAdminClient(); } catch { return NextResponse.json({ error: "Document storage is not available." }, { status: 503 }); }
  const uploaded = await admin.storage.from("field-evidence").upload(path, file, { contentType: file.type, upsert: false });
  if (uploaded.error) return NextResponse.json({ error: "The document could not be stored." }, { status: 503 });
  const { data, error } = await supabase.rpc("register_asset_document", {
    p_asset_id: id, p_kind: kind, p_title: title, p_filename: file.name.slice(0, 200), p_content_type: file.type, p_byte_size: file.size, p_storage_path: path,
  });
  const result = data as { ok?: boolean; id?: string; message?: string } | null;
  if (error || !result?.ok) {
    await admin.storage.from("field-evidence").remove([path]);
    return NextResponse.json({ error: result?.message ?? "The document could not be filed." }, { status: 409 });
  }
  return NextResponse.json({ ok: true, id: result.id }, { status: 201 });
}
