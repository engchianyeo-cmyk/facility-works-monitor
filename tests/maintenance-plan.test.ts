import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { planFrequency, PLAN_FREQUENCIES } from "@/lib/maintenance/plan";

const read = (p: string) => readFileSync(p, "utf8");

describe("M34 maintenance plan", () => {
  it("puts tasks under daily, weekly, monthly, quarterly, six-monthly and annual", () => {
    expect(planFrequency(1, "day")).toBe("daily");
    expect(planFrequency(7, "day")).toBe("weekly");
    expect(planFrequency(1, "week")).toBe("weekly");
    expect(planFrequency(1, "month")).toBe("monthly");
    expect(planFrequency(3, "month")).toBe("quarterly");
    expect(planFrequency(6, "month")).toBe("sixmonthly");
    expect(planFrequency(12, "month")).toBe("annual");
    expect(planFrequency(1, "year")).toBe("annual");
    expect(planFrequency(2, "week")).toBe("other");
    expect(PLAN_FREQUENCIES.map(f => f.label)).toEqual(["Daily", "Weekly", "Monthly", "Quarterly", "Six-monthly", "Annual", "Other"]);
  });

  it("is open to every signed-in role, outside the planner-only /maintenance area, and linked from the header", () => {
    const page = read("app/maintenance-plan/page.tsx");
    expect(page).toContain('redirect("/login?next=/maintenance-plan")');
    expect(page).not.toContain('"technician") redirect');
    expect(page).toContain('rpc("pm_planner_for"');
    expect(page).toContain('rpc("facility_technicians"');
    expect(read("components/site-header.tsx")).toContain('href="/maintenance-plan"');
  });

  it("leaves the decisions to the database", () => {
    expect(read("app/api/maintenance/plan/assign/route.ts")).toContain('rpc("assign_pm_technician"');
    const upload = read("app/api/assets/[id]/documents/route.ts");
    expect(upload).toContain('rpc("asset_document_editor"');
    expect(upload).toContain('rpc("register_asset_document"');
    expect(upload).toContain("asset-documents/${id}/");
    expect(upload).toContain(".remove([path])");
    const file = read("app/api/asset-documents/[id]/file/route.ts");
    expect(file).toMatch(/from\("asset_documents"\)[\s\S]*createSignedUrl\(data\.storage_path, 300/);
    expect(read("app/api/asset-documents/[id]/retire/route.ts")).toContain('rpc("retire_asset_document"');
  });

  it("shows the O&M manual on the Work Order", () => {
    expect(read("app/work-orders/[id]/page.tsx")).toContain('from("asset_documents")');
  });
});
