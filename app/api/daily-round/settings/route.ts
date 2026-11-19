import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M36: switch the Daily round on or off, set its times, the Technician who does it and the one who covers. */
export async function POST(request: Request) {
  if (!(await getCurrentIdentity())) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const { data, error } = await (await createClient()).rpc("set_daily_round_settings", {
    p_facility_id: b.facility_id, p_enabled: b.enabled === true, p_technician_id: b.technician_id || null, p_cover_id: b.cover_id || null,
    p_ready: b.ready, p_due: b.due, p_reason: b.reason,
  });
  const r = data as { ok?: boolean; message?: string } | null;
  if (error || !r?.ok) return NextResponse.json({ error: r?.message ?? "The settings could not be saved." }, { status: 409 });
  return NextResponse.json({ ok: true });
}
