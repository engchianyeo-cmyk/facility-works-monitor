"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Technician = { id: string; name: string; detail?: string | null };

/** Choose the field-witness Technician while a Work Order is Draft or Awaiting Approval. */
export default function TechnicianPicker({ workOrderId, technicians, currentId }: { workOrderId: string; technicians: Technician[]; currentId: string | null }) {
  const router = useRouter();
  const [id, setId] = useState(currentId ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!id) return;
    setSaving(true); setError(null); setMessage(null);
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/technician`, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ technician_id: id }),
      });
      const result = await response.json();
      if (!response.ok) { setError(result.message ?? "The Technician could not be assigned."); return; }
      setMessage("Technician assigned. They have been notified.");
      router.refresh();
    } catch { setError("Unable to reach the Work Order service."); }
    finally { setSaving(false); }
  }

  return (
    <form onSubmit={submit} className="space-y-3">
      <label className="block text-sm font-bold text-violet-950">Field-witness Technician
        <select required value={id} onChange={(event) => setId(event.target.value)} className="mt-1 min-h-11 w-full rounded-lg border border-slate-300 bg-white px-3 text-sm">
          <option value="">Select an active Technician at this facility</option>
          {technicians.map((technician) => <option key={technician.id} value={technician.id}>{technician.name}{technician.detail ? ` · ${technician.detail}` : ""}</option>)}
        </select>
      </label>
      {technicians.length === 0 && <p className="text-sm text-amber-700">No active Technicians are available.</p>}
      {error && <p className="text-sm text-red-700" role="alert">{error}</p>}
      {message && <p className="text-sm text-emerald-700" role="status">{message}</p>}
      <button disabled={saving || !id || id === currentId} className="min-h-11 rounded-lg bg-violet-700 px-4 text-sm font-bold text-white disabled:opacity-50">{saving ? "Assigning…" : "Assign Technician"}</button>
    </form>
  );
}
