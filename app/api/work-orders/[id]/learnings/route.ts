import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** D-59a: share what was learnt from a Work Order, or hide a learning (Super-Administrator, Facility Administrator, Facility Manager). */
type RouteContext = { params: Promise<{ id: string }> };

export async function POST(request: Request, context: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const { id } = await context.params;
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const supabase = await createClient();
  if (body.action === "hide") {
    const { data, error } = await supabase.rpc("hide_work_order_learning", { p_learning_id: String(body.learning_id ?? ""), p_reason: String(body.reason ?? "") });
    const result = data as { ok?: boolean; message?: string } | null;
    if (error || !result?.ok) return NextResponse.json({ error: result?.message ?? "The learning could not be hidden." }, { status: 409 });
    return NextResponse.json({ ok: true });
  }
  const payload = {
    confirmed_cause: String(body.confirmed_cause ?? ""),
    fix_that_worked: String(body.fix_that_worked ?? ""),
    tip: String(body.tip ?? ""),
    ai_suggestion: typeof body.ai_suggestion === "string" ? body.ai_suggestion : "",
  };
  const { data, error } = await supabase.rpc("share_work_order_learning", { p_work_order_id: id, p_payload: payload });
  const result = data as { ok?: boolean; message?: string } | null;
  if (error || !result?.ok) return NextResponse.json({ error: result?.message ?? "What you learnt could not be saved." }, { status: 409 });
  return NextResponse.json({ ok: true });
}
