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

  test("Administrator registers an Asset and the persisted detail renders", async ({ page }) => {
    assetTag = `PILOT-${runId}`;
    await page.goto("/assets/new");
    await page.getByLabel("Asset tag *").fill(assetTag);
    await page.getByLabel("Asset name *").fill(`Pilot AHU ${runId}`);
    await page.getByLabel("Asset type *").fill("Air handling unit");
    await page.getByLabel("Site *").fill("Synthetic Pilot Site");
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

  test("Work Order persists, advances through the lifecycle and accepts protected evidence", async ({ page }) => {
    await page.goto("/work-orders/new");
    const workOrderForm = page.locator("form").filter({ has: page.getByRole("button", { name: "Create and submit" }) });
    await workOrderForm.locator('[name="title"]').fill(`Pilot corrective work ${runId}`);
    await workOrderForm.locator('[name="description"]').fill("Synthetic end-to-end corrective maintenance acceptance record.");
    await workOrderForm.locator('[name="site"]').fill("Synthetic Pilot Site");
    await workOrderForm.locator('[name="location"]').fill("Level 3 synthetic plantroom");
    await selectContaining(page, "Asset", assetTag);
    await page.getByRole("button", { name: "Create and submit" }).click();
    await expect(page).toHaveURL(/\/work-orders\/[0-9a-f-]+$/, { timeout: 20_000 });
    await expect(page.getByRole("heading", { name: `Pilot corrective work ${runId}`, exact: true }).first()).toBeVisible();

    await page.getByRole("button", { name: "Approve Work Order" }).click();
    await page.getByLabel("Override reason, when applicable").fill("Synthetic Administrator override for isolated acceptance only.");
    await page.getByRole("button", { name: "Confirm approval" }).click();
    await expect(page.getByText(/approved/i).first()).toBeVisible({ timeout: 20_000 });

    const assignment = page.locator("form").filter({ has: page.getByRole("button", { name: "Assign work order" }) });
    const technicianValue = await assignment.locator("select").nth(1).locator("option").filter({ hasText: "Pilot Technician" }).getAttribute("value");
    if (!technicianValue) throw new Error("Synthetic Pilot Technician was not available for assignment.");
    await assignment.locator("select").nth(1).selectOption(technicianValue);
    await assignment.getByRole("button", { name: "Assign work order" }).click();
    await expect(assignment.getByRole("status")).toContainText("Technician assigned", { timeout: 20_000 });

    await page.getByRole("button", { name: "Accept assignment" }).click();
    await page.getByRole("button", { name: "Start work" }).click();
    await expect(page.getByText(/In Progress/i).first()).toBeVisible({ timeout: 20_000 });

    const evidence = page.locator("section").filter({ has: page.getByRole("heading", { name: "Evidence" }) });
    await evidence.getByLabel("Photo or PDF").setInputFiles({
      name: `pilot-${runId}.png`,
      mimeType: "image/png",
      buffer: Buffer.from("89504e470d0a1a0a", "hex"),
    });
    await evidence.getByLabel("Short note (optional)").fill("Synthetic Pilot evidence; no personal data.");
    await evidence.getByRole("button", { name: "Add evidence" }).click();
    await expect(evidence.getByText(`pilot-${runId}.png`)).toBeVisible({ timeout: 20_000 });

    await page.getByRole("button", { name: "Record completion" }).click();
    await page.getByLabel("Completion notes").fill("Synthetic corrective work completed and condition verified.");
    await page.getByLabel("Labour hours").fill("1.25");
    await page.getByRole("button", { name: "Submit completion" }).click();
    await expect(page.getByText(/Awaiting Review/i).first()).toBeVisible({ timeout: 20_000 });

    await page.getByRole("button", { name: "Accept completion" }).click();
    await page.getByLabel("Decision reason, when applicable").fill("Synthetic acceptance confirms recorded evidence.");
    await page.getByRole("button", { name: "Confirm acceptance" }).click();
    await page.getByRole("button", { name: "Close Work Order" }).click();
    await expect(page.getByText(/^Closed$/).first()).toBeVisible({ timeout: 20_000 });
  });
});
