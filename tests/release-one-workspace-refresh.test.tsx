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
