"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

export type Endorsement = { id: string; stage: "submission" | "review"; endorser: string; statement: string; endorsed_at: string };

const STAGE_LABEL = { submission: "Before submission", review: "Before the Approver's review" } as const;

/**
 * D-11: a second Technician of the facility endorses the Work Order as authentic
 * (joint and several responsibility with the responsible Technician).
 */
export default function TechnicianEndorsement({ workOrderId, required, canEndorse, endorsements, stageSetting }: {
  workOrderId: string; required: boolean; canEndorse: boolean; endorsements: Endorsement[]; stageSetting: string;
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
    {endorsements.length > 0
      ? <ul className="mt-3 space-y-2 text-sm">{endorsements.map((item) => <li key={item.id} className="rounded-lg border border-amber-200 bg-white p-3">
          <p className="font-semibold">{item.endorser} · {STAGE_LABEL[item.stage]} · {new Date(item.endorsed_at).toLocaleString("en-SG")}</p>
          <p className="mt-1 whitespace-pre-wrap text-slate-700">{item.statement}</p>
        </li>)}</ul>
      : <p className="mt-3 text-sm text-slate-600">Not yet endorsed.</p>}
    {required && canEndorse && <form onSubmit={endorse} className="mt-4 space-y-3">
      <label className="block text-sm font-semibold">What did you check?
        <textarea required minLength={10} maxLength={1000} value={statement} onChange={(event) => setStatement(event.target.value)}
          placeholder="e.g. Inspected the site and the photos; the work and quotation are as recorded." className="mt-1 block w-full rounded border bg-white p-2 font-normal" />
      </label>
      <button disabled={busy || statement.trim().length < 10} className="min-h-11 rounded-lg bg-amber-700 px-4 text-sm font-bold text-white disabled:opacity-50">{busy ? "Recording…" : "Endorse as authentic"}</button>
    </form>}
    {message && <p role={failed ? "alert" : "status"} className={`mt-2 text-sm ${failed ? "text-red-700" : "text-emerald-700"}`}>{message}</p>}
  </section>;
}
