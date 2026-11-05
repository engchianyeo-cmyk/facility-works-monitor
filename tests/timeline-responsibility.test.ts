import { describe, expect, it } from "vitest";
import { nextStepKey, responsibilityFor, type ResponsibilityContext } from "@/lib/work-orders/timeline-responsibility";

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
  it("names the Approver for the review, and tells Technician 1 it is not theirs", () => {
    const r = responsibilityFor("reviewed", base);
    expect(r.role).toBe("Approver");
    expect(r.who).toBe("the Approver");
    expect(r.viewerIsResponsible).toBe(false);
    expect(responsibilityFor("reviewed", { ...base, viewer: { id: "a1", role: "approver" } }).viewerIsResponsible).toBe(true);
  });
  it("sends Technician 1 to upload the invoice, then Finance to record the payment", () => {
    expect(responsibilityFor("closed", base)).toMatchObject({ role: "Technician 1", href: "#payment-heading", viewerIsResponsible: true });
    expect(responsibilityFor("closed", { ...base, invoiceUploaded: true, viewer: { id: "f1", role: "finance" } })).toMatchObject({ role: "Finance", viewerIsResponsible: true });
    expect(responsibilityFor("closed", { ...base, inHouse: true }).role).toBe("System");
  });
  it("gives the endorsement to Technician 2, any other Technician, and links to the endorsement panel", () => {
    const r = responsibilityFor("endorse-review", { ...base, endorserName: { submission: null, review: null }, viewer: { id: "t2", role: "technician" } });
    expect(r).toMatchObject({ role: "Technician 2", who: "any other Technician of this facility", href: "#technician-endorsement", viewerIsResponsible: true });
  });
});
