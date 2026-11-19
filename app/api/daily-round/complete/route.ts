import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M36: complete and close a Daily round once every item is recorded. */
export async function POST(request: Request) {
  if (!(await getCurrentIdentity())) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const { data, error } = await (await createClient()).rpc("complete_daily_round", { p_work_order_id: b.work_order_id, p_note: b.note ?? null });
  const r = data as { ok?: boolean; message?: string; faults?: number } | null;
  if (error || !r?.ok) return NextResponse.json({ error: r?.message ?? "The round could not be completed." }, { status: 409 });
  return NextResponse.json({ ok: true, faults: r.faults ?? 0 });
}
