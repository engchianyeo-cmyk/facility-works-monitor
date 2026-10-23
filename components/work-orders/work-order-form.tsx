"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { WORK_ORDER_SOURCES } from "@/lib/work-orders/types";
import { operationalLabel } from "@/lib/product-terminology";
import AssetSelector from "@/components/assets/asset-selector";
import type { AssetSummary } from "@/lib/assets/types";

type Option = { id: string; name: string; code?: string };
type Person = { id: string; name: string; role: string };
type Area = { id: string; name: string; facilityId: string | null; mapped: boolean };
type ExistingOrder = Record<string, string | number | null | undefined>;

export default function WorkOrderForm({
  categories,
  departments,
  assets,
  workOrder,
  role,
  people = [],
  facilities = [],
  areas = [],
}: {
  categories: Option[];
  departments: Option[];
  assets: AssetSummary[];
  workOrder?: ExistingOrder;
  role?: string;
  people?: Person[];
  facilities?: Option[];
  areas?: Area[];
}) {
  const router = useRouter();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const isEdit = Boolean(workOrder?.id);
  const superior = role !== undefined && role !== "technician";
  const technicians = people.filter((person) => person.role === "technician");
  const input = "w-full rounded-lg border border-slate-300 px-3 py-2 text-sm";

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setSaving(true); setError(null);
    const form = new FormData(event.currentTarget);
    const payload: Record<string, FormDataEntryValue | null> = Object.fromEntries(form.entries());
    for (const key of ["facility_area_id", "category_id", "department_id", "asset_id", "due_date", "estimated_hours", "health_score_at_creation", "failure_probability", "predicted_failure_date", "confidence_score"]) {
      if (payload[key] === "") payload[key] = null;
    }
    const copied = form.getAll("copied_party_ids").map(String);
    try {
      const response = await fetch(isEdit ? `/api/work-orders/${workOrder!.id}` : "/api/work-orders", {
        method: isEdit ? "PATCH" : "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(isEdit ? payload : { ...payload, emergency_work: form.get("emergency_work") === "on", in_house_work: form.get("in_house_work") === "on", copied_party_ids: copied, assigned_technician_id: payload.assigned_technician_id || null, facility_id: payload.facility_id || null }),
      });
      const result = await response.json();
      if (!response.ok) { setError(result.message ?? result.error ?? "Unable to save work order."); return; }
      const id = String(result.data?.id ?? workOrder?.id);
      router.push(isEdit ? `/work-orders/${id}` : `/work-orders/${id}?created=1#next-steps`); router.refresh();
    } catch { setError("Unable to reach the work-order service."); }
    finally { setSaving(false); }
  }

  const value = (key: string) => workOrder?.[key] ?? "";
  return (
    <form onSubmit={submit} className="space-y-5 rounded-xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
      {!isEdit && (
        <p className="rounded-lg border border-blue-200 bg-blue-50 p-3 text-sm text-blue-950">
          Fill in the essentials and create the Draft. You can add photos, mark the location on the layout plan and attach the quotation afterwards — on this device or your computer — before you submit it. Your Drafts are under <strong>My Drafts</strong>. <a href="/help/work-orders" className="font-semibold underline">How to fill in a Work Order</a>
        </p>
      )}
      <div><label className="mb-1 block text-sm font-medium">Title *</label><input required minLength={3} maxLength={200} name="title" className={input} defaultValue={String(value("title"))} /></div>
      <div><label className="mb-1 block text-sm font-medium">Reason the work is needed *</label><textarea required minLength={10} rows={4} name="description" className={input} defaultValue={String(value("description"))} placeholder="What is wrong, why it needs fixing, and any safety or operational impact." /></div>
      {!isEdit && (
        <label className="flex items-start gap-3 rounded-lg border-2 border-red-200 bg-red-50 p-4 text-sm">
          <input type="checkbox" name="emergency_work" className="mt-1 h-5 w-5" />
          <span><span className="font-bold text-red-900">Emergency — contractor to start immediately</span><br /><span className="text-red-800">No quotation is needed before work starts. Approvers are notified on submission. The contractor&apos;s quotation follows after the work and is approved at review.</span></span>
        </label>
      )}
      {!isEdit && (
        <label className="flex items-start gap-3 rounded-lg border-2 border-teal-200 bg-teal-50 p-4 text-sm">
          <input type="checkbox" name="in_house_work" className="mt-1 h-5 w-5" />
          <span><span className="font-bold text-teal-900">In-house services — no pricing</span><br /><span className="text-teal-800">The work is done by in-house staff. It is approved, carried out and reviewed as normal, but no quotation, invoice or payment is required.</span></span>
        </label>
      )}
      {!isEdit && superior && (
        <div className="grid gap-4 rounded-lg border border-violet-200 bg-violet-50 p-4 sm:grid-cols-2">
          <p className="text-sm text-violet-900 sm:col-span-2">You are creating this because the Technician is unavailable. Assign the Technician who will witness the work. You cannot approve a Work Order you created.</p>
          <div><label className="mb-1 block text-sm font-medium">Field-witness Technician</label><select name="assigned_technician_id" className={input} defaultValue=""><option value="">Assign later (required before submission)</option>{technicians.map((person) => <option key={person.id} value={person.id}>{person.name}</option>)}</select></div>
          {facilities.length > 1 && <div><label className="mb-1 block text-sm font-medium">Facility</label><select name="facility_id" className={input} defaultValue=""><option value="">From the asset or my membership</option>{facilities.map((facility) => <option key={facility.id} value={facility.id}>{facility.name}</option>)}</select></div>}
        </div>
      )}
      {!isEdit && !superior && facilities.length > 1 && (
        <div><label className="mb-1 block text-sm font-medium">Facility</label><select name="facility_id" className={input} defaultValue=""><option value="">From the asset or my membership</option>{facilities.map((facility) => <option key={facility.id} value={facility.id}>{facility.name}</option>)}</select></div>
      )}
      {!isEdit && areas.length > 0 && (
        <div className="rounded-lg border border-blue-200 bg-blue-50 p-4">
          <label className="mb-1 block text-sm font-bold text-blue-950" htmlFor="facility_area_id">Area / room of the work</label>
          <select id="facility_area_id" name="facility_area_id" className={input} defaultValue="" onChange={(event) => {
            const location = event.currentTarget.form?.elements.namedItem("location") as HTMLInputElement | null;
            const chosen = event.currentTarget.selectedOptions[0]?.text.replace(/ — highlighted automatically$/, "") ?? "";
            if (location && !location.value && event.currentTarget.value) location.value = chosen;
          }}>
            <option value="">Choose the area (e.g. Utility Block, Electrical Room)</option>
            {areas.map((area) => <option key={area.id} value={area.id}>{area.name}{area.mapped ? " — highlighted automatically" : ""}</option>)}
          </select>
          <p className="mt-2 text-xs text-blue-900">Areas already placed on the facility layout plan are highlighted automatically on the Work Order. For other areas, mark the spot on the layout plan after creating the Draft — the location is required before submission so everyone, including Finance, can see where the work is.</p>
        </div>
      )}
      <div><label className="mb-1 block text-sm font-medium">Location *</label><input required name="location" className={input} defaultValue={String(value("location"))} placeholder="e.g. Utility Block chiller plant room, pump P-CHW-03" /></div>
      <details open={isEdit} className="rounded-lg border border-slate-200 p-4 [&_summary]:cursor-pointer">
      <summary className="text-sm font-semibold text-slate-800">More details (optional): asset, priority, due date, copy to…</summary>
      <div className="mt-4 space-y-5">
      <div className="grid gap-4 sm:grid-cols-2">
        <div><label className="mb-1 block text-sm font-medium">Site</label><input name="site" className={input} defaultValue={String(value("site"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Contact number</label><input type="tel" autoComplete="tel" maxLength={255} name="contact_number" className={input} defaultValue={String(value("contact_number"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Category</label><select name="category_id" className={input} defaultValue={String(value("category_id"))}><option value="">None</option>{categories.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></div>
        <div><label className="mb-1 block text-sm font-medium">Department</label><select name="department_id" className={input} defaultValue={String(value("department_id"))}><option value="">None</option>{departments.map((item) => <option key={item.id} value={item.id}>{item.code ? `${item.code} — ` : ""}{item.name}</option>)}</select></div>
        <div><label className="mb-1 block text-sm font-medium">Priority</label><select name="priority" className={input} defaultValue={String(value("priority") || "medium")}><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option><option value="critical">Critical</option></select></div>
        <div><label className="mb-1 block text-sm font-medium">Source</label><select name="source" className={input} defaultValue={String(value("source") || "manual")}>{WORK_ORDER_SOURCES.map((source) => <option key={source} value={source}>{operationalLabel(source)}</option>)}</select></div>
        <div><label className="mb-1 block text-sm font-medium">Due date</label><input type="date" name="due_date" className={input} defaultValue={String(value("due_date"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Estimated hours</label><input type="number" min="0" step="0.25" name="estimated_hours" className={input} defaultValue={String(value("estimated_hours"))} /></div>
        {!isEdit && <AssetSelector assets={assets} />}
        <div><label className="mb-1 block text-sm font-medium">Source reference</label><input name="source_reference" className={input} defaultValue={String(value("source_reference"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Alert reference</label><input name="alert_id" className={input} defaultValue={String(value("alert_id"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Prediction reference</label><input name="prediction_reference" className={input} defaultValue={String(value("prediction_reference"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Health score (0–100)</label><input type="number" min="0" max="100" step="0.01" name="health_score_at_creation" className={input} defaultValue={String(value("health_score_at_creation"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Failure probability (0–1)</label><input type="number" min="0" max="1" step="0.001" name="failure_probability" className={input} defaultValue={String(value("failure_probability"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Predicted failure date</label><input type="date" name="predicted_failure_date" className={input} defaultValue={String(value("predicted_failure_date"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Confidence score (0–1)</label><input type="number" min="0" max="1" step="0.001" name="confidence_score" className={input} defaultValue={String(value("confidence_score"))} /></div>
      </div>
      <div><label className="mb-1 block text-sm font-medium">Recommended action</label><textarea rows={2} name="recommended_action" className={input} defaultValue={String(value("recommended_action"))} /></div>
      {!isEdit && people.length > 0 && (
        <fieldset className="rounded-lg border border-slate-200 p-4">
          <legend className="px-1 text-sm font-medium">Copy to (notified at each stage and on invoice upload)</legend>
          <p className="text-xs text-slate-500">Finance is copied automatically when the Work Order is Completed.</p>
          <div className="mt-2 grid max-h-56 gap-1 overflow-y-auto sm:grid-cols-2">
            {people.filter((person) => !["technician", "finance"].includes(person.role)).map((person) => (
              <label key={person.id} className="flex min-h-10 items-center gap-3 text-sm"><input type="checkbox" name="copied_party_ids" value={person.id} />{person.name} <span className="text-slate-500">· {operationalLabel(person.role)}</span></label>
            ))}
          </div>
        </fieldset>
      )}
      <div><label className="mb-1 block text-sm font-medium">Internal notes</label><textarea rows={2} name="internal_notes" className={input} defaultValue={String(value("internal_notes"))} /></div>
      </div>
      </details>
      {error && <p className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
      <div className="flex flex-wrap gap-3">
        <button disabled={saving} className="min-h-11 w-full rounded-lg bg-slate-900 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50 sm:w-auto" type="submit">{saving ? "Saving…" : isEdit ? "Save changes" : "Create Draft"}</button>
        {!isEdit && <p className="self-center text-sm text-slate-600">Next: attach photos, video or voice notes and the contractor quotation, then submit for approval.</p>}
      </div>
    </form>
  );
}
