"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { roleLabel } from "@/lib/product-terminology";

type Person = { id: string; name: string; role: string };

/** People copied on a Work Order are notified at each stage and when the invoice is uploaded. */
export default function CopiedParties({ workOrderId, people, selected, canEdit }: { workOrderId: string; people: Person[]; selected: string[]; canEdit: boolean }) {
  const router = useRouter();
  const [chosen, setChosen] = useState<string[]>(selected);
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const byId = useMemo(() => new Map(people.map((person) => [person.id, person])), [people]);
  const choosable = people.filter((person) => person.role !== "finance");
  const current = selected.map((id) => byId.get(id)).filter((person): person is Person => Boolean(person));

  async function save() {
    setSaving(true); setError(null);
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/copied-parties`, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ profile_ids: chosen.filter((id) => byId.get(id)?.role !== "finance") }),
      });
      const result = await response.json();
      if (!response.ok) { setError(result.message ?? "Copied parties could not be saved."); return; }
      setEditing(false);
      router.refresh();
    } catch { setError("Unable to reach the Work Order service."); }
    finally { setSaving(false); }
  }

  return (
    <section className="rounded-xl border border-slate-200 bg-white p-5" aria-labelledby="copied-parties-title">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 id="copied-parties-title" className="font-semibold text-slate-900">Copied parties</h2>
          <p className="mt-1 text-sm text-slate-600">Notified at each stage and when the contractor invoice is uploaded. Finance is copied automatically when the Work Order is Completed.</p>
        </div>
        {canEdit && !editing && <button type="button" onClick={() => setEditing(true)} className="min-h-11 rounded-lg border border-slate-300 px-4 text-sm font-bold">Change</button>}
      </div>
      {!editing && (current.length === 0
        ? <p className="mt-3 text-sm text-slate-500">No one is copied.</p>
        : <ul className="mt-3 flex flex-wrap gap-2">{current.map((person) => <li key={person.id} className="rounded-full bg-slate-100 px-3 py-1 text-sm">{person.name} · {roleLabel(person.role)}</li>)}</ul>)}
      {editing && (
        <div className="mt-4 space-y-3">
          <fieldset className="max-h-64 space-y-1 overflow-y-auto rounded-lg border border-slate-200 p-3">
            <legend className="px-1 text-sm font-bold">Choose people to copy</legend>
            {choosable.map((person) => (
              <label key={person.id} className="flex min-h-10 items-center gap-3 text-sm">
                <input type="checkbox" checked={chosen.includes(person.id)} onChange={(event) => setChosen((list) => event.target.checked ? [...list, person.id] : list.filter((id) => id !== person.id))} />
                <span>{person.name} <span className="text-slate-500">· {roleLabel(person.role)}</span></span>
              </label>
            ))}
          </fieldset>
          {error && <p className="text-sm text-red-700" role="alert">{error}</p>}
          <div className="flex gap-3">
            <button type="button" disabled={saving} onClick={save} className="min-h-11 rounded-lg bg-blue-700 px-4 text-sm font-bold text-white disabled:opacity-50">{saving ? "Saving…" : "Save copied parties"}</button>
            <button type="button" disabled={saving} onClick={() => { setChosen(selected); setEditing(false); }} className="min-h-11 rounded-lg border border-slate-300 px-4 text-sm font-bold">Cancel</button>
          </div>
        </div>
      )}
    </section>
  );
}
