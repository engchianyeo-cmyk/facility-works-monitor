"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { PM_MODES } from "@/lib/maintenance/window";

type Facility = { id: string; name: string; mode: string };

/** M35 (owner D-67): each facility's planned maintenance setting; the Super-Administrator changes it with a reason. */
export default function PmModeBanner({ facilities, canChange }: { facilities: Facility[]; canChange: boolean }) {
  if (!facilities.length) return null;
  return (
    <section aria-label="Planned maintenance setting" className="rounded-xl border border-teal-200 bg-teal-50/60 p-4">
      <h2 className="text-sm font-black uppercase tracking-wide text-teal-900">Planned maintenance setting</h2>
      <p className="mt-1 text-sm text-slate-700">Once a day the app lists the next month, moves weekend dates to Friday or Monday and creates the Work Orders that are due, as each facility&apos;s setting allows.</p>
      <ul className="mt-3 grid gap-3 md:grid-cols-2">{facilities.map((facility) => <ModeRow key={facility.id} facility={facility} canChange={canChange} />)}</ul>
    </section>
  );
}

function ModeRow({ facility, canChange }: { facility: Facility; canChange: boolean }) {
  const router = useRouter();
  const [mode, setMode] = useState(facility.mode);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);
  const current = PM_MODES.find((item) => item.id === facility.mode) ?? PM_MODES[1];
  async function save() {
    setBusy(true); setNote(null);
    const response = await fetch("/api/maintenance/pm-mode", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ facility_id: facility.id, mode, reason }) });
    const result = await response.json().catch(() => ({})) as { error?: string };
    setBusy(false);
    if (!response.ok) { setNote({ ok: false, text: result.error ?? "The setting could not be changed." }); return; }
    setNote({ ok: true, text: "Setting changed. The reason is recorded." }); setReason(""); router.refresh();
  }
  return (
    <li className="rounded-lg border border-teal-100 bg-white p-3 text-sm">
      <p className="font-black text-slate-900">{facility.name}: <span className="text-teal-800">{current.label}</span></p>
      <p className="text-xs text-slate-600">{current.help}</p>
      {canChange && <details className="mt-2"><summary className="cursor-pointer text-xs font-black text-blue-800">Change the setting</summary>
        <div className="mt-2 grid gap-2">
          <label className="text-xs font-bold">Setting<select value={mode} onChange={(e) => setMode(e.target.value)} className="mt-1 block min-h-11 w-full rounded-lg border p-2">{PM_MODES.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
          <label className="text-xs font-bold">Reason *<input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. trial: critical equipment only" className="mt-1 block min-h-11 w-full rounded-lg border p-2" /></label>
          {note && <p role="status" className={`rounded p-2 text-xs ${note.ok ? "bg-emerald-50 text-emerald-800" : "bg-red-50 text-red-800"}`}>{note.text}</p>}
          <button type="button" disabled={busy || mode === facility.mode || reason.trim().length < 5} onClick={() => void save()} className="min-h-11 rounded-lg bg-teal-700 px-4 font-black text-white disabled:opacity-50">{busy ? "Saving…" : "Save"}</button>
        </div></details>}
    </li>
  );
}
