"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

/** ISO timestamp → value for <input type="datetime-local"> in the viewer's local time. */
function toLocalInput(value: string | null) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function workDuration(start: string | null, end: string | null) {
  if (!start || !end) return null;
  const minutes = Math.round((new Date(end).getTime() - new Date(start).getTime()) / 60000);
  if (!Number.isFinite(minutes) || minutes < 0) return null;
  const days = Math.floor(minutes / 1440), hours = Math.floor((minutes % 1440) / 60), rest = minutes % 60;
  return [days ? `${days} d` : "", hours ? `${hours} h` : "", `${rest} min`].filter(Boolean).join(" ");
}

/** D-11: the assigned Technician enters (and may later correct) when the work actually started and ended. */
export default function ActualWorkTimes({ workOrderId, startedAt, endedAt, canEdit }: { workOrderId: string; startedAt: string | null; endedAt: string | null; canEdit: boolean }) {
  const router = useRouter();
  const [start, setStart] = useState(toLocalInput(startedAt));
  const [end, setEnd] = useState(toLocalInput(endedAt));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);
  const duration = workDuration(startedAt, endedAt);
  const max = toLocalInput(new Date().toISOString());

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setMessage("");
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/actual-times`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ started_at: new Date(start).toISOString(), ended_at: end ? new Date(end).toISOString() : null }),
      });
      const result = await response.json();
      setFailed(!response.ok);
      setMessage(response.ok ? "Work times saved." : result.message ?? "Work times could not be saved.");
      if (response.ok) router.refresh();
    } catch { setFailed(true); setMessage("Unable to reach the Work Order service."); }
    finally { setBusy(false); }
  }

  return <section id="actual-work-times" className="rounded-xl border border-sky-200 bg-sky-50 p-5" aria-labelledby="actual-work-times-title">
    <h2 id="actual-work-times-title" className="font-semibold text-sky-950">Actual work times</h2>
    <p className="mt-1 text-sm text-sky-900">When the work on site actually started and ended. Required before the Approver&apos;s review; the end time can be filled in later.</p>
    <dl className="mt-3 grid gap-3 text-sm sm:grid-cols-3">
      <div><dt className="font-semibold">Started</dt><dd>{startedAt ? new Date(startedAt).toLocaleString("en-SG") : "Not entered"}</dd></div>
      <div><dt className="font-semibold">Ended</dt><dd>{endedAt ? new Date(endedAt).toLocaleString("en-SG") : "Not entered"}</dd></div>
      <div><dt className="font-semibold">Duration</dt><dd>{duration ?? "—"}</dd></div>
    </dl>
    {canEdit && <form onSubmit={save} className="mt-4 grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
      <label className="block text-sm font-semibold">Work started
        <input type="datetime-local" required value={start} max={max} onChange={(event) => setStart(event.target.value)} className="mt-1 block min-h-11 w-full rounded border bg-white p-2 font-normal" />
      </label>
      <label className="block text-sm font-semibold">Work ended
        <input type="datetime-local" value={end} min={start || undefined} max={max} onChange={(event) => setEnd(event.target.value)} className="mt-1 block min-h-11 w-full rounded border bg-white p-2 font-normal" />
      </label>
      <button disabled={busy || !start} className="min-h-11 rounded-lg bg-sky-700 px-4 text-sm font-bold text-white disabled:opacity-50">{busy ? "Saving…" : "Save work times"}</button>
    </form>}
    {message && <p role={failed ? "alert" : "status"} className={`mt-2 text-sm ${failed ? "text-red-700" : "text-emerald-700"}`}>{message}</p>}
  </section>;
}
