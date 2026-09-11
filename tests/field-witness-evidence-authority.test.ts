import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { canMutateWorkOrderEvidence } from "@/lib/evidence";

const migration = readFileSync(new URL("../supabase/migrations/0036_technician_field_evidence_authority.sql", import.meta.url), "utf8");
const functionDefinition = migration.split("$function$")[1] ?? "";
const assigned = { role: "technician", userId: "tech-a", assignedTechnicianId: "tech-a", status: "in_progress", hasActiveFacilityMembership: true };

describe("Technician field-witness evidence authority", () => {
  test("allows the assigned Technician without trade-based authorization", () => {
    expect(canMutateWorkOrderEvidence(assigned)).toBe(true);
    expect(migration).toContain("w.assigned_technician_id=actor_id");
    expect(functionDefinition).not.toMatch(/trade_discipline|electrical|mechanical/i);
  });
  test("denies another Technician and an unassigned Work Order", () => {
    expect(canMutateWorkOrderEvidence({ ...assigned, assignedTechnicianId: "tech-b" })).toBe(false);
    expect(canMutateWorkOrderEvidence({ ...assigned, assignedTechnicianId: null })).toBe(false);
  });
  test("denies missing, inactive, or different-facility membership", () => {
    expect(canMutateWorkOrderEvidence({ ...assigned, hasActiveFacilityMembership: false })).toBe(false);
    expect(canMutateWorkOrderEvidence({ role: "technician", userId: "tech-a", assignedTechnicianId: "tech-a", status: "in_progress" })).toBe(false);
    expect(migration).toContain("fm.facility_id=w.facility_id");
    expect(migration).toContain("fm.effective_from<=pg_catalog.now()");
  });
  test.each(["assigned", "in_progress"])("allows field evidence while %s", (status) => expect(canMutateWorkOrderEvidence({ ...assigned, status })).toBe(true));
  test.each(["completed", "reviewed", "closed", "cancelled"])("makes Technician evidence read-only while %s", (status) => expect(canMutateWorkOrderEvidence({ ...assigned, status })).toBe(false));
  test("keeps routine field upload available without an Administrator", () => expect(canMutateWorkOrderEvidence(assigned)).toBe(true));
  test("does not let Technician requester or creator status bypass assignment authority", () => {
    expect(canMutateWorkOrderEvidence({ ...assigned, assignedTechnicianId: "tech-b", requesterId: "tech-a", creatorId: "tech-a" })).toBe(false);
    expect(canMutateWorkOrderEvidence({ ...assigned, status: "completed", requesterId: "tech-a", creatorId: "tech-a" })).toBe(false);
  });
  test.each(["approver", "supervisor", "administrator"])("preserves %s authority without a status restriction", (role) => {
    expect(canMutateWorkOrderEvidence({ ...assigned, role, assignedTechnicianId: null, status: "completed" })).toBe(true);
  });
  test("preserves requester and creator authority for non-Technicians", () => {
    expect(canMutateWorkOrderEvidence({ ...assigned, role: "reviewer", assignedTechnicianId: null, status: "completed", requesterId: "tech-a" })).toBe(true);
    expect(canMutateWorkOrderEvidence({ ...assigned, role: "initiator", assignedTechnicianId: null, status: "closed", creatorId: "tech-a" })).toBe(true);
  });
  test("does not newly grant Facility Manager authority", () => {
    expect(canMutateWorkOrderEvidence({ ...assigned, role: "facility_manager", assignedTechnicianId: null })).toBe(false);
  });
  test("preserves the database function ACL", () => {
    expect(migration).toContain("security definer set search_path=pg_catalog");
    expect(migration).toContain("revoke all on function public.register_evidence_item");
    expect(migration).toContain("grant execute on function public.register_evidence_item");
  });
});
