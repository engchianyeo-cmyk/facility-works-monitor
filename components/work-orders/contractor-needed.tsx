"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

type Request = { id: string; service: string; reason: string; status: string; raisedAt: string };
const input = "w-full rounded-lg border border-slate-300 px-3 py-2 text-sm";

/** D-37 (6 Nov 2026): Technician 1 asks for a contractor when none suitable is listed for this Work Order. */
export default function ContractorNeeded({ workOrderId, requests }: { workOrderId: string; requests: Request[] }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true); setError(null);
    try {
      const response = await fetch("/api/contractor-admission", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "request", work_order_id: workOrderId, service: String(form.get("service") ?? "").trim(), reason: String(form.get("reason") ?? "").trim() }) });
      const result = await response.json().catch(() => ({})) as { message?: string };
      if (!response.ok) throw new Error(result.message ?? "The request could not be sent.");
      setOpen(false);
      router.refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "The request could not be sent.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="rounded-xl border border-slate-200 bg-white p-4 text-sm">
      <h3 className="font-black">No suitable contractor in the list?</h3>
      <p className="mt-1 text-slate-700">Ask for one. The Facility Manager and Procurement Manager are asked to recommend and approve a contractor; it then appears in Prepare Proposal as a trial contractor.</p>
      {requests.length > 0 && (
        <ul className="mt-2 space-y-1">
          {requests.map((request) => <li key={request.id} className="rounded border border-slate-200 bg-slate-50 p-2"><b>{request.service}</b> — {request.status === "open" ? "waiting for a recommendation" : request.status === "answered" ? "contractor recommended; being approved" : "closed"}<br /><span className="text-slate-600">{request.reason}</span></li>)}
        </ul>
      )}
      {open ? (
        <form onSubmit={submit} className="mt-3 space-y-2">
          <label className="block font-bold">Service needed<input name="service" required minLength={2} className={`${input} mt-1 font-normal`} placeholder="e.g. Solar PV and inverters" /></label>
          <label className="block font-bold">Why no listed contractor is suitable<textarea name="reason" required minLength={5} rows={2} className={`${input} mt-1 font-normal`} placeholder="e.g. Only a general building contractor is listed; this needs a solar inverter specialist." /></label>
          {error && <p role="alert" className="font-semibold text-red-700">{error}</p>}
          <div className="flex gap-2">
            <button type="submit" disabled={busy} className="rounded-lg bg-blue-700 px-4 py-2 font-bold text-white disabled:opacity-50">{busy ? "Sending…" : "Send Contractor needed"}</button>
            <button type="button" onClick={() => setOpen(false)} className="rounded-lg border border-slate-300 px-4 py-2">Back</button>
          </div>
        </form>
      ) : <button type="button" onClick={() => setOpen(true)} className="mt-3 rounded-lg border border-slate-300 bg-white px-4 py-2 font-bold">Contractor needed</button>}
    </section>
  );
}
