import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/20260924044237_release_1_three_quotation_control.sql", "utf8");
const estimatePreservation = readFileSync("supabase/migrations/20260924045239_preserve_three_quotation_estimate.sql", "utf8");
const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
const route = readFileSync("app/api/work-orders/[id]/release-1/route.ts", "utf8");

function body(name: string) {
  return migration.split(`create or replace function public.${name}`)[1]?.split("end;$function$;")[0] ?? "";
}

describe("Release-1 S$1,000 quotation control", () => {
  test("retains the governed estimate and prevents threshold downgrade or duplicate contractors", () => {
    const prepare = body("prepare_work_order_proposal");
    expect(prepare).toContain("greatest(coalesce(control.estimated_cost,0),amount)");
    expect(prepare).toContain("DUPLICATE_CONTRACTOR_QUOTATION");
    expect(prepare).toContain("procurement_prequalified");
    expect(prepare).toContain("facility_confirmed");
    expect(estimatePreservation).toContain("greatest(coalesce(prior_estimate,0),coalesce(quotation_amount,0))");
    expect(estimatePreservation).toContain("save_work_order_proposal_20260924_core");
  });

  test("requires authentic documents and distinct submitted contractors", () => {
    const submit = body("submit_work_order_proposal");
    expect(submit).toContain("QUOTATION_DOCUMENT_REQUIRED");
    expect(submit).toContain("count(distinct vendor_id)");
    expect(submit).toContain("ready_for_selection");
  });

  test("requires collection completion and a selection rationale before independent approval", () => {
    const recommend = body("recommend_work_order_quotation");
    const approve = body("approve_work_order_proposal");
    expect(recommend).toContain("INSUFFICIENT_QUOTATIONS");
    expect(recommend).toContain("selection rationale");
    expect(approve).toContain("control.cost_status<>'recommended'");
    expect(approve).toContain("INSUFFICIENT_QUOTATIONS");
  });

  test("exposes collection and recommendation controls in API and UI", () => {
    expect(route).toContain('recommend_quotation: () => supabase.rpc("recommend_work_order_quotation"');
    expect(workspace).toContain("Add Competing Quotation");
    expect(workspace).toContain("Quotation comparison");
    expect(workspace).toContain("Selection rationale");
  });
});
