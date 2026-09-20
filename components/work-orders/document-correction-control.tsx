"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

export default function DocumentCorrectionControl({ workOrderId, role, status, openReason }: { workOrderId: string; role: string; status: string; openReason: string | null }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const authorized = ["approver", "supervisor", "facility_manager", "administrator"].includes(role);
  const eligible = ["completed", "reviewed", "closed"].includes(status);
  if (!eligible && !openReason) return null;

  async function submit(event: FormEvent<HTMLFormElement>, operation: "open" | "close") {
    event.preventDefault(); setBusy(true); setMessage(null);
    const form = new FormData(event.currentTarget);
    const response = await fetch(`/api/work-orders/${workOrderId}/document-correction`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ operation, reason: form.get("reason"), note: form.get("note") }) });
    const result = await response.json();
    if (!response.ok || !result.ok) setMessage(result.message ?? "Correction update failed.");
    else { setMessage(operation === "open" ? "Supporting-document correction opened." : "Correction verified and closed."); router.refresh(); }
    setBusy(false);
  }

  return <section className="rounded border border-amber-300 bg-amber-50 p-5" aria-labelledby="document-correction-heading">
    <h2 id="document-correction-heading" className="font-black text-amber-950">Supporting-document correction</h2>
    {openReason ? <><p className="mt-1 text-sm text-amber-900">Open: {openReason}. The original completion and review history remains unchanged.</p>{authorized && <form onSubmit={(event) => void submit(event, "close")} className="mt-4 flex flex-wrap items-end gap-3"><label className="min-w-64 flex-1 text-sm font-bold">Verification note<input name="note" required className="mt-1 min-h-11 w-full rounded border border-amber-300 bg-white px-3" /></label><button disabled={busy} className="min-h-11 rounded bg-amber-800 px-4 font-bold text-white">Verify Documents & Close Correction</button></form>}</> : authorized ? <form onSubmit={(event) => void submit(event, "open")} className="mt-3 flex flex-wrap items-end gap-3"><label className="min-w-64 flex-1 text-sm font-bold">Correction reason<input name="reason" required defaultValue="Mandatory supporting documents were missing from the completed Work Order." className="mt-1 min-h-11 w-full rounded border border-amber-300 bg-white px-3" /></label><button disabled={busy} className="min-h-11 rounded bg-amber-800 px-4 font-bold text-white">Open Document Correction</button></form> : <p className="mt-1 text-sm text-amber-900">Authorized management must open a correction before the assigned Technician can add missing documents.</p>}
    {message && <p role="status" className="mt-3 text-sm font-bold text-amber-950">{message}</p>}
  </section>;
}
