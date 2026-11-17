import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M33: the site team's own answers for the assistant (GET: the active ones; POST: add, edit or retire one). */
export async function GET() {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ answers: [] }, { status: 401 });
  const supabase = await createClient();
  const { data } = await supabase.from("assistant_answers").select("id,question,answer,keywords").eq("active", true).order("updated_at", { ascending: false }).limit(300);
  return NextResponse.json({ answers: data ?? [] }, { headers: { "cache-control": "no-store" } });
}

export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity || !["administrator", "facility_administrator", "facility_manager"].includes(identity.role)) {
    return NextResponse.json({ error: "Only the Super-Administrator, a Facility Administrator or a Facility Manager can teach the assistant." }, { status: 403 });
  }
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const keywords = String(body.keywords ?? "").split(",").map((word) => word.trim()).filter(Boolean).slice(0, 20);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("save_assistant_answer", {
    p_id: typeof body.id === "string" && body.id ? body.id : null,
    p_question: String(body.question ?? ""),
    p_answer: String(body.answer ?? ""),
    p_keywords: keywords,
    p_source_question: typeof body.source_question === "string" && body.source_question ? body.source_question : null,
    p_active: body.active !== false,
  });
  const result = data as { ok?: boolean; id?: string; message?: string } | null;
  if (error || !result?.ok) return NextResponse.json({ error: result?.message ?? "The answer could not be saved." }, { status: 409 });
  return NextResponse.json({ ok: true, id: result.id });
}
