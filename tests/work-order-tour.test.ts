import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { asksForGuidance, workOrderTour } from "@/lib/help/work-order-tour";

describe("Ollie walks a first-time user through a Work Order (UAT 21 Nov 2026)", () => {
  it("gives a Technician the steps for the Work Order's stage", () => {
    const draft = workOrderTour("draft", "technician", true).map((s) => s.title);
    expect(draft[0]).toBe("Let's go through this Work Order");
    expect(draft).toContain("3 · Mark the location");
    expect(draft).toContain("5 · Submit for approval");
    expect(workOrderTour("in_progress", "technician", true).map((s) => s.title)).toContain("3 · Record what you did");
    expect(workOrderTour("submitted", "approver", false).some((s) => s.text.includes("Approve or Return to Draft"))).toBe(true);
  });

  it("recognises 'what should I do now?' and similar", () => {
    for (const q of ["what should i do now?", "What's next", "walk me through it", "first time here", "how do I start"]) expect(asksForGuidance(q)).toBe(true);
    for (const q of ["which priority should I choose", "password"]) expect(asksForGuidance(q)).toBe(false);
  });

  it("offers the walk-through in Ollie's panel and to first-time Technicians", () => {
    const panel = readFileSync("components/help/help-panel.tsx", "utf8");
    expect(panel).toContain("Walk me through this Work Order, step by step");
    expect(panel).toContain("First time on a Work Order?");
    expect(panel).toContain("Show me on the page, step by step");
  });
});

describe("Ollie does not mistake app words for places (UAT 21 Nov 2026)", () => {
  it("searches the facility only for place questions", async () => {
    const { placeTerms } = await import("@/lib/help/places");
    expect(placeTerms("I am new and need you to guide me through the work order")).toEqual([]);
    expect(placeTerms("what should i do now?")).toEqual([]);
    expect(placeTerms("Is there a room to store morphine?")).toEqual(["controlled drug", "vault"]);
  });
  it("shows what is still missing on the Work Order", () => {
    expect(readFileSync("components/help/help-panel.tsx", "utf8")).toContain("Still missing on this Work Order");
    expect(readFileSync("app/work-orders/[id]/page.tsx", "utf8")).toContain("missing={draftMissing.map(String)}");
  });
});
