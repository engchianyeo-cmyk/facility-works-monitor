import { expect, test } from "@playwright/test";
import { login, requiredEnvironment } from "./pilot-helpers";

test("Administrator can find the controlled UAT dataset and open representative detail", async ({ page }) => {
  await login(page, requiredEnvironment("E2E_ADMIN_EMAIL"), requiredEnvironment("E2E_ADMIN_PASSWORD"));
  await page.goto("/work-orders?search=WO-TEST-013&priority=critical&status=in_progress");
  await expect(page.getByText("WO-TEST-013", { exact: true })).toBeVisible();
  await page.getByText("WO-TEST-013", { exact: true }).click();
  await expect(page.getByRole("heading", { name: "Damaged Socket SOCKET-L2-P-04", exact: true }).first()).toBeVisible();
  await expect(page.getByText(/Immediate control: isolated and warning posted/)).toBeVisible();
  await expect(page.getByText(/SOCKET-L2-P-04/).first()).toBeVisible();
});
