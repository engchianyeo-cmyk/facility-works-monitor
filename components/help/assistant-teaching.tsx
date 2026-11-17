"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export type AskedQuestion = { id: string; asker_role: string; page_path: string; question: string; answered_by: string; matched_answer: string | null; ai_answer: string | null; helpful: boolean | null; created_at: string };
export type TeamAnswerRow = { id: string; question: string; answer: string; keywords: string[]; active: boolean; source_question_id: string | null; updated_at: string };

const ROLE: Record<string, string> = { administrator: "Super-Administrator", facility_administrator: "Facility Administrator", facility_manager: "Facility Manager", supervisor: "Supervisor", approver: "Approver", technician: "Technician", finance: "Finance", reviewer: "Reviewer", initiator: "Initiator" };
const when = (value: string) => new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Singapore" }).format(new Date(value));

/** M33: the team reads what people asked and teaches the assistant better answers. */
export default function AssistantTeaching({ questions, answers, name }: { questions: AskedQuestion[]; answers: TeamAnswerRow[]; name: string }) {
  const router = useRouter();
  const [filter, setFilter] = useState<"needs" | "all">("needs");
  const [form, setForm] = useState<{ id: string | null; question: string; answer: string; keywords: string; source: string | null; active: boolean } | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const shown = filter === "needs" ? questions.filter((item) => item.helpful === false || item.answered_by === "none") : questions;
  const answeredFrom = new Set(answers.map((item) => item.source_question_id).filter(Boolean));

  async function save(body: Record<string, unknown>, done: string) {
    setBusy(true); setError(null); setMessage(null);
    try {
      const response = await fetch("/api/assistant/answers", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      const result = (await response.json().catch(() => ({}))) as { error?: string };
      if (!response.ok) throw new Error(result.error ?? "Could not be saved.");
      setMessage(done); setForm(null); router.refresh();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Could not be saved.");
    } finally { setBusy(false); }
  }

  const input = "mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm font-normal";
  return (
    <div className="space-y-6">
      <section id="questions" className="rounded-xl border border-slate-200 bg-white p-5">
        <h2 className="text-lg font-bold text-slate-900">Questions people asked {name}</h2>
        <p className="mt-1 text-sm text-slate-600">Kept with the asker&apos;s role and page only. Write an answer for a question {name} could not answer well; {name} gives it to everyone from then on.</p>
        <div className="mt-3 flex gap-2 text-sm">
          <button type="button" onClick={() => setFilter("needs")} className={`rounded-full border px-3 py-1 font-semibold ${filter === "needs" ? "border-blue-700 bg-blue-700 text-white" : "border-slate-300"}`}>Needs an answer ({questions.filter((item) => item.helpful === false || item.answered_by === "none").length})</button>
          <button type="button" onClick={() => setFilter("all")} className={`rounded-full border px-3 py-1 font-semibold ${filter === "all" ? "border-blue-700 bg-blue-700 text-white" : "border-slate-300"}`}>All ({questions.length})</button>
        </div>
        {shown.length === 0 ? <p className="mt-3 text-sm text-slate-500">Nothing here yet.</p> : (
          <ul className="mt-3 divide-y rounded-lg border">
            {shown.map((item) => (
              <li key={item.id} className="p-3 text-sm">
                <p className="font-semibold text-slate-900">&ldquo;{item.question}&rdquo;</p>
                <p className="mt-1 text-xs text-slate-500">{ROLE[item.asker_role] ?? item.asker_role} · page {item.page_path} · {when(item.created_at)} · {item.answered_by === "none" ? "no answer found" : item.answered_by === "ai" ? "answered by AI" : `prepared answer ${item.matched_answer ?? ""}`} · {item.helpful === null ? "not rated" : item.helpful ? "helped" : "did not help"}{answeredFrom.has(item.id) ? " · team answer written" : ""}</p>
                {item.ai_answer && <details className="mt-1 text-xs text-slate-700"><summary className="cursor-pointer">AI answer given</summary><p className="mt-1 whitespace-pre-line">{item.ai_answer}</p></details>}
                <button type="button" onClick={() => setForm({ id: null, question: item.question, answer: item.ai_answer ?? "", keywords: "", source: item.id, active: true })} className="mt-2 rounded border border-violet-300 px-2 py-1 text-xs font-semibold text-violet-900">Write an answer</button>
              </li>
            ))}
          </ul>
        )}
      </section>

      {form && (
        <section className="rounded-xl border-2 border-violet-400 bg-violet-50 p-5">
          <h2 className="text-lg font-bold text-slate-900">{form.id ? "Edit the answer" : `Teach ${name} an answer`}</h2>
          <div className="mt-3 grid gap-3">
            <label className="text-sm font-semibold">Question, as people would ask it<input value={form.question} maxLength={300} onChange={(event) => setForm({ ...form, question: event.target.value })} className={input} /></label>
            <label className="text-sm font-semibold">Answer (short steps, the app&apos;s own button names)<textarea rows={5} maxLength={3000} value={form.answer} onChange={(event) => setForm({ ...form, answer: event.target.value })} className={input} /></label>
            <label className="text-sm font-semibold">Key words, separated by commas (help {name} find it)<input value={form.keywords} onChange={(event) => setForm({ ...form, keywords: event.target.value })} placeholder="e.g. sla, response time, countdown" className={input} /></label>
            <div className="flex flex-wrap gap-2">
              <button type="button" disabled={busy} onClick={() => void save({ id: form.id, question: form.question, answer: form.answer, keywords: form.keywords, source_question: form.source, active: form.active }, `Saved. ${name} now gives this answer.`)} className="rounded-lg bg-violet-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{busy ? "Saving…" : "Save answer"}</button>
              <button type="button" onClick={() => setForm(null)} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold">Cancel</button>
            </div>
          </div>
        </section>
      )}
      {message && <p role="status" className="text-sm font-semibold text-emerald-800">{message}</p>}
      {error && <p role="alert" className="text-sm font-semibold text-red-700">{error}</p>}

      <section className="rounded-xl border border-slate-200 bg-white p-5">
        <h2 className="text-lg font-bold text-slate-900">Answers the team taught {name} ({answers.filter((item) => item.active).length} in use)</h2>
        {answers.length === 0 ? <p className="mt-2 text-sm text-slate-500">None yet. Start from a question above, or add one.</p> : (
          <ul className="mt-3 divide-y rounded-lg border">
            {answers.map((item) => (
              <li key={item.id} className={`p-3 text-sm ${item.active ? "" : "opacity-60"}`}>
                <p className="font-semibold text-slate-900">{item.question}{item.active ? "" : " (retired)"}</p>
                <p className="mt-1 whitespace-pre-line text-slate-700">{item.answer}</p>
                {item.keywords.length > 0 && <p className="mt-1 text-xs text-slate-500">Key words: {item.keywords.join(", ")}</p>}
                <div className="mt-2 flex gap-2">
                  <button type="button" onClick={() => setForm({ id: item.id, question: item.question, answer: item.answer, keywords: item.keywords.join(", "), source: item.source_question_id, active: item.active })} className="rounded border border-slate-300 px-2 py-1 text-xs font-semibold">Edit</button>
                  <button type="button" disabled={busy} onClick={() => void save({ id: item.id, question: item.question, answer: item.answer, keywords: item.keywords.join(", "), active: !item.active }, item.active ? "Retired." : "Back in use.")} className="rounded border border-slate-300 px-2 py-1 text-xs font-semibold">{item.active ? "Retire" : "Use again"}</button>
                </div>
              </li>
            ))}
          </ul>
        )}
        <button type="button" onClick={() => setForm({ id: null, question: "", answer: "", keywords: "", source: null, active: true })} className="mt-3 rounded-lg border border-violet-300 px-3 py-2 text-sm font-semibold text-violet-900">Add an answer</button>
      </section>
    </div>
  );
}
