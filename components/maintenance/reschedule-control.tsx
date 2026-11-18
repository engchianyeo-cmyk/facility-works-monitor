"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { addDays } from "@/lib/maintenance/window";
import { formatPmDate } from "@/lib/maintenance/presentation";

/** M35 (owner D-67 A/B): move a planned date inside its window with a reason; beyond it needs the Super-Administrator
 *  or the Facility Administrator (the database checks). */
export default function RescheduleControl({ id, originalDue, currentDue, windowDays, canGoBeyond }: { id: string; originalDue: string; currentDue: string; windowDays: number; canGoBeyond: boolean }) {
  const router = useRouter();
  const [date, setDate] = useState(currentDue);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);
  const earliest = addDays(originalDue, -windowDays);
  const latest = addDays(originalDue, windowDays);
  const beyond = date < earliest || date > latest;
  async function save() {
    setBusy(true); setNote(null);
    const response = await fetch(`/api/maintenance/occurrences/${id}/reschedule`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ new_date: date, reason }) });
    const result = await response.json().catch(() => ({})) as { ok?: boolean; message?: string; code?: string };
    setBusy(false);
    if (!response.ok || !result.ok) { setNote({ ok: false, text: result.message ?? "The date could not be changed." }); return; }
    setNote({ ok: true, text: result.code === "NO_CHANGE" ? "No change." : `Moved to ${formatPmDate(date)}. The reason is recorded.` });
    setReason("");
    router.refresh();
  }
  return (
    <details className="mt-3">
      <summary className="cursor-pointer py-2 text-sm font-black text-blue-800">Change the date</summary>
      <div className="mt-2 rounded-lg bg-slate-50 p-4 text-sm">
        <p className="text-slate-600">Planned <strong>{formatPmDate(originalDue)}</strong>. {windowDays > 0 ? <>Allowed <strong>{formatPmDate(earliest)}</strong> to <strong>{formatPmDate(latest)}</strong> (± {windowDays} day{windowDays === 1 ? "" : "s"}).</> : "This task has a fixed date."}{canGoBeyond ? " You may also approve a date outside it." : " Outside it needs the Super-Administrator or the Facility Administrator."}</p>
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <label className="font-bold">New date *<input type="date" value={date} min={canGoBeyond ? undefined : earliest} max={canGoBeyond ? undefined : latest} onChange={(e) => setDate(e.target.value)} className="mt-1 min-h-11 w-full rounded-lg border p-2" /></label>
          <label className="font-bold">Reason *<input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. shutdown booked that day" className="mt-1 min-h-11 w-full rounded-lg border p-2" /></label>
        </div>
        {beyond && <p className="mt-2 font-semibold text-amber-800">This date is outside the allowed window{canGoBeyond ? "; it will be recorded as approved beyond the window." : "."}</p>}
        {note && <p role="status" className={`mt-2 rounded p-2 ${note.ok ? "bg-emerald-50 text-emerald-800" : "bg-red-50 text-red-800"}`}>{note.text}</p>}
        <button type="button" disabled={busy || reason.trim().length < 3 || date === currentDue || (beyond && !canGoBeyond)} onClick={() => void save()} className="mt-3 min-h-11 rounded-lg bg-blue-700 px-4 font-black text-white disabled:opacity-50">{busy ? "Saving…" : "Save the new date"}</button>
      </div>
    </details>
  );
}
