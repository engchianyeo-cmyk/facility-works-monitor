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

test("several quotation lines are entered in one table and saved together", async () => {
  const saveMany = vi.fn().mockResolvedValue(true);
  render(<ActualCostEditor lines={[]} editable userId="owner" confirmed={false} busy={false} onSave={vi.fn()} onSaveMany={saveMany} onConfirm={vi.fn()}/>);
  fireEvent.change(screen.getByLabelText("Description, line 1"), { target: { value: "Insulating oil" } });
  fireEvent.change(screen.getByLabelText("Unit, line 1"), { target: { value: "litre" } });
  fireEvent.change(screen.getByLabelText("Quantity, line 1"), { target: { value: "1020" } });
  fireEvent.change(screen.getByLabelText("Unit rate, line 1"), { target: { value: "5.80" } });
  fireEvent.click(screen.getByRole("button", { name: "+ Add another line" }));
  fireEvent.change(screen.getByLabelText("Category, line 2"), { target: { value: "equipment" } });
  fireEvent.change(screen.getByLabelText("Description, line 2"), { target: { value: "Vacuum oil plant" } });
  fireEvent.change(screen.getByLabelText("Unit, line 2"), { target: { value: "day" } });
  fireEvent.change(screen.getByLabelText("Quantity, line 2"), { target: { value: "1.5" } });
  fireEvent.change(screen.getByLabelText("Unit rate, line 2"), { target: { value: "1200" } });
  expect(screen.getByText(/These lines: S\$7,716\.00/)).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "Save 2 cost lines" }));
  expect(saveMany).toHaveBeenCalledWith([
    expect.objectContaining({ cost_type: "material", description: "Insulating oil", unit: "litre", quantity: 1020, unit_rate: 5.8 }),
    expect.objectContaining({ cost_type: "equipment", description: "Vacuum oil plant", unit: "day", quantity: 1.5, unit_rate: 1200 }),
  ]);
});

test("D-23: the owner deletes a mistaken line after confirming", async () => {
  const remove = vi.fn().mockResolvedValue(undefined);
  render(<ActualCostEditor lines={[line]} editable userId="owner" confirmed busy={false} onSave={vi.fn()} onSaveMany={vi.fn()} onDelete={remove} onConfirm={vi.fn()}/>);
  expect(screen.queryByRole("button", { name: "Add Actual Cost" })).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Delete line: Motor replacement" }));
  fireEvent.click(screen.getByRole("button", { name: "Confirm delete" }));
  expect(remove).toHaveBeenCalledWith("line");
});
