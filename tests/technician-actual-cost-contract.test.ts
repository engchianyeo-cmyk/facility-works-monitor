import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/0038_governed_technician_actual_costs.sql", "utf8");

describe("governed Technician actual-cost contract", () => {
  test("separates proposed, actual and legacy-unclassified cost lines without rewriting history", () => {
    expect(migration).toContain("add column cost_phase text");
    expect(migration).toContain("alter column cost_phase set default 'proposed'");
    expect(migration).not.toMatch(/update public\.work_order_cost_lines\s+set cost_phase/i);
    expect(migration).toContain("cost_phase)\n    values");
    expect(migration).toContain("actor_id,'actual'");
    expect(migration).toContain("PROPOSED_COST_PROTECTED");
    expect(migration).toContain("existing.cost_phase is distinct from 'actual'");
  });

  test.each(["labour", "material", "service", "equipment", "callout"])("accepts supported actual %s cost", (kind) => {
    expect(migration).toContain(`'${kind}'`);
  });

  test("requires assigned same-facility active Technician execution authority", () => {
    expect(migration).toContain("actor->>'role'<>'technician'");
    expect(migration).toContain("w.assigned_technician_id<>actor_id");
    expect(migration).toContain("public.technician_facility_read_permitted(w.facility_id)");
    expect(migration).toContain("w.status not in ('assigned','in_progress')");
    expect(migration).toContain("existing.entered_by<>actor_id");
  });

  test("preserves contractor assignment for service and call-out actuals", () => {
    expect(migration).toContain("case when kind in ('service','callout') then w.assigned_vendor_id end");
    expect(migration).not.toMatch(/update public\.work_orders set[^;]*assigned_vendor_id/is);
  });

  test("writes previous and new values to the Work Order audit atomically", () => {
    expect(migration).toContain("work_order_actual_cost_created");
    expect(migration).toContain("work_order_actual_cost_updated");
    expect(migration).toContain("'previous',previous_value,'new',pg_catalog.to_jsonb(result)");
    expect(migration).toContain("'facility_id',w.facility_id,'cost_line_id',result.id");
  });

  test("supports explicit zero-cost confirmation and gates physical completion", () => {
    expect(migration).toContain("actual_costs_confirmed_at");
    expect(migration).toContain("work_order_actual_costing_confirmed");
    expect(migration).toContain("ACTUAL_COSTING_CONFIRMATION_REQUIRED");
    expect(migration).toContain("actual_line_count");
    expect(migration).toContain("actual_total");
  });

  test("retains definer security, RLS, and denies direct browser mutation", () => {
    expect(migration).toContain("security definer set search_path=pg_catalog");
    expect(migration).toContain("revoke all on function public.manage_work_order_actual_cost(uuid,uuid,jsonb) from public,anon,service_role");
    expect(migration).toContain("grant execute on function public.manage_work_order_actual_cost(uuid,uuid,jsonb) to authenticated");
    for (const privilege of ["INSERT", "UPDATE", "DELETE"]) expect(migration).toContain(`'${privilege}'`);
    expect(migration).toContain("c.relrowsecurity");
  });

  test("preserves evidence and responsibility contracts while extending completion only", () => {
    expect(migration).not.toContain("create or replace function public.register_evidence_item");
    expect(migration).not.toContain("create or replace function public.accept_work_responsibility");
    expect(migration).toContain("create or replace function public.submit_physical_completion");
    expect(migration).toContain("At least one active After evidence item is required.");
  });
});
