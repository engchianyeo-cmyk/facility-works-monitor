import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { draftNextSteps } from "@/lib/work-orders/next-steps";
import manifest from "@/app/manifest";

const read = (path: string) => readFileSync(path, "utf8");

describe("D-10 quick creation on phone and computer", () => {
  test("turns the Draft readiness list into linked next steps", () => {
    const steps = draftNextSteps([
      "Location marked on the layout plan",
      "Before photo, video or voice note of the site",
      "Quotations: 0 of 1 submitted",
      "Recommended contractor quotation",
      "Reason the work is needed",
      "Something new",
    ], "wo-1");
    expect(steps.map((step) => step.href)).toEqual([
      "#drawings-documents-heading",
      "#work-order-evidence",
      "#proposal-heading",
      "#proposal-heading",
      "/work-orders/wo-1/edit",
      null,
    ]);
    expect(steps.at(-1)?.label).toBe("Something new");
  });

  test("an empty readiness list means nothing is left to do", () => {
    expect(draftNextSteps([], "wo-1")).toEqual([]);
  });

  test("My Drafts lists only the user's own Drafts and is linked for every creator", () => {
    const list = read("app/work-orders/page.tsx");
    expect(list).toContain('values.view === "drafts"');
    expect(list).toContain('query.eq("status", "draft").or(`assigned_technician_id.eq.${identity.userId},requested_by.eq.${identity.userId}`)');
    expect(read("components/site-header.tsx")).toContain('href="/work-orders?view=drafts"');
  });

  test("Create Draft lands on the next steps; optional fields fold away; required fields stay visible", () => {
    const form = read("components/work-orders/work-order-form.tsx");
    expect(form).toContain("`/work-orders/${id}?created=1#next-steps`");
    const details = form.indexOf("<details");
    for (const required of ['name="title"', 'name="description"', 'name="location"', 'name="emergency_work"', 'name="in_house_work"']) {
      expect(form.indexOf(required)).toBeGreaterThan(-1);
      expect(form.indexOf(required)).toBeLessThan(details);
    }
    expect(read("app/work-orders/[id]/page.tsx")).toContain('status === "draft" && isPreparer(context)');
  });

  test("FMWorks can be added to a phone home screen", () => {
    const value = manifest();
    expect(value.display).toBe("standalone");
    expect(value.start_url).toBe("/");
    expect(value.icons?.map((icon) => icon.sizes)).toEqual(expect.arrayContaining(["192x192", "512x512"]));
    expect(value.shortcuts?.map((item) => item.url)).toEqual(["/work-orders/new", "/work-orders?view=drafts"]);
  });
});
