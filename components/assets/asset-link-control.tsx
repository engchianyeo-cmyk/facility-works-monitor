"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import AssetSelector from "@/components/assets/asset-selector";
import type { AssetSummary } from "@/lib/assets/types";

export default function AssetLinkControl({ parent, parentId, assets, currentAssetId, unavailable }: { parent: "work-orders" | "incidents"; parentId: string; assets: AssetSummary[]; currentAssetId: string | null; unavailable: boolean }) {
  const router = useRouter(); const [busy, setBusy] = useState(false); const [error, setError] = useState("");
  async function submit(event: React.FormEvent<HTMLFormElement>) { event.preventDefault(); setBusy(true); setError(""); const body = Object.fromEntries(new FormData(event.currentTarget)); try { const response = await fetch(`/api/${parent}/${parentId}/asset`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }); const result = await response.json() as { message?: string }; if (!response.ok) throw new Error(result.message ?? "Asset link could not be updated."); router.refresh(); } catch (cause) { setError(cause instanceof Error ? cause.message : "Asset link could not be updated."); } finally { setBusy(false); } }
  return <form onSubmit={submit} className="space-y-3"><AssetSelector assets={assets} currentAssetId={currentAssetId} unavailable={unavailable} label="Primary Asset" /><label className="block text-sm font-medium">Reason for change<input name="reason" className="mt-1 w-full rounded-lg border p-2 text-sm" placeholder={currentAssetId ? "Required when changing or removing the current Asset" : "Optional for first link"} /></label>{error && <p role="alert" className="text-sm text-red-700">{error}</p>}<button disabled={busy} className="min-h-11 rounded-lg bg-blue-700 px-4 py-2 text-sm font-bold text-white disabled:opacity-50">{busy ? "Updating…" : "Update Asset link"}</button></form>;
}
