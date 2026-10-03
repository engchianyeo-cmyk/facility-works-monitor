"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

export default function ProcurementPolicy({ versionId, threshold }: { versionId: string; threshold: number }) {
  const router = useRouter();
  const [amount, setAmount] = useState(String(threshold));
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);
  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setMessage("");
    try {
      const response = await fetch("/api/administration/procurement-policy", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ threshold: Number(amount), reason, expected_version: versionId }) });
      const result = await response.json();
      setFailed(!response.ok);
      setMessage(response.ok ? "Company policy saved. Existing Work Orders retain their policy version." : result.message ?? "Company policy could not be saved.");
      if (response.ok) { setReason(""); router.refresh(); }
    } catch { setFailed(true); setMessage("Company policy could not be saved. Try again."); }
    finally { setBusy(false); }
  }
  return <form onSubmit={save} className="space-y-4 rounded-xl border bg-white p-6">
    <p className="text-slate-600">New procurement controls require one quotation below this threshold and three quotations at or above it. Existing controls and historical decisions retain their original policy.</p>
    <label className="block font-semibold">Low-value threshold (S$)<input required type="number" min="0.01" max="999999999999.99" step="0.01" value={amount} onChange={event => setAmount(event.target.value)} className="mt-2 block min-h-11 rounded border p-2" /></label>
    <label className="block font-semibold">Reason for policy change<textarea required maxLength={1000} value={reason} onChange={event => setReason(event.target.value)} className="mt-2 block w-full rounded border p-2" /></label>
    <button disabled={busy} className="min-h-11 rounded bg-blue-700 px-5 font-bold text-white disabled:opacity-50">{busy ? "Saving…" : "Save company policy"}</button>
    {message && <p role={failed ? "alert" : "status"}>{message}</p>}
  </form>;
}
