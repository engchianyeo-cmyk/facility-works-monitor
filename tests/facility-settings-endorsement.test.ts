import { readFileSync } from "node:fs";
import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ identity: vi.fn(), rpc: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.identity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: async () => ({ rpc: mocks.rpc }) }));
import { POST as saveSettings } from "@/app/api/administration/facility-settings/route";
import { POST as endorse } from "@/app/api/work-orders/[id]/endorsement/route";
import { POST as saveTimes } from "@/app/api/work-orders/[id]/actual-times/route";
import { DEFAULT_ENDORSEMENT_STAGE, ENDORSEMENT_STAGES, endorsementStageLabel } from "@/lib/facility-settings";
import { draftNextSteps } from "@/lib/work-orders/next-steps";

const facility = "10000000-0000-4000-8000-0000000000f1";
const approver = "10000000-0000-4000-8000-000000000003";
const settings = { facility_id: facility, designated_approver_id: approver, endorsement_stage: "before_review", reason: "Designate the Approver" };
const request = (path: string, body: unknown) => new NextRequest(`http://localhost${path}`, { method: "POST", body: JSON.stringify(body) });
const context = { params: Promise.resolve({ id: "wo-1" }) };
const read = (path: string) => readFileSync(path, "utf8");

beforeEach(() => {
  vi.clearAllMocks();
  mocks.identity.mockResolvedValue({ role: "administrator", userId: "admin" });
  mocks.rpc.mockResolvedValue({ data: { ok: true }, error: null });
});

describe("D-11 facility settings", () => {
  it("recommends endorsement before the Approver's review and offers all three options", () => {
    expect(DEFAULT_ENDORSEMENT_STAGE).toBe("before_review");
    expect(ENDORSEMENT_STAGES.map((stage) => stage.value)).toEqual(["before_review", "before_submission", "both"]);
    expect(endorsementStageLabel(null)).toContain("recommended");
  });

  it.each(["technician", "approver", "supervisor", "facility_manager", "finance"])("denies %s", async (role) => {
    mocks.identity.mockResolvedValue({ role });
    expect((await saveSettings(request("/api/administration/facility-settings", settings))).status).toBe(403);
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it("passes the Administrator's change to set_facility_settings", async () => {
    expect((await saveSettings(request("/api/administration/facility-settings", settings))).status).toBe(200);
    expect(mocks.rpc).toHaveBeenCalledWith("set_facility_settings", { p_facility_id: facility, p_designated_approver_id: approver, p_endorsement_stage: "before_review", p_reason: "Designate the Approver" });
  });

  it.each([{ ...settings, endorsement_stage: "sometimes" }, { ...settings, reason: " " }, { ...settings, facility_id: "x" }, { ...settings, designated_approver_id: "x" }])("rejects malformed settings", async (body) => {
    expect((await saveSettings(request("/api/administration/facility-settings", body))).status).toBe(400);
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it("is linked from the Administrator navigation with Facility Locations", () => {
    const header = read("components/site-header.tsx");
    expect(header).toContain('href="/administration/facilities"');
    expect(header).toContain('href="/administration/facility-locations"');
  });
});

describe("D-11 second Technician endorsement and actual work times", () => {
  it("endorses with a statement of what was checked", async () => {
    mocks.identity.mockResolvedValue({ role: "technician" });
    expect((await endorse(request("/api/work-orders/wo-1/endorsement", { statement: "short" }), context)).status).toBe(400);
    expect((await endorse(request("/api/work-orders/wo-1/endorsement", { statement: "Checked the site and photos." }), context)).status).toBe(200);
    expect(mocks.rpc).toHaveBeenCalledWith("endorse_work_order", { p_work_order_id: "wo-1", p_statement: "Checked the site and photos." });
  });

  it("returns a refused endorsement as an error", async () => {
    mocks.identity.mockResolvedValue({ role: "technician" });
    mocks.rpc.mockResolvedValue({ data: { ok: false, code: "ACCESS_DENIED", message: "A second Technician must endorse it." }, error: null });
    expect((await endorse(request("/api/work-orders/wo-1/endorsement", { statement: "Checked the site and photos." }), context)).status).toBe(403);
  });

  it("records start now and end later", async () => {
    mocks.identity.mockResolvedValue({ role: "technician" });
    expect((await saveTimes(request("/api/work-orders/wo-1/actual-times", { started_at: "2026-10-22T01:00:00.000Z", ended_at: null }), context)).status).toBe(200);
    expect(mocks.rpc).toHaveBeenCalledWith("set_work_order_actual_times", { p_work_order_id: "wo-1", p_started_at: "2026-10-22T01:00:00.000Z", p_ended_at: null });
    expect((await saveTimes(request("/api/work-orders/wo-1/actual-times", { started_at: "not a date" }), context)).status).toBe(400);
  });

  it("maps the review requirements to where they are done", () => {
    expect(draftNextSteps(["Second Technician endorsement", "Actual start and end times of the work"], "wo-1").map((step) => step.href))
      .toEqual(["#technician-endorsement", "#actual-work-times"]);
  });

  it("does not offer Finance as a copied party; Finance is copied at Completed", () => {
    expect(read("components/work-orders/copied-parties.tsx")).toContain('person.role !== "finance"');
    expect(read("components/work-orders/work-order-form.tsx")).toContain('["technician", "finance"].includes(person.role)');
  });

  it("names the assigned Technician and who may change the Work Order (D-12)", () => {
    const header = read("components/work-orders/work-order-decision-header.tsx");
    expect(header).toContain("Assigned Technician:");
    expect(header).toContain("Only the assigned Technician (or the superior who created it, while a Draft) can change");
    expect(header).toContain("You are signed in as");
    expect(read("app/work-orders/[id]/page.tsx")).toContain("viewerResponsible: isPreparer(context) || order.assigned_technician_id === identity.userId");
  });

  it("treats the attached quotation as the official record; the summary of charges is optional (D-13)", () => {
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    expect(workspace).toContain("Summary of charges (optional — the attached quotation is the official record)");
    expect(workspace).not.toContain("Itemized charges (from authentic quotation)");
  });

  it("offers Other supporting document as an evidence category (D-14)", async () => {
    const evidence = await import("@/lib/evidence");
    expect(evidence.EVIDENCE_CATEGORIES).toEqual(["before", "after", "document"]);
    expect(evidence.EVIDENCE_CATEGORY_LABELS.document).toBe("Other supporting document");
    expect(evidence.validCategory("document")).toBe(true);
    expect(evidence.validCategory("other")).toBe(false);
  });

  it("points a passed due date to Edit Work Order (D-15)", () => {
    expect(draftNextSteps(["Due date has passed — update the due date"], "wo-1")[0].href).toBe("/work-orders/wo-1/edit");
  });

  it("keeps the audit history in a scrollable box to shorten the Work Order page (D-16)", () => {
    expect(read("app/work-orders/[id]/page.tsx")).toContain('max-h-[28rem] divide-y divide-slate-100 overflow-y-auto');
  });
});
