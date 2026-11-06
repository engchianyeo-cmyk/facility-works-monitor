"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

type Score = { capacity: string; quality: number; onTime: number; safety: number; documents: number; price: number; comments: string | null };
const CAPACITY: Record<string, string> = { facility_manager: "Facility Manager", approver: "Approver", technician_1: "Technician 1", technician_2: "Technician 2" };
const CRITERIA: Array<[string, string, string]> = [
  ["quality", "Quality of work", "Workmanship and whether the fault was properly fixed"],
  ["on_time", "On time", "Arrived and finished when agreed"],
  ["safety", "Safety and housekeeping", "Permit, isolation, PPE, area left clean (a 1 fails the trial)"],
  ["documents", "Documents", "Quotation, report and invoice accurate and complete"],
  ["price", "Price", "Fair against the market for this work"],
];

/** D-37 (6 Nov 2026): score a trial contractor's job once it is approved as Completed. */
export default function TrialEvaluation({ workOrderId, contractor, scores, canScore }: { workOrderId: string; contractor: string; scores: Score[]; canScore: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const values = Object.fromEntries(CRITERIA.map(([key]) => [key, Number(form.get(key))]));
    setBusy(true); setError(null);
    try {
      const response = await fetch("/api/contractor-admission", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "score", work_order_id: workOrderId, scores: { ...values, comments: String(form.get("comments") ?? "").trim() } }) });
      const result = await response.json().catch(() => ({})) as { message?: string };
      if (!response.ok) throw new Error(result.message ?? "The score could not be saved.");
      router.refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "The score could not be saved.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <section id="trial-evaluation" className={`rounded-xl border-2 bg-white p-4 text-sm ${canScore ? "border-red-500" : "border-slate-200"}`}>
      {canScore && <p className="mb-2 inline-block rounded bg-red-600 px-2 py-1 text-xs font-black uppercase text-white">Action needed — score this trial job</p>}
      <h3 className="text-lg font-black">Trial contractor evaluation — {contractor}</h3>
      <p className="mt-1 text-slate-700">{contractor} is on trial at this facility. Each completed trial job is scored 1 (poor) to 5 (excellent). Two scored jobs with an average of at least 3.5, and no 1 on safety, are needed for admission to the facility&apos;s list.</p>
      {scores.length > 0 && (
        <table className="mt-2 w-full text-left text-xs"><thead><tr><th>By</th><th>Quality</th><th>On time</th><th>Safety</th><th>Documents</th><th>Price</th><th>Comments</th></tr></thead>
          <tbody>{scores.map((score, index) => <tr key={index} className="border-t border-slate-200"><td>{CAPACITY[score.capacity] ?? score.capacity}</td><td>{score.quality}</td><td>{score.onTime}</td><td>{score.safety}</td><td>{score.documents}</td><td>{score.price}</td><td>{score.comments ?? ""}</td></tr>)}</tbody></table>
      )}
      {canScore && (
        <form onSubmit={submit} className="mt-3 space-y-2">
          {CRITERIA.map(([key, label, hint]) => (
            <fieldset key={key} className="flex flex-wrap items-center gap-3 rounded border border-slate-200 p-2">
              <legend className="sr-only">{label}</legend>
              <span className="w-56"><b>{label}</b><br /><span className="text-xs text-slate-600">{hint}</span></span>
              {[1, 2, 3, 4, 5].map((value) => <label key={value} className="flex items-center gap-1"><input type="radio" name={key} value={value} required />{value}</label>)}
            </fieldset>
          ))}
          <label className="block font-bold">Comments<textarea name="comments" rows={2} maxLength={2000} className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 font-normal" /></label>
          {error && <p role="alert" className="font-semibold text-red-700">{error}</p>}
          <button type="submit" disabled={busy} className="rounded-lg bg-red-600 px-4 py-2 font-bold text-white hover:bg-red-700 disabled:opacity-50">{busy ? "Saving…" : "Save my scores"}</button>
        </form>
      )}
    </section>
  );
}
