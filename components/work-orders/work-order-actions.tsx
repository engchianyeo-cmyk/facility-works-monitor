"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { priorityLabel, workOrderStatusLabel } from "@/lib/product-terminology";
import { authorizedExecutionActions, EXECUTION_SUCCESS, executionResponseMessage, validateCompletionDraft } from "@/lib/work-orders/execution-interaction";
import type { WorkOrderAction, WorkOrderStatus } from "@/lib/work-orders/types";
import type { CompletionSnapshot } from "@/lib/work-orders/rework";

type Interaction = "approve" | "complete" | "review" | "return_for_rework" | "cancel" | null;
type SubmissionState = "online" | "submitting" | "failed" | "unavailable";

type Props = {
  id: string;
  reference: string;
  title: string;
  location: string;
  priority: string;
  dueDate: string | null;
  overdue: boolean;
  technician: boolean;
  status: WorkOrderStatus;
  allowedActions: WorkOrderAction[];
  canEdit: boolean;
  canDuplicate: boolean;
  reviewContext?: {
    requestedWork: string;
    assignee: string;
    completionNotes: string | null;
    cumulativeLabourHours: number | null;
    completedAt: string | null;
    evidence: string;
    relatedIncident: string | null;
    priorCycles: CompletionSnapshot[];
  };
  currentRework?: CompletionSnapshot | null;
};

function dueLabel(dueDate: string | null, overdue: boolean) {
  if (!dueDate) return "Due date not recorded";
  const parsed = new Date(`${dueDate}T00:00:00Z`);
  const formatted = Number.isNaN(parsed.getTime())
    ? dueDate
    : new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeZone: "UTC" }).format(parsed);
  return overdue ? `Overdue · Due ${formatted}` : `Due ${formatted}`;
}

function dateTimeLabel(value: string | null) {
  if (!value) return "Not recorded";
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? "Unavailable"
    : new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short" }).format(parsed);
}

export default function WorkOrderActions(props: Props) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [interaction, setInteraction] = useState<Interaction>(null);
  const [completionNotes, setCompletionNotes] = useState("");
  const [actualHours, setActualHours] = useState("");
  const [approvalReason, setApprovalReason] = useState("");
  const [cancellationReason, setCancellationReason] = useState("");
  const [reviewReason, setReviewReason] = useState("");
  const [reworkReason, setReworkReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [submissionState, setSubmissionState] = useState<SubmissionState>("online");
  const submittingRef = useRef(false);
  const actions = useMemo(() => authorizedExecutionActions(props.status, props.allowedActions), [props.allowedActions, props.status]);
  const decisionActions = actions.filter(({ action }) => action === "review" || action === "return_for_rework");
  const primary = actions.find(({ action }) => action !== "review" && action !== "return_for_rework") ?? null;

  useEffect(() => {
    const update = () => setSubmissionState(navigator.onLine ? "online" : "unavailable");
    update();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => { window.removeEventListener("online", update); window.removeEventListener("offline", update); };
  }, []);

  function openAction(action: WorkOrderAction) {
    setError(null); setMessage(null);
    if (action === "complete" || action === "cancel" || action === "approve" || action === "review" || action === "return_for_rework") {
      setInteraction(action);
      return;
    }
    void transition(action, {});
  }

  async function transition(action: WorkOrderAction, payload: Record<string, unknown>) {
    if (submittingRef.current) return;
    if (!navigator.onLine) {
      setSubmissionState("unavailable");
      setError("No network connection is available. Nothing was submitted. Reconnect and retry.");
      return;
    }
    submittingRef.current = true; setBusy(action); setError(null); setMessage(null); setSubmissionState("submitting");
    try {
      const response = await fetch(`/api/work-orders/${props.id}/transition`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action, ...payload }),
      });
      const result = await response.json() as Record<string, unknown>;
      if (!response.ok) {
        setSubmissionState(response.status >= 500 ? "unavailable" : "failed");
        setError(executionResponseMessage(response.status, result));
        return;
      }
      setSubmissionState("online");
      setMessage(EXECUTION_SUCCESS[action] ?? "The server confirmed this action.");
      router.refresh();
    } catch {
      setSubmissionState("failed");
      setError("The network request failed. Nothing was submitted. Check your connection and retry.");
    } finally {
      submittingRef.current = false; setBusy(null);
    }
  }

  function submitCompletion(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const result = validateCompletionDraft(completionNotes, actualHours);
    if (!result.ok) { setError(result.error); return; }
    void transition("complete", result.payload);
  }

  function submitApproval(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const reason = approvalReason.trim();
    void transition("approve", reason ? { reason } : {});
  }

  function submitCancellation(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const reason = cancellationReason.trim();
    if (!reason) { setError("A cancellation reason is required."); return; }
    void transition("cancel", { reason });
  }

  function submitReview(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const reason = reviewReason.trim();
    void transition("review", reason ? { reason } : {});
  }

  function submitRework(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const reason = reworkReason.trim();
    if (!reason) { setError("A rework reason is required."); return; }
    void transition("return_for_rework", { reason });
  }

  async function duplicate() {
    if (submittingRef.current) return;
    submittingRef.current = true; setBusy("duplicate"); setError(null); setMessage(null); setSubmissionState("submitting");
    try {
      const response = await fetch(`/api/work-orders/${props.id}/duplicate`, { method: "POST" });
      const result = await response.json() as { data?: { id?: string }; message?: string; error?: string };
      if (!response.ok || !result.data?.id) {
        setSubmissionState(response.status >= 500 ? "unavailable" : "failed");
        setError(executionResponseMessage(response.status, result as Record<string, unknown>));
        return;
      }
      setSubmissionState("online");
      router.push(`/work-orders/${result.data.id}/edit`); router.refresh();
    } catch {
      setSubmissionState("failed");
      setError("The network request failed. No duplicate was created. Check your connection and retry.");
    } finally { submittingRef.current = false; setBusy(null); }
  }

  const stateLabel = submissionState === "online" ? "ONLINE" : submissionState === "submitting" ? "SUBMITTING" : submissionState === "failed" ? "FAILED · RETRY REQUIRED" : "UNAVAILABLE";

  return (
    <section aria-labelledby="execution-title" className="overflow-hidden rounded-2xl border-2 border-blue-200 bg-white shadow-sm">
      <div className="bg-slate-950 p-5 text-white sm:p-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0"><p className="font-mono text-xs font-black tracking-wide text-blue-300">{props.reference}</p><h2 id="execution-title" className="mt-1 text-xl font-black">{props.technician ? "Technician execution" : "Work Order actions"}</h2></div>
          <span data-submission-state={submissionState} className="rounded-full border border-slate-600 px-3 py-1 text-xs font-black">{stateLabel}</span>
        </div>
        <h3 className="mt-4 text-lg font-black">{props.title}</h3>
        <p className="mt-1 text-sm text-slate-200">{props.location}</p>
        <dl className="mt-4 grid grid-cols-2 gap-3 text-sm">
          <div><dt className="text-xs font-bold text-slate-400">Priority</dt><dd className="mt-1 font-black">{priorityLabel(props.priority)}</dd></div>
          <div><dt className="text-xs font-bold text-slate-400">Status</dt><dd className="mt-1 font-black">{workOrderStatusLabel(props.status)}</dd></div>
          <div className="col-span-2"><dt className="text-xs font-bold text-slate-400">Due</dt><dd className={`mt-1 font-black ${props.overdue ? "text-amber-300" : ""}`}>{dueLabel(props.dueDate, props.overdue)}</dd></div>
        </dl>
      </div>

      <div className="space-y-5 p-5 sm:p-6">
        {props.currentRework && (
          <section aria-labelledby="rework-context-title" className="rounded-xl border-2 border-orange-300 bg-orange-50 p-4 text-orange-950">
            <p className="text-xs font-black uppercase tracking-wide">Rework cycle {props.currentRework.cycle}</p>
            <h3 id="rework-context-title" className="mt-1 font-black">Completion returned for correction</h3>
            <p className="mt-2 whitespace-pre-wrap text-sm"><span className="font-bold">Required correction:</span> {props.currentRework.reason}</p>
            <p className="mt-2 text-xs">Returned by {props.currentRework.actor} on {dateTimeLabel(props.currentRework.returnedAt)}. Prior completion evidence remains in the audit record.</p>
            <p className="mt-2 text-sm font-bold">When resubmitting, labour hours must be the cumulative total across all completion cycles.</p>
          </section>
        )}

        {props.reviewContext && decisionActions.length > 0 && (
          <section aria-labelledby="completion-decision-title" className="space-y-4 rounded-xl border-2 border-violet-200 bg-violet-50 p-4 text-violet-950">
            <div><p className="text-xs font-black uppercase tracking-wide text-violet-700">Completion decision</p><h3 id="completion-decision-title" className="mt-1 text-lg font-black">Review the completed work</h3></div>
            <dl className="grid gap-3 text-sm sm:grid-cols-2">
              <div><dt className="font-bold text-violet-700">Requested work</dt><dd className="mt-1 whitespace-pre-wrap">{props.reviewContext.requestedWork}</dd></div>
              <div><dt className="font-bold text-violet-700">Assigned technician</dt><dd className="mt-1">{props.reviewContext.assignee}</dd></div>
              <div><dt className="font-bold text-violet-700">Completion statement</dt><dd className="mt-1 whitespace-pre-wrap">{props.reviewContext.completionNotes ?? "Completion statement unavailable"}</dd></div>
              <div><dt className="font-bold text-violet-700">Cumulative labour</dt><dd className="mt-1">{props.reviewContext.cumulativeLabourHours ?? "Unavailable"} hours</dd></div>
              <div><dt className="font-bold text-violet-700">Completed</dt><dd className="mt-1">{dateTimeLabel(props.reviewContext.completedAt)}</dd></div>
              <div><dt className="font-bold text-violet-700">Evidence</dt><dd className="mt-1">{props.reviewContext.evidence}</dd></div>
              {props.reviewContext.relatedIncident && <div className="sm:col-span-2"><dt className="font-bold text-violet-700">Related incident</dt><dd className="mt-1">{props.reviewContext.relatedIncident}</dd></div>}
            </dl>
            <a href="#work-order-evidence" className="inline-flex min-h-11 items-center font-black text-violet-800 underline decoration-2 underline-offset-4 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-violet-200">Review evidence record</a>
            {props.reviewContext.priorCycles.length > 0 && <details className="rounded-lg border border-violet-200 bg-white p-3"><summary className="cursor-pointer font-bold">Prior rework cycles ({props.reviewContext.priorCycles.length})</summary><ol className="mt-3 space-y-3">{props.reviewContext.priorCycles.map((cycle) => <li key={`${cycle.cycle}-${cycle.returnedAt}`} className="border-l-4 border-orange-300 pl-3 text-sm"><p className="font-bold">Cycle {cycle.cycle}: {cycle.reason}</p><p className="mt-1">Prior completion: {cycle.completionNotes ?? "Unavailable"} · {cycle.cumulativeLabourHours ?? "Unavailable"} hours · {cycle.evidenceIds.length} evidence item(s)</p></li>)}</ol></details>}
            <div className="grid gap-3 sm:grid-cols-2">
              {decisionActions.some(({ action }) => action === "review") && <button type="button" disabled={busy !== null} onClick={() => openAction("review")} className="min-h-12 rounded-xl bg-emerald-700 px-5 font-black text-white disabled:opacity-50">Accept completion</button>}
              {decisionActions.some(({ action }) => action === "return_for_rework") && <button type="button" disabled={busy !== null} onClick={() => openAction("return_for_rework")} className="min-h-12 rounded-xl border-2 border-orange-400 bg-white px-5 font-black text-orange-900 disabled:opacity-50">Return for rework</button>}
            </div>
          </section>
        )}

        <div className="rounded-xl border border-blue-100 bg-blue-50 p-4 text-sm text-blue-950">
          <p className="font-black">Before you finish</p>
          <p className="mt-1">Completion requires a clear work summary and labour hours. Evidence can be added below when it helps record the work; no mandatory evidence requirement is recorded for this workflow.</p>
        </div>

        {primary ? <div><p className="mb-2 text-xs font-black uppercase tracking-wide text-slate-500">Next authorized action</p><button type="button" disabled={busy !== null} onClick={() => openAction(primary.action)} className="min-h-12 w-full rounded-xl bg-blue-700 px-5 py-3 text-base font-black text-white shadow-sm hover:bg-blue-800 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-blue-300 disabled:cursor-not-allowed disabled:opacity-50">{busy === primary.action ? "Submitting…" : props.currentRework && primary.action === "complete" ? "Record corrected completion" : primary.label}</button></div> : decisionActions.length === 0 && <p className="rounded-xl border border-dashed border-slate-300 p-4 text-sm text-slate-600">No workflow action is currently available for your role and this Work Order state.</p>}

        {interaction === "complete" && <form onSubmit={submitCompletion} aria-describedby="completion-help execution-error" className="space-y-4 rounded-xl border border-blue-200 bg-slate-50 p-4"><div><h3 className="font-black">Record completion</h3><p id="completion-help" className="mt-1 text-sm text-slate-600">The Work Order will become Completed — Awaiting Review only after the server confirms submission.</p></div><label className="block text-sm font-bold">Completion notes <span aria-hidden="true">*</span><textarea required rows={5} maxLength={4000} value={completionNotes} onChange={(event) => setCompletionNotes(event.target.value)} className="mt-1 min-h-32 w-full rounded-lg border border-slate-300 bg-white p-3 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-blue-200" placeholder="Summarize the work completed and the resulting condition." /></label><label className="block text-sm font-bold">Labour hours <span aria-hidden="true">*</span><input required type="number" min="0" step="0.25" inputMode="decimal" value={actualHours} onChange={(event) => setActualHours(event.target.value)} className="mt-1 min-h-12 w-full rounded-lg border border-slate-300 bg-white px-3 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-blue-200" /></label><div className="rounded-lg bg-white p-3 text-sm"><span className="font-bold">Evidence status:</span> No mandatory requirement is recorded. Review the Evidence panel below before submitting if photographs or documents support the completion record.</div><div className="grid gap-3 sm:grid-cols-2"><button disabled={busy !== null} className="min-h-12 rounded-xl bg-blue-700 px-5 font-black text-white focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-blue-300 disabled:opacity-50">{busy === "complete" ? "Submitting completion…" : "Submit completion"}</button><button type="button" disabled={busy !== null} onClick={() => setInteraction(null)} className="min-h-12 rounded-xl border border-slate-300 bg-white px-5 font-bold focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-slate-300">Keep working</button></div></form>}

        {interaction === "review" && <form onSubmit={submitReview} aria-describedby="review-help execution-error" className="space-y-4 rounded-xl border border-emerald-200 bg-emerald-50 p-4"><div><h3 className="font-black text-emerald-950">Accept completion</h3><p id="review-help" className="mt-1 text-sm text-emerald-900">This records the completion decision. An Administrator reviewing their own completion must provide an override reason.</p></div><label className="block text-sm font-bold text-emerald-950">Decision reason, when applicable<textarea rows={3} maxLength={2000} value={reviewReason} onChange={(event) => setReviewReason(event.target.value)} className="mt-1 w-full rounded-lg border border-emerald-300 bg-white p-3" /></label><div className="grid gap-3 sm:grid-cols-2"><button disabled={busy !== null} className="min-h-12 rounded-xl bg-emerald-700 px-5 font-black text-white disabled:opacity-50">{busy === "review" ? "Recording decision…" : "Confirm acceptance"}</button><button type="button" disabled={busy !== null} onClick={() => setInteraction(null)} className="min-h-12 rounded-xl border border-slate-300 bg-white px-5 font-bold">Back</button></div></form>}

        {interaction === "return_for_rework" && <form onSubmit={submitRework} aria-describedby="rework-help execution-error" className="space-y-4 rounded-xl border border-orange-300 bg-orange-50 p-4"><div><h3 className="font-black text-orange-950">Return for rework</h3><p id="rework-help" className="mt-1 text-sm text-orange-900">State exactly what must be corrected. The prior completion and evidence remain in immutable activity history.</p></div><label className="block text-sm font-bold text-orange-950">Required correction <span aria-hidden="true">*</span><textarea required rows={4} maxLength={2000} value={reworkReason} onChange={(event) => setReworkReason(event.target.value)} className="mt-1 w-full rounded-lg border border-orange-300 bg-white p-3" /></label><div className="grid gap-3 sm:grid-cols-2"><button disabled={busy !== null} className="min-h-12 rounded-xl bg-orange-700 px-5 font-black text-white disabled:opacity-50">{busy === "return_for_rework" ? "Returning…" : "Confirm return for rework"}</button><button type="button" disabled={busy !== null} onClick={() => setInteraction(null)} className="min-h-12 rounded-xl border border-slate-300 bg-white px-5 font-bold">Back</button></div></form>}

        {interaction === "approve" && <form onSubmit={submitApproval} aria-describedby="approval-help execution-error" className="space-y-4 rounded-xl border border-blue-200 bg-slate-50 p-4"><div><h3 className="font-black">Confirm approval</h3><p id="approval-help" className="mt-1 text-sm text-slate-600">An override reason is required by the server only for an Administrator approving their own request.</p></div><label className="block text-sm font-bold">Override reason, when applicable<textarea rows={3} maxLength={1000} value={approvalReason} onChange={(event) => setApprovalReason(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 bg-white p-3 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-blue-200" /></label><div className="grid gap-3 sm:grid-cols-2"><button disabled={busy !== null} className="min-h-12 rounded-xl bg-blue-700 px-5 font-black text-white disabled:opacity-50">{busy === "approve" ? "Submitting approval…" : "Confirm approval"}</button><button type="button" disabled={busy !== null} onClick={() => setInteraction(null)} className="min-h-12 rounded-xl border border-slate-300 bg-white px-5 font-bold">Back</button></div></form>}

        {interaction === "cancel" && <form onSubmit={submitCancellation} aria-describedby="cancellation-help execution-error" className="space-y-4 rounded-xl border border-red-200 bg-red-50 p-4"><div><h3 className="font-black text-red-950">Cancel Work Order</h3><p id="cancellation-help" className="mt-1 text-sm text-red-900">Cancellation is recorded in activity history and does not delete the Work Order.</p></div><label className="block text-sm font-bold text-red-950">Cancellation reason <span aria-hidden="true">*</span><textarea required rows={4} maxLength={2000} value={cancellationReason} onChange={(event) => setCancellationReason(event.target.value)} className="mt-1 w-full rounded-lg border border-red-300 bg-white p-3 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-red-200" /></label><div className="grid gap-3 sm:grid-cols-2"><button disabled={busy !== null} className="min-h-12 rounded-xl bg-red-700 px-5 font-black text-white disabled:opacity-50">{busy === "cancel" ? "Submitting cancellation…" : "Confirm cancellation"}</button><button type="button" disabled={busy !== null} onClick={() => setInteraction(null)} className="min-h-12 rounded-xl border border-slate-300 bg-white px-5 font-bold">Keep Work Order</button></div></form>}

        {(props.canEdit || props.allowedActions.includes("cancel") || props.canDuplicate) && <div className="border-t border-slate-200 pt-4"><p className="mb-3 text-xs font-black uppercase tracking-wide text-slate-500">Secondary actions</p><div className="grid gap-3 sm:grid-cols-2">{props.canEdit && <button type="button" disabled={busy !== null} className="min-h-11 rounded-lg border border-slate-300 px-4 text-sm font-bold focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-slate-300" onClick={() => router.push(`/work-orders/${props.id}/edit`)}>Edit Work Order</button>}{props.allowedActions.includes("cancel") && <button type="button" disabled={busy !== null} onClick={() => openAction("cancel")} className="min-h-11 rounded-lg border border-red-300 px-4 text-sm font-bold text-red-700 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-red-200">Cancel Work Order</button>}{props.canDuplicate && <button type="button" disabled={busy !== null} onClick={() => void duplicate()} className="min-h-11 rounded-lg border border-slate-300 px-4 text-sm font-bold focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-slate-300">{busy === "duplicate" ? "Creating draft…" : "Duplicate as draft"}</button>}</div></div>}

        {error && <div id="execution-error" role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-semibold text-red-800">{error}</div>}
        {message && <div role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm font-semibold text-emerald-800">{message}</div>}
      </div>
    </section>
  );
}
