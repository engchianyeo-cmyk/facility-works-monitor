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

export default function TechnicianEndorsement({ workOrderId, required, canEndorse, endorsements, stageSetting, blocked = null, superseded = false, finalCost = null }: {
  workOrderId: string; required: boolean; canEndorse: boolean; endorsements: Endorsement[]; stageSetting: string;
  blocked?: { code: string; message: string } | null; superseded?: boolean; finalCost?: FinalCostSummary | null;
}) {
  const router = useRouter();
  const [statement, setStatement] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);

  async function endorse(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setMessage("");
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/endorsement`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ statement }),
      });
      const result = await response.json();
      setFailed(!response.ok);
      setMessage(response.ok ? (result.code === "NO_CHANGE" ? "No endorsement is needed at this stage." : "Endorsement recorded.") : result.message ?? "The endorsement could not be recorded.");
      if (response.ok) { setStatement(""); router.refresh(); }
    } catch { setFailed(true); setMessage("Unable to reach the Work Order service."); }
    finally { setBusy(false); }
  }

  return <section id="technician-endorsement" className="rounded-xl border border-amber-200 bg-amber-50 p-5" aria-labelledby="technician-endorsement-title">
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
      <label className="block text-sm font-semibold">What did you check?
        <textarea required minLength={10} maxLength={1000} value={statement} onChange={(event) => setStatement(event.target.value)}
          placeholder="e.g. Inspected the site and the photos; the work, final cost and any variation order are as recorded." className="mt-1 block w-full rounded border bg-white p-2 font-normal" />
      </label>
      <button disabled={busy || statement.trim().length < 10} className="min-h-11 rounded-lg bg-amber-700 px-4 text-sm font-bold text-white disabled:opacity-50">{busy ? "Recording…" : "Endorse as authentic"}</button>
    </form>}
    {message && <p role={failed ? "alert" : "status"} className={`mt-2 text-sm ${failed ? "text-red-700" : "text-emerald-700"}`}>{message}</p>}
  </section>;
}
