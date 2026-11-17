import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M34: take an asset document out of use (kept on record, not deleted). */
export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const { id } = await params;
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("retire_asset_document", { p_document_id: id, p_reason: typeof body.reason === "string" ? body.reason : "" });
  const result = data as { ok?: boolean; message?: string } | null;
  if (error || !result?.ok) return NextResponse.json({ error: result?.message ?? "The document could not be retired." }, { status: 409 });
  return NextResponse.json({ ok: true });
}
