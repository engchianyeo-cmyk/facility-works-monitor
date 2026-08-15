"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { IncidentAction } from "@/lib/incidents/types";

const LABELS: Record<IncidentAction, string> = { acknowledge: "Acknowledge", mobilise: "Mobilising", arrive: "On Site", start_rescue: "Rescue In Progress", make_safe: "Situation Safe", start_recovery: "Start Recovery", close: "Close Incident", cancel: "Cancel Incident" };
const PHASES: Partial<Record<IncidentAction, string>> = { mobilise: "mobilising", arrive: "on_site", start_rescue: "rescue_in_progress", make_safe: "safe", start_recovery: "recovery" };

export default function IncidentActions({ id, actions }: { id: string; actions: IncidentAction[] }) {
  const router = useRouter(); const [busy, setBusy] = useState(false); const [error, setError] = useState("");
  async function act(action: IncidentAction) {
    if (busy) return; setBusy(true); setError("");
    const endpoint = action === "acknowledge" ? "acknowledge" : action === "close" ? "close" : "phase";
    const body = endpoint === "phase" ? JSON.stringify({ phase: PHASES[action] }) : undefined;
    try { const response = await fetch(`/api/incidents/${id}/${endpoint}`, { method: "POST", headers: body ? { "content-type": "application/json" } : undefined, body }); const result = await response.json() as { message?: string }; if (!response.ok) throw new Error(result.message || "Incident could not be updated."); router.refresh(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Incident could not be updated."); }
    finally { setBusy(false); }
  }
  const primary = actions[0]; if (!primary) return null;
  return <div><p className="mb-3 text-sm text-slate-700">Only the next authorized response step is available.</p>{error && <p role="alert" className="mb-3 rounded-lg bg-white p-3 text-sm font-semibold text-red-700">{error}</p>}<button type="button" disabled={busy} onClick={() => act(primary)} className="min-h-16 w-full rounded-xl bg-red-700 px-6 py-4 text-lg font-black text-white shadow-md hover:bg-red-800 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-red-300 disabled:opacity-50">{busy ? "Updating…" : LABELS[primary]}</button></div>;
}
