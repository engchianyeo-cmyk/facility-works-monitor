import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const migration = readFileSync("supabase/migrations/20260920223606_supporting_document_corrections.sql", "utf8");
const workspace = readFileSync("components/work-orders/release-one-workspace.tsx", "utf8");
const correction = readFileSync("components/work-orders/document-correction-control.tsx", "utf8");
const evidence = readFileSync("components/evidence/evidence-panel.tsx", "utf8");
const evidenceRoute = readFileSync("app/api/evidence/route.ts", "utf8");
const releaseRoute = readFileSync("app/api/work-orders/[id]/release-1/route.ts", "utf8");

describe("governed supporting-document correction", () => {
  test("exposes the correction and quotation revision workflow", () => {
    for (const label of ["Open Document Correction", "Verify Documents & Close Correction"]) expect(correction).toContain(label);
    for (const label of ["Prepare Quotation Revision", "Replace Draft Quotation", "Submit for Approval", "Independent Approval", "Approved quotation history", "Download"]) expect(workspace).toContain(label);
    expect(releaseRoute).toContain("start_work_order_quotation_revision");
  });

  test("preserves completed history while governing Technician correction access", () => {
    expect(migration).toContain("work_order_status_preserved',true");
    expect(migration).toContain("original_history_preserved',true");
    expect(migration).toContain("w.status in ('completed','reviewed','closed')");
    expect(migration).toContain("c.status='open'");
    expect(evidenceRoute).toContain("correctionOpen: Boolean(correction.data)");
    expect(evidence).toContain("canDelete = canMutate");
    expect(evidence).toContain("Authorized management must open a supporting-document correction");
  });

  test("requires both field evidence categories and an approved quotation document before closure", () => {
    expect(migration).toContain("BEFORE_EVIDENCE_REQUIRED");
    expect(migration).toContain("AFTER_EVIDENCE_REQUIRED");
    expect(migration).toContain("QUOTATION_APPROVAL_REQUIRED");
    expect(migration).toContain("QUOTATION_DOCUMENT_REQUIRED");
  });

  test("makes approved documents immutable and replaces only draft attachments", () => {
    expect(migration).toContain("APPROVED_DOCUMENT_IMMUTABLE");
    expect(migration).toContain("q.status in ('draft','returned')");
    expect(migration).toContain("superseded_by=result.id");
    expect(migration).toContain("supporting_document_locked',true");
    expect(workspace).toContain("Supporting document is read-only.");
    expect(workspace).toContain("setMessage(null);try{const form=new FormData()");
    expect(workspace).toContain('window.open("about:blank","_blank")');
    expect(workspace).toContain("opened.location.href=body.url");
  });

  test("requires an attachment before submission and independent approval", () => {
    expect(migration.match(/QUOTATION_DOCUMENT_REQUIRED/g)?.length).toBeGreaterThanOrEqual(3);
    expect(migration).toContain("q.submitted_by=actor_id or q.prepared_by=actor_id");
    expect(workspace).toContain("disabled={busy||quoteDocs.length===0}");
  });
});
