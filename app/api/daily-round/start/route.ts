import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M36: start today's Daily round by hand (normally the daily run does it). */
export async function POST(request: Request) {
  if (!(await getCurrentIdentity())) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Singapore" }).format(new Date());
  const { data, error } = await (await createClient()).rpc("create_daily_round", { p_facility_id: b.facility_id, p_date: today });
  const r = data as { ok?: boolean; message?: string } | null;
  if (error || !r?.ok) return NextResponse.json({ error: r?.message ?? "The round could not be started." }, { status: 409 });
  return NextResponse.json({ ok: true });
}
