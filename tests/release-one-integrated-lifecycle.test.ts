import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/20260921004602_release_1_integrated_commercial_lifecycle.sql", "utf8");
const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
const route = readFileSync("app/api/work-orders/[id]/release-1/route.ts", "utf8");
const readinessRoute = readFileSync("app/api/work-orders/[id]/readiness/route.ts", "utf8");
const approvalBasis = readFileSync("components/work-orders/approval-basis-control.tsx", "utf8");
const paymentCorrection = readFileSync("supabase/migrations/20260921061036_correct_payment_assessment_actual_cost.sql", "utf8");
const evidenceFinalCost = readFileSync("supabase/migrations/20260921122902_evidence_final_cost_completion_controls.sql", "utf8");
const reconciliation = readFileSync("supabase/migrations/20260924040748_release_1_lifecycle_financial_reconciliation.sql", "utf8");
const evidencePanel = readFileSync("components/evidence/evidence-panel.tsx", "utf8");

describe("integrated Release 1 commercial lifecycle", () => {
  test("starts proposal and final-account workflows without seeded records", () => {
    expect(workspace).toContain("canAddQuotation");
    expect(workspace).toContain("Create Draft Quotation");
    expect(workspace).toContain("!data.payment||");
    expect(route).toContain('prepare_proposal: () => supabase.rpc("prepare_work_order_proposal"');
    expect(workspace).toContain('submit("save_payment_proposal"');
  });

  test("separates Technician recommendation from independent contractor selection", () => {
    expect(migration).toContain("recommended_vendor_id");
    expect(migration).toContain("decision_pending_independent_approval',true");
    expect(migration).toContain("update public.work_orders set assigned_vendor_id=q.vendor_id");
    expect(migration).toContain("q.submitted_by=actor_id or q.prepared_by=actor_id");
    expect(route).toContain("contractor:vendors!work_orders_assigned_vendor_fkey");
  });

  test("limits choices to Procurement-prequalified and Facility-confirmed contractors", () => {
    expect(migration).toContain("vendor_facility_eligibility");
    expect(migration).toContain("e.procurement_prequalified and e.facility_confirmed");
    expect(migration).toContain("CONTRACTOR_INELIGIBLE");
    expect(workspace).toContain("Select Procurement-prequalified, Facility-confirmed contractor");
  });

  test("makes rejection, actual cost and procurement controls operational", () => {
    for (const operation of ["return_proposal", "return_payment", "reopen_payment_correction", "actual_cost", "confirm_actual_costs", "procurement"]) expect(route).toContain(operation);
    for (const label of ["Return Proposal for Revision", "Return Payment Proposal", "Reopen Payment for Correction", "Add Actual Cost", "Confirm Actual Costing", "Record Procurement Commitment"]) expect(workspace).toContain(label);
    expect(migration).toContain("work_order_proposal_returned");
    expect(migration).toContain("contractor_payment_proposal_returned");
  });

  test("configures the governed three-quotation threshold", () => {
    expect(migration).toContain("SGD_1000_AND_ABOVE_THREE_QUOTES");
    expect(migration).toContain("1000,null,3");
    expect(workspace).toContain("quotations required from");
  });

  test("exposes the governed pre-work approval basis in the Work Order journey", () => {
    for (const field of ["proposed_cost", "cost_basis", "execution_arrangement", "safety_isolation_information"]) expect(approvalBasis).toContain(field);
    expect(approvalBasis).toContain("Save Approval Basis");
    expect(readinessRoute).toContain('rpc("set_work_order_approval_basis"');
  });

  test("creates final accounts from actual costs and preserves approved-payment correction history", () => {
    expect(paymentCorrection).toContain("c.cost_phase='actual'");
    expect(paymentCorrection).toContain("'draft',actual_total");
    expect(paymentCorrection).toContain("reopen_work_order_payment_for_correction");
    expect(paymentCorrection).toContain("prior_approval_preserved_in_activity_history");
    expect(paymentCorrection).toContain("result.reviewed_at+interval '30 days'");
  });

  test("governs evidence replacement, completion withdrawal and separates final cost from physical completion", () => {
    for (const contract of ["void_work_order_evidence", "AFTER_EVIDENCE_REQUIRED", "withdraw_physical_completion", "save_work_order_final_cost", "approve_work_order_final_cost_variance"]) expect(evidenceFinalCost).toContain(contract);
    const correctedCompletion = reconciliation.split("create or replace function public.submit_physical_completion")[1]?.split("end;$function$;")[0] ?? "";
    expect(correctedCompletion).not.toContain("FINAL_INVOICE_REQUIRED");
    expect(correctedCompletion).not.toContain("FINAL_COST_REQUIRED");
    expect(correctedCompletion).toContain("ACTUAL_COSTING_CONFIRMATION_REQUIRED");
    for (const control of ["Download", "video/mp4", "video/webm"]) expect(evidencePanel).toContain(control);
    for (const control of ["Final Cost Reconciliation", "Save Final Cost Reconciliation", "Attach Final Invoice", "Authorize Final Cost Variance"]) expect(workspace).toContain(control);
    expect(route).toContain("approve_final_cost_variance");
  });
});
