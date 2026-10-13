// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import ActualCostEditor, { type ActualCostLine } from "@/components/work-orders/actual-cost-editor";

afterEach(cleanup);
const line: ActualCostLine = { id: "line", cost_phase: "actual", cost_type: "material", description: "Motor replacement",
  quantity: 1, unit: "item", unit_rate: 120, amount: 120, worker_name: null, entered_by: "owner",
  technician_certified_at: null, approved_at: null };

test("a confirmed active cost can be revised on its original line", async () => {
  const save = vi.fn().mockResolvedValue(undefined);
  render(<ActualCostEditor lines={[line]} editable userId="owner" confirmed busy={false} onSave={save} onConfirm={vi.fn()}/>);
  fireEvent.click(screen.getByRole("button", { name: "Edit actual cost: Motor replacement" }));
  fireEvent.change(screen.getByLabelText("Unit rate (SGD)"), { target: { value: "180" } });
  fireEvent.click(screen.getByRole("button", { name: "Save actual cost change" }));
  expect(save).toHaveBeenCalledWith(expect.objectContaining({ cost_line_id: "line", unit_rate: 180, quantity: 1 }));
  expect(screen.getByText(/reopens costing confirmation/)).toBeTruthy();
});

test.each([
  { ...line, entered_by: "other" },
  { ...line, technician_certified_at: "2026-10-13" },
  { ...line, approved_at: "2026-10-13" },
])("does not offer editing another owner's or a locked line", locked => {
  render(<ActualCostEditor lines={[locked]} editable userId="owner" confirmed busy={false} onSave={vi.fn()} onConfirm={vi.fn()}/>);
  expect(screen.queryByRole("button", { name: /Edit actual cost:/ })).toBeNull();
});

test("a non-executing actor sees costs without a mutation form", () => {
  render(<ActualCostEditor lines={[line]} editable={false} userId="owner" confirmed busy={false} onSave={vi.fn()} onConfirm={vi.fn()}/>);
  expect(screen.queryByRole("button", { name: "Add Actual Cost" })).toBeNull();
  expect(screen.queryByRole("button", { name: /Edit actual cost:/ })).toBeNull();
});
