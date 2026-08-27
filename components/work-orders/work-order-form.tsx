"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { WORK_ORDER_SOURCES } from "@/lib/work-orders/types";
import { operationalLabel } from "@/lib/product-terminology";
import AssetSelector from "@/components/assets/asset-selector";
import type { AssetSummary } from "@/lib/assets/types";

type Option = { id: string; name: string; code?: string };
type ExistingOrder = Record<string, string | number | null | undefined>;

export default function WorkOrderForm({
  categories,
  departments,
  assets,
  workOrder,
}: {
  categories: Option[];
  departments: Option[];
  assets: AssetSummary[];
  workOrder?: ExistingOrder;
}) {
  const router = useRouter();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const isEdit = Boolean(workOrder?.id);
  const input = "w-full rounded-lg border border-slate-300 px-3 py-2 text-sm";

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setSaving(true); setError(null);
    const form = new FormData(event.currentTarget);
    const payload: Record<string, FormDataEntryValue | null> = Object.fromEntries(form.entries());
    for (const key of ["category_id", "department_id", "asset_id", "due_date", "estimated_hours", "health_score_at_creation", "failure_probability", "predicted_failure_date", "confidence_score"]) {
      if (payload[key] === "") payload[key] = null;
    }
    payload.submit = String((event.nativeEvent as SubmitEvent).submitter?.getAttribute("data-submit")) === "true" ? "true" : "false";
    try {
      const response = await fetch(isEdit ? `/api/work-orders/${workOrder!.id}` : "/api/work-orders", {
        method: isEdit ? "PATCH" : "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...payload, submit: payload.submit === "true" }),
      });
      const result = await response.json();
      if (!response.ok) { setError(result.message ?? result.error ?? "Unable to save work order."); return; }
      const id = String(result.data?.id ?? workOrder?.id);
      router.push(`/work-orders/${id}`); router.refresh();
    } catch { setError("Unable to reach the work-order service."); }
    finally { setSaving(false); }
  }

  const value = (key: string) => workOrder?.[key] ?? "";
  return (
    <form onSubmit={submit} className="space-y-5 rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
      <div><label className="mb-1 block text-sm font-medium">Title *</label><input required minLength={3} maxLength={200} name="title" className={input} defaultValue={String(value("title"))} /></div>
      <div><label className="mb-1 block text-sm font-medium">Description</label><textarea rows={4} name="description" className={input} defaultValue={String(value("description"))} /></div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div><label className="mb-1 block text-sm font-medium">Site</label><input name="site" className={input} defaultValue={String(value("site"))} /></div>
        <div><label className="mb-1 block text-sm font-medium">Location *</label><input required name="location" className={input} defaultValue={String(value("location"))} /></div>
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
      <div><label className="mb-1 block text-sm font-medium">Internal notes</label><textarea rows={2} name="internal_notes" className={input} defaultValue={String(value("internal_notes"))} /></div>
      {error && <p className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
      <div className="flex flex-wrap gap-3">
        <button disabled={saving} className="rounded-lg bg-slate-900 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50" type="submit">{saving ? "Saving…" : isEdit ? "Save changes" : "Save draft"}</button>
        {!isEdit && <button data-submit="true" disabled={saving} className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50" type="submit">Create and submit</button>}
      </div>
    </form>
  );
}
