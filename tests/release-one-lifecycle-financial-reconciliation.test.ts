import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/20260924040748_release_1_lifecycle_financial_reconciliation.sql", "utf8");
const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
const route = readFileSync("app/api/work-orders/[id]/release-1/route.ts", "utf8");
const releaseGate = readFileSync("scripts/release-verify.mjs", "utf8");

function functionBody(name: string) {
  return migration.split(`create or replace function public.${name}`)[1]?.split("end;$function$;")[0] ?? "";
}

describe("WP-2A lifecycle and financial reconciliation", () => {
  test("allows physical completion without final cost or invoice but retains physical evidence and execution-cost confirmation", () => {
    const body = functionBody("submit_physical_completion");
    expect(body).toContain("ACTUAL_COSTING_CONFIRMATION_REQUIRED");
    expect(body).toContain("submit_physical_completion_20260921_core");
    expect(body).not.toContain("FINAL_INVOICE_REQUIRED");
    expect(body).not.toContain("FINAL_COST_REQUIRED");
    expect(page).not.toContain("A supporting final invoice is required.");
    expect(page).not.toContain("Final Work Cost must be confirmed");
  });

  test("keeps the later payment invoice gate", () => {
    const priorPaymentMigration = readFileSync("supabase/migrations/20260919064024_release_1_proposal_payment_workflow.sql", "utf8");
    expect(priorPaymentMigration).toContain("INVOICE_REQUIRED");
    expect(workspace).toContain("Submit Payment Proposal");
    expect(workspace).toContain("invoiceDocs.length===0");
  });

  test("blocks closure until payment or independently approved no-payment disposition", () => {
    const readiness = functionBody("work_order_closure_readiness");
    const transition = functionBody("transition_work_order");
    expect(readiness).toContain("payment.status='paid'");
    expect(readiness).toContain("disposition.status='approved'");
    expect(transition).toContain("FINANCIAL_DISPOSITION_REQUIRED");
    expect(page).toContain('action !== "close"');
  });

  test("prevents self-approval of no-payment and Finance payment", () => {
    expect(functionBody("approve_work_order_no_payment")).toContain("result.proposed_by=actor_id");
    expect(functionBody("approve_work_order_no_payment")).toContain("SELF_APPROVAL_DENIED");
    expect(functionBody("record_work_order_finance_payment")).toContain("result.approved_by=actor_id");
    expect(functionBody("record_work_order_finance_payment")).toContain("SELF_APPROVAL_DENIED");
  });

  test("does not expose the renamed transition core to authenticated callers", () => {
    expect(migration).toContain("revoke all on function public.transition_work_order_20260924_core(uuid,text,jsonb) from authenticated");
    expect(migration).not.toMatch(/grant execute on function[^;]*transition_work_order_20260924_core[^;]*to authenticated/);
  });

  test("uses the actual cost ledger as the authoritative reconciliation and never adds quotation", () => {
    const finalCost = functionBody("save_work_order_final_cost");
    const payment = functionBody("save_work_order_payment_proposal");
    expect(finalCost).toContain("sum(c.amount)");
    expect(finalCost).toContain("ACTUAL_COST_MISMATCH");
    expect(finalCost).toContain("quotation_excluded_from_actual_total");
    expect(payment).toContain("final_cost.confirmed_actual_cost");
    expect(payment).toContain("quotation_excluded_from_payment_total");
    expect(payment).not.toMatch(/assessed_amount[^\n]+approved_budget/);
  });

  test("preserves WO-TEST-012 as quotation 650, actual/payment 620 rather than 1270", () => {
    const fixture = readFileSync("supabase/migrations/20260919064024_release_1_proposal_payment_workflow.sql", "utf8");
    expect(fixture).toContain("total_amount=650");
    expect(fixture).toContain("assessed_amount=620");
    expect(fixture).toContain("'actual_cost_preserved',620");
    expect(`${migration}\n${fixture}`).not.toContain("1270");
  });

  test("exposes governed no-payment operations through the API and UI", () => {
    expect(route).toContain('propose_no_payment: () => supabase.rpc("propose_work_order_no_payment"');
    expect(route).toContain('approve_no_payment: () => supabase.rpc("approve_work_order_no_payment"');
    expect(workspace).toContain("Propose No Payment Required");
    expect(workspace).toContain("Approve No Payment Required");
  });

  test("does not claim the tracked SQL release gate covers this migration", () => {
    expect(releaseGate).not.toContain("20260924040748_release_1_lifecycle_financial_reconciliation.sql");
  });
});
