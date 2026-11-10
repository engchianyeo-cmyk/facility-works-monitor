import { describe, expect, it } from "vitest";
import { nextStepKey, responsibilityFor, stepPassedOver, type ResponsibilityContext } from "@/lib/work-orders/timeline-responsibility";

const base: ResponsibilityContext = {
  technician1Name: "Yang Ying Zhang", technician1Id: "t1", approverName: null,
  endorserName: { submission: null, review: "Ying Zhang" }, inHouse: false, invoiceUploaded: false,
  viewer: { id: "t1", role: "technician" },
};

describe("D-34 timeline responsibility", () => {
  it("picks the first step not yet done as next, and none once closed", () => {
    const steps = [{ key: "created", at: "x" }, { key: "submitted", at: "x" }, { key: "reviewed", at: null }, { key: "closed", at: null }];
    expect(nextStepKey(steps, "completed")).toBe("reviewed");
    expect(nextStepKey(steps, "closed")).toBeNull();
  });
  it("UAT 10 Nov 2026: after approval as Completed, never points back to a step that was not recorded", () => {
    const steps = [{ key: "started", at: "x" }, { key: "finished", at: null }, { key: "completed", at: "x" }, { key: "endorse-review", at: null },
      { key: "reviewed", at: "x" }, { key: "invoiced", at: null }, { key: "closed", at: null }];
    expect(nextStepKey(steps, "reviewed")).toBe("invoiced");
    expect(stepPassedOver(steps, 1, "reviewed")).toBe(true);
    expect(stepPassedOver(steps, 3, "reviewed")).toBe(true);
    expect(stepPassedOver(steps, 5, "reviewed")).toBe(false);
    // Before the review, missing times are still required and stay the next step.
    expect(nextStepKey(steps.map((step) => step.key === "reviewed" ? { ...step, at: null } : step), "completed")).toBe("finished");
    expect(stepPassedOver(steps, 1, "completed")).toBe(false);
  });
  it("names the Approver for the review, and tells Technician 1 it is not theirs", () => {
    const r = responsibilityFor("reviewed", base);
    expect(r.role).toBe("Approver");
    expect(r.who).toBe("an approver who did not raise it");
    expect(r.viewerIsResponsible).toBe(false);
    expect(responsibilityFor("reviewed", { ...base, viewer: { id: "a1", role: "approver" } }).viewerIsResponsible).toBe(true);
  });
  it("sends Technician 1 to upload the invoice, then Finance to record the payment", () => {
    expect(responsibilityFor("closed", base)).toMatchObject({ role: "Technician 1", href: "#payment-heading", viewerIsResponsible: true });
    expect(responsibilityFor("closed", { ...base, invoiceUploaded: true, viewer: { id: "f1", role: "finance" } })).toMatchObject({ role: "Finance", viewerIsResponsible: true });
    expect(responsibilityFor("closed", { ...base, inHouse: true }).role).toBe("System");
    expect(responsibilityFor("invoiced", base)).toMatchObject({ role: "Technician 1", action: "upload the contractor invoice", href: "#payment-heading" });
  });
  it("gives the endorsement to Technician 2, any other Technician, and links to the endorsement panel", () => {
    const r = responsibilityFor("endorse-review", { ...base, endorserName: { submission: null, review: null }, viewer: { id: "t2", role: "technician" } });
    expect(r).toMatchObject({ role: "Technician 2", who: "any other Technician of this facility", href: "#technician-endorsement", viewerIsResponsible: true });
  });
});

describe("No contractor payment (UAT 9 Nov 2026)", () => {
  const none = { ...base, contractorPayable: false, noPayment: { status: null, proposedBy: null } };
  it("asks for No payment required instead of an invoice, and lets Technician 1 or a Supervisor propose it", () => {
    expect(responsibilityFor("invoiced", none)).toMatchObject({ role: "Technician 1", href: "#payment-heading", viewerIsResponsible: true });
    expect(responsibilityFor("invoiced", none).action).toContain("No payment required");
    expect(responsibilityFor("invoiced", { ...none, viewer: { id: "s1", role: "supervisor" } }).viewerIsResponsible).toBe(true);
    expect(responsibilityFor("invoiced", { ...none, viewer: { id: "a1", role: "approver" } }).viewerIsResponsible).toBe(false);
  });
  it("then sends it to an approver who did not propose it, and closes once approved", () => {
    const proposed = { ...none, noPayment: { status: "proposed", proposedBy: "s1" } };
    expect(responsibilityFor("invoiced", { ...proposed, viewer: { id: "a1", role: "approver" } })).toMatchObject({ role: "Approver", href: "#payment-heading", viewerIsResponsible: true });
    expect(responsibilityFor("invoiced", { ...proposed, viewer: { id: "s1", role: "supervisor" } }).viewerIsResponsible).toBe(false);
    expect(responsibilityFor("closed", { ...none, noPayment: { status: "approved", proposedBy: "s1" } }).role).toBe("System");
  });
  it("labels the step and explains the amounts beside the review note", async () => {
    const { readFileSync } = await import("node:fs");
    const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
    expect(page).toContain('label: "Approve No payment required (no contractor payment)"');
    const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
    expect(actions).toContain("No amount was approved for this Work Order, so the final cost of S$");
    expect(actions).not.toContain('"None (emergency or in-house)"');
    expect(readFileSync("components/work-orders/release-one-workspace.tsx", "utf8")).toContain("No contractor payment on this Work Order.");
  });
});

describe("Draft with no Technician yet (UAT 9 Nov 2026)", () => {
  it("gives the Draft steps and the link to the person who created it", () => {
    const noTech = { ...base, technician1Id: null, technician1Name: null, preparer: { id: "s1", name: "Sam Supervisor" } };
    const mine = responsibilityFor("submitted", { ...noTech, viewer: { id: "s1", role: "supervisor" } });
    expect(mine.viewerIsResponsible).toBe(true);
    expect(mine.who).toContain("Sam Supervisor");
    expect(responsibilityFor("created", { ...noTech, viewer: { id: "a1", role: "approver" } }).viewerIsResponsible).toBe(false);
    expect(responsibilityFor("submitted", { ...base, preparer: { id: "s1", name: "Sam" } }).viewerIsResponsible).toBe(true);
  });
});

describe("The person who raised a Work Order does not approve it (UAT 9 Nov 2026)", () => {
  it("gives no red box to the raiser, but does to another approver and to the Administrator", () => {
    const raised = { ...base, preparer: { id: "a1", name: "Yeo Eng Chian" } };
    expect(responsibilityFor("reviewed", { ...raised, viewer: { id: "a1", role: "approver" } }).viewerIsResponsible).toBe(false);
    expect(responsibilityFor("approved", { ...raised, viewer: { id: "a2", role: "supervisor" } }).viewerIsResponsible).toBe(true);
    expect(responsibilityFor("reviewed", { ...raised, viewer: { id: "a1", role: "administrator" } }).viewerIsResponsible).toBe(true);
  });
});
