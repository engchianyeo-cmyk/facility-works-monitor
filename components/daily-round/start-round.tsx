"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

/** M36: start today's round by hand (the daily run normally does it at 06:00). */
export default function StartRound({ facilityId }: { facilityId: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function start() {
    setBusy(true); setError("");
    const response = await fetch("/api/daily-round/start", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ facility_id: facilityId }) });
    const body = await response.json().catch(() => ({})) as { error?: string };
    setBusy(false);
    if (!response.ok) { setError(body.error ?? "Not started."); return; }
    router.refresh();
  }
  return <div><button type="button" disabled={busy} onClick={() => void start()} className="min-h-11 rounded-lg bg-blue-700 px-4 font-black text-white disabled:opacity-50">{busy ? "Starting…" : "Start today's round now"}</button>{error && <p role="alert" className="mt-2 text-sm font-semibold text-red-700">{error}</p>}</div>;
}
