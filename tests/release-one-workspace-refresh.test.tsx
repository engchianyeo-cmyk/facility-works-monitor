// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import ReleaseOneWorkspace from "@/components/work-orders/release-one-workspace";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: vi.fn() }) }));
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

function workspace(status: string) {
  return { ok: true, data: { order: { status, assigned_technician_id: "owner" }, costs: [], quotations: [], documents: [], eligible_contractors: [] } };
}

test("physical completion refreshes commercial controls and exposes the no-payment decision without a manual reload", async () => {
  const fetcher = vi.fn()
    .mockResolvedValueOnce({ ok: true, json: async () => workspace("in_progress") })
    .mockResolvedValueOnce({ ok: true, json: async () => workspace("completed") });
  vi.stubGlobal("fetch", fetcher);
  const { rerender } = render(<ReleaseOneWorkspace id="work-order" role="technician" status="in_progress" userId="owner" />);
  await screen.findByRole("button", { name: "Confirm Actual Costing" });
  expect(screen.queryByLabelText("No-payment reason")).toBeNull();
  rerender(<ReleaseOneWorkspace id="work-order" role="technician" status="completed" userId="owner" />);
  expect(await screen.findByLabelText("No-payment reason")).toBeTruthy();
  expect(screen.queryByRole("button", { name: "Confirm Actual Costing" })).toBeNull();
});

test.each([
  ["technician", "owner", true],
  ["technician", "other-technician", false],
  ["supervisor", "manager", true],
  ["facility_manager", "manager", true],
  ["administrator", "manager", true],
  ["approver", "independent-approver", false],
  ["reviewer", "requester", false],
  ["initiator", "requester", false],
])("%s (%s) receives the RPC-authorized no-payment proposal capability", async (role, userId, allowed) => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => workspace("completed") }));
  render(<ReleaseOneWorkspace id="work-order" role={role} status="completed" userId={userId} />);
  await screen.findByRole("heading", { name: "Closure Financial Disposition" });
  expect(screen.queryByRole("button", { name: "Propose No Payment Required" }) !== null).toBe(allowed);
});

test("Approver retains independent no-payment approval without receiving proposal controls", async () => {
  const response = workspace("completed");
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({
    ...response,
    data: { ...response.data, financial_disposition: { id: "disposition", disposition_type: "no_payment_required", reason_code: "in_house", reason: "In-house work", status: "proposed", proposed_by: "owner", approved_at: null } },
  }) }));
  render(<ReleaseOneWorkspace id="work-order" role="approver" status="completed" userId="independent-approver" />);
  expect(await screen.findByRole("button", { name: "Approve No Payment Required" })).toBeTruthy();
  expect(screen.queryByRole("button", { name: "Propose No Payment Required" })).toBeNull();
});

test("D-21: after submission the Technician opens cost correction deliberately", async () => {
  const { fireEvent } = await import("@testing-library/react");
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => workspace("completed") }));
  render(<ReleaseOneWorkspace id="work-order" role="technician" status="completed" userId="owner" />);
  fireEvent.click(await screen.findByRole("button", { name: "Correct the actual costs (before the review)" }));
  expect(await screen.findByRole("button", { name: "Confirm Actual Costing" })).toBeTruthy();
});

test("only the assigned Technician sees the Final Cost Reconciliation form; the independent checker does not", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => workspace("completed") }));
  render(<ReleaseOneWorkspace id="work-order" role="technician" status="completed" userId="owner" />);
  expect(await screen.findByRole("button", { name: "Save Final Cost Reconciliation" })).toBeTruthy();
  expect(screen.getByText(/As the assigned Technician, I supervised this work/)).toBeTruthy();
  cleanup();
  render(<ReleaseOneWorkspace id="work-order" role="technician" status="completed" userId="checker" />);
  await screen.findByRole("heading", { name: "Closure Financial Disposition" });
  expect(screen.queryByRole("button", { name: "Save Final Cost Reconciliation" })).toBeNull();
  expect(screen.queryByText(/I supervised this work/)).toBeNull();
});

test("a chosen revised quotation is flagged in red until it is attached, then confirmed", async () => {
  const { fireEvent } = await import("@testing-library/react");
  const base = workspace("in_progress");
  const withVariation = { ...base, data: { ...base.data, final_cost: { id: "fc", status: "variance_approved", variation_order: true, final_contractor_amount: 13500, confirmed_actual_cost: 13500, variation_justification: "Extra oil and gasket work.", comments: "Checked." } } };
  const fetcher = vi.fn().mockImplementation(async (url: string) => ({ ok: true, json: async () => (String(url).includes("commercial-documents") ? { ok: true } : withVariation) }));
  vi.stubGlobal("fetch", fetcher);
  render(<ReleaseOneWorkspace id="work-order" role="technician" status="in_progress" userId="owner" />);
  const button = await screen.findByRole("button", { name: "Attach Revised Quotation" });
  expect(button.className).toContain("bg-red-600");
  const input = button.closest("form")!.querySelector("input[type=file]") as HTMLInputElement;
  const file = new File(["%PDF-1.4"], "Revised_Quotation_VO.pdf", { type: "application/pdf" });
  fireEvent.change(input, { target: { files: [file] } });
  expect(screen.getByText(/File chosen but not attached yet/)).toBeTruthy();
  fireEvent.submit(button.closest("form")!);
  expect(await screen.findByText("Attached ✓ Revised_Quotation_VO.pdf")).toBeTruthy();
  expect(fetcher.mock.calls.some(([url]) => String(url).includes("commercial-documents"))).toBe(true);
});

test("a saved final cost shows as a summary and reopens only on request", async () => {
  const { fireEvent } = await import("@testing-library/react");
  const base = workspace("completed");
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ ...base, data: { ...base.data, final_cost: { id: "fc", status: "variance_approved", variation_order: true, final_contractor_amount: 13500, confirmed_actual_cost: 13500, variation_justification: "Extra oil and gasket work.", comments: "Checked.", submitted_at: "2026-10-30T13:00:00Z" } } }) }));
  render(<ReleaseOneWorkspace id="work-order" role="technician" status="completed" userId="owner" />);
  expect(await screen.findByText("Saved ✓ Final Cost Reconciliation")).toBeTruthy();
  expect(screen.queryByRole("button", { name: "Save Final Cost Reconciliation" })).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Change the final cost" }));
  expect(screen.getByRole("button", { name: "Save Final Cost Reconciliation" })).toBeTruthy();
});

test("once the final cost and its quotation are saved, the declaration box and the replace control are hidden", async () => {
  const { fireEvent } = await import("@testing-library/react");
  const base = workspace("completed");
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ ...base, data: { ...base.data,
    final_cost: { id: "fc", status: "variance_approved", variation_order: true, final_contractor_amount: 13500, confirmed_actual_cost: 13500, variation_justification: "Extra oil and gasket work.", comments: "Checked.", submitted_at: "2026-10-30T13:00:00Z" },
    documents: [{ id: "d1", document_type: "final_invoice", final_cost_submission_id: "fc", original_filename: "Revised_Quotation_VO.pdf", content_type: "application/pdf", byte_size: 100, uploaded_at: "2026-10-30T13:05:00Z" }] } }) }));
  render(<ReleaseOneWorkspace id="work-order" role="technician" status="completed" userId="owner" />);
  expect(await screen.findByText("Saved ✓ Final Cost Reconciliation")).toBeTruthy();
  expect(screen.queryByText(/As the assigned Technician, I supervised/)).toBeNull();
  expect(screen.queryByRole("button", { name: "Replace Revised Quotation" })).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Change the final cost" }));
  expect(screen.getByRole("button", { name: "Replace Revised Quotation" })).toBeTruthy();
});

test("an uploaded invoice is listed once and confirmed, with Replace hidden until asked for", async () => {
  const { fireEvent } = await import("@testing-library/react");
  const base = workspace("reviewed");
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ ...base, data: { ...base.data,
    payment: { id: "pay", status: "approved_for_payment", assessed_amount: 13500, invoice_reference: "VQ-INV-2026-1219", invoice_amount: 13500, invoice_uploaded_at: "2026-10-30T15:00:00Z", invoice_received_at: null, payment_due_at: null, paid_at: null },
    documents: [{ id: "inv", document_type: "invoice", payment_assessment_id: "pay", quotation_id: null, original_filename: "Invoice_VO.pdf", uploaded_at: "2026-10-30T15:00:00Z" }] } }) }));
  render(<ReleaseOneWorkspace id="work-order" role="technician" status="reviewed" userId="owner" />);
  expect(await screen.findByText("Uploaded ✓ Contractor invoice VQ-INV-2026-1219")).toBeTruthy();
  expect(screen.getAllByText("Invoice_VO.pdf")).toHaveLength(1);
  expect(screen.queryByRole("button", { name: "Replace Invoice" })).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Replace the invoice" }));
  expect(screen.getByRole("button", { name: "Replace Invoice" })).toBeTruthy();
});

test("the payment section is outlined in red while Finance has to act", async () => {
  const base = workspace("reviewed");
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ ...base, data: { ...base.data,
    payment: { id: "pay", status: "approved_for_payment", assessed_amount: 13500, invoice_reference: "VQ-INV-2026-1219", invoice_amount: 13500, invoice_uploaded_at: "2026-10-30T15:00:00Z", invoice_received_at: null, payment_due_at: null, paid_at: null } } }) }));
  render(<ReleaseOneWorkspace id="work-order" role="finance" status="reviewed" userId="finance-user" />);
  expect(await screen.findByText("Action needed — Finance: confirm the invoice was received")).toBeTruthy();
  expect(screen.getByRole("button", { name: "Confirm Invoice Received" }).className).toContain("bg-red-600");
});
