import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/20260918041022_release_1_markup_procurement.sql", "utf8");
const component = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
const markupEditor = readFileSync("components/work-orders/drawing-markup-editor.tsx", "utf8");
const route = readFileSync("app/api/work-orders/[id]/release-1/route.ts", "utf8");
const controls = readFileSync("supabase/migrations/20260918083838_release_1_uat_markup_financial_controls.sql", "utf8");

describe("Release 1 markup and commercial workspace", () => {
  test("keeps Work Order visibility separate from mutation authority", () => {
    expect(migration).toContain("work_order_markups_read");
    expect(migration).toContain("w.assigned_technician_id is distinct from");
    expect(migration).toContain("Only the assigned same-facility Technician may add field markup.");
    expect(migration).toContain("actor->>'role' not in ('supervisor','facility_manager','administrator')");
  });

  test("persists calibrated drawing or PDF markup with audit", () => {
    expect(migration).toContain("source_type in ('drawing','pdf')");
    expect(migration).toContain("x_percent between 0 and 100");
    expect(migration).toContain("work_order_markup_recorded");
    for (const tool of ["Pin", "Arrow", "Circle", "Rectangle", "Freehand", "Text / Note", "Undo", "Redo", "Delete", "Save markup"]) expect(markupEditor).toContain(tool);
    expect(controls).toContain("drawing_revision");
    expect(controls).toContain("annotation_type");
    expect(controls).toContain("geometry jsonb");
  });

  test("wires quotation, actual cost and procurement commands", () => {
    for (const rpc of ["record_contractor_quotation", "manage_work_order_actual_cost", "record_work_order_procurement"]) expect(route).toContain(rpc);
    for (const label of ["Prepare Proposal", "Save Draft", "Submit for Approval", "Procurement commitments"]) expect(component).toContain(label);
    expect(migration).toContain("work_order_procurement_recorded");
  });

  test("shows governed financial summary and separates recommendation from approval", () => {
    for (const label of ["Estimated cost", "Quoted cost", "Approved amount / budget", "Actual cost", "Variance", "Contractor", "Quotation", "Cost status", "Financial approval"]) expect(component).toContain(label);
    expect(controls).toContain("SGD_BELOW_1000_ONE_QUOTE");
    expect(controls).toContain("Technicians cannot approve expenditure.");
    expect(controls).toContain("financial_approved_by is distinct from recommended_by");
    expect(component).toContain("approver&&recommendedQuote");
    expect(component).toContain("item.vendor_id===data.order?.recommended_vendor_id");
    expect(component).toContain('["approver","supervisor","facility_manager","administrator"]');
  });

  test("normalizes JSON RPC envelopes before rendering collections", () => {
    expect(route).toContain('rpcCollection(quotationResult.data, "quotations")');
    expect(route).toContain('rpcCollection(rateResult.data, "rates")');
    expect(component).toContain("Array.isArray(w.quotations)");
    expect(component).toContain("Array.isArray(w.documents)");
  });

  test("denies direct authenticated writes", () => {
    expect(migration).toContain("revoke all on public.work_order_markups,public.work_order_procurement_commitments from anon,authenticated");
    expect(migration).toContain("revoke all on function public.record_work_order_markup(uuid,jsonb),public.record_work_order_procurement(uuid,jsonb) from public,anon,service_role");
  });
});
