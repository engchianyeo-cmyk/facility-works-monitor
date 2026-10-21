import { expect, test } from "@playwright/test";
import { login, requiredEnvironment, selectContaining } from "./pilot-helpers";

const adminEmail = requiredEnvironment("E2E_ADMIN_EMAIL");
const adminPassword = requiredEnvironment("E2E_ADMIN_PASSWORD");
const runId = requiredEnvironment("E2E_SYNTHETIC_RUN_ID").slice(0, 8);

test.describe.serial("Pilot-critical operational workflows", () => {
  test.setTimeout(120_000);
  let assetTag = "";

  test.beforeEach(async ({ page }) => {
    await login(page, adminEmail, adminPassword);
  });

  test("Administrator registers an Asset and the persisted detail renders", async ({ page }, testInfo) => {
    assetTag = `PILOT-${runId}-${testInfo.retry}`;
    await page.goto("/assets/new");
    await page.getByLabel("Asset tag *").fill(assetTag);
    await page.getByLabel("Asset name *").fill(`Pilot AHU ${runId}`);
    await page.getByLabel("Asset type *").fill("Air handling unit");
    await page.getByLabel("Site *").fill("Main Building");
    await page.getByLabel("Exact location *").fill("Level 3 synthetic plantroom");
    await page.getByRole("button", { name: "Create Asset" }).click();
    await expect(page).toHaveURL(/\/assets\/[0-9a-f-]+$/, { timeout: 20_000 });
    await expect(page.getByText(new RegExp(`^${assetTag}$`, "i")).first()).toBeVisible();
  });

  test("Administrator creates a Preventive Maintenance requirement for the Asset", async ({ page }) => {
    await page.goto("/maintenance/new");
    await selectContaining(page, "Asset *", assetTag);
    await page.getByLabel("Title *").fill(`Quarterly Pilot Service ${runId}`);
    await page.getByLabel("Scope *").fill("Inspect filters, belts and safety interlocks using synthetic Pilot data.");
    await page.getByLabel("Every *").fill("3");
    await page.getByLabel("Unit *").selectOption("month");
    const today = new Date().toISOString().slice(0, 10);
    await page.getByLabel("Effective date *").fill(today);
    await page.getByLabel("First due date *").fill(today);
    await page.getByRole("button", { name: "Create Maintenance Requirement" }).click();
    await expect(page).toHaveURL(/\/maintenance\/[0-9a-f-]+$/, { timeout: 20_000 });
    await expect(page.getByRole("heading", { name: `Quarterly Pilot Service ${runId}` })).toBeVisible();
  });

  test("Administrator reports an Incident linked to the Asset", async ({ page }) => {
    await page.goto("/incidents/new");
    await page.getByLabel("Incident type").selectOption("fire");
    await page.getByLabel("Severity").selectOption("critical");
    await page.getByRole("textbox", { name: "Location", exact: true }).fill("Synthetic Pilot Site Level 3");
    await selectContaining(page, "Primary affected Asset", assetTag);
    await page.getByLabel("What is happening?").fill(`Synthetic smoke detector activation ${runId}`);
    await page.getByRole("button", { name: "Report emergency incident" }).click();
    await expect(page).toHaveURL(/\/incidents\/[0-9a-f-]+$/, { timeout: 20_000 });
    await expect(page.getByText(`Synthetic smoke detector activation ${runId}`)).toBeVisible();
  });
  // The Work Order lifecycle journey is covered by tests/e2e/lifecycle-v2.spec.ts (Lifecycle v2).
});
