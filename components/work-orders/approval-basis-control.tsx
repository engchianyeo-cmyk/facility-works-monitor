"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

const input = "mt-1 min-h-11 w-full rounded-lg border border-blue-300 bg-white px-3 text-sm";

export default function ApprovalBasisControl({ workOrderId }: { workOrderId: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true); setError(null); setMessage(null);
    const form = new FormData(event.currentTarget);
    const payload = {
      proposed_cost: Number(form.get("proposed_cost")),
      cost_basis: String(form.get("cost_basis") ?? "").trim(),
      execution_arrangement: String(form.get("execution_arrangement") ?? "").trim(),
      safety_isolation_information: String(form.get("safety_isolation_information") ?? "").trim(),
    };
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/readiness`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload) });
      const body = await response.json();
      if (!response.ok || !body.ok) throw new Error(body.message ?? "Approval basis could not be saved.");
      setMessage("Structured approval basis saved.");
      router.refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Approval basis could not be saved.");
    } finally {
      setBusy(false);
    }
  }

  return <section className="rounded-xl border-2 border-blue-200 bg-blue-50 p-5" aria-labelledby="approval-basis-heading">
    <h2 id="approval-basis-heading" className="font-black text-blue-950">Pre-work Approval Basis</h2>
    <form onSubmit={submit} className="mt-4 grid gap-4 sm:grid-cols-2">
      <label className="text-sm font-bold text-blue-950">Proposed cost (SGD)<input name="proposed_cost" required type="number" min="0" step="0.01" className={input}/></label>
      <label className="text-sm font-bold text-blue-950">Cost basis<input name="cost_basis" required placeholder="Contractor quotation" className={input}/></label>
      <label className="text-sm font-bold text-blue-950">Execution arrangement<input name="execution_arrangement" required placeholder="Assigned Technician with contractor" className={input}/></label>
      <label className="text-sm font-bold text-blue-950">Safety / isolation information<input name="safety_isolation_information" required placeholder="State permit and isolation controls" className={input}/></label>
      <button disabled={busy} className="min-h-11 rounded-lg bg-blue-700 px-4 font-black text-white disabled:opacity-50 sm:col-span-2">{busy?"Saving...":"Save Approval Basis"}</button>
    </form>
    {error&&<p role="alert" className="mt-3 text-sm font-bold text-red-800">{error}</p>}
    {message&&<p role="status" className="mt-3 text-sm font-bold text-emerald-800">{message}</p>}
  </section>;
}
