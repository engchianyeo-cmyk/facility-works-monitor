"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Technician = { id: string; name: string; detail?: string | null };

/**
 * Choose Technician 1 (does and records the work) while a Work Order is Draft or Awaiting Approval, or, with
 * which="second" (D-49, 10 Nov 2026), name Technician 2, the independent checker.
 */
export default function TechnicianPicker({ workOrderId, technicians, currentId, which = "first", excludeIds = [] }: {
  workOrderId: string; technicians: Technician[]; currentId: string | null; which?: "first" | "second"; excludeIds?: Array<string | null | undefined>;
}) {
  const router = useRouter();
  const [id, setId] = useState(currentId ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const second = which === "second";
  const choices = technicians.filter((technician) => !excludeIds.includes(technician.id));

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!id) return;
    setSaving(true); setError(null); setMessage(null);
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/${second ? "second-technician" : "technician"}`, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ technician_id: id }),
      });
      const result = await response.json();
      if (!response.ok) { setError(result.message ?? (second ? "Technician 2 could not be named." : "The Technician could not be assigned.")); return; }
      setMessage(second ? "Technician 2 named. They have been notified to work with Technician 1." : "Technician assigned. They have been notified.");
      router.refresh();
    } catch { setError("Unable to reach the Work Order service."); }
    finally { setSaving(false); }
  }

  return (
    <form onSubmit={submit} className="space-y-3">
      <label className="block text-sm font-bold text-violet-950">{second ? "Technician 2 (independent checker: checks and endorses the work)" : "Technician 1 (does and records the work)"}
        <select required value={id} onChange={(event) => setId(event.target.value)} className="mt-1 min-h-11 w-full rounded-lg border border-slate-300 bg-white px-3 text-sm">
          <option value="">{second ? "Select another active Technician at this facility" : "Select an active Technician at this facility"}</option>
          {choices.map((technician) => <option key={technician.id} value={technician.id}>{technician.name}{technician.detail ? ` · ${technician.detail}` : ""}</option>)}
        </select>
      </label>
      {choices.length === 0 && <p className="text-sm text-amber-700">No other active Technicians are available.</p>}
      {error && <p className="text-sm text-red-700" role="alert">{error}</p>}
      {message && <p className="text-sm text-emerald-700" role="status">{message}</p>}
      <button disabled={saving || !id || id === currentId} className="min-h-11 rounded-lg bg-violet-700 px-4 text-sm font-bold text-white disabled:opacity-50">
        {saving ? (second ? "Naming…" : "Assigning…") : second ? (currentId ? "Change Technician 2" : "Name Technician 2") : "Assign Technician"}
      </button>
    </form>
  );
}
