"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

type Row = { code: string; defaultLabel: string; label: string };

export default function TerminologyEditor({ title, rows }: { title: string; rows: Row[] }) {
  const router = useRouter();
  const [values, setValues] = useState<Record<string, string>>(Object.fromEntries(rows.map((row) => [row.code, row.label])));
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);
  async function save(code: string, label: string) {
    setBusy(code); setMessage("");
    try {
      const response = await fetch("/api/administration/terminology", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code, label }) });
      const result = await response.json();
      setFailed(!response.ok);
      setMessage(response.ok ? (label.trim() ? "Label saved." : "Default label restored.") : result.message ?? "The label could not be saved.");
      if (response.ok) router.refresh();
    } catch { setFailed(true); setMessage("The label could not be saved. Try again."); }
    finally { setBusy(null); }
  }
  return <section className="rounded-xl border bg-white p-6">
    <h2 className="text-xl font-bold">{title}</h2>
    <ul className="mt-4 divide-y">
      {rows.map((row) => (
        <li key={row.code} className="grid gap-3 py-3 sm:grid-cols-[12rem_1fr_auto_auto] sm:items-center">
          <span className="text-sm text-slate-600">Default: <strong className="text-slate-900">{row.defaultLabel}</strong></span>
          <input aria-label={`Company name for ${row.defaultLabel}`} maxLength={60} value={values[row.code] ?? ""} placeholder={row.defaultLabel} onChange={(event) => setValues((current) => ({ ...current, [row.code]: event.target.value }))} className="min-h-11 rounded border p-2" />
          <button type="button" disabled={busy !== null} onClick={() => void save(row.code, values[row.code] ?? "")} className="min-h-11 rounded bg-blue-700 px-4 text-sm font-bold text-white disabled:opacity-50">{busy === row.code ? "Saving…" : "Save"}</button>
          <button type="button" disabled={busy !== null || !row.label} onClick={() => { setValues((current) => ({ ...current, [row.code]: "" })); void save(row.code, ""); }} className="min-h-11 rounded border px-4 text-sm font-bold disabled:opacity-50">Reset</button>
        </li>
      ))}
    </ul>
    {message && <p className="mt-3" role={failed ? "alert" : "status"}>{message}</p>}
  </section>;
}
