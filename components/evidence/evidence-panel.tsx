"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { EVIDENCE_CATEGORIES, type EvidenceParent } from "@/lib/evidence";

type Item = { id: string; original_filename: string; byte_size: number; category: string; description: string | null; uploaded_at: string; uploader_name: string };
const label = (value: string) => value.charAt(0).toUpperCase() + value.slice(1);

export default function EvidencePanel({ parentType, parentId }: { parentType: EvidenceParent; parentId: string }) {
  const [items, setItems] = useState<Item[]>([]);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [uploading, setUploading] = useState(false);
  const [message, setMessage] = useState("");
  const load = useCallback(async () => {
    try {
      const response = await fetch(`/api/evidence?parent_type=${parentType}&parent_id=${parentId}`, { cache: "no-store" });
      const result = await response.json();
      if (!response.ok) throw new Error();
      setItems(result.data);
      setState("ready");
    } catch { setState("error"); }
  }, [parentId, parentType]);
  useEffect(() => { void load(); }, [load]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setUploading(true); setMessage("");
    const form = event.currentTarget, body = new FormData(form);
    body.set("parent_type", parentType); body.set("parent_id", parentId);
    try {
      const response = await fetch("/api/evidence", { method: "POST", body }), result = await response.json();
      if (!response.ok) throw new Error(result.message ?? "Upload failed.");
      form.reset(); setMessage("Evidence uploaded and recorded in activity history."); await load();
    } catch (error) { setMessage(error instanceof Error ? error.message : "Evidence upload failed safely."); }
    finally { setUploading(false); }
  }
  async function open(id: string) {
    setMessage("");
    try {
      const response = await fetch(`/api/evidence/${id}/access`, { method: "POST" }), result = await response.json();
      if (!response.ok) throw new Error(result.message ?? "Evidence is unavailable.");
      window.open(result.url, "_blank", "noopener,noreferrer");
    } catch (error) { setMessage(error instanceof Error ? error.message : "Evidence is unavailable."); }
  }

  return <section aria-labelledby={`evidence-${parentId}`} className="rounded-2xl border border-slate-200 bg-white p-5 sm:p-6">
    <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-xs font-black uppercase tracking-widest text-blue-700">Field proof</p><h2 id={`evidence-${parentId}`} className="text-xl font-black">Evidence</h2><p className="mt-1 text-sm text-slate-600">Photos or PDF documents that help prove the work or site condition.</p></div>{state === "ready" && <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-black text-blue-800">{items.length} item{items.length === 1 ? "" : "s"}</span>}</div>
    {state === "loading" ? <p className="mt-5 text-sm text-slate-500">Loading evidence…</p> : state === "error" ? <p role="alert" className="mt-5 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">Evidence is temporarily unavailable. Existing work remains accessible.</p> : items.length ? <ul className="mt-5 grid gap-3 sm:grid-cols-2">{items.map(item => <li key={item.id} className="rounded-xl border p-4"><div className="flex justify-between gap-3"><div className="min-w-0"><p className="text-xs font-black uppercase text-blue-700">{label(item.category)}</p><p className="truncate font-bold">{item.original_filename}</p></div><button type="button" onClick={() => void open(item.id)} className="min-h-11 shrink-0 rounded-lg border border-blue-300 px-3 text-sm font-black text-blue-800">Open</button></div>{item.description && <p className="mt-2 text-sm">{item.description}</p>}<p className="mt-2 text-xs text-slate-500">{item.uploader_name} · {new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short" }).format(new Date(item.uploaded_at))} · {Math.ceil(item.byte_size / 1024)} KB</p></li>)}</ul> : <div className="mt-5 rounded-xl border border-dashed p-6 text-center"><p className="font-bold">No evidence attached</p><p className="mt-1 text-sm text-slate-500">Evidence is not required unless the work instructions say so.</p></div>}
    <form onSubmit={submit} className="mt-6 grid gap-4 rounded-xl bg-slate-50 p-4 sm:grid-cols-2"><label className="text-sm font-bold">Category<select name="category" defaultValue="other" className="mt-1 min-h-12 w-full rounded-lg border bg-white px-3">{EVIDENCE_CATEGORIES.map(value => <option key={value} value={value}>{label(value)}</option>)}</select></label><label className="text-sm font-bold">Photo or PDF<input name="file" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" required className="mt-1 block min-h-12 w-full rounded-lg border bg-white p-2 text-sm" /></label><label className="text-sm font-bold sm:col-span-2">Short note (optional)<input name="description" maxLength={500} className="mt-1 min-h-12 w-full rounded-lg border px-3" placeholder="What does this evidence show?" /></label><div className="sm:col-span-2"><p className="mb-3 text-xs text-slate-600">Online connection required. Maximum 10 MB. Do not upload passwords, identity documents, or unrelated personal information.</p><button disabled={uploading} className="min-h-12 w-full rounded-xl bg-blue-700 px-5 font-black text-white disabled:opacity-50 sm:w-auto">{uploading ? "Uploading…" : "Add evidence"}</button></div></form>
    {message && <p role="status" className="mt-3 text-sm font-semibold text-blue-800">{message}</p>}
  </section>;
}
