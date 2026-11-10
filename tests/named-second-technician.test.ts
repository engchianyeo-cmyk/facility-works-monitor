import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { noticeText, waitingForReader } from "@/lib/notices";
import { emailRule } from "@/lib/notifications/email-rules";
import { canSetSecondTechnician } from "@/lib/work-orders/permissions";
import { responsibilityFor, type ResponsibilityContext } from "@/lib/work-orders/timeline-responsibility";

/** D-49 (10 Nov 2026): Technician 2 is named on the Work Order, told in advance and when the endorsement is due. */
const base: ResponsibilityContext = {
  technician1Name: "Ying Zhang", technician1Id: "t1", technician2Name: "Yang Ying Zhang", technician2Id: "t2", approverName: null,
  endorserName: { submission: null, review: null }, inHouse: true, invoiceUploaded: false, viewer: { id: "t2", role: "technician" },
};

describe("D-49 named Technician 2", () => {
  it("names Technician 2 on the endorsement step and points only them to it", () => {
    expect(responsibilityFor("endorse-review", base)).toMatchObject({ role: "Technician 2", who: "Yang Ying Zhang", viewerIsResponsible: true, href: "#technician-endorsement" });
    expect(responsibilityFor("endorse-review", { ...base, viewer: { id: "t3", role: "technician" } }).viewerIsResponsible).toBe(false);
    expect(responsibilityFor("endorse-review", { ...base, technician2Id: null, technician2Name: null, viewer: { id: "t3", role: "technician" } }))
      .toMatchObject({ who: "any other Technician of this facility", viewerIsResponsible: true });
  });

  it("tells Technician 2 when named and when the endorsement is due, by email as well", () => {
    expect(noticeText("work_order_second_technician_named").text).toContain("work with Technician 1");
    expect(noticeText("work_order_endorsement_due")).toMatchObject({ href: "#technician-endorsement" });
    expect(emailRule("work_order_second_technician_named", "technician")).toBe("send");
    expect(emailRule("work_order_endorsement_due", "technician")).toBe("send");
  });

  it("keeps the Work Order waiting for Technician 2 until they have endorsed it for review", () => {
    const order = { status: "completed", assigned_technician_id: "t1", in_house_work: true, second_technician_id: "t2" };
    expect(waitingForReader(order, { id: "t2", role: "technician" })).toBe(true);
    expect(waitingForReader(order, { id: "t2", role: "technician" }, true)).toBe(false);
    expect(waitingForReader({ ...order, status: "in_progress" }, { id: "t2", role: "technician" })).toBe(false);
    expect(waitingForReader(order, { id: "t3", role: "technician" })).toBe(false);
  });

  it("lets approval authorities name Technician 2 until the work is approved as Completed", () => {
    expect(canSetSecondTechnician("supervisor", "in_progress")).toBe(true);
    expect(canSetSecondTechnician("approver", "completed")).toBe(true);
    expect(canSetSecondTechnician("technician", "draft")).toBe(false);
    expect(canSetSecondTechnician("supervisor", "reviewed")).toBe(false);
  });

  it("shows the Technician 2 section and route on the Work Order page", () => {
    const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
    expect(page).toContain('id="technician-2"');
    expect(page).toContain('which="second"');
    const route = readFileSync("app/api/work-orders/[id]/second-technician/route.ts", "utf8");
    expect(route).toContain('rpc("set_work_order_second_technician"');
  });
});
