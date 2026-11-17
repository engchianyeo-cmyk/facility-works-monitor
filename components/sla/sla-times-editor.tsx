"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";

export type SlaTimesRow = { priority: string; acknowledgement_minutes: number | null; attendance_minutes: number | null; make_safe_minutes: number | null; rectification_minutes: number; kpi_target_percent: number };
export type SlaScope = { id: string | null; name: string; current: SlaTimesRow[]; ownSla: boolean };

const PRIORITIES = [
  { key: "critical", label: "P1 Critical" },
  { key: "high", label: "P2 High" },
  { key: "medium", label: "P3 Medium" },
  { key: "low", label: "P4 Low" },
] as const;
const STAGES = [
  { key: "acknowledgement_minutes", label: "Acknowledge", optional: true },
  { key: "attendance_minutes", label: "Attend on site", optional: true },
  { key: "make_safe_minutes", label: "Make safe", optional: true },
  { key: "rectification_minutes", label: "Fix", optional: false },
] as const;
type StageKey = (typeof STAGES)[number]["key"];
type Unit = "min" | "h" | "days";
type Cell = { value: string; unit: Unit };
type Grid = Record<string, Record<StageKey, Cell> & { kpi: string }>;
const FACTOR: Record<Unit, number> = { min: 1, h: 60, days: 1440 };

/** Shows a stored number of minutes in the largest whole unit: 240 → 4 h, 1440 → 1 days. */
export function toCell(minutes: number | null | undefined): Cell {
  if (!minutes) return { value: "", unit: "min" };
  if (minutes % 1440 === 0) return { value: String(minutes / 1440), unit: "days" };
  if (minutes % 60 === 0) return { value: String(minutes / 60), unit: "h" };
  return { value: String(minutes), unit: "min" };
}
export function toMinutes(cell: Cell): number | null {
  const n = Number(cell.value);
  return cell.value.trim() === "" || !Number.isFinite(n) ? null : Math.round(n * FACTOR[cell.unit]);
}

function gridFor(rows: SlaTimesRow[]): Grid {
  const grid = {} as Grid;
  for (const p of PRIORITIES) {
    const row = rows.find((item) => item.priority === p.key);
    grid[p.key] = {
      acknowledgement_minutes: toCell(row?.acknowledgement_minutes), attendance_minutes: toCell(row?.attendance_minutes),
      make_safe_minutes: toCell(row?.make_safe_minutes), rectification_minutes: toCell(row?.rectification_minutes),
      kpi: row ? String(row.kpi_target_percent) : p.key === "critical" || p.key === "high" ? "95" : "90",
    };
  }
  return grid;
}

export default function SlaTimesEditor({ scopes }: { scopes: SlaScope[] }) {
  const router = useRouter();
  const [index, setIndex] = useState(0);
  const scope = scopes[index];
  const startFrom = scope.ownSla ? scope.current : scopes[0].current;
  const [grid, setGrid] = useState<Grid>(() => gridFor(startFrom));
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const standardNote = useMemo(() => scope.id && !scope.ownSla ? "This facility uses the standard. Saving gives it its own SLA, starting from the standard's times." : null, [scope]);

  function choose(next: number) {
    setIndex(next);
    const target = scopes[next];
    setGrid(gridFor(target.ownSla ? target.current : scopes[0].current));
    setMessage(null); setError(null);
  }
  function setCell(priority: string, stage: StageKey, change: Partial<Cell>) {
    setGrid((current) => ({ ...current, [priority]: { ...current[priority], [stage]: { ...current[priority][stage], ...change } } }));
  }

  async function post(body: Record<string, unknown>) {
    setBusy(true); setError(null); setMessage(null);
    try {
      const response = await fetch("/api/administration/sla-times", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      const result = (await response.json().catch(() => ({}))) as { error?: string };
      if (!response.ok) throw new Error(result.error ?? "Could not be saved.");
      return true;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Could not be saved.");
      return false;
    } finally { setBusy(false); }
  }

  async function save() {
    const rows = PRIORITIES.map((p) => ({
      priority: p.key,
      acknowledgement_minutes: toMinutes(grid[p.key].acknowledgement_minutes),
      attendance_minutes: toMinutes(grid[p.key].attendance_minutes),
      make_safe_minutes: toMinutes(grid[p.key].make_safe_minutes),
      rectification_minutes: toMinutes(grid[p.key].rectification_minutes),
      kpi_target_percent: Number(grid[p.key].kpi),
    }));
    if (await post({ facility_id: scope.id, rows, reason })) { setMessage(`Saved: ${scope.name}. New Work Orders use these times from now on.`); setReason(""); router.refresh(); }
  }
  async function applyStandard() {
    if (await post({ facility_id: scope.id, action: "use_standard", reason })) { setMessage(`${scope.name} now uses the standard SLA.`); setReason(""); router.refresh(); }
  }

  const input = "w-20 rounded border border-slate-300 px-2 py-1 text-sm";
  return (
    <section className="space-y-4 rounded-xl border border-slate-200 bg-white p-4 sm:p-5">
      <label className="block text-sm font-semibold">Which SLA
        <select value={index} onChange={(event) => choose(Number(event.target.value))} className="mt-1 block w-full max-w-md rounded-lg border border-slate-300 px-3 py-2">
          {scopes.map((item, i) => <option key={item.id ?? "standard"} value={i}>{item.name}{item.id ? (item.ownSla ? " (its own SLA)" : " (uses the standard)") : ""}</option>)}
        </select>
      </label>
      {standardNote && <p className="rounded-lg bg-amber-50 p-3 text-sm text-amber-900">{standardNote}</p>}
      <div className="overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead className="bg-slate-50 text-left"><tr><th className="px-3 py-2">Priority</th>{STAGES.map((stage) => <th key={stage.key} className="px-3 py-2">{stage.label} within{stage.optional ? "" : " *"}</th>)}<th className="px-3 py-2">Target met on</th></tr></thead>
          <tbody className="divide-y">{PRIORITIES.map((p) => (
            <tr key={p.key}>
              <td className="px-3 py-2 font-bold">{p.label}</td>
              {STAGES.map((stage) => (
                <td key={stage.key} className="px-3 py-2 whitespace-nowrap">
                  <input aria-label={`${p.label} ${stage.label}`} inputMode="decimal" value={grid[p.key][stage.key].value} onChange={(event) => setCell(p.key, stage.key, { value: event.target.value })} placeholder={stage.optional ? "—" : ""} className={input} />
                  <select aria-label={`${p.label} ${stage.label} unit`} value={grid[p.key][stage.key].unit} onChange={(event) => setCell(p.key, stage.key, { unit: event.target.value as Unit })} className="ml-1 rounded border border-slate-300 px-1 py-1 text-sm">
                    <option value="min">min</option><option value="h">hours</option><option value="days">days</option>
                  </select>
                </td>
              ))}
              <td className="px-3 py-2 whitespace-nowrap"><input aria-label={`${p.label} target percent`} inputMode="decimal" value={grid[p.key].kpi} onChange={(event) => setGrid((current) => ({ ...current, [p.key]: { ...current[p.key], kpi: event.target.value } }))} className="w-16 rounded border border-slate-300 px-2 py-1 text-sm" /> %</td>
            </tr>
          ))}</tbody>
        </table>
      </div>
      <p className="text-xs text-slate-500">* Fix is required. Leave a box empty when that step does not apply (for example Make safe for P3 and P4). Times count round the clock from when the Work Order starts; times must not run backwards (acknowledge, attend, make safe, fix).</p>
      <label className="block text-sm font-semibold">Reason for the change (kept in the record)
        <input value={reason} onChange={(event) => setReason(event.target.value)} maxLength={300} placeholder="e.g. Agreed with the facility owner on 17 Nov 2026" className="mt-1 block w-full rounded-lg border border-slate-300 px-3 py-2 font-normal" />
      </label>
      <div className="flex flex-wrap gap-2">
        <button type="button" disabled={busy || reason.trim().length < 5} onClick={() => void save()} className="rounded-lg bg-blue-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{busy ? "Saving…" : "Save SLA times"}</button>
        {scope.id && scope.ownSla && <button type="button" disabled={busy || reason.trim().length < 5} onClick={() => void applyStandard()} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold disabled:opacity-50">Use the standard for this facility</button>}
      </div>
      {message && <p role="status" className="text-sm font-semibold text-emerald-800">{message}</p>}
      {error && <p role="alert" className="text-sm font-semibold text-red-700">{error}</p>}
    </section>
  );
}
