"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { AssistantAvatar } from "@/components/help/mascot";

const MAX_BYTES = 300 * 1024;
const TYPES = ["image/png", "image/jpeg", "image/webp", "image/svg+xml"];

export default function AssistantSettingsForm({ name: initialName, pictureUrl }: { name: string; pictureUrl: string | null }) {
  const router = useRouter();
  const [name, setName] = useState(initialName);
  const [image, setImage] = useState<string | null>(null);
  const [keepCurrent, setKeepCurrent] = useState(Boolean(pictureUrl));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  function choose(file: File | undefined) {
    setError(null);
    if (!file) return;
    if (!TYPES.includes(file.type)) return setError("Choose a PNG, JPEG, WebP or SVG picture.");
    if (file.size > MAX_BYTES) return setError("The picture must be 300 KB or smaller.");
    const reader = new FileReader();
    reader.onload = () => { setImage(String(reader.result)); setKeepCurrent(false); };
    reader.readAsDataURL(file);
  }

  async function save(useDefault = false) {
    setBusy(true); setError(null); setMessage(null);
    try {
      let picture: string | null = useDefault ? null : image;
      if (!useDefault && !picture && keepCurrent && pictureUrl) {
        const response = await fetch(pictureUrl);
        const blob = await response.blob();
        picture = await new Promise<string>((resolve) => { const reader = new FileReader(); reader.onload = () => resolve(String(reader.result)); reader.readAsDataURL(blob); });
      }
      const response = await fetch("/api/assistant/settings", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name: useDefault ? "Ollie" : name, image: picture }) });
      const result = (await response.json().catch(() => ({}))) as { error?: string };
      if (!response.ok) throw new Error(result.error ?? "Could not be saved.");
      setMessage(useDefault ? "Back to Ollie." : "Saved. Everyone sees the change on their next page.");
      if (useDefault) { setImage(null); setKeepCurrent(false); setName("Ollie"); }
      router.refresh();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Could not be saved.");
    } finally {
      setBusy(false);
    }
  }

  const preview = image ?? (keepCurrent ? pictureUrl : null);
  return (
    <section className="space-y-4 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex items-center gap-4">
        {/* eslint-disable-next-line @next/next/no-img-element -- local preview of the chosen file */}
        {preview ? <img src={preview} alt="New picture preview" className="h-24 w-24 rounded-full border object-contain" /> : <AssistantAvatar size={96} name={name || "Ollie"} />}
        <p className="text-sm text-slate-600">Preview. Square pictures work best (at least 128 × 128 pixels).</p>
      </div>
      <label className="block text-sm font-medium">Name (1–30 characters)
        <input value={name} maxLength={30} onChange={(event) => setName(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2" />
      </label>
      <label className="block text-sm font-medium">New picture (PNG, JPEG, WebP or SVG, up to 300 KB)
        <input type="file" accept={TYPES.join(",")} onChange={(event) => choose(event.target.files?.[0])} className="mt-1 block w-full text-sm" />
      </label>
      <div className="flex flex-wrap gap-2">
        <button type="button" disabled={busy || !name.trim()} onClick={() => void save()} className="rounded-lg bg-blue-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{busy ? "Saving…" : "Save"}</button>
        <button type="button" disabled={busy} onClick={() => void save(true)} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold">Use Ollie again</button>
      </div>
      {message && <p role="status" className="text-sm font-semibold text-emerald-800">{message}</p>}
      {error && <p role="alert" className="text-sm font-semibold text-red-700">{error}</p>}
    </section>
  );
}
