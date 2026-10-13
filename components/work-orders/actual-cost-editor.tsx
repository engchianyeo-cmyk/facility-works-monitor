"use client";

import { useState } from "react";

export type ActualCostLine = {
  id: string; cost_phase: string | null; cost_type: string; description: string;
  quantity: number; unit: string; unit_rate: number; amount: number;
  worker_name: string | null; entered_by: string;
  technician_certified_at: string | null; approved_at: string | null;
};

export default function ActualCostEditor({ lines, editable, userId, confirmed, busy, onSave, onConfirm }: {
  lines: ActualCostLine[]; editable: boolean; userId: string; confirmed: boolean; busy: boolean;
  onSave: (payload: Record<string, unknown>) => Promise<void>; onConfirm: () => Promise<void>;
}) {
  const [editingId, setEditingId] = useState<string | null>(null);
  const actual = lines.filter(line => line.cost_phase === "actual");
  const canEdit = (line: ActualCostLine) => editable && line.entered_by === userId
    && !line.technician_certified_at && !line.approved_at;
  const editing = actual.find(line => line.id === editingId && canEdit(line));
  const input = "mt-1 min-h-11 w-full rounded border border-slate-300 bg-white px-3 text-sm";
  return <section className="mt-6 border-t border-slate-200 pt-5" aria-labelledby="actual-cost-heading">
    <h3 id="actual-cost-heading" className="font-black">Actual Cost</h3>
    <p className="mt-1 text-sm text-slate-600">{confirmed ? "Confirmed" : "Draft"} execution costs. Changes require costing confirmation again; approved quotations and certified lines retain their controls.</p>
    {actual.map(line => <article key={line.id} className="mt-3 flex flex-wrap items-center justify-between gap-3 rounded border bg-white p-3 text-sm">
      <div><strong>{line.description}</strong><p>{line.quantity} {line.unit} × S${Number(line.unit_rate).toFixed(2)}</p></div>
      <strong>S${Number(line.amount).toFixed(2)}</strong>
      {canEdit(line) && <button type="button" disabled={busy} onClick={() => setEditingId(line.id)} className="min-h-11 rounded border px-3 font-bold">Edit actual cost: {line.description}</button>}
    </article>)}
    {!actual.length && <p className="mt-2 text-sm text-slate-500">No actual cost recorded. A genuine zero-cost outcome may be confirmed explicitly.</p>}
    {editable && <>
      <form key={editing?.id ?? "new"} className="mt-4 grid gap-3 rounded border-l-4 border-blue-600 bg-slate-50 p-4 sm:grid-cols-2" onSubmit={async event => {
        event.preventDefault();
        const form = event.currentTarget;
        const values = new FormData(form);
        await onSave({ ...(editing ? { cost_line_id: editing.id } : {}), cost_type: values.get("cost_type"),
          description: String(values.get("description") ?? "").trim(), quantity: Number(values.get("quantity")),
          unit: String(values.get("unit") ?? "").trim(), unit_rate: Number(values.get("unit_rate")),
          worker_name: String(values.get("worker_name") ?? "").trim() });
        // Preserve inputs for correction and review after the request.
      }}>
        <p className="font-bold sm:col-span-2">{editing ? "Update actual cost for a work variation" : "Add actual cost for additional work"}</p>
        <label className="text-sm font-bold">Cost type<select name="cost_type" defaultValue={editing?.cost_type ?? "service"} className={input}>{["service", "labour", "material", "equipment", "callout"].map(type => <option key={type} value={type}>{type}</option>)}</select></label>
        <label className="text-sm font-bold">Description / variation details<input name="description" required maxLength={1000} defaultValue={editing?.description ?? ""} className={input}/></label>
        <label className="text-sm font-bold">Worker (optional)<input name="worker_name" maxLength={200} defaultValue={editing?.worker_name ?? ""} className={input}/></label>
        <label className="text-sm font-bold">Quantity<input name="quantity" required type="number" min="0" step="0.01" defaultValue={editing?.quantity ?? 1} className={input}/></label>
        <label className="text-sm font-bold">Unit<input name="unit" required maxLength={100} defaultValue={editing?.unit ?? "lump_sum"} className={input}/></label>
        <label className="text-sm font-bold">Unit rate (SGD)<input name="unit_rate" required type="number" min="0" step="0.01" defaultValue={editing?.unit_rate ?? ""} className={input}/></label>
        <button disabled={busy} className="min-h-11 rounded bg-blue-700 px-4 font-bold text-white">{editing ? "Save actual cost change" : "Add Actual Cost"}</button>
        {editing && <button type="button" disabled={busy} onClick={() => setEditingId(null)} className="min-h-11 rounded border bg-white px-4 font-bold">Cancel edit</button>}
      </form>
      {confirmed && <p className="mt-3 text-sm text-amber-900">A saved addition or change reopens costing confirmation and records the previous and new values in the audit.</p>}
      <button type="button" disabled={busy} onClick={() => void onConfirm()} className="mt-3 min-h-11 rounded border border-blue-700 bg-white px-4 font-bold text-blue-700">{confirmed ? "Reconfirm Actual Costing" : "Confirm Actual Costing"}</button>
    </>}
  </section>;
}
