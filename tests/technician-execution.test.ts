import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import {
  authorizedExecutionActions,
  WORK_RECORD_SUCCESS,
  executionResponseMessage,
  validateWorkRecordDraft,
} from "@/lib/work-orders/execution-interaction";

const root = new URL("../", import.meta.url);
const component = readFileSync(new URL("components/work-orders/work-order-actions.tsx", root), "utf8");
const page = readFileSync(new URL("app/work-orders/[id]/page.tsx", root), "utf8");

describe("Technician execution interaction", () => {
  test("renders only actions authorized by the server page", () => {
    expect(authorizedExecutionActions("assigned", ["start"])).toEqual([{ action: "start", label: "Start work" }]);
    expect(authorizedExecutionActions("assigned", [])).toEqual([]);
    expect(page).toContain("canAct(action, context)");
    expect(page).toContain('identity.role === "technician"');
    expect(page).not.toContain('.eq("assigned_technician_id", identity.userId)');
    expect(page).toContain("canRecordWork(context)");
  });

  test("keeps the protected start interaction to one intentional action", () => {
    expect(authorizedExecutionActions("assigned", ["start"])[0]).toEqual({ action: "start", label: "Start work" });
    expect(component).toContain('void transition(action, {})');
    expect(component).toContain('`/api/work-orders/${props.id}/transition`');
  });

  test("validates work records without claiming completion", () => {
    expect(validateWorkRecordDraft("", "2")).toEqual({ ok: false, error: "Work performed statement is required." });
    expect(validateWorkRecordDraft("Replaced bearing", "-1")).toEqual({ ok: false, error: "Labour hours must be zero or greater." });
    expect(validateWorkRecordDraft(" Replaced bearing ", "2.5")).toEqual({ ok: true, payload: { completion_notes: "Replaced bearing", actual_labour_hours: 2.5 } });
  });

  test("preserves controlled input following recoverable failures", () => {
    for (const state of ["completionNotes", "actualHours", "approvalReason", "cancellationReason", "reviewReason", "reworkReason"]) {
      expect(component).toContain(`value={${state}}`);
    }
    expect(component).not.toContain("form.reset");
    expect(component).not.toContain("setCompletionNotes(\"\")");
    expect(component).toContain("Nothing was submitted");
  });

  test("prevents duplicate submissions synchronously", () => {
    expect(component).toContain("const submittingRef = useRef(false)");
    expect(component).toContain("if (submittingRef.current) return");
    expect(component).toContain("submittingRef.current = true");
    expect(component).toContain("submittingRef.current = false");
  });

  test("classifies session, authorization, server and service failures safely", () => {
    expect(executionResponseMessage(401, {})).toMatch(/session is no longer active/i);
    expect(executionResponseMessage(403, {})).toMatch(/not authorized/i);
    expect(executionResponseMessage(409, { message: "Transition is no longer permitted." })).toBe("Transition is no longer permitted.");
    expect(executionResponseMessage(503, {})).toMatch(/temporarily unavailable.*Nothing was submitted/i);
  });

  test("uses canonical completion language without claiming approval", () => {
    expect(WORK_RECORD_SUCCESS).toBe("Work record saved. Awaiting authorised completion.");
    expect(component).toContain("Record Work Done");
    expect(component).toContain("does not formally complete or close");
  });

  test("provides a mobile-oriented accessible interaction structure", () => {
    for (const contract of ["min-h-12", "w-full", "overflow-hidden", "focus-visible:ring-4", 'role="alert"', 'role="status"', "aria-describedby"]) {
      expect(component).toContain(contract);
    }
    expect(component).not.toContain("overflow-x-auto");
    expect(page.indexOf("<WorkOrderActions")).toBeLessThan(page.indexOf("Assignment details"));
  });

  test("collects approval, completion and cancellation input inline", () => {
    expect(component).toContain('interaction === "approve"');
    expect(component).toContain('interaction === "record_work"');
    expect(component).toContain('interaction === "cancel"');
    expect(component).toContain('interaction === "review"');
    expect(component).toContain('interaction === "return_for_rework"');
    expect(component).toContain("Cancellation reason");
    expect(component).not.toContain("window.prompt");
    expect(component).not.toContain("window.confirm");
  });
});
