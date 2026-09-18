import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/20260918041022_release_1_markup_procurement.sql", "utf8");
const component = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
const route = readFileSync("app/api/work-orders/[id]/release-1/route.ts", "utf8");

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
    expect(component).toContain("Add markup pin");
  });

  test("wires quotation, actual cost and procurement commands", () => {
    for (const rpc of ["record_contractor_quotation", "manage_work_order_actual_cost", "record_work_order_procurement"]) expect(route).toContain(rpc);
    for (const label of ["Record quotation revision", "Add actual cost", "Confirm costing complete", "Record commitment"]) expect(component).toContain(label);
    expect(migration).toContain("work_order_procurement_recorded");
  });

  test("normalizes JSON RPC envelopes before rendering collections", () => {
    expect(route).toContain('rpcCollection(quotationResult.data, "quotations")');
    expect(route).toContain('rpcCollection(rateResult.data, "rates")');
    expect(component).toContain("Array.isArray(workspace.quotations)");
    expect(component).toContain("Array.isArray(workspace.rates)");
  });

  test("denies direct authenticated writes", () => {
    expect(migration).toContain("revoke all on public.work_order_markups,public.work_order_procurement_commitments from anon,authenticated");
    expect(migration).toContain("revoke all on function public.record_work_order_markup(uuid,jsonb),public.record_work_order_procurement(uuid,jsonb) from public,anon,service_role");
  });
});
