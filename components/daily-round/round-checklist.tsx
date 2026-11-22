"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { rangeText, readingStatus, roundProgress, type RoundCheck, type RoundResult } from "@/lib/daily-round";

type Draft = { ok: boolean | null; reading: string; note: string };

/** M36: tick off the Daily round, item by item; each answer is saved straight away.
 *  M38: each reading shows its normal range; outside it the Technician is warned, and OK needs a reason. */
export default function RoundChecklist({ workOrderId, checks, results, canRecord, closed }: { workOrderId: string; checks: RoundCheck[]; results: RoundResult[]; canRecord: boolean; closed: boolean }) {
  const router = useRouter();
  const initial = useMemo(() => Object.fromEntries(results.map((r) => [r.item_id, { ok: r.ok, reading: r.reading ?? "", note: r.note ?? "" }])), [results]);
  const [drafts, setDrafts] = useState<Record<string, Draft>>(initial);
  const [saved, setSaved] = useState<Record<string, boolean>>(Object.fromEntries(results.map((r) => [r.item_id, true])));
  const [busy, setBusy] = useState("");
  const [error, setError] = useState<Record<string, string>>({});
  const [note, setNote] = useState("");
  const [done, setDone] = useState<string | null>(null);
  const editable = canRecord && !closed;
  const progress = roundProgress(checks, checks.flatMap((c) => c.items).filter((i) => saved[i.id]).map((i) => ({ item_id: i.id, ok: drafts[i.id]?.ok ?? true, reading: null, note: null, recorded_at: "" })));

  const draft = (id: string): Draft => drafts[id] ?? { ok: null, reading: "", note: "" };
  function change(id: string, patch: Partial<Draft>) {
    setDrafts((d) => ({ ...d, [id]: { ...draft(id), ...patch } }));
    setSaved((s) => ({ ...s, [id]: false }));
  }
  async function save(id: string, ok: boolean) {
    const current = { ...draft(id), ok };
    setDrafts((d) => ({ ...d, [id]: current }));
    setBusy(id); setError((e) => ({ ...e, [id]: "" }));
    const response = await fetch("/api/daily-round/record", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ work_order_id: workOrderId, item_id: id, ok, reading: current.reading, note: current.note }) });
    const body = await response.json().catch(() => ({})) as { error?: string };
    setBusy("");
    if (!response.ok) { setError((e) => ({ ...e, [id]: body.error ?? "Not saved." })); setSaved((s) => ({ ...s, [id]: false })); return; }
    setSaved((s) => ({ ...s, [id]: true }));
  }
  async function complete() {
    setBusy("complete");
    const response = await fetch("/api/daily-round/complete", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ work_order_id: workOrderId, note }) });
    const body = await response.json().catch(() => ({})) as { error?: string; faults?: number };
    setBusy("");
    if (!response.ok) { setDone(body.error ?? "The round could not be completed."); return; }
    setDone(body.faults ? `Round completed with ${body.faults} item(s) Not OK. Report each fault as a Work Order.` : "Round completed. Everything was OK.");
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <p className="text-sm font-bold text-slate-700">{progress.done} of {progress.total} recorded{progress.faults ? ` · ${progress.faults} Not OK` : ""}</p>
      {checks.filter((c) => c.active).map((check) => (
        <section key={check.id} className="rounded-xl border border-slate-200 bg-white">
          <h3 className="border-b border-slate-100 px-4 py-3 font-black text-slate-900">{check.title}{check.equipment && <span className="ml-2 font-mono text-xs font-bold text-blue-700">{check.equipment}</span>}</h3>
          <ul className="divide-y divide-slate-100">
            {check.items.filter((i) => i.active).map((item) => {
              const d = draft(item.id);
              const normal = rangeText(item);
              const status = readingStatus(item, d.reading);
              const outside = status === "low" || status === "high";
              // Outside the range, OK is allowed only with a reason (the database checks this too).
              const askWhyOk = outside && d.ok !== false;
              return (
                <li key={item.id} className="grid gap-2 p-4 sm:grid-cols-[1fr_auto] sm:items-center">
                  <div>
                    <p className="font-semibold text-slate-900">{item.label}</p>
                    {(normal || item.guide) && (
                      <p className="mt-1 text-sm text-slate-700">
                        {normal && <span className="mr-2 inline-block rounded-md bg-slate-100 px-2 py-0.5 font-bold text-slate-800">Normal: {normal}</span>}
                        {item.guide && <span className="text-slate-600">{item.guide}</span>}
                      </p>
                    )}
                    {item.unit && <label className="mt-1 flex items-center gap-2 text-sm">Reading<input inputMode="decimal" value={d.reading} disabled={!editable} aria-invalid={outside || status === "not-number"} onChange={(e) => change(item.id, { reading: e.target.value })} className={`min-h-11 w-28 rounded-lg border p-2 ${outside ? "border-amber-500 bg-amber-50" : status === "in" ? "border-emerald-500" : ""}`} /><span className="text-slate-600">{item.unit}</span>
                      {status === "in" && <span className="text-xs font-bold text-emerald-800">Within normal</span>}</label>}
                    {outside && <p role="status" className="mt-1 rounded-md bg-amber-50 p-2 text-sm font-semibold text-amber-900">{status === "high" ? "Above" : "Below"} the normal range ({normal}). Choose Not OK and say what is wrong — or, if it is still OK, say why.</p>}
                    {status === "not-number" && <p className="mt-1 text-sm font-semibold text-red-700">Enter the reading as a number, e.g. 7.5.</p>}
                    {d.ok === false && <label className="mt-1 block text-sm">What is wrong *<input value={d.note} disabled={!editable} onChange={(e) => change(item.id, { note: e.target.value })} className="mt-1 min-h-11 w-full rounded-lg border p-2" /></label>}
                    {askWhyOk && <label className="mt-1 block text-sm">Why it is still OK *<input value={d.note} disabled={!editable} onChange={(e) => change(item.id, { note: e.target.value })} placeholder="e.g. door open for loading, back in range in 10 min" className="mt-1 min-h-11 w-full rounded-lg border p-2" /></label>}
                    {error[item.id] && <p role="alert" className="mt-1 text-sm font-semibold text-red-700">{error[item.id]}</p>}
                  </div>
                  <div className="flex items-center gap-2">
                    <button type="button" disabled={!editable || busy === item.id || status === "not-number" || (outside && d.note.trim().length < 3)} title={outside && d.note.trim().length < 3 ? "Outside the normal range: say why it is still OK first" : undefined} onClick={() => void save(item.id, true)} className={`min-h-11 rounded-lg px-4 text-sm font-black ${d.ok === true && saved[item.id] ? "bg-emerald-700 text-white" : "border border-emerald-600 text-emerald-800"} disabled:opacity-60`}>OK</button>
                    <button type="button" disabled={!editable || busy === item.id} onClick={() => d.ok === false && d.note.trim() ? void save(item.id, false) : change(item.id, { ok: false })} className={`min-h-11 rounded-lg px-4 text-sm font-black ${d.ok === false && saved[item.id] ? "bg-red-700 text-white" : "border border-red-600 text-red-800"} disabled:opacity-60`}>{d.ok === false && !saved[item.id] ? "Save Not OK" : "Not OK"}</button>
                    <span className="w-14 text-xs text-slate-500">{busy === item.id ? "Saving…" : saved[item.id] ? "Saved" : ""}</span>
                  </div>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
      {editable && (
        <div className="rounded-xl border border-blue-200 bg-blue-50 p-4">
          <label className="block text-sm font-bold">Note for the round (optional)<input value={note} onChange={(e) => setNote(e.target.value)} className="mt-1 min-h-11 w-full rounded-lg border bg-white p-2" /></label>
          <button type="button" disabled={!progress.complete || busy === "complete"} onClick={() => void complete()} className="mt-3 min-h-11 rounded-lg bg-blue-700 px-5 font-black text-white disabled:opacity-50">{busy === "complete" ? "Completing…" : progress.complete ? "Complete the round" : `Record all items to complete (${progress.total - progress.done} left)`}</button>
        </div>
      )}
      {done && <p role="status" className="rounded-lg border border-slate-200 bg-white p-3 text-sm font-semibold">{done} <Link href="/work-orders/new" className="text-blue-700 underline">Report a fault</Link></p>}
    </div>
  );
}
