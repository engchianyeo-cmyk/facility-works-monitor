"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { WorkOrderAction, WorkOrderStatus } from "@/lib/work-orders/types";

const ACTIONS: Record<WorkOrderStatus, { action: WorkOrderAction; label: string }[]> = {
  draft: [{ action: "submit", label: "Submit" }],
  submitted: [{ action: "approve", label: "Approve" }],
  approved: [],
  assigned: [{ action: "accept", label: "Accept assignment" }, { action: "start", label: "Start work" }],
  in_progress: [{ action: "complete", label: "Complete work" }],
  completed: [{ action: "review", label: "Review completion" }],
  reviewed: [{ action: "close", label: "Close work order" }],
  closed: [],
  cancelled: [],
};

export default function WorkOrderActions({
  id,
  status,
  allowedActions,
  canEdit,
  canDuplicate,
}: {
  id: string;
  status: WorkOrderStatus;
  allowedActions: WorkOrderAction[];
  canEdit: boolean;
  canDuplicate: boolean;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const actions = ACTIONS[status].filter(({ action }) => allowedActions.includes(action));

  async function transition(action: WorkOrderAction) {
    const payload: Record<string, unknown> = { action };
    if (action === "approve") {
      const reason = window.prompt("Administrator override reason (leave blank when this is not a self-approval):");
      if (reason) payload.reason = reason.trim();
    }
    if (action === "complete") {
      const completionNotes = window.prompt("Completion notes (required):");
      if (completionNotes === null) return;
      const actualHours = window.prompt("Actual labour hours (required):");
      if (actualHours === null) return;
      payload.completion_notes = completionNotes.trim(); payload.actual_labour_hours = actualHours.trim();
    }
    setBusy(action); setError(null); setMessage(null);
    try {
      const response = await fetch(`/api/work-orders/${id}/transition`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload) });
      const result = await response.json();
      if (!response.ok) { setError(result.message ?? result.error ?? "Transition failed."); return; }
      if (action === "accept") setMessage("Assignment accepted. You can now start work when ready.");
      router.refresh();
    } catch { setError("Unable to reach the workflow service."); }
    finally { setBusy(null); }
  }

  async function cancel() {
    const reason = window.prompt("Cancellation reason (required):");
    if (reason === null || !reason.trim()) return;
    setBusy("cancel"); setError(null);
    try {
      const response = await fetch(`/api/work-orders/${id}/transition`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "cancel", reason: reason.trim() }) });
      const result = await response.json();
      if (!response.ok) { setError(result.message ?? result.error ?? "Cancellation failed."); return; }
      router.refresh();
    } catch { setError("Unable to reach the workflow service."); }
    finally { setBusy(null); }
  }

  async function duplicate() {
    setBusy("duplicate"); setError(null);
    try {
      const response = await fetch(`/api/work-orders/${id}/duplicate`, { method: "POST" });
      const result = await response.json();
      if (!response.ok) { setError(result.message ?? result.error ?? "Duplication failed."); return; }
      router.push(`/work-orders/${result.data.id}/edit`); router.refresh();
    } catch { setError("Unable to reach the work-order service."); }
    finally { setBusy(null); }
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {canEdit && <button className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold" onClick={() => router.push(`/work-orders/${id}/edit`)}>Edit</button>}
        {actions.map(({ action, label }) => <button key={action} disabled={busy !== null} onClick={() => transition(action)} className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{busy === action ? "Working…" : label}</button>)}
        {allowedActions.includes("cancel") && <button disabled={busy !== null} onClick={cancel} className="rounded-lg border border-red-300 px-4 py-2 text-sm font-semibold text-red-700 disabled:opacity-50">{busy === "cancel" ? "Cancelling…" : "Cancel work order"}</button>}
        {canDuplicate && <button disabled={busy !== null} onClick={duplicate} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold disabled:opacity-50">{busy === "duplicate" ? "Duplicating…" : "Duplicate as draft"}</button>}
      </div>
      {error && <p className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
      {message && <p className="rounded-lg bg-emerald-50 p-3 text-sm text-emerald-700" role="status">{message}</p>}
    </div>
  );
}
