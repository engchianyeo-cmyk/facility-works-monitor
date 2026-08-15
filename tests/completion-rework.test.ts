import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { activeReworkContext, reworkHistory } from "@/lib/work-orders/rework";
import { authorizedExecutionActions } from "@/lib/work-orders/execution-interaction";

const root = new URL("../", import.meta.url);
const component = readFileSync(new URL("components/work-orders/work-order-actions.tsx", root), "utf8");
const page = readFileSync(new URL("app/work-orders/[id]/page.tsx", root), "utf8");

const returned = {
  action: "work_order_returned_for_rework",
  actor: "Supervisor Tan",
  created_at: "2026-08-14T08:00:00Z",
  note: JSON.stringify({
    cycle: 2,
    reason: "Provide the final insulation resistance reading.",
    previous_completion: {
      completion_notes: "Cable replaced and tested.",
      cumulative_labour_hours: 4.5,
      completed_at: "2026-08-14T07:00:00Z",
      evidence_ids: ["evidence-1", "evidence-2"],
    },
  }),
};

describe("completion review and rework interaction", () => {
  test("offers separate accept and return decisions only when authorized", () => {
    expect(authorizedExecutionActions("completed", ["review", "return_for_rework"]))
      .toEqual([{ action: "review", label: "Accept completion" }, { action: "return_for_rework", label: "Return for rework" }]);
    expect(authorizedExecutionActions("completed", [])).toEqual([]);
  });

  test("requires a reason before submitting rework and retains controlled input", () => {
    expect(component).toContain('if (!reason) { setError("A rework reason is required."); return; }');
    expect(component).toContain("value={reworkReason}");
    expect(component).not.toContain('setReworkReason("")');
  });

  test("uses the shared synchronous double-submit guard", () => {
    expect(component).toContain("if (submittingRef.current) return");
    expect(component).toContain("submittingRef.current = true");
  });

  test("presents technician correction context from immutable audit history", () => {
    expect(activeReworkContext("in_progress", [returned])).toMatchObject({ cycle: 2, reason: "Provide the final insulation resistance reading." });
    expect(component).toContain("Completion returned for correction");
    expect(component).toContain("Record corrected completion");
    expect(page).toContain("activeReworkContext");
  });

  test("preserves previous completion, labour and evidence as historical context", () => {
    expect(reworkHistory([returned])).toEqual([expect.objectContaining({
      completionNotes: "Cable replaced and tested.",
      cumulativeLabourHours: 4.5,
      evidenceIds: ["evidence-1", "evidence-2"],
    })]);
    expect(component).toContain("Prior rework cycles");
  });

  test("handles malformed or unknown audit data without inventing context", () => {
    expect(reworkHistory([{ action: "work_order_returned_for_rework", note: "not-json" }])).toEqual([]);
    expect(activeReworkContext("future_status", [returned])).toBeNull();
  });

  test("uses inline forms and canonical Approval Centre terminology", () => {
    expect(component).not.toContain("window.prompt");
    expect(component).not.toContain("window.confirm");
    expect(readFileSync(new URL("components/operations/OperationsWorkspace.tsx", root), "utf8")).toContain("Approval Centre");
  });
});
