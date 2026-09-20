import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

type Context = { params: Promise<{ id: string; documentId: string }> };

export async function POST(_: Request, { params }: Context) {
  if (!await getCurrentIdentity()) return NextResponse.json({ ok: false, code: "AUTHENTICATION_REQUIRED", message: "Authentication is required." }, { status: 401 });
  const { id, documentId } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase.from("work_order_commercial_documents").select("storage_path,original_filename").eq("id", documentId).eq("work_order_id", id).is("deleted_at", null).maybeSingle();
  if (error || !data) return NextResponse.json({ ok: false, code: "NOT_FOUND", message: "Commercial document was not found." }, { status: 404 });
  const signed = await createAdminClient().storage.from("field-evidence").createSignedUrl(data.storage_path, 300);
  if (signed.error || !signed.data?.signedUrl) return NextResponse.json({ ok: false, code: "DOCUMENT_UNAVAILABLE", message: "Commercial document is unavailable." }, { status: 503 });
  return NextResponse.json({ ok: true, url: signed.data.signedUrl, filename: data.original_filename });
}
