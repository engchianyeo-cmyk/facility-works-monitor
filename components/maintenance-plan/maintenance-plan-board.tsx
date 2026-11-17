"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { PLAN_FREQUENCIES, type PlanFrequency, type PlanTask, type PlanTechnician } from "@/lib/maintenance/plan";

type Props = {
  tasks: PlanTask[];
  facilities: Array<{ id: string; name: string }>;
  plannerFacilities: string[];
  editorAssets: string[];
  technicians: Record<string, PlanTechnician[]>;
  names: Record<string, string>;
  myId: string;
};

export default function MaintenancePlanBoard({ tasks, facilities, plannerFacilities, editorAssets, technicians, names, myId }: Props) {
  const router = useRouter();
  const [frequency, setFrequency] = useState<PlanFrequency | "all">("all");
  const [facility, setFacility] = useState(facilities.length === 1 ? facilities[0].id : "");
  const [search, setSearch] = useState("");
  const [mine, setMine] = useState(false);
  const [unassigned, setUnassigned] = useState(false);
  const [busy, setBusy] = useState("");
  const [message, setMessage] = useState<{ tone: "ok" | "error"; text: string } | null>(null);
  const facilityName = useMemo(() => new Map(facilities.map(f => [f.id, f.name])), [facilities]);

  const scoped = tasks.filter(t => (!facility || t.facilityId === facility)
    && (!mine || t.technicianId === myId) && (!unassigned || !t.technicianId)
    && (!search || `${t.assetTag} ${t.assetName} ${t.title} ${t.location} ${t.number}`.toLowerCase().includes(search.toLowerCase())));
  const counts = Object.fromEntries(PLAN_FREQUENCIES.map(f => [f.id, scoped.filter(t => t.frequency === f.id).length]));
  const shown = scoped.filter(t => frequency === "all" || t.frequency === frequency);
  const groups = PLAN_FREQUENCIES.map(f => ({ ...f, items: shown.filter(t => t.frequency === f.id) })).filter(g => g.items.length);
  const withManual = scoped.filter(t => t.documents.some(d => d.kind === "om_manual")).length;

  async function assign(task: PlanTask, technicianId: string) {
    setBusy(task.id); setMessage(null);
    const response = await fetch("/api/maintenance/plan/assign", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ requirement_id: task.id, technician_id: technicianId || null }) });
    const body = await response.json().catch(() => ({}));
    setBusy("");
    if (!response.ok) { setMessage({ tone: "error", text: body.error ?? "The Technician could not be assigned." }); return; }
    setMessage({ tone: "ok", text: `${task.assetTag} · ${task.title}: ${technicianId ? `assigned to ${names[technicianId] ?? "the Technician"}` : "Technician removed"}. New Work Orders from this task go to them.` });
    router.refresh();
  }

  async function upload(task: PlanTask, file: File | undefined) {
    if (!file) return;
    setBusy(`doc-${task.assetId}`); setMessage(null);
    const form = new FormData();
    form.append("file", file); form.append("kind", "om_manual"); form.append("title", `O&M manual – ${task.assetName}`.slice(0, 200));
    const response = await fetch(`/api/assets/${task.assetId}/documents`, { method: "POST", body: form });
    const body = await response.json().catch(() => ({}));
    setBusy("");
    if (!response.ok) { setMessage({ tone: "error", text: body.error ?? "The manual could not be filed." }); return; }
    setMessage({ tone: "ok", text: `O&M manual filed for ${task.assetTag}.` });
    router.refresh();
  }

  async function retire(documentId: string, title: string) {
    const reason = window.prompt(`Why should "${title}" be taken out of use? (It stays on record.)`);
    if (!reason) return;
    setBusy(`retire-${documentId}`);
    const response = await fetch(`/api/asset-documents/${documentId}/retire`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ reason }) });
    const body = await response.json().catch(() => ({}));
    setBusy("");
    setMessage(response.ok ? { tone: "ok", text: "Document taken out of use." } : { tone: "error", text: body.error ?? "The document could not be retired." });
    if (response.ok) router.refresh();
  }

  if (!tasks.length) return (
    <section className="mt-6 rounded-xl border border-dashed border-slate-300 bg-white p-10 text-center">
      <h2 className="font-black">No maintenance tasks yet</h2>
      <p className="mt-1 text-sm text-slate-500">Tasks appear here once maintenance requirements are set up for the equipment of your facility.</p>
    </section>
  );

  return (
    <div className="mt-6 space-y-5">
      <section className="grid gap-3 rounded-xl border border-slate-200 bg-white p-4 sm:grid-cols-2 lg:grid-cols-5">
        {facilities.length > 1 && <label className="text-xs font-bold">Facility
          <select value={facility} onChange={e => setFacility(e.target.value)} className="mt-1 min-h-11 w-full rounded-lg border p-2 text-sm">
            <option value="">All facilities</option>{facilities.map(f => <option key={f.id} value={f.id}>{f.name}</option>)}
          </select></label>}
        <label className="text-xs font-bold lg:col-span-2">Equipment, task or location
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="e.g. chiller, FCU, Level 2" className="mt-1 min-h-11 w-full rounded-lg border p-2 text-sm" /></label>
        <label className="flex min-h-11 items-center gap-2 self-end text-sm font-bold"><input type="checkbox" checked={mine} onChange={e => setMine(e.target.checked)} className="h-5 w-5" />Only my tasks</label>
        <label className="flex min-h-11 items-center gap-2 self-end text-sm font-bold"><input type="checkbox" checked={unassigned} onChange={e => setUnassigned(e.target.checked)} className="h-5 w-5" />Only unassigned</label>
      </section>

      <div className="flex flex-wrap gap-2" role="tablist" aria-label="How often">
        <Tab active={frequency === "all"} onClick={() => setFrequency("all")} label="All" count={scoped.length} />
        {PLAN_FREQUENCIES.filter(f => f.id !== "other" || counts.other).map(f => <Tab key={f.id} active={frequency === f.id} onClick={() => setFrequency(f.id)} label={f.label} count={counts[f.id]} />)}
      </div>
      <p className="text-sm text-slate-600">{scoped.length} tasks · {scoped.filter(t => t.technicianId).length} with a Technician · {withManual} with an O&amp;M manual filed</p>

      {message && <p role="status" className={`rounded-lg border p-3 text-sm font-bold ${message.tone === "ok" ? "border-emerald-200 bg-emerald-50 text-emerald-900" : "border-red-200 bg-red-50 text-red-800"}`}>{message.text}</p>}

      {groups.length === 0 && <p className="rounded-xl border border-dashed border-slate-300 bg-white p-8 text-center text-sm text-slate-500">No tasks match these filters.</p>}
      {groups.map(group => (
        <section key={group.id} className="rounded-xl border border-slate-200 bg-white shadow-sm">
          <h2 className="border-b border-slate-200 px-4 py-3 text-lg font-black">{group.label} <span className="text-sm font-bold text-slate-500">· {group.items.length}</span></h2>
          <ul className="divide-y divide-slate-100">
            {group.items.map(task => {
              const planner = Boolean(task.facilityId && plannerFacilities.includes(task.facilityId));
              const editor = editorAssets.includes(task.assetId);
              const options = task.facilityId ? technicians[task.facilityId] ?? [] : [];
              return (
                <li key={task.id} className="grid gap-3 p-4 lg:grid-cols-[2fr_1.2fr_1.4fr]">
                  <div className="min-w-0">
                    <p className="font-mono text-xs font-black text-blue-700">{task.assetTag} · {task.number}{task.state === "draft" && <span className="ml-2 rounded bg-amber-100 px-1.5 py-0.5 font-sans text-amber-900">Draft</span>}</p>
                    <h3 className="mt-0.5 font-black break-words">{task.title}</h3>
                    <p className="text-sm text-slate-600">{task.assetName}{task.location ? ` · ${task.location}` : ""}{facilities.length > 1 && task.facilityId ? ` · ${facilityName.get(task.facilityId) ?? ""}` : ""}</p>
                    <p className="mt-1 text-xs text-slate-500">{task.every} · Criticality {task.criticality}</p>
                    {task.scope && <details className="mt-1 text-sm"><summary className="cursor-pointer text-xs font-bold text-slate-600">What is checked</summary><p className="mt-1 whitespace-pre-line text-slate-700">{task.scope}</p></details>}
                  </div>
                  <div>
                    <p className="text-xs font-bold uppercase text-slate-400">Technician responsible</p>
                    {planner ? (
                      <select aria-label={`Technician for ${task.assetTag} ${task.title}`} value={task.technicianId ?? ""} disabled={busy === task.id} onChange={e => assign(task, e.target.value)} className="mt-1 min-h-11 w-full rounded-lg border p-2 text-sm">
                        <option value="">Not assigned</option>
                        {options.map(t => <option key={t.id} value={t.id}>{t.display_name}{t.trade_discipline ? ` (${t.trade_discipline})` : ""}</option>)}
                      </select>
                    ) : (
                      <p className="mt-1 text-sm font-bold">{task.technicianId ? (task.technicianId === myId ? "You" : names[task.technicianId] ?? "Assigned") : "Not assigned"}</p>
                    )}
                  </div>
                  <div>
                    <p className="text-xs font-bold uppercase text-slate-400">O&amp;M manual and documents</p>
                    {task.documents.length === 0 && <p className="mt-1 text-sm text-amber-800">No manual filed yet</p>}
                    <ul className="mt-1 space-y-1">
                      {task.documents.map(d => (
                        <li key={d.id} className="flex flex-wrap items-center gap-2 text-sm">
                          <a href={`/api/asset-documents/${d.id}/file`} target="_blank" rel="noopener" className="font-bold text-blue-700 underline break-all">{d.title}</a>
                          <a href={`/api/asset-documents/${d.id}/file?download=1`} className="text-xs text-slate-500 underline">Download</a>
                          {editor && <button type="button" disabled={busy === `retire-${d.id}`} onClick={() => retire(d.id, d.title)} className="text-xs text-red-700 underline">Take out of use</button>}
                        </li>
                      ))}
                    </ul>
                    {editor && <label className="mt-2 inline-flex min-h-11 cursor-pointer items-center rounded-lg border border-slate-300 px-3 text-sm font-bold hover:bg-slate-50">
                      {busy === `doc-${task.assetId}` ? "Uploading…" : "Upload O&M manual (PDF)"}
                      <input type="file" accept="application/pdf,image/png,image/jpeg,image/webp" className="sr-only" onChange={e => { upload(task, e.target.files?.[0]); e.target.value = ""; }} />
                    </label>}
                  </div>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
    </div>
  );
}

function Tab({ active, onClick, label, count }: { active: boolean; onClick: () => void; label: string; count: number }) {
  return <button type="button" role="tab" aria-selected={active} onClick={onClick} className={`min-h-11 rounded-full px-4 text-sm font-black ${active ? "bg-slate-900 text-white" : "border border-slate-300 bg-white text-slate-700 hover:bg-slate-50"}`}>{label} <span className="opacity-70">{count}</span></button>;
}
