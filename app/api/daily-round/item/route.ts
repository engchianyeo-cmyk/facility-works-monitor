import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M36: add or change an item of a Daily round check (tick only, or a reading with its unit; M38: its normal range and guide). */
function limit(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const n = typeof value === "number" ? value : Number(String(value).trim().replace("−", "-").replace(",", "."));
  return Number.isFinite(n) ? n : null;
}

export async function POST(request: Request) {
  if (!(await getCurrentIdentity())) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const { data, error } = await (await createClient()).rpc("save_daily_round_item", {
    p_item_id: b.id || null, p_check_id: b.check_id || null, p_label: b.label, p_reading_unit: b.unit ?? null,
    p_position: typeof b.position === "number" ? b.position : null, p_active: b.active !== false,
    p_reading_min: limit(b.min), p_reading_max: limit(b.max), p_reading_guide: typeof b.guide === "string" ? b.guide : null,
  });
  const r = data as { ok?: boolean; message?: string; id?: string } | null;
  if (error || !r?.ok) return NextResponse.json({ error: r?.message ?? "The item could not be saved." }, { status: 409 });
  return NextResponse.json({ ok: true, id: r.id });
}
