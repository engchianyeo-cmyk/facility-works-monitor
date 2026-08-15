"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { INCIDENT_SEVERITIES, INCIDENT_TYPES } from "@/lib/incidents/types";
import { incidentTypeLabel, operationalLabel } from "@/lib/product-terminology";
import AssetSelector from "@/components/assets/asset-selector";
import type { AssetSummary } from "@/lib/assets/types";

export default function IncidentForm({ assets }: { assets: AssetSummary[] }) {
  const router = useRouter(); const [busy, setBusy] = useState(false); const [error, setError] = useState("");
  async function submit(formData: FormData) {
    if (busy) return; setBusy(true); setError("");
    try {
      const response = await fetch("/api/incidents", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(Object.fromEntries(formData)) });
      const result = await response.json() as { ok?: boolean; data?: { id?: string }; message?: string };
      if (!response.ok || !result.ok || !result.data?.id) throw new Error(result.message || "Incident could not be reported.");
      router.push(`/incidents/${result.data.id}`); router.refresh();
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Incident could not be reported."); setBusy(false); }
  }
  return <form action={submit} className="space-y-5 rounded-xl border-2 border-red-200 bg-white p-6 shadow-sm">
    {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
    <div className="grid gap-5 sm:grid-cols-2"><label className="text-sm font-medium">Incident type<select name="incident_type" required defaultValue="" className="mt-1 w-full rounded-lg border p-2.5"><option value="" disabled>Select type</option>{INCIDENT_TYPES.map(x=><option key={x} value={x}>{incidentTypeLabel(x)}</option>)}</select></label><label className="text-sm font-medium">Severity<select name="severity" defaultValue="emergency" className="mt-1 w-full rounded-lg border p-2.5">{INCIDENT_SEVERITIES.map(x=><option key={x} value={x}>{operationalLabel(x)}</option>)}</select></label></div>
    <label className="block text-sm font-medium">Location<input name="location" required maxLength={200} className="mt-1 w-full rounded-lg border p-2.5" /></label>
    <AssetSelector assets={assets} label="Primary affected Asset" />
    <label className="block text-sm font-medium">What is happening?<textarea name="description" required maxLength={4000} rows={5} className="mt-1 w-full rounded-lg border p-2.5" /></label>
    <button disabled={busy} className="rounded-lg bg-red-700 px-5 py-3 font-bold text-white disabled:opacity-50">{busy ? "Activating response…" : "Report emergency incident"}</button>
  </form>;
}
