import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/20260919064024_release_1_proposal_payment_workflow.sql", "utf8");
const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
const route = readFileSync("app/api/work-orders/[id]/release-1/route.ts", "utf8");
const upload = readFileSync("app/api/work-orders/[id]/commercial-documents/route.ts", "utf8");

describe("Release 1 proposal and contractor payment workflow", () => {
  test("exposes each real UI transition", () => {
    for (const label of ["Proposal / Quotation", "Prepare Proposal", "Save Draft", "Submit for Approval", "Independent Approval", "Contractor Final Account / Payment Proposal", "Prepare Final Account", "Attach Invoice", "Submit Payment Proposal", "Independent Payment Approval", "Record Finance Payment"]) expect(workspace).toContain(label);
    for (const operation of ["save_proposal", "submit_proposal", "approve_proposal", "save_payment_proposal", "submit_payment_proposal", "approve_payment", "record_finance_payment"]) expect(route).toContain(operation);
  });

  test("keeps known amounts distinct and authentic quotation fields empty", () => {
    expect(migration).toContain("'SGD',650");
    expect(migration).toContain("assessed_amount=620");
    expect(migration).toContain("actual_cost_preserved',620");
    for (const field of ["quotation_ref=null", "quotation_date=null", "contractor_legal_name=null", "gst_treatment=null", "itemization_note=null"]) expect(migration).toContain(field);
    expect(workspace).toContain("Pending authentic quotation");
    expect(workspace).toContain("Pending authentic invoice");
    expect(workspace).toContain('`S$${new Intl.NumberFormat');
  });

  test("requires independent approvals and keeps Finance payment separate", () => {
    expect(migration).toContain("SELF_APPROVAL_DENIED");
    expect(migration).toContain("q.submitted_by=actor_id or q.prepared_by=actor_id");
    expect(migration).toContain("result.recommended_by=actor_id");
    expect(migration).toContain("Finance payment recording is restricted to an Administrator.");
    expect(migration).toContain("w.reviewed_at+interval '30 days'");
    expect(migration).toContain("completion_notification_queued',true");
  });

  test("stores private documents separately and authorizes registration", () => {
    expect(migration).toContain("work_order_commercial_documents");
    expect(migration).toContain("Only the assigned same-facility Technician may attach commercial documents.");
    expect(upload).toContain('.from("field-evidence").upload');
    expect(upload).toContain("register_work_order_commercial_document");
    expect(upload).toContain('.remove([path])');
  });
});
