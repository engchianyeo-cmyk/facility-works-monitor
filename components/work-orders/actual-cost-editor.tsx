"use client";

import { useState } from "react";

export type ActualCostLine = {
  id: string; cost_phase: string | null; cost_type: string; description: string;
  quantity: number; unit: string; unit_rate: number; amount: number;
  worker_name: string | null; entered_by: string;
  technician_certified_at: string | null; approved_at: string | null;
};

type DraftRow = { key: number; cost_type: string; description: string; unit: string; quantity: string; unit_rate: string };
const COST_TYPES = [["material", "Material / consumables"], ["equipment", "Equipment"], ["service", "Service"], ["labour", "Labour"], ["callout", "Call-out"]] as const;
const typeLabel = (value: string) => COST_TYPES.find(([code]) => code === value)?.[1] ?? value;
const sgd = (value: number) => `S$${value.toLocaleString("en-SG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const blankRow = (key: number): DraftRow => ({ key, cost_type: "material", description: "", unit: "", quantity: "1", unit_rate: "" });

export default function ActualCostEditor({ lines, editable, userId, confirmed, busy, onSave, onSaveMany, onDelete, onConfirm, contractorWork = false, actionNeeded = false }: {
  lines: ActualCostLine[]; editable: boolean; userId: string; confirmed: boolean; busy: boolean;
  onSave: (payload: Record<string, unknown>) => Promise<void>; onConfirm: () => Promise<void>;
  /** Saves several lines in one go (e.g. every line of the contractor's revised quotation); resolves true when all were saved. */
  onSaveMany?: (payloads: Record<string, unknown>[]) => Promise<boolean>;
  /** D-22: contractor work - the actual cost is the final contractor charge; these lines are an optional itemised record. */
  contractorWork?: boolean;
  /** D-23: deletes the field owner's own uncertified line (audited). */
  onDelete?: (costLineId: string) => Promise<void>;
  /** Red highlight: the Technician still has to confirm the cost record. */
  actionNeeded?: boolean;
}) {
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [rows, setRows] = useState<DraftRow[]>([blankRow(1)]);
  const [nextKey, setNextKey] = useState(2);
  const rowAmount = (row: DraftRow) => (Number(row.quantity) || 0) * (Number(row.unit_rate) || 0);
  const rowsTotal = rows.reduce((sum, row) => sum + rowAmount(row), 0);
  const rowsReady = rows.length > 0 && rows.every((row) => row.description.trim() && row.unit.trim() && Number(row.quantity) >= 0 && row.unit_rate !== "" && Number(row.unit_rate) >= 0);
  const setRow = (key: number, change: Partial<DraftRow>) => setRows((current) => current.map((row) => row.key === key ? { ...row, ...change } : row));
  const [editingId, setEditingId] = useState<string | null>(null);
  const actual = lines.filter(line => line.cost_phase === "actual");
  const actualTotal = actual.reduce((sum, line) => sum + Number(line.amount), 0);
  const canEdit = (line: ActualCostLine) => editable && line.entered_by === userId
    && !line.technician_certified_at && !line.approved_at;
  const editing = actual.find(line => line.id === editingId && canEdit(line));
  const input = "mt-1 min-h-11 w-full rounded border border-slate-300 bg-white px-3 text-sm";
  return <section className={`mt-6 pt-5 ${actionNeeded ? "rounded border-4 border-red-500 bg-red-50 px-4 pb-4" : "border-t border-slate-200"}`} aria-labelledby="actual-cost-heading">
    {actionNeeded && <p className="mb-2 inline-block rounded bg-red-600 px-3 py-1 text-sm font-black text-white">Action needed: check the lines, then click {confirmed ? "Reconfirm" : "Confirm"} Actual Costing</p>}
    <h3 id="actual-cost-heading" className="font-black">{contractorWork ? "Itemised cost record (optional)" : "Actual Cost"}</h3>
    {contractorWork && <p className="mt-1 text-sm text-slate-700">For contractor work the actual cost is the <strong>final contractor charge</strong> entered in Final Cost Reconciliation, backed by the attached quotation. Lines here are optional, for example your own staff&apos;s labour or materials you supplied. Confirm the record (even if empty) before submitting the work for review.</p>}
    <p className="mt-1 text-sm text-slate-600">{confirmed ? "Confirmed" : "Draft"} execution costs. Changes require costing confirmation again; approved quotations and certified lines retain their controls.</p>
    {actual.map(line => <article key={line.id} className="mt-3 flex flex-wrap items-center justify-between gap-3 rounded border bg-white p-3 text-sm">
      <div><strong>{line.description}</strong><p>{typeLabel(line.cost_type)} · {line.quantity} {line.unit} × S${Number(line.unit_rate).toFixed(2)}</p></div>
      <strong>S${Number(line.amount).toFixed(2)}</strong>
      {canEdit(line) && <div className="flex flex-wrap gap-2">
        <button type="button" disabled={busy} onClick={() => { setEditingId(line.id); setDeletingId(null); }} className="min-h-11 rounded border px-3 font-bold">Edit actual cost: {line.description}</button>
        {onDelete && (deletingId === line.id
          ? <><button type="button" disabled={busy} onClick={async () => { await onDelete(line.id); setDeletingId(null); if (editingId === line.id) setEditingId(null); }} className="min-h-11 rounded bg-red-700 px-3 font-bold text-white">Confirm delete</button>
              <button type="button" disabled={busy} onClick={() => setDeletingId(null)} className="min-h-11 rounded border px-3 font-bold">Keep line</button></>
          : <button type="button" disabled={busy} onClick={() => setDeletingId(line.id)} className="min-h-11 rounded border border-red-300 px-3 font-bold text-red-700">Delete line: {line.description}</button>)}
      </div>}
    </article>)}
    {!actual.length && <p className="mt-2 text-sm text-slate-500">No actual cost recorded. A genuine zero-cost outcome may be confirmed explicitly.</p>}
    {actual.length > 0 && <p className="mt-3 text-right text-sm font-bold">{contractorWork ? "Total of itemised lines" : "Total actual cost"}: {sgd(actualTotal)} <span className="font-normal text-slate-600">({actual.length} line{actual.length === 1 ? "" : "s"})</span></p>}
    {editable && onSaveMany && <section className="mt-4 rounded border-l-4 border-emerald-600 bg-emerald-50 p-4" aria-labelledby="cost-lines-heading">
      <h4 id="cost-lines-heading" className="font-bold">Add several lines from the contractor&apos;s quotation</h4>
      <p className="mt-1 text-sm text-slate-700">Enter each line of the contractor&apos;s (revised) quotation: materials, equipment and services. Amounts are before GST. To change a line already saved, use its Edit button above.</p>
      <div className="mt-3 overflow-x-auto"><table className="w-full min-w-[44rem] text-sm">
        <thead><tr className="text-left text-xs uppercase text-slate-600"><th className="p-1">Category</th><th className="p-1">Description</th><th className="p-1">Unit</th><th className="p-1">Qty</th><th className="p-1">Unit rate (S$)</th><th className="p-1 text-right">Amount (S$)</th><th className="p-1"><span className="sr-only">Remove</span></th></tr></thead>
        <tbody>{rows.map((row, index) => <tr key={row.key} className="align-top">
          <td className="p-1"><select aria-label={`Category, line ${index + 1}`} value={row.cost_type} onChange={(event) => setRow(row.key, { cost_type: event.target.value })} className={input}>{COST_TYPES.map(([code, label]) => <option key={code} value={code}>{label}</option>)}</select></td>
          <td className="p-1"><input aria-label={`Description, line ${index + 1}`} value={row.description} maxLength={1000} onChange={(event) => setRow(row.key, { description: event.target.value })} placeholder="e.g. Insulating oil to IEC 60296" className={input}/></td>
          <td className="p-1 w-24"><input aria-label={`Unit, line ${index + 1}`} value={row.unit} maxLength={100} onChange={(event) => setRow(row.key, { unit: event.target.value })} placeholder="litre" className={input}/></td>
          <td className="p-1 w-24"><input aria-label={`Quantity, line ${index + 1}`} type="number" min="0" step="0.01" value={row.quantity} onChange={(event) => setRow(row.key, { quantity: event.target.value })} className={input}/></td>
          <td className="p-1 w-32"><input aria-label={`Unit rate, line ${index + 1}`} type="number" min="0" step="0.01" value={row.unit_rate} onChange={(event) => setRow(row.key, { unit_rate: event.target.value })} className={input}/></td>
          <td className="p-1 pt-4 text-right font-semibold">{rowAmount(row).toFixed(2)}</td>
          <td className="p-1"><button type="button" disabled={busy || rows.length === 1} onClick={() => setRows((current) => current.filter((item) => item.key !== row.key))} className="min-h-11 rounded border px-2 text-xs font-bold text-red-700 disabled:opacity-40">Remove</button></td>
        </tr>)}</tbody>
      </table></div>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
        <button type="button" disabled={busy} onClick={() => { setRows((current) => [...current, blankRow(nextKey)]); setNextKey((key) => key + 1); }} className="min-h-11 rounded border border-emerald-700 bg-white px-4 font-bold text-emerald-800">+ Add another line</button>
        <p className="text-sm font-bold">These lines: {sgd(rowsTotal)} · New total{contractorWork ? " of itemised lines" : " actual cost"}: {sgd(actualTotal + rowsTotal)}</p>
      </div>
      <button type="button" disabled={busy || !rowsReady} onClick={async () => {
        const saved = await onSaveMany(rows.map((row) => ({ cost_type: row.cost_type, description: row.description.trim(), unit: row.unit.trim(), quantity: Number(row.quantity), unit_rate: Number(row.unit_rate), worker_name: "" })));
        if (saved) { setRows([blankRow(nextKey)]); setNextKey((key) => key + 1); }
      }} className="mt-3 min-h-11 w-full rounded bg-emerald-700 px-4 font-bold text-white disabled:opacity-40">Save {rows.length} cost line{rows.length === 1 ? "" : "s"}</button>
    </section>}
    {editable && <>
      {(editing || !onSaveMany) && <form key={editing?.id ?? "new"} className="mt-4 grid gap-3 rounded border-l-4 border-blue-600 bg-slate-50 p-4 sm:grid-cols-2" onSubmit={async event => {
        event.preventDefault();
        const form = event.currentTarget;
        const values = new FormData(form);
        await onSave({ ...(editing ? { cost_line_id: editing.id } : {}), cost_type: values.get("cost_type"),
          description: String(values.get("description") ?? "").trim(), quantity: Number(values.get("quantity")),
          unit: String(values.get("unit") ?? "").trim(), unit_rate: Number(values.get("unit_rate")),
          worker_name: String(values.get("worker_name") ?? "").trim() });
        // Preserve inputs for correction and review after the request.
      }}>
        <p className="font-bold sm:col-span-2">{editing ? `Correct the saved line: ${editing.description}` : "Add a single actual cost line"}</p>
        <label className="text-sm font-bold">Cost type<select name="cost_type" defaultValue={editing?.cost_type ?? "service"} className={input}>{COST_TYPES.map(([code, label]) => <option key={code} value={code}>{label}</option>)}</select></label>
        <label className="text-sm font-bold">Description / variation details<input name="description" required maxLength={1000} defaultValue={editing?.description ?? ""} className={input}/></label>
        <label className="text-sm font-bold">Worker (optional)<input name="worker_name" maxLength={200} defaultValue={editing?.worker_name ?? ""} className={input}/></label>
        <label className="text-sm font-bold">Quantity<input name="quantity" required type="number" min="0" step="0.01" defaultValue={editing?.quantity ?? 1} className={input}/></label>
        <label className="text-sm font-bold">Unit<input name="unit" required maxLength={100} defaultValue={editing?.unit ?? "lump_sum"} className={input}/></label>
        <label className="text-sm font-bold">Unit rate (SGD)<input name="unit_rate" required type="number" min="0" step="0.01" defaultValue={editing?.unit_rate ?? ""} className={input}/></label>
        <button disabled={busy} className="min-h-11 rounded bg-blue-700 px-4 font-bold text-white">{editing ? "Save actual cost change" : "Add Actual Cost"}</button>
        {editing && <button type="button" disabled={busy} onClick={() => setEditingId(null)} className="min-h-11 rounded border bg-white px-4 font-bold">Cancel edit</button>}
      </form>}
      {confirmed && <p className="mt-3 text-sm text-amber-900">A saved addition or change reopens costing confirmation and records the previous and new values in the audit.</p>}
      <button type="button" disabled={busy} onClick={() => void onConfirm()} className="mt-3 min-h-11 rounded border border-blue-700 bg-white px-4 font-bold text-blue-700">{confirmed ? "Reconfirm Actual Costing" : "Confirm Actual Costing"}</button>
    </>}
  </section>;
}
