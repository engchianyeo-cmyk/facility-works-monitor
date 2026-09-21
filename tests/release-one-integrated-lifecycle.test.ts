import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/20260921004602_release_1_integrated_commercial_lifecycle.sql", "utf8");
const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
const route = readFileSync("app/api/work-orders/[id]/release-1/route.ts", "utf8");

describe("integrated Release 1 commercial lifecycle", () => {
  test("starts proposal and final-account workflows without seeded records", () => {
    expect(workspace).toContain("technician&&!quote");
    expect(workspace).toContain("Create Draft Proposal");
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
    for (const operation of ["return_proposal", "return_payment", "actual_cost", "confirm_actual_costs", "procurement"]) expect(route).toContain(operation);
    for (const label of ["Return Proposal for Revision", "Return Payment Proposal", "Add Actual Cost", "Confirm Actual Costing", "Record Procurement Commitment"]) expect(workspace).toContain(label);
    expect(migration).toContain("work_order_proposal_returned");
    expect(migration).toContain("contractor_payment_proposal_returned");
  });

  test("configures the governed three-quotation threshold", () => {
    expect(migration).toContain("SGD_1000_AND_ABOVE_THREE_QUOTES");
    expect(migration).toContain("1000,null,3");
    expect(workspace).toContain("quotations required from");
  });
});
