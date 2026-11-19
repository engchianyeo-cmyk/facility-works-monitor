import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M36: record one item of a Daily round (OK / Not OK, reading, note). The database decides who may. */
export async function POST(request: Request) {
  if (!(await getCurrentIdentity())) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const { data, error } = await (await createClient()).rpc("record_daily_round_item", { p_work_order_id: b.work_order_id, p_item_id: b.item_id, p_ok: b.ok, p_reading: b.reading ?? null, p_note: b.note ?? null });
  const r = data as { ok?: boolean; message?: string } | null;
  if (error || !r?.ok) return NextResponse.json({ error: r?.message ?? "The item could not be saved." }, { status: 409 });
  return NextResponse.json({ ok: true });
}
