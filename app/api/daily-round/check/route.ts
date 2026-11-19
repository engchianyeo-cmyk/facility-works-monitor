import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M36: add or change a check of the Daily round (for example "Chiller CH-01"). */
export async function POST(request: Request) {
  if (!(await getCurrentIdentity())) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const { data, error } = await (await createClient()).rpc("save_daily_round_check", {
    p_check_id: b.id || null, p_facility_id: b.facility_id || null, p_title: b.title, p_equipment: b.equipment ?? null,
    p_position: typeof b.position === "number" ? b.position : null, p_active: b.active !== false,
  });
  const r = data as { ok?: boolean; message?: string; id?: string } | null;
  if (error || !r?.ok) return NextResponse.json({ error: r?.message ?? "The check could not be saved." }, { status: 409 });
  return NextResponse.json({ ok: true, id: r.id });
}
