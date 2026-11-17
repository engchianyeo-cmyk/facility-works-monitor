import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { ASSISTANT_HOURLY_LIMIT, ASSISTANT_MAX_QUESTION, assistantAiEnabled, assistantModel, looksSensitive } from "@/lib/assistant/config";
import { buildSystemPrompt, type LearningForPrompt } from "@/lib/assistant/prompt";
import { loadAssistantSettings } from "@/lib/assistant/settings";
import { createClient } from "@/lib/supabase/server";

/**
 * D-58 option A: the in-app AI assistant. Off unless FMW_ASSISTANT_AI=on and ANTHROPIC_API_KEY are set.
 * It only explains and guides: it receives the question, the person's role, the page and (if open) the Work Order's
 * number and status, never their data, passwords or other facilities. Questions are not stored by FMWorks.
 */
const recent = new Map<string, number[]>();

function underLimit(userId: string, now = Date.now()): boolean {
  const hour = now - 60 * 60 * 1000;
  const times = (recent.get(userId) ?? []).filter((time) => time > hour);
  if (times.length >= ASSISTANT_HOURLY_LIMIT) {
    recent.set(userId, times);
    return false;
  }
  times.push(now);
  recent.set(userId, times);
  return true;
}

export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  if (!assistantAiEnabled()) return NextResponse.json({ error: "The AI assistant is not switched on for this system. Use the prepared answers." }, { status: 503 });

  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const question = String(body.question ?? "").trim();
  if (question.length < 3) return NextResponse.json({ error: "Please type a question." }, { status: 400 });
  if (question.length > ASSISTANT_MAX_QUESTION) return NextResponse.json({ error: `Please keep the question under ${ASSISTANT_MAX_QUESTION} characters.` }, { status: 400 });
  if (looksSensitive(question)) return NextResponse.json({ error: "That looks like a password, code or card number. Remove it; never share these. If it was a real password, change it now." }, { status: 400 });
  if (!underLimit(identity.userId)) return NextResponse.json({ error: "You have asked many questions this hour. Please try again later or use the prepared answers." }, { status: 429 });

  const path = typeof body.path === "string" && body.path.startsWith("/") ? body.path.slice(0, 200) : "/";
  const raw = body.workOrder as { id?: unknown; reference?: unknown; status?: unknown; inHouse?: unknown } | null | undefined;
  const workOrder = raw && typeof raw.reference === "string" && typeof raw.status === "string"
    ? { reference: raw.reference.slice(0, 40), status: raw.status.slice(0, 40), inHouse: raw.inHouse === true }
    : null;

  // D-59a: what the team learnt on similar jobs (row security: only Work Orders this person may see).
  const supabase = await createClient();
  const workOrderId = raw && typeof raw.id === "string" && /^[0-9a-f-]{36}$/i.test(raw.id) ? raw.id : null;
  const [settings, matches, team] = await Promise.all([
    loadAssistantSettings(supabase),
    workOrderId ? supabase.rpc("work_order_learning_matches", { p_work_order_id: workOrderId, p_limit: 5 }) : Promise.resolve({ data: [] }),
    supabase.from("assistant_answers").select("question,answer").eq("active", true).order("updated_at", { ascending: false }).limit(60),
  ]);
  const teamAnswers = ((team as { data: unknown }).data ?? []) as Array<{ question: string; answer: string }>;
  const learnings = (((matches as { data: unknown }).data ?? []) as LearningForPrompt[]).slice(0, 5);

  try {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": String(process.env.ANTHROPIC_API_KEY),
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: assistantModel(),
        max_tokens: 700,
        system: buildSystemPrompt({ role: identity.role, displayName: identity.displayName, path, workOrder, assistantName: settings.name, learnings, teamAnswers }),
        messages: [{ role: "user", content: question }],
      }),
      signal: AbortSignal.timeout(30_000),
    });
    const result = (await response.json().catch(() => null)) as { content?: Array<{ type: string; text?: string }> } | null;
    const answer = result?.content?.filter((part) => part.type === "text").map((part) => part.text ?? "").join("\n").trim();
    if (!response.ok || !answer) {
      console.warn("[assistant] AI service error", { status: response.status });
      return NextResponse.json({ error: "The AI assistant could not answer just now. Use the prepared answers or try again." }, { status: 502 });
    }
    // M33: keep the question and the AI's answer (role and page only) so the team can check and improve it.
    const { data: kept } = await supabase.rpc("log_assistant_question", { p_question: question, p_path: path, p_answered_by: "ai", p_matched: null, p_ai_answer: answer.slice(0, 8000) });
    return NextResponse.json({ answer, questionId: (kept as { id?: string } | null)?.id ?? null }, { headers: { "cache-control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "The AI assistant could not be reached. Use the prepared answers or try again." }, { status: 504 });
  }
}
