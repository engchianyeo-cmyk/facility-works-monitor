import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const root = new URL("../", import.meta.url);
const migration = readFileSync(new URL("supabase/migrations/0034_work_order_execution_completion_authority.sql", root), "utf8");

describe("0034 work execution and completion authority", () => {
  test("records execution without completing the Work Order and retains an audit", () => {
    expect(migration).toContain("record_work_order_execution");
    expect(migration).toContain("'work_order_execution_recorded'");
    expect(migration).toContain("'status_unchanged',true");
    expect(migration).not.toMatch(/record_work_order_execution[\s\S]*?completed_at\s*=/);
  });

  test("limits formal completion to Administrator in the public transition function", () => {
    expect(migration).toContain("actor_role <> 'administrator'");
    expect(migration).toContain("Administrator authority is required to mark a Work Order Completed.");
    expect(migration).toContain("transition_work_order_0034_core");
    expect(migration).toContain("revoke all on function public.transition_work_order_0034_core(uuid,text,jsonb)");
  });

  test("requires saved work data and active After evidence only", () => {
    expect(migration).toContain("existing.completion_notes");
    expect(migration).toContain("existing.actual_labour_hours");
    expect(migration).toContain("e.category='after' and e.deleted_at is null");
    expect(migration).not.toContain("e.category in ('after','completion')");
  });

  test("preserves definer security and does not redefine completed-work verification", () => {
    expect(migration.match(/security definer/g)).toHaveLength(2);
    expect(migration.match(/set search_path = pg_catalog/g)).toHaveLength(2);
    expect(migration).not.toContain("create or replace function public.verify_completed_work");
    expect(migration).not.toContain("public.profiles set");
  });
});
