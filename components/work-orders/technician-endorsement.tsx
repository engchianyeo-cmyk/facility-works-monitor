"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

export type Endorsement = { id: string; stage: "submission" | "review"; endorser: string; statement: string; endorsed_at: string };

const STAGE_LABEL = { submission: "Before submission", review: "Before the Approver's review" } as const;

/**
 * D-11: a second Technician of the facility endorses the Work Order as authentic
 * (joint and several responsibility with the responsible Technician).
 */
type FinalCostSummary = { final_contractor_amount: number; variation_order: boolean | null; variation_justification: string | null; documents: number };
const money = (value: number) => `S$${Number(value).toLocaleString("en-SG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export type QuotationSummary = { id: string; contractor: string; amount: number; reference: string | null; awarded: boolean };

/** D-25: the independent checker's minimum checks, by endorsement stage. */
export function checkerChecks(stage: "submission" | "review", inHouse: boolean, competing: boolean) {
  const checks: Array<{ key: string; label: string }> = stage === "review" ? [
    { key: "supervised_work", label: "I verified on site that the work has been done and that the materials installed and the labour performed match the contractor's final quotation. (You need not have supervised the work yourself.)" },
    ...(inHouse ? [] : [{ key: "final_quotation", label: "I checked that the contractor's final quotation justifies the work done and the materials installed (including the revised quotation and its justification, if there is a variation order)." }]),
    { key: "field_evidence", label: "I reviewed the site field evidence (After photos and records) of the work completed." },
  ] : [
    { key: "site_evidence", label: "I reviewed the site evidence (Before photos) and the condition reported." },
    { key: "quotation_scope", label: "I checked that the quotation covers the work actually needed." },
  ];
  if (competing) checks.push({ key: "award_basis", label: "I reviewed the awarded contractor's quotation against the competing quotations, and the basis of the award is justified." });
  return checks;
}

export default function TechnicianEndorsement({ workOrderId, required, canEndorse, endorsements, stageSetting, blocked = null, superseded = false, finalCost = null, stage = "review", inHouse = false, quotations = [] }: {
  workOrderId: string; required: boolean; canEndorse: boolean; endorsements: Endorsement[]; stageSetting: string;
  blocked?: { code: string; message: string } | null; superseded?: boolean; finalCost?: FinalCostSummary | null;
  stage?: "submission" | "review"; inHouse?: boolean; quotations?: QuotationSummary[];
}) {
  const router = useRouter();
  const competing = quotations.length > 1;
  const checks = checkerChecks(stage, inHouse, competing);
  const [ticked, setTicked] = useState<Record<string, boolean>>({});
  const [awardNote, setAwardNote] = useState("");
  const allTicked = checks.every((check) => ticked[check.key]) && (!competing || awardNote.trim().length >= 10);
  const [statement, setStatement] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);

  async function endorse(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setMessage("");
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/endorsement`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ statement, checklist: { ...Object.fromEntries(checks.map((check) => [check.key, Boolean(ticked[check.key])])), ...(competing ? { award_basis_note: awardNote.trim() } : {}) } }),
      });
      const result = await response.json();
      setFailed(!response.ok);
      setMessage(response.ok ? (result.code === "NO_CHANGE" ? "No endorsement is needed at this stage." : "Endorsement recorded.") : result.message ?? "The endorsement could not be recorded.");
      if (response.ok) { setStatement(""); setTicked({}); setAwardNote(""); router.refresh(); }
    } catch { setFailed(true); setMessage("Unable to reach the Work Order service."); }
    finally { setBusy(false); }
  }

  const actionNeeded = Boolean(required && canEndorse && !blocked);
  return <section id="technician-endorsement" className={`rounded-xl p-5 ${actionNeeded ? "border-4 border-red-600 bg-amber-50 shadow-lg" : "border border-amber-200 bg-amber-50"}`} aria-labelledby="technician-endorsement-title">
    {actionNeeded && <p className="mb-3 inline-block rounded bg-red-600 px-3 py-1 text-sm font-black uppercase tracking-wide text-white">Action needed — your endorsement</p>}
    <h2 id="technician-endorsement-title" className="font-semibold text-amber-950">Second Technician endorsement</h2>
    <p className="mt-1 text-sm text-amber-900">A second Technician of this facility confirms the Work Order is authentic. Both Technicians share joint and several responsibility. This facility: {stageSetting}.</p>
    {required && <p className="mt-2 text-sm font-bold text-amber-900">Endorsement is needed now.</p>}
    {superseded && <p role="alert" className="mt-2 rounded border border-red-200 bg-white p-2 text-sm font-semibold text-red-800">The final cost or variation order changed after the last endorsement, so it no longer counts. Check the changes and endorse again.</p>}
    {finalCost && <div className="mt-3 rounded-lg border border-amber-200 bg-white p-3 text-sm" aria-label="Final cost being endorsed">
      <p className="font-semibold">You are endorsing this final cost</p>
      <p className="mt-1">Final contractor charge: <strong>{money(finalCost.final_contractor_amount)}</strong></p>
      <p>Variation order: <strong>{finalCost.variation_order === true ? "Yes" : finalCost.variation_order === false ? "No — price unchanged (approved quotation)" : "Not stated"}</strong></p>
      {finalCost.variation_order === true && <p>Justification: {finalCost.variation_justification ?? "—"}</p>}
      {finalCost.variation_order === true && <p>Revised quotation: {finalCost.documents > 0 ? <a href="#final-cost-heading" className="font-semibold text-blue-700 underline">attached — open it under Final Cost Reconciliation</a> : "not attached yet"}</p>}
    </div>}
    {required && blocked && <p role="status" className="mt-2 text-sm font-semibold text-amber-900">Waiting: {blocked.message}</p>}
    {endorsements.length > 0
      ? <ul className="mt-3 space-y-2 text-sm">{endorsements.map((item) => <li key={item.id} className="rounded-lg border border-amber-200 bg-white p-3">
          <p className="font-semibold">{item.endorser} · {STAGE_LABEL[item.stage]} · {new Date(item.endorsed_at).toLocaleString("en-SG")}</p>
          <p className="mt-1 whitespace-pre-wrap text-slate-700">{item.statement}</p>
        </li>)}</ul>
      : <p className="mt-3 text-sm text-slate-600">Not yet endorsed.</p>}
    {required && canEndorse && !blocked && <form onSubmit={endorse} className="mt-4 space-y-3">
      <div className="rounded-lg border-2 border-amber-400 bg-white p-4">
        <p className="font-black text-amber-950">Your responsibility as the independent checker</p>
        <p className="mt-1 text-sm text-slate-700">You confirm, independently of the responsible Technician, that this Work Order is authentic. You share joint and several responsibility for what is recorded. If anything does not match, do not endorse: tell the responsible Technician or the Approver.</p>
        {quotations.length > 0 && <div className="mt-3 text-sm">
          <p className="font-semibold">Quotations{competing ? " to compare" : ""}</p>
          <ul className="mt-1 divide-y rounded border">{quotations.map((quote) => <li key={quote.id} className="flex flex-wrap justify-between gap-2 px-3 py-2">
            <span>{quote.contractor}{quote.reference ? ` · ${quote.reference}` : ""}{quote.awarded && <span className="ml-2 rounded bg-blue-100 px-2 py-0.5 text-xs font-bold text-blue-800">Awarded</span>}</span>
            <span className="font-semibold">{money(quote.amount)}</span>
          </li>)}</ul>
          <p className="mt-1 text-xs text-slate-600">Open the quotation documents under Proposal / Quotation and Quotation comparison.</p>
        </div>}
        <fieldset className="mt-3 space-y-2">
          <legend className="text-sm font-semibold">Tick each check you have done</legend>
          {checks.map((check) => <label key={check.key} className="flex min-h-11 cursor-pointer items-start gap-2 text-sm">
            <input type="checkbox" checked={Boolean(ticked[check.key])} onChange={(event) => setTicked((current) => ({ ...current, [check.key]: event.target.checked }))} className="mt-1 h-5 w-5" />
            <span>{check.label}</span>
          </label>)}
        </fieldset>
        {competing && <label className="mt-3 block text-sm font-semibold">Basis of the award (why this contractor&apos;s quotation was chosen)
          <textarea required minLength={10} maxLength={1000} value={awardNote} onChange={(event) => setAwardNote(event.target.value)} placeholder="e.g. Lowest compliant price; same scope as the other two; contractor available for the weekend shutdown." className="mt-1 block w-full rounded border bg-white p-2 font-normal" />
        </label>}
        <p className="mt-2 text-xs font-semibold text-slate-600">{checks.filter((check) => ticked[check.key]).length} of {checks.length} checks ticked</p>
      </div>
      <label className="block text-sm font-semibold">What did you check?
        <textarea required minLength={10} maxLength={1000} value={statement} onChange={(event) => setStatement(event.target.value)}
          placeholder="e.g. Inspected the site and the photos; the work, final cost and any variation order are as recorded." className="mt-1 block w-full rounded border bg-white p-2 font-normal" />
      </label>
      <button disabled={busy || statement.trim().length < 10 || !allTicked} className="min-h-11 rounded-lg bg-amber-700 px-4 text-sm font-bold text-white disabled:opacity-50">{busy ? "Recording…" : "Endorse as authentic"}</button>
    </form>}
    {message && <p role={failed ? "alert" : "status"} className={`mt-2 text-sm ${failed ? "text-red-700" : "text-emerald-700"}`}>{message}</p>}
  </section>;
}
