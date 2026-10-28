import { readFileSync } from "node:fs";
import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ identity: vi.fn(), rpc: vi.fn(), upload: vi.fn(), remove: vi.fn(), signed: vi.fn(), row: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.identity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: async () => ({ rpc: mocks.rpc, from: () => ({ select: () => ({ eq: () => ({ maybeSingle: mocks.row }) }) }) }) }));
vi.mock("@/lib/supabase/admin", () => ({ createAdminClient: () => ({ storage: { from: () => ({ upload: mocks.upload, remove: mocks.remove, createSignedUrl: mocks.signed }) } }) }));
import { POST as saveFacility } from "@/app/api/administration/facilities/route";
import { POST as addArea } from "@/app/api/administration/facilities/[id]/areas/route";
import { POST as setStaff } from "@/app/api/administration/facilities/[id]/staff/route";
import { POST as uploadDrawing } from "@/app/api/administration/facilities/[id]/drawings/route";
import { DELETE as removeDrawing } from "@/app/api/administration/facility-drawings/[id]/route";
import { GET as drawingFile } from "@/app/api/facility-drawings/[id]/file/route";
import { facilityDrawingSrc, markupDrawingsFor, type FacilityDrawingRow } from "@/lib/facility-drawings";
import { safeFilename } from "@/lib/administration/facility-admin";
import { validDrawingReference } from "@/lib/facility-location";

const facility = "10000000-0000-4000-8000-0000000000f1";
const person = "10000000-0000-4000-8000-000000000003";
const drawingId = "10000000-0000-4000-8000-0000000000d1";
const admin = { role: "administrator", userId: "admin" };
const json = (url: string, body: unknown, method = "POST") => new NextRequest(`http://localhost${url}`, { method, body: JSON.stringify(body), headers: { "content-type": "application/json" } });
const params = (id: string) => ({ params: Promise.resolve({ id }) });
const read = (path: string) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const row = (over: Partial<FacilityDrawingRow> = {}): FacilityDrawingRow => ({ id: drawingId, facility_id: facility, code: "TPY-L1-001", title: "Level 1", revision: "Rev A",
  original_filename: "l1.png", content_type: "image/png", byte_size: 1000, width: 1600, height: 900, uploaded_at: "2026-10-27T00:00:00Z", ...over });

beforeEach(() => { vi.clearAllMocks(); mocks.identity.mockResolvedValue(admin); mocks.rpc.mockResolvedValue({ data: { ok: true }, error: null }); });

describe("D-17 facility setup", () => {
  it("lets only the Administrator add a facility, seeding the standard areas by default", async () => {
    mocks.identity.mockResolvedValueOnce({ role: "facility_manager", userId: "fm" });
    expect((await saveFacility(json("/x", { facility_id: null, code: "TPY-01", name: "Toa Payoh", reason: "New" }))).status).toBe(403);
    const response = await saveFacility(json("/x", { facility_id: null, code: "TPY-01", name: "Toa Payoh", address: "1 Lorong 1", reason: "New site" }));
    expect(response.status).toBe(201);
    expect(mocks.rpc).toHaveBeenCalledWith("admin_save_facility", expect.objectContaining({ p_facility_id: null, p_code: "TPY-01", p_active: true, p_seed_standard_areas: true }));
  });

  it("requires a reason and an explicit in-use flag when changing a facility", async () => {
    expect((await saveFacility(json("/x", { facility_id: facility, code: "TPY-01", name: "Toa Payoh", reason: "x" }))).status).toBe(400);
    expect((await saveFacility(json("/x", { facility_id: facility, code: "TPY-01", name: "Toa Payoh", active: false, reason: "Closed" }))).status).toBe(200);
    expect(mocks.rpc).toHaveBeenCalledWith("admin_save_facility", expect.objectContaining({ p_active: false, p_seed_standard_areas: false }));
  });

  it("adds areas and staff through the audited database functions", async () => {
    expect((await addArea(json("/x", { area_code: "ELR-02", name: "Riser L2", level: "L2" }), params(facility))).status).toBe(201);
    expect(mocks.rpc).toHaveBeenCalledWith("admin_add_facility_area", { p_facility_id: facility, p_area_code: "ELR-02", p_name: "Riser L2", p_level: "L2" });
    expect((await setStaff(json("/x", { profile_id: person, active: true }), params(facility))).status).toBe(400);
    expect((await setStaff(json("/x", { profile_id: person, active: true, reason: "Assigned" }), params(facility))).status).toBe(200);
    expect(mocks.rpc).toHaveBeenCalledWith("admin_set_facility_membership", { p_facility_id: facility, p_profile_id: person, p_active: true, p_reason: "Assigned" });
  });

  it("uploads a drawing privately, registers it, and removes the file if registration is refused", async () => {
    mocks.upload.mockResolvedValue({ error: null });
    const form = () => { const f = new FormData(); f.set("file", new File([new Uint8Array(10)], "Level 1 plan.png", { type: "image/png" })); f.set("code", "tpy-l1-001"); f.set("title", "Level 1"); f.set("width", "1600"); f.set("height", "900"); return f; };
    const request = () => new NextRequest("http://localhost/x", { method: "POST", body: form() });
    expect((await uploadDrawing(request(), params(facility))).status).toBe(201);
    const path = mocks.upload.mock.calls[0][0] as string;
    expect(path).toMatch(new RegExp(`^drawings/facility/${facility}/[0-9a-f-]{36}-Level-1-plan\\.png$`));
    expect(mocks.rpc).toHaveBeenCalledWith("admin_register_facility_drawing", expect.objectContaining({ p_code: "TPY-L1-001", p_width: 1600, p_height: 900, p_storage_path: path }));
    expect(mocks.remove).not.toHaveBeenCalled();
    mocks.rpc.mockResolvedValueOnce({ data: { ok: false, code: "VALIDATION_ERROR", message: "Duplicate" }, error: null });
    expect((await uploadDrawing(request(), params(facility))).status).toBe(400);
    expect(mocks.remove).toHaveBeenCalledTimes(1);
  });

  it("refuses unsupported drawing files", async () => {
    const f = new FormData(); f.set("file", new File(["x"], "plan.dwg", { type: "application/acad" })); f.set("code", "A-1"); f.set("title", "Plan");
    expect((await uploadDrawing(new NextRequest("http://localhost/x", { method: "POST", body: f }), params(facility))).status).toBe(400);
    expect(mocks.upload).not.toHaveBeenCalled();
  });

  it("withdraws a drawing with a reason", async () => {
    expect((await removeDrawing(json("/x", {}, "DELETE"), params(drawingId))).status).toBe(400);
    expect((await removeDrawing(json("/x", { reason: "Superseded" }, "DELETE"), params(drawingId))).status).toBe(200);
  });

  it("serves drawings to signed-in staff through a short-lived link, with download names", async () => {
    mocks.identity.mockResolvedValueOnce(null);
    expect((await drawingFile(new NextRequest("http://localhost/x"), params(drawingId))).status).toBe(401);
    mocks.identity.mockResolvedValue({ role: "technician", userId: "t" });
    mocks.row.mockResolvedValue({ data: { storage_path: "drawings/facility/f/x.pdf", original_filename: "x.pdf" }, error: null });
    mocks.signed.mockResolvedValue({ data: { signedUrl: "https://storage.example/x" }, error: null });
    const response = await drawingFile(new NextRequest("http://localhost/x?download=1"), params(drawingId));
    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("https://storage.example/x");
    expect(mocks.signed).toHaveBeenCalledWith("drawings/facility/f/x.pdf", 300, { download: "x.pdf" });
  });

  it("uses a facility's own image drawings for markup and pins, falling back to the mock-ups", () => {
    expect(markupDrawingsFor([]).map((d) => d.code)).toContain("FW-001");
    const own = markupDrawingsFor([row(), row({ id: "pdf", code: "TPY-PDF", content_type: "application/pdf", width: null, height: null })]);
    expect(own.map((d) => d.code)).toEqual(["TPY-L1-001"]);
    expect(own[0].src).toBe(facilityDrawingSrc(drawingId));
    expect(validDrawingReference("TPY-L1-001", own)).toBe(true);
    expect(validDrawingReference("FW-001", own)).toBe(false);
    expect(safeFilename("../../etc/passwd")).toBe("etc-passwd");
  });

  it("puts facility setup on the Facilities page and drawings where staff work", () => {
    const page = read("app/administration/facilities/page.tsx");
    for (const text of ["Add a new facility", "Areas (", "Drawings (", "Staff ("]) expect(page).toContain(text);
    expect(read("app/work-orders/[id]/page.tsx")).toContain("drawings={markupDrawingsFor(facilityDrawings)}");
    expect(read("components/site-header.tsx")).toContain('href="/drawings"');
  });
});

describe("D-19 variation order at the final cost", () => {
  it("asks whether there was a variation order and carries the approved quotation forward when the price is unchanged", () => {
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    expect(workspace).toContain("Was there a variation order from the contractor?");
    expect(workspace).toContain("No — price unchanged");
    expect(workspace).toContain("Yes — variation order");
    expect(workspace).toContain("Variation justification (why the price changed)");
    expect(workspace).toContain("Same as approved quotation");
    expect(read("app/api/work-orders/[id]/release-1/route.ts")).toContain("variation_order,final_quotation_id,variation_justification");
    const migration = read("supabase/migrations/20261027140000_final_quotation_variation.sql");
    for (const code of ["VARIATION_CONFIRMATION_REQUIRED", "VARIATION_JUSTIFICATION_REQUIRED", "PRICE_UNCHANGED_MISMATCH"]) expect(migration).toContain(code);
  });

  it("shows the recommended or approved quotation in the Cost Summary, not the latest entered", () => {
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    expect(workspace).toContain('const summaryQuote=data?.quotations.find((item)=>item.status==="approved")??recommendedQuote??quote;');
    expect(workspace).toContain('["Quotation",summaryQuote?.quotation_ref');
  });

  it("shows the company stage name in the Status card", async () => {
    const { deriveWorkOrderOperationalStage } = await import("@/lib/work-orders/operational-stage");
    expect(deriveWorkOrderOperationalStage({ status: "submitted" }).label).toBe("Awaiting Approval");
  });
});

describe("D-20 second Technician endorses the final cost", () => {
  it("shows what is being endorsed and waits for the final cost and revised quotation", () => {
    const panel = read("components/work-orders/technician-endorsement.tsx");
    expect(panel).toContain("You are endorsing this final cost");
    expect(panel).toContain("no longer counts. Check the changes and endorse again.");
    expect(panel).toContain("{required && canEndorse && !blocked && <form");
    expect(read("app/work-orders/[id]/page.tsx")).toContain('supabase.rpc("work_order_endorsement_status"');
    const migration = read("supabase/migrations/20261027140000_final_quotation_variation.sql");
    expect(migration).toContain("final_cost_fingerprint is not distinct from public.work_order_final_cost_fingerprint(w.id)");
    expect(migration).toContain("grant execute on function public.work_order_endorsement_status(uuid) to authenticated;");
  });
});

describe("Signed-in name in the header", () => {
  it("reloads the whole page after sign-in so the header shows the new account", () => {
    const form = read("components/auth-form.tsx");
    expect(form).toContain("window.location.assign(");
    expect(form).not.toContain("router.replace(");
  });
});

describe("Work Order page tidy-up (27 Oct UAT review)", () => {
  const page = () => read("app/work-orders/[id]/page.tsx");
  it("names the assigned and endorsing Technicians in Assignment details", () => {
    expect(page()).toContain('["Assigned Technician", assignedTechnicianName ?? resolvedAssignee]');
    expect(page()).toContain('["Endorsing Technician", endorsingTechnician]');
  });
  it("shows the condition/predictive section only for those sources", () => {
    expect(page()).toContain('const predictive = ["condition_based", "predictive"].includes(order.source);');
  });
  it("uses the lifecycle v2 steps in the Workflow timeline", () => {
    expect(page()).toContain("Second Technician endorsed (work and final cost)");
    expect(page()).not.toContain('["accepted_at", "Accepted"]');
  });
  it("folds the audit history behind a button, with each entry's details folded too", () => {
    expect(page()).toContain("Show audit history");
    expect(page()).toContain('<summary className="cursor-pointer text-xs font-semibold text-blue-700">Details</summary>');
  });
  it("labels the Cost Summary plainly and shows the recommended quotation in the Proposal section", () => {
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    for (const label of ["Highest quotation received", "Recommended quotation", "Pending (after the work)", "Recommended, awaiting approval", "Awaiting Approver", "Pending approval"]) expect(workspace).toContain(label);
    expect(workspace).toContain('const displayQuote=quote&&["draft","returned"].includes(quote.status)?quote:summaryQuote;');
  });
});

describe("Administrator approval of a Work Order they raised", () => {
  it("shows Approve Work and Quotation with a required audited reason instead of hiding it", () => {
    const page = read("app/work-orders/[id]/page.tsx");
    expect(page).toContain('approvalSummary?.approval_blocker === "OVERRIDE_REASON_REQUIRED"');
    expect(page).toContain("approvalReasonRequired={approvalReasonRequired}");
    expect(read("components/work-orders/work-order-actions.tsx")).toContain("required={props.approvalReasonRequired}");
  });
});

describe("D-21 correcting an actual cost before the review", () => {
  it("lets the assigned Technician edit costs while Submitted for Review and resets the final cost", () => {
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    expect(workspace).toContain('((data.order?.status??status)==="completed"&&correctingCosts)');
    expect(workspace).toContain("Correct the actual costs (before the review)");
    const migration = read("supabase/migrations/20261028100000_actual_cost_correction_before_review.sql");
    expect(migration).toContain("if w.status not in ('assigned','in_progress','completed')");
    expect(migration).toContain("update public.work_order_final_cost_submissions set status='draft'");
  });
});

describe("Several actual-cost lines from a quotation", () => {
  it("offers a multi-line table for materials, equipment and services with running totals", () => {
    const editor = read("components/work-orders/actual-cost-editor.tsx");
    for (const text of ["Add several lines from the contractor&apos;s quotation", "Material / consumables", "+ Add another line", "New total actual cost", "Total actual cost:"]) expect(editor).toContain(text);
    expect(read("components/work-orders/release-one-workspace.tsx")).toContain("onSaveMany={saveCostLines}");
  });
});
