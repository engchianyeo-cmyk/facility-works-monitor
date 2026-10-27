import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { isUuidLike } from "@/lib/work-orders/decision-header";

const fail = (code: string, message: string, status: number) => NextResponse.json({ ok: false, code, message }, { status });

/** D-17: view or download a facility drawing. Any signed-in staff member who can see the drawing record (database rules) gets a short-lived link. */
export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!await getCurrentIdentity()) return fail("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const { id } = await params;
  if (!isUuidLike(id)) return fail("NOT_FOUND", "Drawing not found.", 404);
  const supabase = await createClient();
  const { data, error } = await supabase.from("facility_drawings").select("storage_path,original_filename").eq("id", id).maybeSingle();
  if (error || !data) return fail("NOT_FOUND", "Drawing not found.", 404);
  const download = request.nextUrl.searchParams.get("download") === "1";
  try {
    const { data: signed, error: signedError } = await createAdminClient().storage.from("field-evidence")
      .createSignedUrl(data.storage_path, 300, download ? { download: data.original_filename } : undefined);
    if (signedError || !signed) return fail("ACCESS_FAILED", "The drawing could not be opened.", 503);
    const response = NextResponse.redirect(signed.signedUrl, 302);
    response.headers.set("Cache-Control", "private, no-store");
    return response;
  } catch { return fail("ACCESS_FAILED", "The drawing could not be opened.", 503); }
}
