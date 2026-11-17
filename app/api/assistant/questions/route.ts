import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { looksSensitive } from "@/lib/assistant/config";
import { createClient } from "@/lib/supabase/server";

/** M33: keep a question asked in Help (role and page only) and, later, whether the answer helped. */
export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const question = String(body.question ?? "").trim().slice(0, 1000);
  if (question.length < 2 || looksSensitive(question)) return NextResponse.json({ ok: false, kept: false });
  const answeredBy = body.answered_by === "prepared" || body.answered_by === "ai" ? body.answered_by : "none";
  const supabase = await createClient();
  const { data } = await supabase.rpc("log_assistant_question", {
    p_question: question,
    p_path: typeof body.path === "string" ? body.path.slice(0, 200) : "/",
    p_answered_by: answeredBy,
    p_matched: typeof body.matched === "string" ? body.matched.slice(0, 100) : null,
    p_ai_answer: null,
  });
  const result = data as { ok?: boolean; id?: string } | null;
  return NextResponse.json({ ok: Boolean(result?.ok), id: result?.id ?? null });
}

export async function PATCH(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (typeof body.id !== "string" || typeof body.helpful !== "boolean") return NextResponse.json({ error: "Invalid rating." }, { status: 400 });
  const supabase = await createClient();
  const { data } = await supabase.rpc("rate_assistant_answer", { p_question_id: body.id, p_helpful: body.helpful });
  const result = data as { ok?: boolean; message?: string } | null;
  return result?.ok ? NextResponse.json({ ok: true }) : NextResponse.json({ error: result?.message ?? "Could not be saved." }, { status: 409 });
}
