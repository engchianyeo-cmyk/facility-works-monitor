import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M35: the Super-Administrator sets a facility's planned maintenance setting (Off / Plan only / Full …) with a reason. */
export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_set_pm_mode", { p_facility_id: body.facility_id, p_mode: body.mode, p_reason: body.reason });
  const result = data as { ok?: boolean; message?: string } | null;
  if (error || !result?.ok) return NextResponse.json({ error: result?.message ?? "The setting could not be changed." }, { status: 409 });
  return NextResponse.json({ ok: true });
}
