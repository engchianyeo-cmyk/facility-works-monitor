// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import WorkCompletionSteps from "@/components/work-orders/work-completion-steps";
import TechnicianEndorsement from "@/components/work-orders/technician-endorsement";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: () => undefined }) }));

afterEach(cleanup);

test("marks done steps and points to the next one", () => {
  render(<WorkCompletionSteps steps={[
    { label: "Start the work", done: true, href: "#execution-title" },
    { label: "Add After photos of the finished work", done: false, href: "#work-order-evidence" },
    { label: "Submit Physical Completion for review", done: false, href: "#execution-title" },
  ]} />);
  expect(screen.getByText("1 of 3 done")).toBeTruthy();
  expect(screen.getByRole("link", { name: "Do this now" }).getAttribute("href")).toBe("#work-order-evidence");
  expect(screen.getByRole("link", { name: "Review" }).getAttribute("href")).toBe("#execution-title");
});

test("D-25: the checker can only endorse after ticking every check and stating the award basis", () => {
  render(<TechnicianEndorsement workOrderId="wo" required canEndorse endorsements={[]} stageSetting="Before the Approver's review" stage="review"
    quotations={[{ id: "a", contractor: "Voltquay", amount: 11762.5, reference: "VQ-Q-2026-0957", awarded: true }, { id: "b", contractor: "Ampwell", amount: 12690, reference: null, awarded: false }]} />);
  fireEvent.change(screen.getByLabelText("What did you check?"), { target: { value: "Inspected the site and the documents." } });
  const button = screen.getByRole("button", { name: "Endorse as authentic" }) as HTMLButtonElement;
  expect(button.disabled).toBe(true);
  for (const box of screen.getAllByRole("checkbox")) fireEvent.click(box);
  expect(button.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText(/Basis of the award/), { target: { value: "Lowest compliant quotation for the same scope." } });
  expect(button.disabled).toBe(false);
});
