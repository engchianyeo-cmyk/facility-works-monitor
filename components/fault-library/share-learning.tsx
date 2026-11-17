"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { playTune, speak } from "@/lib/help/ollie-voice";

export type SharedLearning = {
  id: string;
  shared_by: string | null;
  shared_by_name: string;
  confirmed_cause: string | null;
  fix_that_worked: string | null;
  tip: string | null;
  ai_suggestion: string | null;
  hidden_at: string | null;
  created_at: string;
};

/** D-59a: after the work is done, the people on the Work Order are asked what they learnt. */
export default function ShareLearning({ workOrderId, canShare, canHide, userId, learnings, assistantName }: {
  workOrderId: string;
  canShare: boolean;
  canHide: boolean;
  userId: string;
  learnings: SharedLearning[];
  assistantName: string;
}) {
  const router = useRouter();
  const mine = learnings.find((item) => item.shared_by === userId) ?? null;
  const [cause, setCause] = useState(mine?.confirmed_cause ?? "");
  const [fix, setFix] = useState(mine?.fix_that_worked ?? "");
  const [tip, setTip] = useState(mine?.tip ?? "");
  const [ai, setAi] = useState(mine?.ai_suggestion ?? "");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function post(body: Record<string, unknown>) {
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/learnings`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      const result = (await response.json().catch(() => ({}))) as { error?: string };
      if (!response.ok) throw new Error(result.error ?? "Could not be saved.");
      return true;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Could not be saved.");
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function share() {
    if (await post({ confirmed_cause: cause, fix_that_worked: fix, tip, ai_suggestion: ai })) {
      setMessage(`Thank you — saved. ${assistantName} and the next Technician will see it on similar faults.`);
      router.refresh();
    }
  }

  async function hide(id: string) {
    const reason = window.prompt("Why hide this learning? (at least 5 characters)");
    if (!reason) return;
    if (await post({ action: "hide", learning_id: id, reason })) router.refresh();
  }

  // D-58: the assistant chimes (and speaks, if the person turned voice on) once per job per visit to ask for a tip.
  const asking = canShare && !mine;
  useEffect(() => {
    if (!asking) return;
    const key = `fmw.ollie.asked.${workOrderId}`;
    try {
      if (window.sessionStorage.getItem(key)) return;
      window.sessionStorage.setItem(key, "1");
    } catch {
      return;
    }
    const ask = () => {
      playTune("learn");
      speak(`${assistantName} here. The work is done. What did you learn from this job? Please share the cause, the fix or a tip.`);
    };
    const activation = (navigator as { userActivation?: { hasBeenActive: boolean } }).userActivation;
    if (activation && !activation.hasBeenActive) {
      window.addEventListener("pointerdown", ask, { once: true });
      return () => window.removeEventListener("pointerdown", ask);
    }
    ask();
  }, [asking, workOrderId, assistantName]);

  const input = "mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm";
  const visible = learnings.filter((item) => !item.hidden_at);
  const hidden = learnings.filter((item) => item.hidden_at);
  if (!canShare && learnings.length === 0) return null;

  return (
    <section className={`rounded-xl p-4 ${canShare && !mine ? "border-4 border-violet-500 bg-violet-50" : "border border-slate-200 bg-white"}`} aria-labelledby="share-learning-heading">
      <h2 id="share-learning-heading" className="text-lg font-bold text-slate-900">What we learnt from this job</h2>
      {canShare && !mine && <p className="mt-1 text-sm font-semibold text-violet-900">{assistantName} asks: what did you learn? A minute now saves the next Technician hours.</p>}

      {visible.length > 0 && (
        <ul className="mt-3 space-y-2">
          {visible.map((item) => (
            <li key={item.id} className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm">
              {item.confirmed_cause && <p><strong>Cause:</strong> {item.confirmed_cause}</p>}
              {item.fix_that_worked && <p className="mt-1"><strong>Fix that worked:</strong> {item.fix_that_worked}</p>}
              {item.tip && <p className="mt-1"><strong>Tip:</strong> {item.tip}</p>}
              <p className="mt-1 text-xs text-slate-500">Shared by {item.shared_by_name}{item.ai_suggestion ? ` · AI suggestion: ${item.ai_suggestion.replace("_", " ")}` : ""}</p>
              {canHide && <button type="button" disabled={busy} onClick={() => void hide(item.id)} className="mt-2 rounded border border-slate-300 px-2 py-1 text-xs font-semibold text-slate-700">Hide</button>}
            </li>
          ))}
        </ul>
      )}
      {canHide && hidden.length > 0 && <p className="mt-2 text-xs text-slate-500">{hidden.length} hidden learning(s) kept for the record.</p>}

      {canShare && (
        <div className="mt-4 grid gap-3">
          <label className="text-sm font-medium">Confirmed cause<textarea rows={2} maxLength={1000} value={cause} onChange={(event) => setCause(event.target.value)} className={input} placeholder="What was actually wrong, e.g. charger voltage sensing lead broken; cells C14 and C15 shorted" /></label>
          <label className="text-sm font-medium">Fix that worked<textarea rows={2} maxLength={1000} value={fix} onChange={(event) => setFix(event.target.value)} className={input} placeholder="What fixed it, e.g. replaced the control board and the two cells; equalisation charge" /></label>
          <label className="text-sm font-medium">Tip for the next person<textarea rows={2} maxLength={1000} value={tip} onChange={(event) => setTip(event.target.value)} className={input} placeholder="Anything that would have saved you time or kept you safe" /></label>
          <label className="text-sm font-medium">Did an AI suggestion help? (optional)
            <select value={ai} onChange={(event) => setAi(event.target.value)} className={input}>
              <option value="">Not answered</option>
              <option value="right">It was right</option>
              <option value="partly">Partly right</option>
              <option value="wrong">It was wrong</option>
              <option value="not_used">No AI suggestion used</option>
            </select>
          </label>
          <div className="flex flex-wrap items-center gap-3">
            <button type="button" disabled={busy || !(cause.trim() || fix.trim() || tip.trim())} onClick={() => void share()} className="rounded-lg bg-violet-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">
              {busy ? "Saving…" : mine ? "Update what I shared" : "Share what I learnt"}
            </button>
            <span className="text-xs text-slate-500">Write at least one. Everyone who can see this Work Order will see it.</span>
          </div>
        </div>
      )}
      {message && <p role="status" className="mt-3 text-sm font-semibold text-emerald-800">{message}</p>}
      {error && <p role="alert" className="mt-3 text-sm font-semibold text-red-700">{error}</p>}
    </section>
  );
}
