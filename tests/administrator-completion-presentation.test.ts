import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
const permissions = readFileSync("lib/work-orders/permissions.ts", "utf8");

describe("Administrator formal completion presentation", () => {
  test("removes assignment execution actions from the Administrator workflow", () => {
    expect(page).toContain('action !== "accept" && action !== "start"');
    expect(actions).toContain('["accept", "start", "complete"].includes(action)');
  });

  test("does not require Administrator to re-enter an existing work record", () => {
    expect(page).toContain("operationalStage.completion.workRecordReceived && operationalStage.completion.labourHoursRecorded");
  });

  test("renders a single readiness-gated formal completion control", () => {
    expect(actions).toContain("Formal completion");
    expect(actions).toContain("Active After evidence");
    expect(actions).toContain("!props.completionReadiness.ready");
  });

  test("keeps Technician formal-completion authority denied by shared permissions", () => {
    expect(permissions).toContain('if (action === "complete") return false');
  });

  test("visually separates original instructions from the Technician work record", () => {
    expect(page).toContain("Original Work Order / Job Instructions");
    expect(page).toContain("Technician Work Record");
    expect(page).toContain('["Work performed", order.completion_notes]');
  });
});
