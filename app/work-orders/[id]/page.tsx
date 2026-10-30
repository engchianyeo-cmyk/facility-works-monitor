import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import WorkOrderDrawings from "@/components/work-order-drawings";
import ReleaseOneWorkspace from "@/components/work-orders/release-one-workspace";
import EvidencePanel from "@/components/evidence/evidence-panel";
import DocumentCorrectionControl from "@/components/work-orders/document-correction-control";
import TechnicianPicker from "@/components/work-orders/technician-picker";
import CopiedParties from "@/components/work-orders/copied-parties";
import ActualWorkTimes from "@/components/work-orders/actual-work-times";
import TechnicianEndorsement, { type Endorsement, type QuotationSummary } from "@/components/work-orders/technician-endorsement";
import WorkCompletionSteps, { type CompletionStep } from "@/components/work-orders/work-completion-steps";
import { DEFAULT_ENDORSEMENT_STAGE, endorsementStageLabel } from "@/lib/facility-settings";
import { canMutateWorkOrderEvidence } from "@/lib/evidence";
import WorkOrderActions from "@/components/work-orders/work-order-actions";
import DraftNextSteps from "@/components/work-orders/draft-next-steps";
import { draftNextSteps } from "@/lib/work-orders/next-steps";
import WorkOrderAssignment from "@/components/work-orders/work-order-assignment";
import WorkOrderDecisionHeader from "@/components/work-orders/work-order-decision-header";
import AssetLinkControl from "@/components/assets/asset-link-control";
import { getCurrentIdentity } from "@/lib/auth";
import { assetReferenceLabel } from "@/lib/assets/presentation";
import { canLinkWorkOrderAsset, type AssetSummary } from "@/lib/assets/types";
import { operationalLabel, workOrderStatusLabel } from "@/lib/product-terminology";
import { createClient } from "@/lib/supabase/server";
import { buildWorkOrderDecisionModel, safeHumanLabel } from "@/lib/work-orders/decision-header";
import { authorizedExecutionActions } from "@/lib/work-orders/execution-interaction";
import { canAct, canAssign, canEdit, canRecordWork, canSetTechnician, isApprovalAuthority, isPreparer } from "@/lib/work-orders/permissions";
import { deriveWorkOrderOperationalStage } from "@/lib/work-orders/operational-stage";
import { FACILITY_DRAWING_COLUMNS, facilityDrawingSrc, markupDrawingsFor, type FacilityDrawingRow } from "@/lib/facility-drawings";
import { activeReworkContext, reworkHistory } from "@/lib/work-orders/rework";
import {
  WORK_ORDER_ACTIONS,
  type WorkOrderAction,
  type WorkOrderStatus,
} from "@/lib/work-orders/types";

export const revalidate = 0;

/** Lifecycle v2 steps shown in the Workflow timeline (stage names follow Roles & Stages). */
function timelineSteps(order: Record<string, unknown>, endorsedAt: { submission: string | null; review: string | null }, endorsementSetting: string) {
  const at = (value: unknown) => (typeof value === "string" && value ? value : null);
  const steps: Array<{ key: string; label: string; at: string | null; note?: string }> = [
    { key: "created", label: `${workOrderStatusLabel("draft")} created`, at: at(order.created_at) },
  ];
  if (["before_submission", "both"].includes(endorsementSetting) && !order.emergency_work) steps.push({ key: "endorse-submission", label: "Second Technician endorsed (before submission)", at: endorsedAt.submission });
  steps.push(
    { key: "submitted", label: `Submitted — ${workOrderStatusLabel("submitted")}`, at: at(order.submitted_at) },
    { key: "approved", label: workOrderStatusLabel("approved"), at: at(order.approved_at) },
    { key: "started", label: "Work started (actual)", at: at(order.actual_work_started_at) ?? at(order.started_at) },
    { key: "finished", label: "Work finished (actual)", at: at(order.actual_work_ended_at) },
    { key: "completed", label: workOrderStatusLabel("completed"), at: at(order.completed_at) },
  );
  if (["before_review", "both"].includes(endorsementSetting) || order.emergency_work) steps.push({ key: "endorse-review", label: "Second Technician endorsed (work and final cost)", at: endorsedAt.review });
  steps.push(
    { key: "reviewed", label: workOrderStatusLabel("reviewed"), at: at(order.reviewed_at) },
    { key: "closed", label: `${workOrderStatusLabel("closed")} (paid or no payment due)`, at: at(order.closed_at) },
  );
  if (at(order.cancelled_at)) steps.push({ key: "cancelled", label: workOrderStatusLabel("cancelled"), at: at(order.cancelled_at) });
  return steps;
}

/** Elapsed time between two timestamps, e.g. "2 d 3 h 15 min". */
function formatDuration(start: string | null, end: string | null) {
  if (!start || !end) return null;
  const minutes = Math.round((new Date(end).getTime() - new Date(start).getTime()) / 60000);
  if (!Number.isFinite(minutes) || minutes < 0) return null;
  const days = Math.floor(minutes / 1440), hours = Math.floor((minutes % 1440) / 60), rest = minutes % 60;
  return [days ? `${days} d` : "", hours ? `${hours} h` : "", `${rest} min`].filter(Boolean).join(" ");
}

function formatDateTime(value: string | null) {
  if (!value) return "Pending";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Unavailable";
  return new Intl.DateTimeFormat("en-SG", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function display(value: unknown) {
  return value === null || value === undefined || value === "" ? "—" : String(value);
}

function hasValue(value: unknown) {
  return value !== null && value !== undefined && value !== "";
}

function auditNote(value: string | null) {
  if (!value) return null;
  try {
    return JSON.stringify(JSON.parse(value), null, 2);
  } catch {
    return value;
  }
}

function LoadFailure({ message }: { message: string }) {
  return (
    <div className="rounded-lg border border-red-300 bg-red-50 p-4 text-sm text-red-700" role="alert">
      {message}
    </div>
  );
}

export default async function WorkOrderDetailPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const justCreated = (await searchParams)?.created === "1";
  const identity = await getCurrentIdentity();
  if (!identity) redirect(`/login?next=/work-orders/${id}`);

  const supabase = await createClient();
  const orderQuery = supabase
    .from("work_orders")
    .select("*, categories(name), departments(code,name,colour_tag), asset:assets(asset_tag,name,asset_type,criticality,lifecycle_status,site,location,system:asset_systems(name,system_code))")
    .eq("id", id);
  const { data: order, error: orderError } = await orderQuery.maybeSingle();

  if (orderError) {
    return (
      <main className="mx-auto max-w-5xl space-y-6 p-6 lg:p-8">
        <Link href="/work-orders" className="text-sm font-medium text-blue-700 hover:underline">← All work orders</Link>
        <LoadFailure message="This work order could not be loaded. Please try again." />
      </main>
    );
  }
  if (!order) notFound();

  const status = order.status as WorkOrderStatus;
  const context = {
    role: identity.role,
    actorId: identity.userId,
    requesterId: order.requested_by,
    assignedTechnicianId: order.assigned_technician_id,
    status,
  };
  let allowedActions = WORK_ORDER_ACTIONS.filter((action) => canAct(action, context));
  if (status === "assigned") {
    allowedActions = allowedActions.filter((action) => action !== (order.accepted_at ? "accept" : "start"));
  } else {
    allowedActions = allowedActions.filter((action) => action !== "accept");
  }
  if (["closed", "cancelled"].includes(status)) allowedActions = [];

  const assignmentAllowed = canAssign(identity.role, status);
  let assigneeLoadFailed = false;
  let technicians: Array<{ id: string; name: string; detail: string | null }> = [];
  let vendors: Array<{ id: string; name: string; detail: string | null }> = [];
  let teams: Array<{ id: string; name: string }> = [];

  if (assignmentAllowed) {
    const [technicianResult, vendorResult, teamResult] = await Promise.all([
      supabase.from("profiles").select("id,display_name,trade_discipline,department").eq("role", "technician").eq("is_active", true).is("deleted_at", null).order("display_name"),
      supabase.from("vendors").select("id,name,trade").eq("active", true).is("deleted_at", null).order("name"),
      supabase.from("maintenance_teams").select("id,name").eq("is_active", true).is("deleted_at", null).order("name"),
    ]);
    assigneeLoadFailed = Boolean(technicianResult.error || vendorResult.error || teamResult.error);
    if (!assigneeLoadFailed) {
      technicians = (technicianResult.data ?? []).map((item) => ({
        id: item.id,
        name: item.display_name,
        detail: [item.trade_discipline, item.department].filter(Boolean).join(" · ") || null,
      }));
      vendors = (vendorResult.data ?? []).map((item) => ({ id: item.id, name: item.name, detail: item.trade }));
      teams = (teamResult.data ?? []).map((item) => ({ id: item.id, name: item.name }));
    }
  }

  let resolvedAssignee = safeHumanLabel(order.assigned_to);
  if (!resolvedAssignee && order.assigned_technician_id) {
    resolvedAssignee = technicians.find((item) => item.id === order.assigned_technician_id)?.name ?? null;
    if (!resolvedAssignee) {
      const { data } = await supabase.from("profiles").select("display_name").eq("id", order.assigned_technician_id).maybeSingle();
      resolvedAssignee = safeHumanLabel(data?.display_name);
    }
  } else if (!resolvedAssignee && order.assigned_vendor_id) {
    resolvedAssignee = vendors.find((item) => item.id === order.assigned_vendor_id)?.name ?? null;
    if (!resolvedAssignee) {
      const { data } = await supabase.from("vendors").select("name").eq("id", order.assigned_vendor_id).maybeSingle();
      resolvedAssignee = safeHumanLabel(data?.name);
    }
  } else if (!resolvedAssignee && order.assigned_team_id) {
    resolvedAssignee = teams.find((item) => item.id === order.assigned_team_id)?.name ?? null;
    if (!resolvedAssignee) {
      const { data } = await supabase.from("maintenance_teams").select("name").eq("id", order.assigned_team_id).maybeSingle();
      resolvedAssignee = safeHumanLabel(data?.name);
    }
  }

  const [evidenceResult, incidentResult, approvalReadinessResult, verificationReadinessResult, closureReadinessResult] = await Promise.all([
    supabase.from("evidence_items").select("id,category,deleted_at").eq("work_order_id", id),
    order.incident_id
      ? supabase.from("incidents").select("id,incident_number,severity,status").eq("id", order.incident_id).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    ["draft", "submitted"].includes(status) ? supabase.rpc("work_order_approval_summary", { p_work_order_id: id }) : Promise.resolve({ data: null, error: null }),
    status === "completed" && isApprovalAuthority(identity.role)
      ? supabase.rpc("work_order_verification_readiness", { p_work_order_id: id })
      : Promise.resolve({ data: null, error: null }),
    status === "reviewed" ? supabase.rpc("work_order_closure_readiness", { p_work_order_id: id }) : Promise.resolve({ data: null, error: null }),
  ]);
  const evidenceItems = evidenceResult.error ? [] : evidenceResult.data ?? [];
  const evidenceCount = evidenceResult.error ? undefined : evidenceItems.filter((item) => !item.deleted_at).length;
  const hasActiveAfterEvidence = evidenceItems.some((item) => item.category === "after" && !item.deleted_at);
  const operationalStage = deriveWorkOrderOperationalStage({
    status,
    startedAt: order.started_at,
    completionNotes: order.completion_notes,
    actualLabourHours: order.actual_labour_hours,
    evidence: evidenceItems,
  });
  // D-24: contractor work with an approved quotation is submitted with the final cost and the official quotation.
  const quotationPackageRequired = ["assigned", "in_progress"].includes(status) && !order.in_house_work && !order.emergency_work;
  const [controlResult, finalCostResult2] = quotationPackageRequired ? await Promise.all([
    supabase.from("work_order_financial_controls").select("approved_budget").eq("work_order_id", id).maybeSingle(),
    supabase.from("work_order_final_cost_submissions").select("id,status,variation_order").eq("work_order_id", id).maybeSingle(),
  ]) : [{ data: null, error: null }, { data: null, error: null }];
  const approvedBudget = (controlResult.data as { approved_budget: number | null } | null)?.approved_budget ?? null;
  const savedFinalCost = finalCostResult2.data as { id: string; status: string; variation_order: boolean | null } | null;
  const revisedQuotationCount = savedFinalCost?.variation_order === true
    ? (await supabase.from("work_order_final_cost_documents").select("id", { count: "exact", head: true }).eq("final_cost_submission_id", savedFinalCost.id).is("deleted_at", null)).count ?? 0
    : 0;
  const completionMissing = [
    !String(order.completion_notes ?? "").trim() ? "Work-performed statement has not been recorded." : null,
    order.actual_labour_hours === null || Number(order.actual_labour_hours) < 0 ? "Valid cumulative labour hours have not been recorded." : null,
    !hasActiveAfterEvidence ? "At least one active After photo or PDF is required." : null,
    quotationPackageRequired && approvedBudget !== null && (!savedFinalCost || savedFinalCost.status === "draft") ? "Final Cost Reconciliation has not been saved (price unchanged, or variation order with the revised quotation)." : null,
    quotationPackageRequired && approvedBudget !== null && savedFinalCost?.variation_order === true && revisedQuotationCount === 0 ? "The contractor's revised quotation for the variation order has not been attached." : null,
  ].filter((item): item is string => Boolean(item));
  if (completionMissing.length > 0) allowedActions = allowedActions.filter((action) => !["complete", "submit_physical_completion"].includes(action));
  const approvalSummary = approvalReadinessResult.error ? null : approvalReadinessResult.data as { ok?: boolean; ready: boolean; missing_requirements: string[]; lowest_authority: string | null; quoted_cost: number | null; can_approve: boolean; approval_blocker?: string | null; approval_blocker_message: string | null } | null;
  const approvalReadiness = approvalSummary?.ok ? {
    ready: approvalSummary.ready,
    missing_requirements: [
      ...approvalSummary.missing_requirements,
      ...(status === "submitted" && approvalSummary.ready && !approvalSummary.can_approve && approvalSummary.approval_blocker_message ? [approvalSummary.approval_blocker_message] : []),
    ],
    required_authority: approvalSummary.lowest_authority ?? "administrator",
    proposed_cost: Number(approvalSummary.quoted_cost ?? 0),
  } : null;
  const verificationReadiness = verificationReadinessResult.error ? null : verificationReadinessResult.data as { verification_ready: boolean; missing_requirements: string[]; completion_event_found: boolean; legacy_completion_record: boolean; self_verification_reason_required: boolean } | null;
  // An Administrator who raised or is assigned to the Work Order may still approve, with an audited reason.
  const approvalReasonRequired = status === "submitted" && approvalSummary?.approval_blocker === "OVERRIDE_REASON_REQUIRED";
  if (status === "submitted" && approvalSummary?.can_approve !== true && !approvalReasonRequired) allowedActions = allowedActions.filter((action) => action !== "approve");
  if (status === "draft" && approvalSummary?.ready !== true) allowedActions = allowedActions.filter((action) => action !== "submit");
  if (status === "completed" && verificationReadiness?.verification_ready !== true) allowedActions = allowedActions.filter((action) => action !== "review");
  const closureReadiness = closureReadinessResult.error ? null : closureReadinessResult.data as { ready?: boolean; missing_requirements?: string[]; resolution?: string | null } | null;
  if (status === "reviewed" && closureReadiness?.ready !== true) allowedActions = allowedActions.filter((action) => action !== "close");
  if (identity.role === "administrator" && order.assigned_technician_id !== identity.userId && ["assigned", "in_progress"].includes(status)) {
    allowedActions = allowedActions.filter((action) => action !== "accept" && action !== "start");
  }
  const relatedIncident = incidentResult.error ? null : incidentResult.data;
  const [finalCostResult, financialControlResult, copiedResult, directoryResult, facilityTechniciansResult, endorsementResult, facilitySettingResult, facilityDrawingsResult] = await Promise.all([
    status === "completed" ? supabase.from("work_order_final_cost_submissions").select("confirmed_actual_cost,status").eq("work_order_id", id).maybeSingle() : Promise.resolve({ data: null, error: null }),
    status === "completed" ? supabase.from("work_order_financial_controls").select("approved_budget,quoted_cost").eq("work_order_id", id).maybeSingle() : Promise.resolve({ data: null, error: null }),
    supabase.from("work_order_copied_parties").select("profile_id").eq("work_order_id", id),
    supabase.rpc("work_order_people_directory"),
    canSetTechnician(identity.role, status) ? supabase.rpc("work_order_facility_technicians", { p_work_order_id: id }) : Promise.resolve({ data: [], error: null }),
    supabase.from("work_order_endorsements").select("id,stage,endorsed_by,statement,endorsed_at,checklist").eq("work_order_id", id).order("endorsed_at", { ascending: true }),
    order.facility_id ? supabase.from("facility_settings").select("endorsement_stage").eq("facility_id", order.facility_id).maybeSingle() : Promise.resolve({ data: null, error: null }),
    order.facility_id ? supabase.from("facility_drawings").select(FACILITY_DRAWING_COLUMNS).eq("facility_id", order.facility_id).eq("active", true).order("code") : Promise.resolve({ data: [], error: null }),
  ]);
  const facilityDrawings = (facilityDrawingsResult.error ? [] : facilityDrawingsResult.data ?? []) as FacilityDrawingRow[];
  const finalCost = finalCostResult.error ? null : (finalCostResult.data as { confirmed_actual_cost: number } | null)?.confirmed_actual_cost ?? null;
  const approvedAmount = financialControlResult.error ? null : (financialControlResult.data as { approved_budget: number | null } | null)?.approved_budget ?? null;
  const copiedIds = (copiedResult.error ? [] : copiedResult.data ?? []).map((row) => String(row.profile_id));
  const people = (directoryResult.error ? [] : (directoryResult.data ?? []) as Array<{ id: string; display_name: string; role: string }>).map((person) => ({ id: person.id, name: person.display_name, role: person.role }));
  const facilityTechnicians = (facilityTechniciansResult.error ? [] : (facilityTechniciansResult.data ?? []) as Array<{ id: string; display_name: string; trade_discipline: string | null }>).map((item) => ({ id: item.id, name: item.display_name, detail: item.trade_discipline }));
  const nameById = new Map(people.map((person) => [person.id, person.name]));
  const endorsements: Endorsement[] = (endorsementResult.error ? [] : (endorsementResult.data ?? []) as Array<{ id: string; stage: "submission" | "review"; endorsed_by: string; statement: string; endorsed_at: string; checklist?: { checks?: string[]; award_basis_note?: string | null } | null }>)
    .map((row) => ({ id: row.id, stage: row.stage, endorser: nameById.get(row.endorsed_by) ?? "Technician", statement: row.statement, endorsed_at: row.endorsed_at, checks: row.checklist?.checks ?? [], awardBasis: row.checklist?.award_basis_note ?? null }));
  // D-25: quotations for the independent checker to compare (awarded = approved, else recommended contractor).
  const quotationResult = ["draft", "completed"].includes(status) ? await supabase.rpc("work_order_contractor_quotations", { p_work_order_id: id }) : null;
  const rawQuotations = quotationResult && !quotationResult.error && quotationResult.data && typeof quotationResult.data === "object"
    ? ((quotationResult.data as { quotations?: unknown }).quotations as Array<{ id: string; vendor_id: string; status: string; total_amount: number; quotation_ref: string | null; contractor_legal_name: string | null }> | undefined) ?? [] : [];
  const checkerQuotations: QuotationSummary[] = rawQuotations.filter((quote) => ["submitted", "approved"].includes(quote.status)).map((quote) => ({
    id: quote.id, contractor: quote.contractor_legal_name ?? "Contractor", amount: Number(quote.total_amount), reference: quote.quotation_ref,
    awarded: quote.status === "approved" || (quote.status === "submitted" && quote.vendor_id === order.recommended_vendor_id),
  }));
  const latestEndorsement = {
    submission: endorsements.filter((item) => item.stage === "submission").map((item) => item.endorsed_at).sort().at(-1) ?? null,
    review: endorsements.filter((item) => item.stage === "review").map((item) => item.endorsed_at).sort().at(-1) ?? null,
  };
  const endorsementStageValue = (facilitySettingResult.data as { endorsement_stage?: string } | null)?.endorsement_stage ?? DEFAULT_ENDORSEMENT_STAGE;
  const endorsementStage = endorsementStageLabel(endorsementStageValue);
  const canEndorse = identity.role === "technician" && identity.userId !== order.assigned_technician_id && identity.userId !== order.requested_by && ["draft", "completed"].includes(status);
  const actualTimes = { started: (order as { actual_work_started_at?: string | null }).actual_work_started_at ?? null, ended: (order as { actual_work_ended_at?: string | null }).actual_work_ended_at ?? null };
  const actualTimesEditable = order.assigned_technician_id === identity.userId && ["assigned", "in_progress", "completed"].includes(status);
  const showActualTimes = actualTimesEditable || Boolean(actualTimes.started) || ["in_progress", "completed", "reviewed", "closed"].includes(status);
  const copiedEditable = !["closed", "cancelled"].includes(status) && (isPreparer(context) || isApprovalAuthority(identity.role));
  const fieldFacilityPermission = order.facility_id
    ? await supabase.rpc("field_work_facility_permitted", { p_facility_id: order.facility_id })
    : { data: false };
  const { data: openDocumentCorrection } = await supabase
    .from("work_order_document_corrections")
    .select("id,reason")
    .eq("work_order_id", id)
    .eq("status", "open")
    .maybeSingle();
  const evidenceCanMutate = canMutateWorkOrderEvidence({ role: identity.role, userId: identity.userId, assignedTechnicianId: order.assigned_technician_id, status, hasActiveFacilityMembership: fieldFacilityPermission.data === true, correctionOpen: Boolean(openDocumentCorrection), creatorId: order.user_id, requesterId: order.requested_by });
  const assetLabel = assetReferenceLabel(order.asset_id, order.asset as { asset_tag: string; name: string } | null);
  const assetLinkAllowed = canLinkWorkOrderAsset(identity.role) && !["closed", "cancelled"].includes(status);
  const assetOptionsResult = assetLinkAllowed
    ? await supabase.from("assets").select("id,asset_tag,name,asset_type,criticality,lifecycle_status,site,location,system:asset_systems(name,system_code)").neq("lifecycle_status", "decommissioned").order("asset_tag")
    : { data: [], error: null };
  const assetOptions = (assetOptionsResult.error ? [] : assetOptionsResult.data ?? []) as unknown as AssetSummary[];

  const { data: activity, error: activityError } = await supabase
    .from("activity_logs")
    .select("id,action,from_status,to_status,actor,note,created_at")
    .eq("work_order_id", id)
    .order("created_at", { ascending: false });
  const priorReworkCycles = reworkHistory(activity ?? []);
  const currentRework = activeReworkContext(String(order.status), activity ?? []);
  // D-11/D-20: the database decides whether the review endorsement is due (it must cover the current final cost
  // and any variation order); readable by the second Technician as well as the reviewers.
  const endorsementStatusResult = status === "completed" ? await supabase.rpc("work_order_endorsement_status", { p_work_order_id: id }) : null;
  const endorsementStatus = (endorsementStatusResult && !endorsementStatusResult.error ? endorsementStatusResult.data : null) as
    { ok?: boolean; due?: boolean; superseded?: boolean; blocked?: { code: string; message: string } | null;
      final_cost?: { final_contractor_amount: number; variation_order: boolean | null; variation_justification: string | null; documents: number } | null } | null;
  // A Technician who can check this Work Order is told in advance while the work is still under way (D-25 follow-up, 30 Oct).
  const upcomingCheck = identity.role === "technician" && identity.userId !== order.assigned_technician_id && identity.userId !== order.requested_by
    && ["assigned", "in_progress"].includes(status) && ["before_review", "both"].includes(endorsementStageValue);
  const reviewEndorsementDue = status === "completed" && endorsementStatus?.ok === true && endorsementStatus.due === true;
  const endorsementRequired = (status === "draft" && Boolean(approvalSummary?.missing_requirements?.includes("Second Technician endorsement")))
    || (status === "completed" && (reviewEndorsementDue || Boolean(verificationReadiness?.missing_requirements?.includes("Second Technician endorsement"))));

  // Shown only for Work Orders raised from condition monitoring or a prediction (not leftover references on reactive work).
  const predictive = ["condition_based", "predictive"].includes(order.source);
  const overviewFields = [
    ["Source", operationalLabel(String(order.source))],
    ["Estimated hours", order.estimated_hours],
    ["Contact number", order.contact_number],
  ].filter(([, value]) => hasValue(value));
  // D-12/D-20: who is responsible and who endorses, by name.
  const assignedTechnicianName = order.assigned_technician_id ? nameById.get(String(order.assigned_technician_id)) ?? resolvedAssignee : null;
  const contractorName = order.assigned_vendor_id
    ? vendors.find((item) => item.id === order.assigned_vendor_id)?.name
      ?? safeHumanLabel((await supabase.from("vendors").select("name").eq("id", order.assigned_vendor_id).maybeSingle()).data?.name)
    : null;
  const endorserNames = (stage: "submission" | "review") => [...new Set(endorsements.filter((item) => item.stage === stage).map((item) => item.endorser))].join(", ");
  const endorsingTechnician = endorserNames("review") || endorserNames("submission")
    ? [endorserNames("submission") && `${endorserNames("submission")} (before submission)`, endorserNames("review") && `${endorserNames("review")} (work and final cost)`].filter(Boolean).join("; ")
    : "Not yet endorsed — any other Technician of this facility";
  const assignmentFields = [
    ["Assigned Technician", assignedTechnicianName ?? resolvedAssignee],
    ["Endorsing Technician", endorsingTechnician],
    ["Contractor", contractorName],
    ["Assigned by", safeHumanLabel(order.assigned_by)],
    ["Assigned at", order.assigned_at ? formatDateTime(order.assigned_at) : null],
  ].filter(([, value]) => hasValue(value));
  const jobInstructionFields = [["Original / imported instructions", order.internal_notes]].filter(([, value]) => hasValue(value));
  const fieldWorkFields = [
    ["Work performed", order.completion_notes],
    ["Actual labour hours", order.actual_labour_hours],
  ].filter(([, value]) => hasValue(value));
  const predictiveFields = [
    ["Source reference", order.source_reference],
    ["Alert reference", order.alert_id],
    ["Prediction reference", order.prediction_reference],
    ["Health score", order.health_score_at_creation],
    ["Failure probability", order.failure_probability],
    ["Predicted failure", order.predicted_failure_date],
    ["Confidence", order.confidence_score],
    ["Recommended action", order.recommended_action],
  ].filter(([, value]) => hasValue(value));
  const today = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Singapore", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
  const decisionModel = buildWorkOrderDecisionModel({
    priority: String(order.priority),
    status: String(order.status),
    dueDate: order.due_date,
    today,
    assignedTechnicianId: order.assigned_technician_id,
    assignedVendorId: order.assigned_vendor_id,
    assignedTeamId: order.assigned_team_id,
    recordedAssignee: order.assigned_to,
    resolvedAssignee,
    incidentLinked: Boolean(order.incident_id),
    incidentReference: relatedIncident?.incident_number,
    incidentSeverity: relatedIncident?.severity,
    incidentStatus: relatedIncident?.status,
    evidenceCount,
    reworkReason: currentRework?.reason,
    operationalStage: operationalStage.label,
  });
  const nextAction = identity.role === "administrator" && ["assigned", "in_progress"].includes(status)
    ? operationalStage.nextAction
    : authorizedExecutionActions(String(order.status), allowedActions)[0]?.label ?? null;
  const location = [order.site, order.location].filter(Boolean).join(" · ") || "Location not recorded";

  // Work stage for the assigned Technician: the page follows the order of the tasks (UAT 29 Oct 2026).
  const workStage = ["assigned", "in_progress"].includes(status) && order.assigned_technician_id === identity.userId;
  const contractorPackage = quotationPackageRequired && approvedBudget !== null;
  const completionSteps: CompletionStep[] = [
    { label: "Start the work", done: status === "in_progress" || Boolean(order.started_at), href: "#execution-title" },
    { label: "Add After photos of the finished work", done: hasActiveAfterEvidence, href: "#work-order-evidence" },
    { label: "Enter when the work actually started and ended", done: Boolean(actualTimes.started && actualTimes.ended), href: "#actual-work-times" },
    { label: "Confirm the cost record", done: Boolean(order.actual_costs_confirmed_at), href: "#actual-cost-heading", note: contractorPackage ? "Itemised lines are optional; confirm even if there are none." : undefined },
    ...(contractorPackage ? [
      { label: "Final Cost Reconciliation: price unchanged, or variation order", done: Boolean(savedFinalCost && savedFinalCost.status !== "draft"), href: "#final-cost-heading" },
      ...(savedFinalCost?.variation_order === true ? [{ label: "Attach the contractor's revised quotation", done: revisedQuotationCount > 0, href: "#final-cost-heading" }] : []),
    ] : []),
    { label: "Record the work done (statement and labour hours)", done: Boolean(String(order.completion_notes ?? "").trim()) && order.actual_labour_hours !== null && order.actual_labour_hours !== undefined, href: "#execution-title" },
    { label: "Submit Physical Completion for review", done: false, href: "#execution-title", note: completionMissing.length ? `Still needed: ${completionMissing.length} item${completionMissing.length === 1 ? "" : "s"} above.` : "Everything is ready." },
  ];
  const actionsEl = (
      <WorkOrderActions
        id={id}
        reference={order.work_order_number}
        title={order.title}
        location={location}
        priority={order.priority}
        dueDate={order.due_date}
        overdue={decisionModel.due.state === "overdue"}
          technician={identity.role === "technician"}
        status={status}
        allowedActions={allowedActions as WorkOrderAction[]}
        approvalReasonRequired={approvalReasonRequired}
        canEdit={canEdit(context)}
        canDuplicate={isApprovalAuthority(identity.role)}
        canRecordWork={canRecordWork(context) && !(identity.role === "administrator" && operationalStage.completion.workRecordReceived && operationalStage.completion.labourHoursRecorded)}
        formalCompletionAuthority={identity.role === "administrator" && order.assigned_technician_id !== identity.userId}
        completionReadiness={operationalStage.completion}
        operationalStage={operationalStage.label}
        completionMissing={completionMissing}
        approvalReadiness={approvalReadiness}
        verificationReadiness={verificationReadiness}
        recordedWork={order.completion_notes}
        recordedHours={order.actual_labour_hours}
        currentRework={currentRework}
        reviewContext={status === "completed" ? {
          requestedWork: order.description || "Requested work description unavailable.",
          assignee: resolvedAssignee ?? "Responsible field person unavailable",
          completionNotes: order.completion_notes,
          cumulativeLabourHours: order.actual_labour_hours,
          completedAt: order.completed_at,
          evidence: decisionModel.evidence.label,
          relatedIncident: relatedIncident?.incident_number ?? null,
          priorCycles: priorReworkCycles,
          finalCost,
          inHouse: Boolean((order as { in_house_work?: boolean }).in_house_work),
          approvedAmount,
        } : undefined}
      />
  );
  const evidenceEl = (
      <div id="work-order-evidence">
        <EvidencePanel parentType="work_order" parentId={id} canMutate={evidenceCanMutate} canDelete={evidenceCanMutate} readOnlyReason={status==="submitted" ? "This Work Order is awaiting approval. The preparer may still add supporting photos, video or voice notes; other users view evidence only." : !order.assigned_technician_id ? "This Work Order has no assigned field owner. Authorized management must record an assignment before field evidence can be added." : undefined} />
      </div>
  );

  return (
    <main className="mx-auto max-w-5xl space-y-8 p-4 sm:p-6 lg:p-8">
      <Link href="/work-orders" className="text-sm font-medium text-blue-700 hover:underline">← All work orders</Link>

      <WorkOrderDecisionHeader
        reference={order.work_order_number}
        title={order.title}
        location={location}
        workType={order.categories?.name ?? operationalLabel(String(order.source))}
        department={order.departments?.name ?? null}
        model={decisionModel}
        incidentHref={relatedIncident ? `/incidents/${relatedIncident.id}` : null}
        nextAction={nextAction}
        responsibility={{
          technician: resolvedAssignee,
          viewer: identity.displayName,
          viewerRole: operationalLabel(identity.role),
          viewerResponsible: isPreparer(context) || order.assigned_technician_id === identity.userId,
          draftToFinish: status === "draft" && isPreparer(context) && approvalReadiness?.ready === false,
        }}
      />

      <section className="rounded-xl border border-slate-200 bg-white p-5">
        <h2 className="mb-4 font-semibold">Workflow timeline</h2>
        <ol className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          {timelineSteps(order, latestEndorsement, endorsementStageValue).map((step) => (
            <li key={step.key} className={`rounded-lg border p-3 text-sm ${step.at ? "border-emerald-200 bg-emerald-50" : "border-slate-200 bg-slate-50"}`}>
              <p className="font-semibold">{step.label}</p>
              <p className="mt-1 text-xs text-slate-500">{step.at ? formatDateTime(step.at) : "Pending"}</p>
            </li>
          ))}
        </ol>
        <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-3">
          <div className="rounded-lg border border-slate-200 p-3"><dt className="font-semibold">Work duration (actual start → end, entered by the Technician)</dt><dd className="mt-1 text-slate-700">{formatDuration(actualTimes.started, actualTimes.ended) ?? "Not yet entered"}</dd></div>
          <div className="rounded-lg border border-slate-200 p-3"><dt className="font-semibold">Labour hours recorded</dt><dd className="mt-1 text-slate-700">{order.actual_labour_hours === null || order.actual_labour_hours === undefined ? "Not yet recorded" : `${order.actual_labour_hours} h`}</dd></div>
          <div className="rounded-lg border border-slate-200 p-3"><dt className="font-semibold">Overall (created → closed)</dt><dd className="mt-1 text-slate-700">{formatDuration(order.created_at, order.closed_at) ?? "Open"}</dd></div>
        </dl>
      </section>

      {upcomingCheck && <div role="note" className="rounded-xl border-2 border-amber-400 bg-amber-50 p-4 text-amber-950">
        <span className="block font-black">You may be the independent checker for this Work Order</span>
        <span className="mt-1 block text-sm">No action yet. Your endorsement will be needed after the assigned Technician submits Physical Completion; a flashing banner will then appear here, and the endorsement panel at the end of the page will turn red with your checklist.</span>
      </div>}

      {endorsementRequired && canEndorse && <a href="#technician-endorsement" className="block rounded-xl border-4 border-red-600 bg-amber-100 p-4 text-amber-950 shadow-sm motion-safe:animate-pulse">
        <span className="block text-lg font-black">You are the independent checker for this Work Order</span>
        <span className="mt-1 block text-sm">Your endorsement is needed. Go to your checklist: {status === "draft" ? "site evidence and quotations" : "verify on site the work done and the materials installed against the contractor's final quotation, and the site evidence"}{checkerQuotations.length > 1 ? ", and the basis of the award against the competing quotations" : ""}.</span>
      </a>}

      {status === "draft" && isPreparer(context) && approvalReadiness && (
        <DraftNextSteps steps={draftNextSteps(approvalReadiness.missing_requirements, id)} justCreated={justCreated} />
      )}

      {workStage ? <>
        <WorkCompletionSteps steps={completionSteps} />
        {evidenceEl}
        {showActualTimes && <ActualWorkTimes workOrderId={id} startedAt={actualTimes.started} endedAt={actualTimes.ended} canEdit={actualTimesEditable} />}
        <ReleaseOneWorkspace id={id} role={identity.role} status={status} userId={identity.userId} />
        {actionsEl}
      </> : <ReleaseOneWorkspace id={id} role={identity.role} status={status} userId={identity.userId} />}

      {!workStage && showActualTimes && <ActualWorkTimes workOrderId={id} startedAt={actualTimes.started} endedAt={actualTimes.ended} canEdit={actualTimesEditable} />}

      <section className="rounded-xl border border-emerald-200 bg-emerald-50 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4"><div><p className="text-xs font-black uppercase tracking-widest text-emerald-800">Physical Asset</p>{assetLabel ? order.asset ? <Link href={`/assets/${order.asset_id}`} className="mt-1 inline-block text-lg font-black text-emerald-950 hover:underline">{assetLabel}</Link> : <p className="mt-1 text-lg font-black text-amber-900">Asset unavailable</p> : <p className="mt-1 text-lg font-black text-slate-700">No Asset linked</p>}<p className="mt-1 text-sm text-emerald-800">The Work Order location remains its historical operational snapshot.</p></div>{order.asset && <div className="text-right text-sm"><p className="font-bold">{order.asset.system?.name ?? "Engineering System: Not configured"}</p><p>{order.asset.location}</p><p>{operationalLabel(order.asset.lifecycle_status)} · {operationalLabel(order.asset.criticality)}</p></div>}</div>
        {assetLinkAllowed && <div className="mt-4 border-t border-emerald-200 pt-4"><AssetLinkControl parent="work-orders" parentId={id} assets={assetOptions} currentAssetId={order.asset_id} unavailable={Boolean(order.asset_id && !order.asset)} /></div>}
      </section>

      {overviewFields.length > 0 && (
        <section className="rounded-xl border border-slate-200 bg-white p-5">
          <h2 className="font-semibold text-slate-900">Work details</h2>
          {overviewFields.length > 0 && (
            <dl className="mt-5 grid gap-4 border-t border-slate-100 pt-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
              {overviewFields.map(([label, value]) => <div key={String(label)}><dt className="text-slate-400">{label}</dt><dd className="mt-1 font-medium text-slate-800">{display(value)}</dd></div>)}
            </dl>
          )}
        </section>
      )}

      {assignmentFields.length > 0 && (
        <section className="rounded-xl border border-slate-200 bg-white p-5">
          <h2 className="font-semibold text-slate-900">Assignment details</h2>
          <dl className="mt-4 grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
            {assignmentFields.map(([label, value]) => <div key={String(label)}><dt className="text-slate-400">{label}</dt><dd className="mt-1 font-medium text-slate-800">{display(value)}</dd></div>)}
          </dl>
        </section>
      )}

      {(order.description || jobInstructionFields.length > 0) && (
        <section className="rounded-xl border border-slate-200 bg-white p-5">
          <h2 className="font-semibold text-slate-900">Original Work Order / Job Instructions</h2>
          {order.description && <p className="mt-3 whitespace-pre-wrap text-sm text-slate-800">{order.description}</p>}
          <dl className="mt-4 space-y-4">
            {jobInstructionFields.map(([label, value]) => <div key={String(label)}><dt className="text-sm font-medium text-slate-500">{label}</dt><dd className="mt-1 whitespace-pre-wrap text-sm text-slate-800">{display(value)}</dd></div>)}
          </dl>
        </section>
      )}

      {fieldWorkFields.length > 0 && (
        <section className="rounded-xl border border-blue-200 bg-blue-50 p-5">
          <h2 className="font-semibold text-blue-950">Field Work Record</h2>
          <dl className="mt-4 space-y-4">
            {fieldWorkFields.map(([label, value]) => <div key={String(label)}><dt className="text-sm font-medium text-blue-700">{label}</dt><dd className="mt-1 whitespace-pre-wrap text-sm text-blue-950">{display(value)}</dd></div>)}
          </dl>
        </section>
      )}

      {predictive && predictiveFields.length > 0 && (
        <section className="rounded-xl border border-purple-200 bg-purple-50 p-5">
          <h2 className="font-semibold text-purple-950">Condition and predictive source context</h2>
          <dl className="mt-4 grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
            {predictiveFields.map(([label, value]) => <div key={String(label)}><dt className="text-purple-600">{label}</dt><dd className="mt-1 text-purple-950">{display(value)}</dd></div>)}
          </dl>
        </section>
      )}

      {canSetTechnician(identity.role, status) && (
        <section className="rounded-xl border border-violet-200 bg-violet-50 p-5">
          <h2 className="font-semibold text-violet-950">Field-witness Technician</h2>
          <p className="mb-4 mt-1 text-sm text-violet-800">Required before submission. The Technician witnesses the contractor&apos;s work, uploads evidence and submits the work for review.</p>
          <TechnicianPicker workOrderId={id} technicians={facilityTechnicians} currentId={order.assigned_technician_id} />
        </section>
      )}
      <CopiedParties workOrderId={id} people={people} selected={copiedIds} canEdit={copiedEditable} />

      {assignmentAllowed && (
        <section className="rounded-xl border border-violet-200 bg-violet-50 p-5">
          <h2 className="font-semibold text-violet-950">Primary assignment</h2>
          <p className="mb-4 mt-1 text-sm text-violet-800">Assign one active technician, vendor, or maintenance team. A new assignment replaces the previous primary assignment.</p>
          {assigneeLoadFailed
            ? <LoadFailure message="Assignable personnel could not be loaded. Assignment is temporarily unavailable." />
            : <WorkOrderAssignment workOrderId={id} technicians={technicians} vendors={vendors} teams={teams} />}
        </section>
      )}

      <DocumentCorrectionControl workOrderId={id} role={identity.role} status={status} openReason={openDocumentCorrection?.reason ?? null} />

      {!workStage && evidenceEl}


      <section className="rounded-xl border border-slate-200 bg-white p-5">
        <details>
          <summary className="flex min-h-11 cursor-pointer list-none flex-wrap items-center justify-between gap-2">
            <h2 className="font-semibold">Audit history</h2>
            <span className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-semibold text-blue-700">Show audit history{activity?.length ? ` (${activity.length} entries)` : ""}</span>
          </summary>
          {activityError
            ? <LoadFailure message="Audit history could not be loaded. Please try again." />
            : !activity?.length
              ? <p className="mt-3 text-sm text-slate-500">No audit activity.</p>
              : <>
                <p className="mb-3 mt-3 text-xs text-slate-500">Newest first. Scroll inside the box to see older entries; open “Details” for the full record of an entry.</p>
                <ul className="max-h-[28rem] divide-y divide-slate-100 overflow-y-auto rounded-lg border border-slate-100 px-3" tabIndex={0} aria-label="Audit history entries">{activity.map((entry) => <li key={entry.id} className="py-3 text-sm">
                  <div className="flex flex-wrap justify-between gap-2"><strong>{entry.actor || "System"} · {operationalLabel(entry.action)}</strong><time className="text-slate-400">{formatDateTime(entry.created_at)}</time></div>
                  {(entry.from_status || entry.to_status) && entry.from_status !== entry.to_status && <p className="mt-1 text-slate-500">{entry.from_status ? workOrderStatusLabel(entry.from_status) : "Not recorded"} → {entry.to_status ? workOrderStatusLabel(entry.to_status) : "Not recorded"}</p>}
                  {entry.note && <details className="mt-1"><summary className="cursor-pointer text-xs font-semibold text-blue-700">Details</summary><pre className="mt-2 overflow-auto whitespace-pre-wrap rounded bg-slate-50 p-3 text-xs text-slate-600">{auditNote(entry.note)}</pre></details>}
                </li>)}</ul>
              </>}
        </details>
      </section>

      {facilityDrawings.length > 0 && <section aria-labelledby="facility-drawing-files-heading" className="rounded-xl border bg-white p-5 shadow-sm">
        <h2 id="facility-drawing-files-heading" className="text-lg font-bold">Facility drawings</h2>
        <p className="mt-1 text-sm text-slate-600">Layout drawings uploaded by the Administrator for this facility.</p>
        <ul className="mt-3 divide-y rounded-lg border">{facilityDrawings.map((drawing) => <li key={drawing.id} className="flex flex-wrap items-center gap-3 p-3 text-sm">
          <span className="min-w-0 flex-1"><strong>{drawing.code}</strong> — {drawing.title} <span className="text-slate-500">· {drawing.revision ?? "No revision"} · {drawing.content_type === "application/pdf" ? "PDF" : "Image"}</span></span>
          <a href={facilityDrawingSrc(drawing.id)} target="_blank" rel="noopener" className="min-h-11 rounded border px-3 py-2 font-semibold text-blue-700">View</a>
          <a href={facilityDrawingSrc(drawing.id, true)} className="min-h-11 rounded border px-3 py-2 font-semibold text-blue-700">Download</a>
        </li>)}</ul>
      </section>}

      <WorkOrderDrawings drawings={markupDrawingsFor(facilityDrawings)} canMutateMarkup={canMutateWorkOrderEvidence({ role: identity.role, userId: identity.userId, assignedTechnicianId: order.assigned_technician_id, status, hasActiveFacilityMembership: fieldFacilityPermission.data === true, creatorId: order.user_id, requesterId: order.requested_by }) || (status === "completed" && order.assigned_technician_id === identity.userId)} />

      {/* The reviewer's decision comes last, after the costs, evidence and records above. */}
      {(endorsementRequired || endorsements.length > 0) && <TechnicianEndorsement workOrderId={id} required={endorsementRequired} canEndorse={canEndorse} endorsements={endorsements} stageSetting={endorsementStage} blocked={status === "completed" ? endorsementStatus?.blocked ?? null : null} superseded={Boolean(endorsementStatus?.superseded)} finalCost={status === "completed" ? endorsementStatus?.final_cost ?? null : null} stage={status === "draft" ? "submission" : "review"} inHouse={Boolean(order.in_house_work)} quotations={checkerQuotations} />}
      {!workStage && actionsEl}
    </main>
  );
}
