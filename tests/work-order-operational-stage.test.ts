import { describe, expect, test } from "vitest";
import { deriveWorkOrderOperationalStage } from "@/lib/work-orders/operational-stage";

const recorded = { status: "assigned" as const, completionNotes: "Pump reset and tested.", actualLabourHours: 5 };

describe("Work Order operational stage", () => {
  test("awaits active After evidence after the work record is submitted", () => {
    const result = deriveWorkOrderOperationalStage({ ...recorded, evidence: [{ category: "before", deleted_at: null }] });
    expect(result.label).toBe("Awaiting After Evidence");
    expect(result.nextAction).toBe("Add After Evidence");
    expect(result.completion.ready).toBe(false);
  });

  test.each([
    ["legacy Completion", [{ category: "completion", deleted_at: null }]],
    ["deleted After", [{ category: "after", deleted_at: "2026-09-10T00:00:00Z" }]],
  ])("does not accept %s as active After evidence", (_name, evidence) => {
    expect(deriveWorkOrderOperationalStage({ ...recorded, evidence }).completion.ready).toBe(false);
  });

  test("is ready only with work, valid labour and active After evidence", () => {
    const result = deriveWorkOrderOperationalStage({ ...recorded, evidence: [{ category: "after", deleted_at: null }] });
    expect(result.label).toBe("Ready for Administrator Completion");
    expect(result.nextAction).toBe("Mark Completed");
    expect(result.completion.ready).toBe(true);
  });

  test("distinguishes assigned, work in progress, submitted and terminal stages", () => {
    expect(deriveWorkOrderOperationalStage({ status: "assigned" }).label).toBe("Assigned — Not Started");
    expect(deriveWorkOrderOperationalStage({ status: "in_progress" }).label).toBe("Work In Progress");
    expect(deriveWorkOrderOperationalStage({ status: "assigned", completionNotes: "Partial" }).label).toBe("Work Record Submitted");
    expect(deriveWorkOrderOperationalStage({ status: "completed" }).label).toBe("Awaiting Verification");
    expect(deriveWorkOrderOperationalStage({ status: "closed" }).label).toBe("Closed");
  });
});
