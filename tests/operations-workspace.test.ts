import { existsSync, readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const root = new URL("../", import.meta.url);
const read = (path: string) => readFileSync(new URL(path, root), "utf8");

describe("Operations Workspace", () => {
  test("provides an authenticated operations route", () => {
    const page = read("app/operations/page.tsx");
    expect(page).toContain("getCurrentIdentity()");
    expect(page).toContain('redirect("/login?next=/operations")');
    expect(page).toContain("createClient()");
    expect(page).not.toContain("createAdminClient");
  });

  test("provides the approved workspace views", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    for (const label of ["Today", "Work Queue", "Approvals", "Team", "Schedule", "Exceptions"]) {
      expect(workspace).toContain(label);
    }
  });

  test("prioritizes attention categories", () => {
    const page = read("app/operations/page.tsx");
    const emergency = page.indexOf('type: "emergency"');
    const critical = page.indexOf('type = "critical"');
    const overdue = page.indexOf('type = "overdue"');
    const unassigned = page.indexOf('type = "unassigned"');
    const approval = page.indexOf('type = "approval"');
    expect(emergency).toBeGreaterThan(-1);
    expect(critical).toBeGreaterThan(emergency);
    expect(overdue).toBeGreaterThan(critical);
    expect(unassigned).toBeGreaterThan(overdue);
    expect(approval).toBeGreaterThan(unassigned);
  });

  test("groups Today into a five-item manage-by-priority view", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    expect(workspace).toContain("data.attention.slice(0, 5)");
    for (const group of ["Immediate", "Decision Required", "Assignment Required", "Watch"]) {
      expect(workspace).toContain(group);
    }
  });

  test("defaults the Work Queue to actionable active work", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    expect(workspace).toContain('useState("active")');
    expect(workspace).toContain('["submitted", "approved", "assigned", "in_progress"]');
    expect(workspace).toContain('<option value="all">All</option>');
  });

  test("covers critical overdue and unassigned work", () => {
    const page = read("app/operations/page.tsx");
    expect(page).toContain('item.priority === "critical"');
    expect(page).toContain("item.overdue");
    expect(page).toContain("!item.assignee");
  });

  test("limits decision wording to existing authorized roles", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    expect(workspace).toContain('["approver", "supervisor", "administrator"].includes(data.role)');
    expect(workspace).toContain('canReview ? "Review decision" : "View work order"');
  });

  test("separates normal approvals from records requiring review", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    expect(workspace).toContain("approvalNeedsReview");
    expect(workspace).toContain("Review Required");
    expect(workspace).toContain("Normal Approval");
    expect(workspace).toContain("Evidence availability is unknown");
    expect(workspace).toContain("No evidence attached");
    expect(workspace).toContain("Evidence available:");
  });

  test("gives technicians a focused mobile-oriented experience", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    expect(workspace).toContain('const visibleViews = technician');
    expect(workspace).toContain('["today", "work", "schedule"].includes(view.id)');
    expect(workspace).toContain("min-h-11");
    expect(workspace).toContain("My Work");
    expect(workspace).toContain('item.id === "today" ? "Emergency"');
    expect(workspace).toContain('if (view.id === "approvals") return canReview');
  });

  test("keeps supervisor resource and exception views", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    expect(workspace).toContain('"supervisor"');
    expect(workspace).toContain("Team Operations");
    expect(workspace).toContain("AttentionQueue");
  });

  test("provides truthful empty and degraded states", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    expect(workspace).toContain("No immediate exceptions");
    expect(workspace).toContain("temporarily unavailable");
    expect(workspace).toContain("not live availability");
    expect(workspace).toContain("degradedForView");
    expect(workspace).toContain("No planned work is scheduled");
  });

  test("differentiates Exceptions from the Today action view", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    expect(workspace).toContain("Barriers to normal workflow");
    expect(workspace).toContain('item.type === "overdue"');
    expect(workspace).toContain('item.type === "unassigned"');
    expect(workspace).not.toContain('data.attention.filter((item) => item.type !== "approval")');
  });

  test("distinguishes physical and documentation status without changing workflow", () => {
    const workspace = read("components/operations/OperationsWorkspace.tsx");
    expect(workspace).toContain("Physical status");
    expect(workspace).toContain("Documentation status");
    expect(workspace).toContain("Work completed on site");
  });

  test("exposes operations in authenticated navigation", () => {
    expect(read("components/site-header.tsx")).toContain('href="/operations"');
    expect(existsSync(new URL("app/operations/page.tsx", root))).toBe(true);
  });
});
