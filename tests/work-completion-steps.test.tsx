// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import WorkCompletionSteps from "@/components/work-orders/work-completion-steps";

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
