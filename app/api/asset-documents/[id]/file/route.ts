import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

/** M34: open or download an asset document. Row security on asset_documents decides who may see it. */
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const { id } = await params;
  const supabase = await createClient();
  const { data } = await supabase.from("asset_documents").select("storage_path,original_filename").eq("id", id).maybeSingle();
  if (!data) return NextResponse.json({ error: "Document not found." }, { status: 404 });
  const download = new URL(request.url).searchParams.get("download") === "1";
  const { data: signed, error } = await createAdminClient().storage.from("field-evidence")
    .createSignedUrl(data.storage_path, 300, download ? { download: data.original_filename } : undefined);
  if (error || !signed?.signedUrl) return NextResponse.json({ error: "The document could not be opened." }, { status: 503 });
  return NextResponse.redirect(signed.signedUrl, 302);
}
