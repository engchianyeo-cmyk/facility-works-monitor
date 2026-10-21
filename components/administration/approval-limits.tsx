"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { roleLabel } from "@/lib/product-terminology";

const ROLES = ["approver", "supervisor", "facility_manager"] as const;

export default function ApprovalLimits({ versionId, limits }: { versionId: string; limits: Record<string, number | null> }) {
  const router = useRouter();
  const [values, setValues] = useState<Record<string, string>>(Object.fromEntries(ROLES.map((role) => [role, String(limits[role] ?? 0)])));
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);
  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setMessage("");
    try {
      const response = await fetch("/api/administration/approval-limits", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ limits: Object.fromEntries(ROLES.map((role) => [role, Number(values[role])])), reason, expected_version: versionId }),
      });
      const result = await response.json();
      setFailed(!response.ok);
      setMessage(response.ok ? "Approval limits saved. Work Orders approved earlier keep the limits in force when they were approved." : result.message ?? "Approval limits could not be saved.");
      if (response.ok) { setReason(""); router.refresh(); }
    } catch { setFailed(true); setMessage("Approval limits could not be saved. Try again."); }
    finally { setBusy(false); }
  }
  return <form onSubmit={save} className="space-y-4 rounded-xl border bg-white p-6">
    <p className="text-slate-600">The highest amount each role may approve — for the quotation when approving work to proceed, and for the final cost when approving work as Completed. The Administrator has no limit.</p>
    <div className="grid gap-4 sm:grid-cols-3">
      {ROLES.map((role) => (
        <label key={role} className="block font-semibold">{roleLabel(role)} (S$)
          <input required type="number" min="0" max="999999999999.99" step="0.01" value={values[role]} onChange={(event) => setValues((current) => ({ ...current, [role]: event.target.value }))} className="mt-2 block min-h-11 w-full rounded border p-2" />
        </label>
      ))}
    </div>
    <label className="block font-semibold">Reason for change<textarea required maxLength={1000} value={reason} onChange={(event) => setReason(event.target.value)} className="mt-2 block w-full rounded border p-2" /></label>
    <button disabled={busy} className="min-h-11 rounded bg-blue-700 px-5 font-bold text-white disabled:opacity-50">{busy ? "Saving…" : "Save approval limits"}</button>
    {message && <p role={failed ? "alert" : "status"}>{message}</p>}
  </form>;
}
