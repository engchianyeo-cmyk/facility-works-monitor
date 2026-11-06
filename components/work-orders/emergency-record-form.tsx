"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

type Area = { id: string; name: string; mapped: boolean };

const input = "w-full rounded-lg border border-slate-300 px-3 py-2 text-sm";

function isoFromLocal(value: string) {
  if (!value) return "";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "" : date.toISOString();
}

async function upload(workOrderId: string, file: File, category: "before" | "after") {
  const body = new FormData();
  body.set("parent_type", "work_order");
  body.set("parent_id", workOrderId);
  body.set("category", category);
  body.set("description", category === "before" ? "Condition found (emergency)" : "Condition after the emergency repair");
  body.set("file", file);
  const response = await fetch("/api/evidence", { method: "POST", body });
  if (!response.ok) {
    const result = await response.json().catch(() => ({})) as { message?: string };
    throw new Error(`${file.name}: ${result.message ?? "upload failed"}`);
  }
}

/** D-36 (6 Nov 2026): one screen to record emergency work that has already been carried out. */
export default function EmergencyRecordForm({ areas }: { areas: Area[] }) {
  const router = useRouter();
  const [saving, setSaving] = useState(false);
  const [progress, setProgress] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const before = form.getAll("before_files").filter((file): file is File => file instanceof File && file.size > 0);
    const after = form.getAll("after_files").filter((file): file is File => file instanceof File && file.size > 0);
    const startedAt = isoFromLocal(String(form.get("started_at") ?? ""));
    const endedAt = isoFromLocal(String(form.get("ended_at") ?? ""));
    if (!startedAt || !endedAt) { setError("Enter when the work started and when it ended."); return; }
    if (endedAt < startedAt) { setError("The end time must be after the start time."); return; }
    if (after.length === 0) { setError("Add at least one photo of the condition after the repair."); return; }
    setSaving(true);
    setError(null);
    const steps: string[] = [];
    const note = (line: string) => { steps.push(line); setProgress([...steps]); };
    let workOrderId: string | null = null;
    try {
      const response = await fetch("/api/work-orders/emergency-record", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: String(form.get("title") ?? "").trim(),
          location: String(form.get("location") ?? "").trim(),
          facility_area_id: String(form.get("facility_area_id") ?? "") || null,
          description: String(form.get("description") ?? "").trim(),
          priority: String(form.get("priority") ?? "high"),
          in_house_work: form.get("work_by") === "in_house",
          started_at: startedAt,
          ended_at: endedAt,
          completion_notes: String(form.get("completion_notes") ?? "").trim(),
          actual_labour_hours: Number(form.get("actual_labour_hours")),
          no_separate_costs: form.get("no_separate_costs") === "on",
        }),
      });
      const result = await response.json().catch(() => ({})) as { message?: string; data?: { id?: string; work_order_number?: string } };
      if (!response.ok || !result.data?.id) throw new Error(result.message ?? "The emergency work could not be recorded. Nothing was saved.");
      workOrderId = result.data.id;
      note(`Work Order ${result.data.work_order_number ?? ""} created as emergency work, with the times, work done and hours.`);
      for (const file of before) await upload(workOrderId, file, "before");
      if (before.length) note(`${before.length} photo(s) of the condition found attached.`);
      for (const file of after) await upload(workOrderId, file, "after");
      note(`${after.length} photo(s) after the repair attached.`);
      if (form.get("no_separate_costs") === "on") {
        const completion = await fetch(`/api/work-orders/${workOrderId}/transition`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "submit_physical_completion" }),
        });
        const done = await completion.json().catch(() => ({})) as { message?: string };
        if (!completion.ok) throw new Error(done.message ?? "Physical completion could not be submitted.");
        note("Physical completion submitted. The Approver now reviews the work.");
      } else {
        note("Log the materials or costs on the Work Order, then submit physical completion there.");
      }
      router.push(`/work-orders/${workOrderId}`);
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : "Something went wrong.";
      setError(workOrderId ? `${message} The Work Order was created; finish the remaining step on its page.` : message);
      if (workOrderId) router.push(`/work-orders/${workOrderId}`);
    } finally {
      setSaving(false);
    }
  }

  const now = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16);

  return (
    <form onSubmit={submit} className="space-y-5 rounded-xl border-2 border-red-300 bg-white p-6">
      <fieldset className="space-y-3">
        <legend className="text-lg font-black text-slate-900">1. What happened and where</legend>
        <div><label className="mb-1 block text-sm font-medium" htmlFor="em-title">Title *</label><input id="em-title" required minLength={3} maxLength={200} name="title" className={input} placeholder="e.g. Burst pipe under wash basin" /></div>
        <div><label className="mb-1 block text-sm font-medium" htmlFor="em-description">What happened *</label><textarea id="em-description" required minLength={10} rows={3} name="description" className={input} placeholder="What you found and why it could not wait, e.g. water flooding the floor." /></div>
        {areas.length > 0 && (
          <div>
            <label className="mb-1 block text-sm font-medium" htmlFor="em-area">Area / room</label>
            <select id="em-area" name="facility_area_id" className={input} defaultValue="" onChange={(event) => {
              const location = event.currentTarget.form?.elements.namedItem("location") as HTMLInputElement | null;
              const chosen = event.currentTarget.selectedOptions[0]?.text.replace(/ — on the layout plan$/, "") ?? "";
              if (location && !location.value && event.currentTarget.value) location.value = chosen;
            }}>
              <option value="">Choose the area</option>
              {areas.map((area) => <option key={area.id} value={area.id}>{area.name}{area.mapped ? " — on the layout plan" : ""}</option>)}
            </select>
          </div>
        )}
        <div><label className="mb-1 block text-sm font-medium" htmlFor="em-location">Location *</label><input id="em-location" required name="location" className={input} placeholder="e.g. Main Building, Level 1 male toilet, wash basin 3" /></div>
        <div>
          <label className="mb-1 block text-sm font-medium" htmlFor="em-priority">Priority</label>
          <select id="em-priority" name="priority" className={input} defaultValue="high"><option value="critical">Critical</option><option value="high">High</option><option value="medium">Medium</option></select>
        </div>
      </fieldset>

      <fieldset className="space-y-2">
        <legend className="text-lg font-black text-slate-900">2. Who did the work</legend>
        <label className="flex items-start gap-3 rounded-lg border border-slate-300 p-3 text-sm"><input type="radio" name="work_by" value="in_house" defaultChecked className="mt-1" /><span><b>In-house staff</b> — no quotation, invoice or payment.</span></label>
        <label className="flex items-start gap-3 rounded-lg border border-slate-300 p-3 text-sm"><input type="radio" name="work_by" value="contractor" className="mt-1" /><span><b>A contractor</b> — the contractor&apos;s quotation is added afterwards and approved at the review.</span></label>
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="text-lg font-black text-slate-900">3. When, what was done and the hours</legend>
        <div className="grid gap-3 sm:grid-cols-2">
          <div><label className="mb-1 block text-sm font-medium" htmlFor="em-start">Work started *</label><input id="em-start" required type="datetime-local" max={now} name="started_at" className={input} /></div>
          <div><label className="mb-1 block text-sm font-medium" htmlFor="em-end">Work ended *</label><input id="em-end" required type="datetime-local" max={now} name="ended_at" className={input} /></div>
        </div>
        <div><label className="mb-1 block text-sm font-medium" htmlFor="em-work">Work performed *</label><textarea id="em-work" required rows={3} name="completion_notes" className={input} placeholder="e.g. Isolated the supply, replaced the burst flexible hose, tested, no leak." /></div>
        <div className="sm:w-1/2"><label className="mb-1 block text-sm font-medium" htmlFor="em-hours">Labour hours *</label><input id="em-hours" required type="number" min="0" step="0.25" name="actual_labour_hours" className={input} placeholder="e.g. 1.5" /></div>
        <label className="flex items-start gap-3 text-sm"><input type="checkbox" name="no_separate_costs" defaultChecked className="mt-1" /><span>No materials or other costs to log separately (a contractor&apos;s charge comes with their quotation). Untick if you need to log materials; you then finish on the Work Order page.</span></label>
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="text-lg font-black text-slate-900">4. Photos</legend>
        <div><label className="mb-1 block text-sm font-medium" htmlFor="em-before">Condition found (if you managed to take one)</label><input id="em-before" type="file" name="before_files" multiple accept="image/*,application/pdf" className="block text-sm" /></div>
        <div><label className="mb-1 block text-sm font-medium" htmlFor="em-after">After the repair * (at least one)</label><input id="em-after" required type="file" name="after_files" multiple accept="image/*,application/pdf" className="block text-sm" /></div>
      </fieldset>

      {error && <p role="alert" className="rounded-lg border border-red-300 bg-red-50 p-3 text-sm font-semibold text-red-800">{error}</p>}
      {progress.length > 0 && <ul role="status" className="list-disc space-y-1 rounded-lg border border-emerald-300 bg-emerald-50 p-3 pl-8 text-sm text-emerald-900">{progress.map((line) => <li key={line}>{line}</li>)}</ul>}
      <button type="submit" disabled={saving} className="min-h-12 w-full rounded-xl bg-red-600 px-5 py-3 text-base font-black text-white hover:bg-red-700 disabled:opacity-50">
        {saving ? "Recording…" : "Record emergency work done"}
      </button>
    </form>
  );
}
