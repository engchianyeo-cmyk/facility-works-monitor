"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { hhmm, rangeText, readingNumber, type RoundCheck, type RoundItem, type RoundSettings } from "@/lib/daily-round";

type Tech = { id: string; display_name: string; trade_discipline: string | null };

async function post(url: string, body: Record<string, unknown>) {
  const response = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  const result = await response.json().catch(() => ({})) as { error?: string };
  return response.ok ? null : result.error ?? "Not saved.";
}

/** M36: who does the Daily round and when (Approver, Supervisor, Facility Manager, Facility Administrator, Super-Admin). */
export function RoundSettingsForm({ facilityId, settings, technicians }: { facilityId: string; settings: RoundSettings; technicians: Tech[] }) {
  const router = useRouter();
  const [form, setForm] = useState({ enabled: settings.enabled, ready: hhmm(settings.ready), due: hhmm(settings.due), technician_id: settings.technician_id ?? "", cover_id: settings.cover_id ?? "", reason: "" });
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const set = (patch: Partial<typeof form>) => setForm((f) => ({ ...f, ...patch }));
  async function save() {
    setBusy(true); setNote(null);
    const error = await post("/api/daily-round/settings", { facility_id: facilityId, ...form });
    setBusy(false);
    setNote(error ? { ok: false, text: error } : { ok: true, text: "Saved. The reason is recorded." });
    if (!error) { set({ reason: "" }); router.refresh(); }
  }
  return (
    <section className="rounded-xl border border-slate-200 bg-white p-5">
      <h2 className="text-lg font-black">Who and when</h2>
      <div className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <label className="flex min-h-11 items-center gap-2 font-bold sm:col-span-2 lg:col-span-3"><input type="checkbox" checked={form.enabled} onChange={(e) => set({ enabled: e.target.checked })} className="h-5 w-5" />Daily round switched on (every day)</label>
        <label className="text-sm font-bold">Ready at<input type="time" value={form.ready} onChange={(e) => set({ ready: e.target.value })} className="mt-1 block min-h-11 w-full rounded-lg border p-2" /></label>
        <label className="text-sm font-bold">Due by<input type="time" value={form.due} onChange={(e) => set({ due: e.target.value })} className="mt-1 block min-h-11 w-full rounded-lg border p-2" /></label>
        <span />
        <label className="text-sm font-bold">Technician who does it<select value={form.technician_id} onChange={(e) => set({ technician_id: e.target.value })} className="mt-1 block min-h-11 w-full rounded-lg border p-2"><option value="">Choose…</option>{technicians.map((t) => <option key={t.id} value={t.id}>{t.display_name}{t.trade_discipline ? ` (${t.trade_discipline})` : ""}</option>)}</select></label>
        <label className="text-sm font-bold">Technician who covers<select value={form.cover_id} onChange={(e) => set({ cover_id: e.target.value })} className="mt-1 block min-h-11 w-full rounded-lg border p-2"><option value="">No cover</option>{technicians.map((t) => <option key={t.id} value={t.id}>{t.display_name}</option>)}</select></label>
        <label className="text-sm font-bold">Reason *<input value={form.reason} onChange={(e) => set({ reason: e.target.value })} placeholder="e.g. new roster" className="mt-1 block min-h-11 w-full rounded-lg border p-2" /></label>
      </div>
      {note && <p role="status" className={`mt-3 rounded p-2 text-sm ${note.ok ? "bg-emerald-50 text-emerald-800" : "bg-red-50 text-red-800"}`}>{note.text}</p>}
      <button type="button" disabled={busy || form.reason.trim().length < 3} onClick={() => void save()} className="mt-3 min-h-11 rounded-lg bg-blue-700 px-5 font-black text-white disabled:opacity-50">{busy ? "Saving…" : "Save"}</button>
    </section>
  );
}

/** M38: the normal range (low and/or high) and a short guide for a reading; a guide only for a tick item. */
function ItemRange({ item, onSave }: { item: RoundItem; onSave: (patch: { min: number | null; max: number | null; guide: string | null }) => Promise<boolean> }) {
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({ min: item.min == null ? "" : String(item.min), max: item.max == null ? "" : String(item.max), guide: item.guide ?? "" });
  const num = (v: string) => (v.trim() ? readingNumber(v) : null);
  const bad = (form.min.trim() && num(form.min) == null) || (form.max.trim() && num(form.max) == null);
  const crossed = num(form.min) != null && num(form.max) != null && (num(form.min) as number) > (num(form.max) as number);
  const shown = rangeText(item);
  const reading = Boolean(item.unit);
  if (!open) return (
    <span className="text-xs">
      {shown ? <span className="mr-2 rounded bg-slate-100 px-1.5 py-0.5 font-bold">Normal: {shown}</span> : reading && <span className="mr-2 font-semibold text-amber-800">No normal range yet</span>}
      {item.guide && <span className="mr-2 text-slate-500">{item.guide}</span>}
      <button type="button" onClick={() => setOpen(true)} className="font-bold text-blue-700 underline">{reading ? (shown || item.guide ? "Change range" : "Set range") : (item.guide ? "Change guide" : "Add guide")}</button>
    </span>
  );
  return (
    <span className="mt-1 flex w-full flex-wrap items-end gap-2 rounded-lg bg-slate-50 p-2 text-xs">
      {reading && <>
        <label className="font-bold">Lowest normal<input inputMode="decimal" value={form.min} onChange={(e) => setForm((f) => ({ ...f, min: e.target.value }))} className="mt-1 block min-h-11 w-24 rounded-lg border p-2" /></label>
        <label className="font-bold">Highest normal<input inputMode="decimal" value={form.max} onChange={(e) => setForm((f) => ({ ...f, max: e.target.value }))} className="mt-1 block min-h-11 w-24 rounded-lg border p-2" /></label>
        <span className="pb-3 text-slate-600">{item.unit}</span>
      </>}
      <label className="font-bold">Guide (optional)<input value={form.guide} maxLength={160} onChange={(e) => setForm((f) => ({ ...f, guide: e.target.value }))} placeholder={reading ? "e.g. Not above the nameplate full-load current" : "e.g. Drain discharges when its test button is pressed"} className="mt-1 block min-h-11 w-72 rounded-lg border p-2" /></label>
      <button type="button" disabled={Boolean(bad) || crossed} onClick={async () => { if (await onSave({ min: num(form.min), max: num(form.max), guide: form.guide.trim() || null })) setOpen(false); }} className="min-h-11 rounded-lg bg-blue-700 px-3 font-black text-white disabled:opacity-50">{reading ? "Save range" : "Save guide"}</button>
      <button type="button" onClick={() => setOpen(false)} className="min-h-11 px-2 font-bold text-slate-600 underline">Cancel</button>
      {(bad || crossed) && <span role="alert" className="w-full font-semibold text-red-700">{bad ? "Use numbers only, e.g. 6 or −20." : "The lowest must not be above the highest."}</span>}
      {reading && <span className="w-full text-slate-500">Leave one side empty for &quot;at most&quot; or &quot;at least&quot;. Technicians see it next to the reading; outside it they must give a reason to tick OK.</span>}
    </span>
  );
}

/** M36: the checklist — checks and their items; add, rename, take out of use (kept on record). */
export function ChecklistEditor({ facilityId, checks }: { facilityId: string; checks: RoundCheck[] }) {
  const router = useRouter();
  const [error, setError] = useState("");
  const [newCheck, setNewCheck] = useState({ title: "", equipment: "" });
  const [newItem, setNewItem] = useState<Record<string, { label: string; unit: string }>>({});
  // Owner, 22 Nov 2026: the empty "New item" boxes under every check read as something to fill in; they open on request.
  const [adding, setAdding] = useState<string | null>(null);
  async function run(url: string, body: Record<string, unknown>) {
    setError("");
    const e = await post(url, body);
    if (e) setError(e); else router.refresh();
    return !e;
  }
  return (
    <section className="rounded-xl border border-slate-200 bg-white p-5">
      <h2 className="text-lg font-black">Checklist</h2>
      <p className="mt-1 text-sm text-slate-600">This is the list the Technician ticks every day; nothing here needs filling in unless you want to change it. Each check has items to tick. Give an item a unit (for example °C, bar, µS/cm) when a reading must be written down, and its normal range so the Technician can judge OK or Not OK. Items taken out of use stay on record.</p>
      {error && <p role="alert" className="mt-2 rounded bg-red-50 p-2 text-sm font-semibold text-red-800">{error}</p>}
      <ol className="mt-4 space-y-4">
        {checks.map((check) => (
          <li key={check.id} className={`rounded-lg border p-4 ${check.active ? "border-slate-200" : "border-dashed border-slate-300 opacity-60"}`}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="font-black">{check.title}{check.equipment && <span className="ml-2 font-mono text-xs text-blue-700">{check.equipment}</span>}</p>
              <button type="button" onClick={() => void run("/api/daily-round/check", { id: check.id, title: check.title, equipment: check.equipment, active: !check.active })} className="text-sm font-bold text-blue-700 underline">{check.active ? "Take out of use" : "Use again"}</button>
            </div>
            <ul className="mt-2 space-y-1 text-sm">
              {check.items.map((item) => (
                <li key={item.id} className={`flex flex-wrap items-center justify-between gap-2 ${item.active ? "" : "line-through opacity-60"}`}>
                  <span>{item.label}{item.unit && <span className="ml-1 text-slate-500">({item.unit})</span>}</span>
                  {item.active && <ItemRange item={item} onSave={(patch) => run("/api/daily-round/item", { id: item.id, label: item.label, unit: item.unit, active: true, ...patch })} />}
                  <button type="button" onClick={() => void run("/api/daily-round/item", { id: item.id, label: item.label, unit: item.unit, min: item.min, max: item.max, guide: item.guide, active: !item.active })} className="text-xs font-bold text-blue-700 underline">{item.active ? "Remove" : "Use again"}</button>
                </li>
              ))}
            </ul>
            {check.active && adding !== check.id && (
              <button type="button" onClick={() => setAdding(check.id)} className="mt-3 min-h-11 text-sm font-bold text-blue-700 underline">+ Add an item to this check (optional)</button>
            )}
            {check.active && adding === check.id && (
              <div className="mt-3 flex flex-wrap items-end gap-2 rounded-lg bg-slate-50 p-2">
                <label className="text-xs font-bold">New item<input value={newItem[check.id]?.label ?? ""} onChange={(e) => setNewItem((n) => ({ ...n, [check.id]: { label: e.target.value, unit: n[check.id]?.unit ?? "" } }))} className="mt-1 block min-h-11 w-64 rounded-lg border p-2" /></label>
                <label className="text-xs font-bold">Unit (if a reading)<input value={newItem[check.id]?.unit ?? ""} onChange={(e) => setNewItem((n) => ({ ...n, [check.id]: { label: n[check.id]?.label ?? "", unit: e.target.value } }))} className="mt-1 block min-h-11 w-28 rounded-lg border p-2" /></label>
                <button type="button" disabled={(newItem[check.id]?.label ?? "").trim().length < 2} onClick={async () => { if (await run("/api/daily-round/item", { check_id: check.id, label: newItem[check.id]?.label, unit: newItem[check.id]?.unit || null, position: (check.items.length + 1) * 10 })) { setNewItem((n) => ({ ...n, [check.id]: { label: "", unit: "" } })); setAdding(null); } }} className="min-h-11 rounded-lg border border-blue-700 px-3 text-sm font-black text-blue-800 disabled:opacity-50">Add item</button>
                <button type="button" onClick={() => setAdding(null)} className="min-h-11 px-2 text-sm font-bold text-slate-600 underline">Cancel</button>
              </div>
            )}
          </li>
        ))}
      </ol>
      <div className="mt-5 flex flex-wrap items-end gap-2 border-t border-slate-200 pt-4">
        <label className="text-sm font-bold">New check<input value={newCheck.title} onChange={(e) => setNewCheck((c) => ({ ...c, title: e.target.value }))} placeholder="e.g. Loading dock doors" className="mt-1 block min-h-11 w-64 rounded-lg border p-2" /></label>
        <label className="text-sm font-bold">Equipment tags<input value={newCheck.equipment} onChange={(e) => setNewCheck((c) => ({ ...c, equipment: e.target.value }))} placeholder="e.g. F2-DR-01" className="mt-1 block min-h-11 w-48 rounded-lg border p-2" /></label>
        <button type="button" disabled={newCheck.title.trim().length < 2} onClick={async () => { if (await run("/api/daily-round/check", { facility_id: facilityId, title: newCheck.title, equipment: newCheck.equipment, position: (checks.length + 1) * 10 })) setNewCheck({ title: "", equipment: "" }); }} className="min-h-11 rounded-lg bg-blue-700 px-4 text-sm font-black text-white disabled:opacity-50">Add check</button>
      </div>
    </section>
  );
}
