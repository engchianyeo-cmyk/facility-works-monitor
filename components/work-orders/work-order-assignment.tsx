"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { AssignmentType } from "@/lib/work-orders/types";

type Assignee = { id: string; name: string; detail?: string | null };

export default function WorkOrderAssignment({
  workOrderId,
  technicians,
  vendors,
  teams,
}: {
  workOrderId: string;
  technicians: Assignee[];
  vendors: Assignee[];
  teams: Assignee[];
}) {
  const router = useRouter();
  const [type, setType] = useState<AssignmentType>("technician");
  const [id, setId] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const options = type === "technician" ? technicians : type === "vendor" ? vendors : teams;

  async function submit(event: React.FormEvent) {
    event.preventDefault(); if (!id) return;
    setSaving(true); setError(null);
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/assign`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ assignment_type: type, assignee_id: id }) });
      const result = await response.json();
      if (!response.ok) { setError(result.message ?? result.error ?? "Assignment failed."); return; }
      router.refresh();
    } catch { setError("Unable to reach the assignment service."); }
    finally { setSaving(false); }
  }

  return (
    <form onSubmit={submit} className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <select value={type} onChange={(event) => { setType(event.target.value as AssignmentType); setId(""); }} className="rounded-lg border border-slate-300 px-3 py-2 text-sm"><option value="technician">Technician</option><option value="vendor">Vendor</option><option value="team">Team</option></select>
        <select required value={id} onChange={(event) => setId(event.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm"><option value="">Select active {type}</option>{options.map((option) => <option key={option.id} value={option.id}>{option.name}{option.detail ? ` — ${option.detail}` : ""}</option>)}</select>
      </div>
      {options.length === 0 && <p className="text-sm text-amber-700">No active {type} records are available.</p>}
      {error && <p className="text-sm text-red-700">{error}</p>}
      <button disabled={saving || !id} className="rounded-lg bg-violet-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Assigning…" : "Assign work order"}</button>
    </form>
  );
}
