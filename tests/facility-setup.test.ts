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
    expect(mocks.rpc).toHaveBeenCalledWith("admin_register_facility_drawing_revision", expect.objectContaining({ p_code: "TPY-L1-001", p_width: 1600, p_height: 900, p_storage_path: path, p_pin_image_path: null }));
    expect(mocks.remove).not.toHaveBeenCalled();
    mocks.rpc.mockResolvedValueOnce({ data: { ok: false, code: "VALIDATION_ERROR", message: "Duplicate" }, error: null });
    expect((await uploadDrawing(request(), params(facility))).status).toBe(400);
    expect(mocks.remove).toHaveBeenCalledTimes(1);
  });

  it("stores a PDF with the image of its first page for pins (D-44)", async () => {
    mocks.upload.mockResolvedValue({ error: null });
    const f = new FormData();
    f.set("file", new File([new Uint8Array(10)], "HLH-A-101.pdf", { type: "application/pdf" })); f.set("code", "HLH-A-101"); f.set("title", "1st Storey Plan"); f.set("revision", "Rev B");
    f.set("pin_file", new File([new Uint8Array(10)], "pin.png", { type: "image/png" })); f.set("pin_width", "3500"); f.set("pin_height", "2474");
    expect((await uploadDrawing(new NextRequest("http://localhost/x", { method: "POST", body: f }), params(facility))).status).toBe(201);
    const [pdfPath, pinPath] = mocks.upload.mock.calls.map((call) => call[0] as string);
    expect(pinPath).toMatch(new RegExp(`^drawings/facility/${facility}/[0-9a-f-]{36}-pin\\.png$`));
    expect(mocks.rpc).toHaveBeenCalledWith("admin_register_facility_drawing_revision", expect.objectContaining({ p_storage_path: pdfPath, p_pin_image_path: pinPath, p_pin_width: 3500, p_pin_height: 2474, p_width: null }));
    const page = readFileSync("app/drawings/page.tsx", "utf8");
    expect(page).toContain("Earlier revisions (");
    expect(readFileSync("lib/facility-drawings.ts", "utf8")).toContain("src: facilityDrawingSrc(row.id, false, pdf)");
    expect(readFileSync("components/administration/facility-setup.tsx", "utf8")).toContain("await pdfFirstPageToPng(file)");
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
    for (const text of ["Add several lines from the contractor&apos;s quotation", "Material / consumables", "+ Add another line", "New total", "Total actual cost"]) expect(editor).toContain(text);
    expect(read("components/work-orders/release-one-workspace.tsx")).toContain("onSaveMany={saveCostLines}");
  });
});

describe("D-22 contractor actual cost is the final contractor charge", () => {
  it("takes the actual cost from the contractor charge and makes itemised lines optional", () => {
    const migration = read("supabase/migrations/20261028120000_actual_cost_from_contractor_charge.sql");
    expect(migration).toContain("if not w.in_house_work then derived_actual:=contractor;");
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    expect(workspace).toContain("(final contractor charge)");
    expect(workspace).not.toContain("Actual repair cost (derived from ledger)");
    expect(read("components/work-orders/actual-cost-editor.tsx")).toContain("Itemised cost record (optional)");
  });
});

describe("D-23 delete a cost line; work times editable until the review", () => {
  it("adds an audited delete and drops the stale time limit", () => {
    expect(read("supabase/migrations/20261028120000_actual_cost_from_contractor_charge.sql")).toContain("work_order_actual_cost_deleted");
    expect(read("app/api/work-orders/[id]/release-1/route.ts")).toContain("delete_actual_cost");
    expect(read("components/work-orders/actual-work-times.tsx")).not.toContain("max={max}");
  });
});

describe("D-24 work submitted with the official quotation", () => {
  it("refuses submission until the final cost and any revised quotation are in", () => {
    const migration = read("supabase/migrations/20261028120000_actual_cost_from_contractor_charge.sql");
    expect(migration).toContain("create or replace function public.submit_physical_completion");
    expect(migration).toContain("Attach the contractor''s revised quotation for the variation order before submitting the work.");
    const page = read("app/work-orders/[id]/page.tsx");
    expect(page).toContain("Final Cost Reconciliation has not been saved");
    expect(page).toContain("The contractor's revised quotation for the variation order has not been attached.");
  });
});

describe("Invoice received date uses the Singapore calendar", () => {
  it("does not refuse today's date just after midnight", () => {
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    expect(workspace).toContain('max={new Intl.DateTimeFormat("sv-SE",{timeZone:"Asia/Singapore"}).format(new Date())}');
    expect(workspace).not.toContain("max={new Date().toISOString().slice(0,10)}");
  });
});

describe("Guided work stage (UAT 29 Oct 2026)", () => {
  it("lists the Technician's steps in page order and arranges the sections to match", () => {
    const page = read("app/work-orders/[id]/page.tsx");
    expect(page).toContain("<WorkCompletionSteps steps={completionSteps} />");
    const order = ["<WorkCompletionSteps", "{evidenceEl}", "<ActualWorkTimes workOrderId={id}", "{workspaceEl}", "{actionsEl}"].map((text) => page.indexOf(text, page.indexOf("{workStage ? <>")));
    expect(order.every((position, index) => position > 0 && (index === 0 || position > order[index - 1]))).toBe(true);
    expect(page.slice(page.indexOf("const workspaceEl = <>"), page.indexOf("const actionsEl = ("))).toContain("<ReleaseOneWorkspace id={id}");
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    expect(workspace.indexOf("{costEditor}\n      <section className={`mt-6 px-4 py-5")).toBeGreaterThan(0);
    expect(workspace).toContain("below, record the work done, then click Submit Physical Completion.");
    expect(read("components/work-orders/work-completion-steps.tsx")).toContain("Steps to submit this Work Order for review");
  });
});

describe("D-25 independent checker", () => {
  it("lists the minimum checks per stage, including the basis of the award when quotations compete", async () => {
    const { checkerChecks } = await import("@/components/work-orders/technician-endorsement");
    expect(checkerChecks("review", false, true).map((check) => check.key)).toEqual(["supervised_work", "final_quotation", "field_evidence", "award_basis"]);
    expect(checkerChecks("review", true, false).map((check) => check.key)).toEqual(["supervised_work", "field_evidence"]);
    expect(checkerChecks("submission", false, false).map((check) => check.key)).toEqual(["site_evidence", "quotation_scope"]);
  });
  it("flashes a banner for the checker, passes the checklist and copies the checker", () => {
    expect(read("app/work-orders/[id]/page.tsx")).toContain("You are the independent checker for this Work Order");
    expect(read("app/api/work-orders/[id]/endorsement/route.ts")).toContain("p_checklist: checklist");
    const migration = read("supabase/migrations/20261030100000_independent_checker.sql");
    expect(migration).toContain("insert into public.work_order_copied_parties(work_order_id, profile_id, added_by) values (w.id, actor_id, actor_id)");
    expect(migration).toContain("AWARD_BASIS_REQUIRED");
  });
});

describe("Closure status in plain words", () => {
  it("no longer labels a Work Order 'unresolved' before it is due", () => {
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    expect(workspace).not.toContain('??"unresolved"');
    for (const label of ["after the work is Completed", "awaiting invoice and payment", "ready to close: paid"]) expect(workspace).toContain(label);
  });
});

describe("Red highlight where the Technician must act", () => {
  it("marks the cost record and Final Cost sections and lists what blocks submission", () => {
    expect(read("components/work-orders/actual-cost-editor.tsx")).toContain("Action needed: check the lines, then click");
    const workspace = read("components/work-orders/release-one-workspace.tsx");
    expect(workspace).toContain("const finalCostActionNeeded=");
    expect(workspace).toContain("choose the revised quotation file, then click Attach Revised Quotation");
    expect(read("components/work-orders/work-order-actions.tsx")).toContain("Action needed before Submit Physical Completion appears here");
  });
});

describe("Work Order page review order", () => {
  const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
  const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
  it("shows the Workflow timeline right after the header", () => {
    const header = page.indexOf("<WorkOrderDecisionHeader");
    const timeline = page.indexOf("Workflow timeline</h2>");
    expect(header).toBeGreaterThan(-1);
    expect(timeline).toBeGreaterThan(header);
    expect(timeline).toBeLessThan(page.indexOf("{workStage ? <>"));
  });
  it("puts the reviewer's decision last, after the evidence, audit history and drawings", () => {
    const decision = page.indexOf("{!workStage && actionsEl}");
    for (const text of ["{!workStage && evidenceEl}", "Show audit history", "<WorkOrderDrawings", "<TechnicianEndorsement"]) {
      expect(page.indexOf(text)).toBeGreaterThan(-1);
      expect(page.indexOf(text)).toBeLessThan(decision);
    }
    expect(page.indexOf("</main>", decision)).toBeGreaterThan(decision);
  });
  it("groups the cost sections together in review order", () => {
    const order = ['title="Proposal / Quotation"', "{costEditor}", 'id="final-cost-heading"', 'title="Purchase reference"', 'id="payment-heading"', 'id="closure-heading"'].map((text) => workspace.indexOf(text, workspace.indexOf("Cost sections in review order")));
    order.forEach((index) => expect(index).toBeGreaterThan(-1));
    expect([...order].sort((a, b) => a - b)).toEqual(order);
  });
});

describe("Independent checker notices (30 Oct 2026)", () => {
  const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
  it("tells a possible checker in advance while the work is under way, without asking for action", () => {
    expect(page).toContain("const upcomingCheck =");
    expect(page).toContain("You may be the independent checker for this Work Order");
    expect(page).toContain("No action yet.");
  });
  it("flashes the checker banner with a red border when the endorsement is due", () => {
    expect(page).toMatch(/endorsementRequired && canEndorse && <a href="#technician-endorsement" className="[^"]*border-red-600[^"]*motion-safe:animate-pulse/);
  });
});

describe("Next authorized action is red (UAT 30 Oct 2026)", () => {
  it("shows the one action waiting for this person as a red button", () => {
    const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
    const block = actions.slice(actions.indexOf("Next authorized action — yours to click"), actions.indexOf("{busy === primary.action"));
    expect(block).toContain("bg-red-600");
    expect(block).not.toContain("bg-blue-700");
  });
});

describe("Approver decisions are red (UAT 30 Oct 2026)", () => {
  it("shows every independent approval form and confirm button in red", () => {
    const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
    const form = workspace.slice(workspace.indexOf("function ApprovalForm("), workspace.indexOf("function ReturnForm("));
    expect(form).toContain("Action needed — your approval");
    expect(form).toContain("bg-red-600");
    expect(form).not.toContain("bg-emerald-700");
    const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
    expect(actions).toMatch(/bg-red-600[^"]*">\{busy === "approve"/);
  });
});

describe("Finance actions are red (UAT 30 Oct 2026)", () => {
  it("shows Confirm Invoice Received and Record Payment and Close as red action buttons", () => {
    const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
    expect(workspace).toContain('className="min-h-11 rounded bg-red-600 px-4 font-bold text-white disabled:opacity-50">Confirm Invoice Received</button>');
    expect(workspace).toContain('className="min-h-11 rounded bg-red-600 px-4 font-bold text-white sm:col-span-2">Record Payment and Close</button>');
  });
});

describe("Payment amounts say before GST (UAT 30 Oct 2026)", () => {
  it("labels the approved, invoice, recommended and paid amounts as before GST", () => {
    const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
    for (const text of ["Approved amount (before GST)", "Invoice amount before GST", "Recommended payment before GST", "Paid amount before GST", "before GST / ${data.payment.payment_reference}"]) expect(workspace).toContain(text);
  });
});

describe("All facilities overview (UAT 30 Oct 2026)", () => {
  const page = readFileSync("app/administration/facilities/overview/page.tsx", "utf8");
  it("is view-only and for the Administrator", () => {
    expect(page).toContain('identity.role !== "administrator"');
    expect(page).not.toMatch(/\.(insert|update|delete|upsert)\(/);
    expect(page).not.toMatch(/rpc\("admin_(save|set|add|register|remove)/);
  });
  it("lists every facility, its users and its requirements, plus company-wide settings", () => {
    for (const text of ["Summary (", "Users of this facility", "Designated Approver", "Second Technician endorsement", "Independent checker", "Layout drawings",
      "Archive closed Work Orders after", "Off-site copy frequency", "Company-wide (applies to every facility)", "Approval limits", "Quotations required", "Contractor payment terms", "Company-wide users"]) {
      expect(page).toContain(text);
    }
  });
  it("is linked from the header and from Facilities setup", () => {
    expect(readFileSync("components/site-header.tsx", "utf8")).toContain('href="/administration/facilities/overview"');
    expect(readFileSync("app/administration/facilities/page.tsx", "utf8")).toContain('href="/administration/facilities/overview"');
  });
});

describe("Technician 1's Draft sections in red (UAT 2 Nov 2026)", () => {
  const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
  it("outlines the evidence, location and quotation sections and the Edit button when the Draft needs them", () => {
    for (const text of ["Action needed — add a Before photo, video or voice note", "Action needed — mark the location on the layout plan", "quotationNeeded={needsQuotation}", "editNeeded={needsEdit}"]) expect(page).toContain(text);
    expect(readFileSync("components/work-orders/release-one-workspace.tsx", "utf8")).toContain("Action needed — prepare and submit the contractor quotation");
    expect(readFileSync("components/work-orders/work-order-actions.tsx", "utf8")).toContain('props.editNeeded ? "bg-red-600 text-white"');
  });
});

describe("Draft wording for people who are not the preparer (UAT 3 Nov 2026)", () => {
  it("tells the Approver the Draft is waiting for the assigned Technician", () => {
    const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
    for (const text of ["Not yet submitted", "Waiting for the assigned Technician to complete and submit it", "Once the assigned Technician submits it, the approval button appears here in red."]) expect(actions).toContain(text);
  });
});

describe("Times are shown in Singapore time (UAT 4 Nov 2026)", () => {
  it("formats every date and time on the Work Order screens in Asia/Singapore, not the server's UTC", () => {
    for (const file of ["app/work-orders/[id]/page.tsx", "components/work-orders/work-order-actions.tsx", "components/work-orders/release-one-workspace.tsx", "components/evidence/evidence-panel.tsx", "components/work-orders/actual-work-times.tsx", "components/work-orders/technician-endorsement.tsx"]) {
      expect(readFileSync(file, "utf8")).toContain('timeZone: "Asia/Singapore"');
    }
    const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
    expect(page.slice(page.indexOf("function formatDateTime"), page.indexOf("function formatDateTime") + 400)).toContain('timeZone: "Asia/Singapore"');
  });
});

describe("Evidence removal is confirmed in the card (UAT 4 Nov 2026)", () => {
  const panel = readFileSync("components/evidence/evidence-panel.tsx", "utf8");
  it("does not depend on browser pop-ups and shows the result next to the item", () => {
    expect(panel).not.toContain("window.confirm");
    expect(panel).not.toContain("window.prompt");
    for (const text of ["Remove this item? It is taken off the Work Order but kept in the audit history.", "Reason for removing it", "cardMessage?.id === item.id"]) expect(panel).toContain(text);
  });
});

describe("Completion checklist only for the assigned Technician (UAT 4 Nov 2026)", () => {
  it("hides 'Action needed before Submit Physical Completion' from other Technicians", () => {
    expect(readFileSync("components/work-orders/work-order-actions.tsx", "utf8")).toContain('props.assignedToViewer && props.completionMissing.length > 0');
    expect(readFileSync("app/work-orders/[id]/page.tsx", "utf8")).toContain("assignedToViewer={order.assigned_technician_id === identity.userId}");
  });
});

describe("In-house work listed for Finance (D-31, UAT 4 Nov 2026)", () => {
  it("shows completed in-house Work Orders with their actual cost on the Finance page", () => {
    const page = readFileSync("app/finance/page.tsx", "utf8");
    expect(page).toContain('supabase.rpc("work_order_in_house_cost_register")');
    expect(page).toContain("In-house work (for reference)");
    expect(readFileSync("supabase/migrations/20261104120000_in_house_cost_register_for_finance.sql", "utf8")).toContain("current_user_role() in ('finance','administrator')");
  });
});

describe("No second click after a confirmed action (UAT 5 Nov 2026)", () => {
  it("hides the action buttons and says it is saved until the page shows the new status", () => {
    const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
    expect(actions).toContain("setRefreshingFrom(props.status);");
    expect(actions).toContain("const blocked = busy !== null || refreshingFrom !== null;");
    expect(actions).toContain("Updating the page… There is no need to click again.");
    expect(actions).not.toContain("busy !== null}");
  });
});

describe("Labour hours on the Final Cost come from Physical Completion (UAT 5 Nov 2026)", () => {
  it("shows the field as read-only and links to where the hours are entered", () => {
    const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
    expect(workspace).toContain('"Not yet recorded"');
    expect(workspace).toContain("Not needed to save this section. Save the Final Cost first; you then enter the hours with the work statement at");
    expect(workspace).toContain('href="#execution-title"');
  });
});

describe("Raise a cancelled Work Order again as a new Draft (D-35, UAT 5 Nov 2026)", () => {
  it("offers its Technician 'Raise again as new Draft' and explains why it cannot be resumed", () => {
    const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
    expect(page).toContain('const canRaiseAgain = identity.role === "technician" && status === "cancelled"');
    expect(page).toContain("canDuplicate={isApprovalAuthority(identity.role) || canRaiseAgain}");
    const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
    expect(actions).toContain('props.raiseAgain ? "Raise again as new Draft" : "Duplicate as draft"');
    expect(actions).toContain("This Work Order is cancelled and cannot be resumed.");
    expect(readFileSync("supabase/migrations/20261105140000_technician_raises_cancelled_again.sql", "utf8")).toContain("raised_again_after_cancellation");
  });
});

describe("Work Order actions say whose turn it is (UAT 5 Nov 2026)", () => {
  it("names the person and step being waited for, and the in-house approved status", () => {
    const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
    expect(actions).toContain("Nothing for you to do here now. Waiting for ${props.waitingFor}.");
    expect(actions).toContain('"Approved — In-house Team to Proceed"');
    const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
    expect(page).toContain("waitingFor={nextResponsibility && !nextResponsibility.viewerIsResponsible");
  });
});

describe("Physical Completion button is red until the work record is saved (UAT 5 Nov 2026)", () => {
  it("points to where the statement and labour hours are entered and drops the contradictory message", () => {
    const actions = readFileSync("components/work-orders/work-order-actions.tsx", "utf8");
    expect(actions).toContain("const workRecordNeeded = props.canRecordWork && !(props.completionReadiness.workRecordReceived && props.completionReadiness.labourHoursRecorded);");
    expect(actions).toContain("Enter the work-performed statement and the cumulative labour hours in the form below, then click Save Work Record.");
    expect(actions).toContain('const workRecordFormOpen = interaction === "record_work" || (workRecordNeeded && interaction === null);');
    expect(actions).toContain("{workRecordFormOpen && (");
    expect(actions).toContain("decisionActions.length === 0 && !props.canRecordWork &&");
  });
});

describe("Final Cost shows the labour hours as soon as the work record is saved (UAT 6 Nov 2026)", () => {
  it("reloads the commercial workspace when the work record changes, not only the status", () => {
    const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
    expect(workspace).toContain("[load,status,workRecordVersion]");
    expect(readFileSync("app/work-orders/[id]/page.tsx", "utf8")).toContain('workRecordVersion={`${order.actual_labour_hours ?? ""}|${order.completion_notes ?? ""}`}');
  });
});

describe("Emergency work already done is recorded on one screen (D-36, UAT 6 Nov 2026)", () => {
  it("offers Technicians the screen and calls the all-or-nothing recording", () => {
    const form = readFileSync("components/work-orders/emergency-record-form.tsx", "utf8");
    expect(form).toContain('fetch("/api/work-orders/emergency-record"');
    expect(form).toContain('JSON.stringify({ action: "submit_physical_completion" })');
    expect(form).toContain("Add at least one photo of the condition after the repair.");
    expect(readFileSync("app/api/work-orders/emergency-record/route.ts", "utf8")).toContain('rpc("record_emergency_work_done"');
    expect(readFileSync("app/work-orders/emergency/page.tsx", "utf8")).toContain('if (identity.role !== "technician") redirect("/work-orders");');
    expect(readFileSync("components/site-header.tsx", "utf8")).toContain('href="/work-orders/emergency"');
    expect(readFileSync("components/work-orders/work-order-form.tsx", "utf8")).toContain("Emergency — work starts immediately (in-house staff or contractor)");
  });
});

describe("Contractor admission screens (D-37, UAT 6 Nov 2026)", () => {
  it("wires each step to its database function and shows trial contractors", () => {
    const route = readFileSync("app/api/contractor-admission/route.ts", "utf8");
    for (const rpc of ["designate_procurement_manager", "raise_contractor_request", "recommend_contractor", "prequalify_contractor", "record_contractor_owner_approval", "score_contractor_trial_job", "admit_contractor", "reject_contractor"]) {
      expect(route).toContain(`rpc("${rpc}"`);
    }
    const board = readFileSync("components/administration/contractor-admission-board.tsx", "utf8");
    expect(board).toContain("Action needed — recommend a contractor");
    expect(board).toContain("Action needed — your step");
    expect(readFileSync("components/work-orders/release-one-workspace.tsx", "utf8")).toContain('item.admission_status==="trial"?" (trial contractor)":""');
    const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
    expect(page).toContain("<ContractorNeeded workOrderId={id} requests={contractorRequests} />");
    expect(page).toContain("<TrialEvaluation workOrderId={id}");
    expect(readFileSync("components/work-orders/trial-evaluation.tsx", "utf8")).toContain("Action needed — score this trial job");
  });
});

describe("A Draft not ready to submit points to what is missing (UAT 7 Nov 2026)", () => {
  it("sends the submit step's link to the first missing item, not to the Submit button", () => {
    const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
    expect(page).toContain('const draftOutstanding = status === "draft" && approvalReadiness ? draftNextSteps(approvalReadiness.missing_requirements, id) : [];');
    expect(page).toContain("finish the Draft first — ${first.label}${more} — then submit it for approval");
    expect(page).toContain("pointToOutstanding(step.key, responsibilityFor(");
  });
});

describe("Only the person whose turn it is gets a link (UAT 7 Nov 2026)", () => {
  it("shows others that there is nothing for them to do instead of linking to someone else's section", () => {
    const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
    expect(page).toContain("Nothing for you to do on this step. When it is your turn, this box turns red with a link.");
    expect(page).toContain("{isNext && who?.viewerIsResponsible && <a href={who.href}");
    expect(page).not.toContain('"Go to the section"');
  });
});

describe("My notices, bell and the Administrator view (D-38, UAT 7 Nov 2026)", () => {
  it("lists the reader's notices with what is waiting for them and marks them read", () => {
    const page = readFileSync("app/notices/page.tsx", "utf8");
    expect(page).toContain('.eq("recipient_profile_id", identity.userId)');
    expect(page).toContain("waitingForReader(order, { id: identity.userId, role: identity.role })");
    expect(readFileSync("components/notices/notices-list.tsx", "utf8")).toContain("Open and act →");
    expect(readFileSync("app/api/notices/read/route.ts", "utf8")).toContain('rpc("mark_my_notices_read"');
    expect(readFileSync("components/site-header.tsx", "utf8")).toContain('href="/notices"');
    expect(readFileSync("app/administration/notices/page.tsx", "utf8")).toContain('if (identity.role !== "administrator")');
  });
});

describe("Finance summary and completed work register (D-39, UAT 7 Nov 2026)", () => {
  it("shows Finance what it needs on each Work Order and in one register with due dates", () => {
    const page = readFileSync("app/work-orders/[id]/page.tsx", "utf8");
    expect(page).toContain('supabase.rpc("finance_completed_work_register", { p_work_order_id: id })');
    expect(page).toContain("{financeSummaryEl}");
    const register = readFileSync("app/finance/register/page.tsx", "utf8");
    expect(register).toContain('supabase.rpc("finance_completed_work_register")');
    expect(register).toContain("Download as spreadsheet (CSV)");
    expect(readFileSync("app/finance/page.tsx", "utf8")).toContain('href="/finance/register"');
  });
});

describe("Work Orders list shows no 'null' and the real Technician (UAT 7 Nov 2026)", () => {
  it("leaves out a missing level and reads the assigned Technician's name", () => {
    const list = readFileSync("app/work-orders/page.tsx", "utf8");
    expect(list).toContain("[order.facility_area.level, `${order.facility_area.area_code} ${order.facility_area.name}`].filter(Boolean).join(\" · \")");
    expect(list).toContain("technician:profiles!work_orders_assigned_technician_id_fkey(display_name)");
  });
});

describe("Payment records Finance can trust (D-41, UAT 7 Nov 2026)", () => {
  it("sends the payment time with its time zone and stops autofill of references", () => {
    const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
    expect(workspace).toContain('paid_at:new Date(String(form.get("paid_at"))).toISOString()');
    expect(workspace).not.toContain('paid_at:field(form,"paid_at")');
    expect(workspace).toContain('name="payment_reference" required autoComplete="off"');
    expect(workspace.match(/name="invoice_reference" autoComplete="off"/g)?.length).toBe(workspace.match(/name="invoice_reference"/g)?.length);
    expect(workspace).toContain('type="datetime-local" max={localNow()}');
  });
  it("makes Finance open the invoice and tick the check before confirming receipt", () => {
    const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
    expect(workspace).toContain("Open the invoice (");
    expect(workspace).toContain("I have checked the invoice against the approved amount.");
    expect(workspace).toContain("disabled={busy||!invoiceOpened}");
    const access = readFileSync("app/api/work-orders/[id]/commercial-documents/[documentId]/access/route.ts", "utf8");
    expect(access).toContain('identity.role === "finance" && commercial.data) await supabase.rpc("record_invoice_opened"');
    expect(readFileSync("app/api/work-orders/[id]/release-1/route.ts", "utf8")).toContain("invoice_opened_at");
  });
});
