import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/0037_governed_work_order_lifecycle.sql", "utf8");
const rollbackHarness = readFileSync("scripts/validate-0037-preview-rollback.sql", "utf8");
const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");

describe("WP-FMW-026A governed Work Order lifecycle", () => {
  const cases: Array<[string, string | RegExp]> = [
    ["1 incomplete approval basis denied", "APPROVAL_NOT_READY"],
    ["2 internal-note-only cost is ignored", "from public.work_order_cost_lines c"],
    ["3 structured cost is summed", "sum(c.amount)"],
    ["4 Supervisor threshold", "proposed<=250000"],
    ["5 Facility Manager threshold", "proposed<=500000"],
    ["6 Administrator threshold", "proposed<=1000000"],
    ["7 Board documentation threshold", "board_approval_reference_date_and_supporting_document"],
    ["8 self approval protection", "SELF_APPROVAL_DENIED"],
    ["9 same-facility Technician acceptance", "public.technician_facility_read_permitted(w.facility_id)"],
    ["10 acceptance audit", "work_order_responsibility_accepted"],
    ["11 cross facility denied", "Active same-facility Technician membership is required."],
    ["12 ownership cannot be stolen", "ASSIGNMENT_CONFLICT"],
    ["13 terminal acceptance denied", "w.status not in ('approved','assigned','in_progress')"],
    ["14 view-only acceptance denied", "actor->>'role'<>'technician'"],
    ["15 assigned Technician completion", "public.submit_physical_completion"],
    ["16 missing work statement", "A work-performed statement is required."],
    ["17 missing labour", "Cumulative non-negative labour hours are required."],
    ["18 missing After evidence", "At least one active After evidence item is required."],
    ["19 other Technician denied", "w.assigned_technician_id<>actor_id"],
    ["20 completion facility boundary", "not public.technician_facility_read_permitted(w.facility_id)"],
    ["21 authoritative completion event", "'work_order_complete'"],
    ["22 completion status", "set status='completed'"],
    ["23 completed evidence read-only preserved", "public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)"],
    ["24 completion event recognized", "l.action='work_order_complete'"],
    ["25 missing event blocks readiness", "authoritative_completion_submission_event"],
    ["26 Administrator reason surfaced", "self_verification_reason_required"],
    ["27 governed verification retained", "public.verify_completed_work(uuid,jsonb)"],
    ["28 legacy history is labelled", "legacy_completion_record"],
    ["29 0035 boundary snapshot", "public.technician_facility_read_permitted(uuid)"],
    ["30 0036 boundary snapshot", "0037 changed protected 0035/0036 security contracts"],
    ["31 anonymous execution denied", "has_function_privilege('anon',object_name,'EXECUTE')"],
  ];

  test.each(cases)("%s", (_, contract) => expect(migration).toMatch(contract));

  test("uses four distinct, unambiguous UI decisions", () => {
    for (const label of ["Approve Work to Proceed", "Accept Work / Take Responsibility", "Record Work Done", "Submit Physical Completion", "Verify Completed Work", "Reject & Reopen"]) {
      expect(`${actions}\n${readFileSync("lib/work-orders/execution-interaction.ts", "utf8")}`).toContain(label);
    }
  });

  test("provides an audited governed authoring path for structured approval basis", () => {
    expect(migration).toContain("public.set_work_order_approval_basis");
    expect(migration).toContain("work_order_approval_basis_recorded");
    expect(migration).toContain("Certified or approved cost lines cannot be replaced");
  });

  test("aligns Facility Manager readiness but scopes lifecycle authority to effective membership", () => {
    expect(migration).toContain("'supervisor','facility_manager','administrator'");
    expect(migration).toContain("public.facility_manager_facility_permitted(w.facility_id)");
    expect(migration).toContain("fm.membership_role='facility_manager'");
    expect(migration).toContain("fm.effective_from<=pg_catalog.now()");
    expect(migration).toContain("fm.effective_to is null or fm.effective_to>pg_catalog.now()");
  });

  test("uses unambiguous decimal monetary boundaries", () => {
    expect(migration).toContain("proposed<=250000");
    expect(migration).toContain("proposed<=500000");
    expect(migration).toContain("proposed<=1000000");
    expect(migration).toContain("proposed>1000000");
  });

  test("protects direct Facility Manager verification and transition calls", () => {
    expect(migration).toContain("verify_completed_work_0037_core");
    expect(migration).toContain("Active same-facility Facility Manager membership is required.");
    expect(migration).toContain("revoke all on function public.verify_completed_work_0037_core(uuid,jsonb) from public,anon,authenticated,service_role");
  });

  test("scopes Supervisor read and lifecycle authority to effective facility membership", () => {
    expect(migration).toContain("public.supervisor_facility_permitted(facility_id)");
    expect(migration).toContain("public.supervisor_facility_permitted(w.facility_id)");
    expect(migration).toContain("fm.membership_role='supervisor'");
    expect(migration).toContain("Active same-facility Supervisor membership is required.");
    expect(rollbackHarness).toContain("Supervisor same-facility Work Order visible");
    expect(rollbackHarness).toContain("Supervisor cross-facility Work Order denied");
    expect(rollbackHarness).toContain("inactive Supervisor membership denies Work Order visibility");
    expect(rollbackHarness).toContain("not-yet-effective Supervisor membership denies Work Order visibility");
    expect(rollbackHarness).toContain("expired Supervisor membership denies Work Order visibility");
    expect(rollbackHarness).toContain("Supervisor approval allowed at 250000");
    expect(rollbackHarness).toContain("Supervisor approval above 250000 denied");
    expect(rollbackHarness).toContain("same-facility Supervisor verification allowed");
    expect(rollbackHarness).toContain("Supervisor receives no Technician authority");
  });

  test("uses only rollback-only profiles for harness role identities", () => {
    expect(rollbackHarness).not.toMatch(/from public\.profiles where role=/);
    expect(rollbackHarness).not.toMatch(/(?:insert into|update|delete from) auth\.users/i);
    expect(rollbackHarness).toContain("WP-FMW-026E Rollback Administrator");
    expect(rollbackHarness).toContain("WP-FMW-026E Rollback Supervisor");
    expect(rollbackHarness).toContain("WP-FMW-026E Rollback Technician 1");
    expect(rollbackHarness).toContain("WP-FMW-026E Rollback Reviewer");
    expect(rollbackHarness).toContain("rollback;");
  });

  test("keeps nullable synthetic Work Order user IDs clear of legacy user foreign keys", () => {
    expect(rollbackHarness).not.toMatch(/insert into public\.users/i);
    expect(rollbackHarness).not.toMatch(/alter table public\.work_orders alter constraint work_orders_user_id_fkey/i);
    expect(rollbackHarness).toContain("status,user_id,requested_by");
    expect(rollbackHarness).toContain("'submitted',null,:'admin_id'");
    expect(rollbackHarness).toContain("'in_progress',null,:'admin_id'");
  });

  test("proves physical-completion facility membership boundaries with eligible synthetic fixtures", () => {
    expect(rollbackHarness).toContain("'in_progress',null,:'admin_id',:'tech2_id','Cross-facility Technician'");
    expect(rollbackHarness).toContain("cross-facility Technician denied");
    expect(rollbackHarness).toContain("inactive Technician membership denies physical completion");
    expect(rollbackHarness).toContain("not-yet-effective Technician membership denies physical completion");
    expect(rollbackHarness).toContain("expired Technician membership denies physical completion");
  });

  test("consolidates active evidence filtering and corrects Engineering System wording", () => {
    expect(page).toContain('item.category === "after" && !item.deleted_at');
    expect(page).toContain("Engineering System: Not configured");
    expect(readFileSync("app/operations/page.tsx", "utf8")).toContain('.is("deleted_at", null)');
  });
});
