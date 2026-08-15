import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import {
  buildWorkOrderDecisionModel,
  dueExposure,
  evidencePresentation,
  incidentPresentation,
  ownershipPresentation,
} from "@/lib/work-orders/decision-header";
import { authorizedExecutionActions } from "@/lib/work-orders/execution-interaction";

const root = new URL("../", import.meta.url);
const component = readFileSync(new URL("components/work-orders/work-order-decision-header.tsx", root), "utf8");
const page = readFileSync(new URL("app/work-orders/[id]/page.tsx", root), "utf8");

function model(overrides: Partial<Parameters<typeof buildWorkOrderDecisionModel>[0]> = {}) {
  return buildWorkOrderDecisionModel({
    priority: "medium",
    status: "in_progress",
    dueDate: "2026-08-30",
    today: "2026-08-14",
    assignedTechnicianId: "1e9de9df-c177-45ea-a4dc-98096f413107",
    recordedAssignee: "Aisha Rahman",
    evidenceCount: 0,
    ...overrides,
  });
}

describe("Work Order decision header presentation", () => {
  test("promotes critical work as the first exception", () => {
    const result = model({ priority: "critical" });
    expect(result.exceptions[0]).toMatchObject({ kind: "critical", label: "Critical priority", rank: 10 });
  });

  test("classifies overdue work with exact calendar exposure", () => {
    const result = dueExposure({ dueDate: "2026-08-11", today: "2026-08-14", status: "in_progress" });
    expect(result).toMatchObject({ state: "overdue", label: "Overdue by 3 days", actionable: true });
  });

  test("makes an absent primary owner explicit", () => {
    expect(ownershipPresentation({})).toEqual({ state: "unassigned", label: "Unassigned", detail: "No primary owner is recorded." });
    expect(model({ assignedTechnicianId: null, recordedAssignee: null }).exceptions.some((item) => item.kind === "unassigned")).toBe(true);
  });

  test("keeps normal assigned work visually subordinate to exceptions", () => {
    expect(model().exceptions).toEqual([]);
  });

  test("preserves Completed — Awaiting Review as a distinct state", () => {
    const result = model({ status: "completed" });
    expect(result.status).toBe("Completed — Awaiting Review");
    expect(result.exceptions).toContainEqual(expect.objectContaining({ kind: "review", label: "Awaiting review" }));
  });

  test("does not promote cancelled critical work as an active exception", () => {
    const result = model({ status: "cancelled", priority: "critical", dueDate: "2026-08-01" });
    expect(result.status).toBe("Cancelled");
    expect(result.due.state).toBe("recorded");
    expect(result.exceptions).toEqual([]);
  });

  test("distinguishes no due date from unavailable due information", () => {
    expect(dueExposure({ dueDate: null, today: "2026-08-14", status: "assigned" }).state).toBe("none");
    expect(dueExposure({ dueDate: undefined, today: "2026-08-14", status: "assigned" }).state).toBe("unavailable");
  });

  test("distinguishes due today, due soon and a future due date without inventing an SLA", () => {
    expect(dueExposure({ dueDate: "2026-08-14", today: "2026-08-14", status: "assigned" }).state).toBe("today");
    expect(dueExposure({ dueDate: "2026-08-16", today: "2026-08-14", status: "assigned" }).state).toBe("soon");
    expect(dueExposure({ dueDate: "2026-08-30", today: "2026-08-14", status: "assigned" }).state).toBe("future");
  });

  test("presents only an authorized related incident record as navigable context", () => {
    const incident = incidentPresentation({ linked: true, reference: "INC-2026-0042", severity: "emergency", status: "on_site" });
    expect(incident).toMatchObject({ available: true, reference: "INC-2026-0042", severity: "Emergency", status: "On Site", active: true });
    expect(page).toContain('.from("incidents").select("id,incident_number,severity,status")');
  });

  test("reports evidence count without claiming sufficiency or approval", () => {
    expect(evidencePresentation(1)).toEqual({ state: "available", label: "Evidence available: 1 item" });
    expect(evidencePresentation(3)).toEqual({ state: "available", label: "Evidence available: 3 items" });
    expect(component).not.toMatch(/Evidence (complete|sufficient|approved)/i);
  });

  test("reports evidence availability failures truthfully", () => {
    expect(evidencePresentation(undefined)).toEqual({ state: "unavailable", label: "Evidence availability unavailable" });
    expect(model({ evidenceCount: undefined }).exceptions).toContainEqual(expect.objectContaining({ kind: "unavailable" }));
  });

  test("handles unknown future enum values without inventing workflow actions", () => {
    const result = model({ status: "quality_hold" });
    expect(result.status).toBe("Quality hold");
    expect(authorizedExecutionActions("quality_hold", ["start"])).toEqual([]);
  });

  test("never promotes raw UUIDs into ownership presentation", () => {
    const identifier = "1e9de9df-c177-45ea-a4dc-98096f413107";
    const ownership = ownershipPresentation({ assignedTechnicianId: identifier, recordedAssignee: identifier, resolvedAssignee: identifier });
    expect(ownership).toMatchObject({ state: "unavailable", label: "Assignment unavailable" });
    expect(JSON.stringify(ownership)).not.toContain(identifier);
    expect(page).not.toContain('["Requested by", order.submitted_by]');
    expect(page).not.toContain('["Asset ID", order.asset_id]');
  });

  test("reuses canonical terminology and server-derived permitted actions", () => {
    const submitted = model({ status: "submitted", assignedTechnicianId: null, recordedAssignee: null });
    expect(submitted.status).toBe("Awaiting Approval");
    expect(submitted.exceptions).toContainEqual(expect.objectContaining({ kind: "approval", label: "Awaiting approval" }));
    expect(submitted.exceptions.some((item) => item.kind === "unassigned")).toBe(false);
    expect(page).toContain("canAct(action, context)");
    expect(page).toContain("authorizedExecutionActions(String(order.status), allowedActions)");
    expect(component).toContain("execution panel below remains the authoritative place");
  });

  test("uses mobile-oriented semantic structure without horizontal scrolling", () => {
    for (const contract of [
      'aria-labelledby="work-order-title"',
      'aria-label="Work Order decision facts"',
      'aria-label="Next permitted action"',
      "break-words",
      "min-h-11",
      "focus-visible:ring-4",
      "grid-cols-2",
      "order-first",
    ]) expect(component).toContain(contract);
    expect(component).not.toContain("overflow-x-auto");
    expect(page.indexOf("<WorkOrderDecisionHeader")).toBeLessThan(page.indexOf("<WorkOrderActions"));
  });
});
