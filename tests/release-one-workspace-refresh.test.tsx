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
