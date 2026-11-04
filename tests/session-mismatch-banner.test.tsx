// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import PresenceHeartbeat from "@/components/presence-heartbeat";

vi.mock("next/navigation", () => ({ usePathname: () => "/work-orders/wo" }));
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

test("warns when another tab has signed this browser in as someone else", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ status: 200, json: async () => ({ success: true, user_id: "ying", display_name: "Ying Zhang", email: "ec@glorybene.com", role: "technician" }) }));
  render(<PresenceHeartbeat expectedUserId="yang" expectedName="Yang Ying Zhang" />);
  expect(await screen.findByText(/This page was opened as Yang Ying Zhang, but this browser is now signed in as Ying Zhang \(ec@glorybene.com\), technician/)).toBeTruthy();
  expect(screen.getByRole("button", { name: "Reload this page" })).toBeTruthy();
});

test("stays silent while the signed-in account is unchanged", async () => {
  const fetcher = vi.fn().mockResolvedValue({ status: 200, json: async () => ({ success: true, user_id: "yang" }) });
  vi.stubGlobal("fetch", fetcher);
  render(<PresenceHeartbeat expectedUserId="yang" expectedName="Yang Ying Zhang" />);
  await vi.waitFor(() => expect(fetcher).toHaveBeenCalled());
  expect(screen.queryByRole("alert")).toBeNull();
});
