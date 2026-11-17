import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { FAQS, PAGE_GUIDES, STAGE_GUIDES, guideForPath, relatedFaqs, searchHelp, stageAdvice, stepsFor } from "@/lib/help/guide-content";

describe("D-58 built-in Help guide", () => {
  it("finds the most specific page guide", () => {
    expect(guideForPath("/")?.id).toBe("home");
    expect(guideForPath("/work-orders")?.id).toBe("work-orders");
    expect(guideForPath("/work-orders/new")?.id).toBe("new-work-order");
    expect(guideForPath("/work-orders/emergency")?.id).toBe("emergency");
    expect(guideForPath("/work-orders/3f2a-uuid")?.id).toBe("work-order");
    expect(guideForPath("/finance/register")?.id).toBe("finance");
    expect(guideForPath("/administration/facilities/overview")?.id).toBe("facilities");
  });

  it("gives role steps, and only the role's own steps on set-up pages", () => {
    const users = guideForPath("/administration/users")!;
    expect(stepsFor(users, "facility_administrator").join(" ")).toContain("your own facility");
    expect(stepsFor(users, "technician")).toEqual(["Only an Administrator or Facility Administrator manages accounts."]);
    const list = guideForPath("/work-orders")!;
    expect(stepsFor(list, "technician")[0]).toContain("+ New Work Order");
    expect(stepsFor(list, "finance")[0]).toContain("Apply filters");
    expect(stepsFor(guideForPath("/work-orders/new")!, "supervisor").join(" ")).toContain("Technician 1");
  });

  it("says what to do next at every Work Order stage", () => {
    for (const status of ["draft", "submitted", "approved", "assigned", "in_progress", "completed", "reviewed", "closed", "cancelled"]) {
      expect(STAGE_GUIDES[status]).toBeDefined();
      expect(stageAdvice(status, "technician", false)?.advice.length).toBeGreaterThan(5);
    }
    expect(stageAdvice("submitted", "approver", false)?.advice).toContain("Approve");
    expect(stageAdvice("reviewed", "finance", false)?.advice).toContain("Open the invoice");
    expect(stageAdvice("reviewed", "technician", true)?.advice).toContain("In-house");
    expect(stageAdvice("draft", "technician", true)?.advice).toContain("no quotation");
    expect(stageAdvice("unknown", "technician", false)).toBeNull();
  });

  it("matches everyday questions to prepared answers", () => {
    expect(searchHelp("there is no approve button", "approver")[0]?.id).toBe("no-approve-button");
    expect(searchHelp("how many quotations")[0]?.id).toBe("quotations-how-many");
    expect(searchHelp("I keep getting signed out")[0]?.id).toBe("two-accounts");
    expect(searchHelp("email in spam")[0]?.id).toBe("email-missing");
    expect(searchHelp("")).toEqual([]);
    expect(searchHelp("zzzz qqqq")).toEqual([]);
  });

  it("keeps the content complete and ids unique", () => {
    const ids = FAQS.map((faq) => faq.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const guide of PAGE_GUIDES) {
      for (const id of guide.related ?? []) expect(ids).toContain(id);
      expect(relatedFaqs(guide, "technician").length).toBeGreaterThanOrEqual(0);
    }
  });

  it("is mounted for signed-in people and fed by the Work Order page; only the AI button calls out", () => {
    const layout = readFileSync("app/layout.tsx", "utf8");
    expect(layout).toContain("identity && <HelpPanel role={identity.role} aiEnabled={assistantAiEnabled()} name={assistant.name} pictureUrl={assistant.pictureUrl} />");
    expect(readFileSync("app/work-orders/[id]/page.tsx", "utf8")).toContain("<HelpContext id={id} reference=");
    const panel = readFileSync("components/help/help-panel.tsx", "utf8");
    expect(panel.match(/fetch\(/g)?.length).toBe(1);
    expect(panel).toContain('fetch("/api/assistant"');
    expect(panel).toContain("if (!aiEnabled");
  });
});
