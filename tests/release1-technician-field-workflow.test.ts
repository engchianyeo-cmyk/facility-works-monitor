import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { canMutateWorkOrderEvidence } from "@/lib/evidence";

const read = (path: string) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const migration0039 = read("supabase/migrations/0039_technician_only_work_order_field_evidence.sql");
const deleteRoute = read("app/api/evidence/[id]/route.ts");
const drawings = read("components/work-order-drawings.tsx");

describe("Release-1 Technician field workflow contract", () => {
  test("responsible same-facility Technician may mutate active Work Order evidence", () => {
    expect(canMutateWorkOrderEvidence({
      role: "technician",
      userId: "tech-1",
      assignedTechnicianId: "tech-1",
      status: "assigned",
      hasActiveFacilityMembership: true,
    })).toBe(true);
    expect(canMutateWorkOrderEvidence({
      role: "technician",
      userId: "tech-1",
      assignedTechnicianId: "tech-1",
      status: "in_progress",
      hasActiveFacilityMembership: true,
    })).toBe(true);
  });

  test("Administrator and management cannot post Technician Before/After Work Order evidence", () => {
    for (const role of ["administrator", "supervisor", "approver", "facility_manager"]) {
      expect(canMutateWorkOrderEvidence({
        role,
        userId: `${role}-1`,
        assignedTechnicianId: null,
        status: "in_progress",
        hasActiveFacilityMembership: true,
        requesterId: `${role}-1`,
        creatorId: `${role}-1`,
      })).toBe(false);
    }
  });

  test("wrong, unassigned, inactive-membership, and terminal Technician evidence mutation is denied", () => {
    expect(canMutateWorkOrderEvidence({ role: "technician", userId: "tech-2", assignedTechnicianId: "tech-1", status: "assigned", hasActiveFacilityMembership: true })).toBe(false);
    expect(canMutateWorkOrderEvidence({ role: "technician", userId: "tech-1", assignedTechnicianId: null, status: "assigned", hasActiveFacilityMembership: true })).toBe(false);
    expect(canMutateWorkOrderEvidence({ role: "technician", userId: "tech-1", assignedTechnicianId: "tech-1", status: "assigned", hasActiveFacilityMembership: false })).toBe(false);
    expect(canMutateWorkOrderEvidence({ role: "technician", userId: "tech-1", assignedTechnicianId: "tech-1", status: "completed", hasActiveFacilityMembership: true })).toBe(false);
  });

  test("database registration enforces Technician-only active assignment and facility membership", () => {
    expect(migration0039).toContain("actor_role<>'technician'");
    expect(migration0039).toContain("w.assigned_technician_id=actor_id");
    expect(migration0039).toContain("w.status in ('assigned','in_progress')");
    expect(migration0039).toContain("fm.facility_id=w.facility_id");
    expect(migration0039).toContain("fm.membership_role='technician'");
    expect(migration0039).toContain("from public,anon,service_role");
    expect(migration0039).toContain("to authenticated");
  });

  test("active Work Order evidence removal also requires the responsible Technician", () => {
    expect(deleteRoute).toContain("Only the responsible Technician may remove active Before/After field evidence");
    expect(deleteRoute).not.toContain('if (item.work_order_id && identity.role !== "administrator")');
  });

  test("Technician layout uses only the configured drawing reference and saved marker", () => {
    expect(drawings).toContain("function configuredDrawing");
    expect(drawings).toContain("drawing_reference?.trim().toUpperCase()");
    expect(drawings).not.toContain("fallbackDrawing");
    expect(drawings).not.toMatch(/2nd|second|pantry|roof\/\.test/);
    expect(drawings).toContain("const marker = locationDrawing && mapX !== null && mapY !== null");
    expect(drawings).toContain("saved facility-plan position");
  });
});
