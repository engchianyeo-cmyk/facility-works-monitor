"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { EVIDENCE_CATEGORIES, type EvidenceParent } from "@/lib/evidence";

type Item = {
  id: string;
  original_filename: string;
  byte_size: number;
  category: string;
  description: string | null;
  uploaded_at: string;
  uploader_name: string;
};

const label = (value: string) => value.charAt(0).toUpperCase() + value.slice(1);

export default function EvidencePanel({ parentType, parentId }: { parentType: EvidenceParent; parentId: string }) {
  const router = useRouter();
  const [items, setItems] = useState<Item[]>([]);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [uploading, setUploading] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [message, setMessage] = useState("");
  const [messageKind, setMessageKind] = useState<"success" | "error" | null>(null);

  const load = useCallback(async () => {
    try {
      const response = await fetch(`/api/evidence?parent_type=${parentType}&parent_id=${parentId}`, { cache: "no-store" });
      const result = await response.json();
      if (!response.ok) throw new Error();
      const loadedItems = result.data as Item[];
      setItems(loadedItems);
      setState("ready");
      return loadedItems;
    } catch {
      setState("error");
      throw new Error("Evidence could not be reloaded to confirm the saved record.");
    }
  }, [parentId, parentType]);

  useEffect(() => { void load().catch(() => undefined); }, [load]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setUploading(true);
    setMessage("");
    setMessageKind(null);
    const form = event.currentTarget;
    const body = new FormData(form);
    body.set("parent_type", parentType);
    body.set("parent_id", parentId);
    const requestedCategory = String(body.get("category") ?? "");
    try {
      const response = await fetch("/api/evidence", { method: "POST", body });
      const result = await response.json() as {
        code?: string;
        message?: string;
        evidence?: { id?: string; category?: string };
      };
      if (!response.ok) throw new Error(result.message ?? "Upload failed.");
      if (!result.evidence?.id || result.evidence.category !== requestedCategory) {
        throw new Error("Evidence registration could not be confirmed.");
      }
      const refreshedItems = await load();
      if (!refreshedItems.some((item) => item.id === result.evidence?.id && item.category === requestedCategory)) {
        throw new Error("Evidence was registered but is not visible in the active evidence record.");
      }
      form.reset();
      setMessageKind("success");
      setMessage("Evidence added successfully.");
      router.refresh();
    } catch (error) {
      setMessageKind("error");
      setMessage(error instanceof Error ? error.message : "Evidence upload failed safely.");
    } finally {
      setUploading(false);
    }
  }

  async function open(id: string) {
    setMessage("");
    try {
      const response = await fetch(`/api/evidence/${id}/access`, { method: "POST" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.message ?? "Evidence is unavailable.");
      window.open(result.url, "_blank", "noopener,noreferrer");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Evidence is unavailable.");
    }
  }

  async function remove(item: Item) {
    if (deletingId) return;
    const confirmed = window.confirm(`Remove ${item.original_filename} from the active evidence record? The audit history will be retained.`);
    if (!confirmed) return;
    const reason = window.prompt("State why this evidence is being removed:", "Uploaded in error")?.trim();
    if (!reason) {
      setMessage("Evidence was not removed. A deletion reason is required.");
      return;
    }

    setDeletingId(item.id);
    setMessage("");
    try {
      const response = await fetch(`/api/evidence/${item.id}`, {
        method: "DELETE",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ reason }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.message ?? "Evidence could not be removed.");
      setMessage(result.message ?? "Evidence removed from the active record.");
      await load();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Evidence could not be removed.");
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <section aria-labelledby={`evidence-${parentId}`} className="rounded-2xl border border-slate-200 bg-white p-5 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs font-black uppercase tracking-widest text-blue-700">Field proof</p>
          <h2 id={`evidence-${parentId}`} className="text-xl font-black">Evidence</h2>
          <p className="mt-1 text-sm text-slate-600">Before and After photos or PDFs prove the site condition and physical work performed.</p>
        </div>
        {state === "ready" && <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-black text-blue-800">{items.length} item{items.length === 1 ? "" : "s"}</span>}
      </div>

      {state === "loading" ? (
        <p className="mt-5 text-sm text-slate-500">Loading evidence…</p>
      ) : state === "error" ? (
        <p role="alert" className="mt-5 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">Evidence is temporarily unavailable. Existing work remains accessible.</p>
      ) : items.length ? (
        <ul className="mt-5 grid gap-3 sm:grid-cols-2">
          {items.map((item) => (
            <li key={item.id} className="rounded-xl border p-4">
              <div className="flex justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-xs font-black uppercase text-blue-700">{label(item.category)}</p>
                  <p className="truncate font-bold">{item.original_filename}</p>
                </div>
                <div className="flex shrink-0 gap-2">
                  <button type="button" onClick={() => void open(item.id)} className="min-h-11 rounded-lg border border-blue-300 px-3 text-sm font-black text-blue-800">Open</button>
                  <button
                    type="button"
                    disabled={deletingId !== null}
                    onClick={() => void remove(item)}
                    className="min-h-11 rounded-lg border border-red-300 px-3 text-sm font-black text-red-700 disabled:opacity-50"
                  >
                    {deletingId === item.id ? "Removing…" : "Delete"}
                  </button>
                </div>
              </div>
              {item.description && <p className="mt-2 text-sm">{item.description}</p>}
              <p className="mt-2 text-xs text-slate-500">{item.uploader_name} · {new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short" }).format(new Date(item.uploaded_at))} · {Math.ceil(item.byte_size / 1024)} KB</p>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mt-5 rounded-xl border border-dashed border-amber-300 bg-amber-50 p-6 text-center">
          <p className="font-bold text-amber-950">No evidence attached</p>
          <p className="mt-1 text-sm text-amber-900">After evidence is required before work can be marked Completed. Add Before evidence whenever the original fault or site condition can be safely recorded.</p>
        </div>
      )}

      <form onSubmit={submit} className="mt-6 grid gap-4 rounded-xl bg-slate-50 p-4 sm:grid-cols-2">
        <label className="text-sm font-bold">Category
          <select name="category" defaultValue="after" className="mt-1 min-h-12 w-full rounded-lg border bg-white px-3">
            {EVIDENCE_CATEGORIES.map((value) => <option key={value} value={value}>{label(value)}</option>)}
          </select>
        </label>
        <label className="text-sm font-bold">Photo or PDF
          <input name="file" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" required className="mt-1 block min-h-12 w-full rounded-lg border bg-white p-2 text-sm" />
        </label>
        <label className="text-sm font-bold sm:col-span-2">Short note (optional)
          <input name="description" maxLength={500} className="mt-1 min-h-12 w-full rounded-lg border px-3" placeholder="What does this Before or After evidence show?" />
        </label>
        <div className="sm:col-span-2">
          <p className="mb-3 text-xs text-slate-600">Online connection required. Maximum 10 MB. Do not upload passwords, identity documents, or unrelated personal information.</p>
          <button disabled={uploading} className="min-h-12 w-full rounded-xl bg-blue-700 px-5 font-black text-white disabled:opacity-50 sm:w-auto">{uploading ? "Uploading…" : "Add evidence"}</button>
        </div>
      </form>

      {message && <p role={messageKind === "error" ? "alert" : "status"} className={`mt-3 text-sm font-semibold ${messageKind === "error" ? "text-red-800" : "text-blue-800"}`}>{message}</p>}
    </section>
  );
}
