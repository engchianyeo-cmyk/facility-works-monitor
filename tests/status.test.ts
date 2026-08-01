import { describe, expect, test } from "vitest";
import { nextStatus } from "@/lib/status";

describe("Workflow", () => {

  test("Submitted -> Approved", () => {

    expect(
      nextStatus(
        "submitted",
        "approve",
      ),
    ).toEqual({
      ok: true,
      to: "approved",
    });

  });

  test("Approved -> In Progress", () => {

    expect(
      nextStatus(
        "approved",
        "start",
      ),
    ).toEqual({
      ok: true,
      to: "in_progress",
    });

  });

  test("In Progress -> Done", () => {

    expect(
      nextStatus(
        "in_progress",
        "complete",
      ),
    ).toEqual({
      ok: true,
      to: "done",
    });

  });

  test("Submitted -> Rejected", () => {

    expect(
      nextStatus(
        "submitted",
        "reject",
      ),
    ).toEqual({
      ok: true,
      to: "rejected",
    });

  });

  test("Cannot approve twice", () => {

    expect(
      nextStatus(
        "approved",
        "approve",
      ).ok,
    ).toBe(false);

  });

});