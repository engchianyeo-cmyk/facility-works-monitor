import { expect, test } from "@playwright/test";
import { login, logout, requiredEnvironment } from "./pilot-helpers";

const adminEmail = requiredEnvironment("E2E_ADMIN_EMAIL");
const adminPassword = requiredEnvironment("E2E_ADMIN_PASSWORD");
const pendingEmail = requiredEnvironment("E2E_PENDING_EMAIL");
const pendingPassword = requiredEnvironment("E2E_PENDING_PASSWORD");
const pendingNewPassword = requiredEnvironment("E2E_PENDING_NEW_PASSWORD");
const reviewerEmail = requiredEnvironment("E2E_REVIEWER_EMAIL");
const reviewerPassword = requiredEnvironment("E2E_REVIEWER_PASSWORD");
const technicianEmail = requiredEnvironment("E2E_TECHNICIAN_EMAIL");
const technicianPassword = requiredEnvironment("E2E_TECHNICIAN_PASSWORD");

test.describe.serial("Pilot identity, password lifecycle and RBAC", () => {
  test("synthetic Administrator can log in and provision a password-pending user", async ({ page }) => {
    await login(page, adminEmail, adminPassword, "/administration/users");
    await expect(page.getByRole("heading", { name: "Users" })).toBeVisible();

    const unique = process.env.E2E_SYNTHETIC_RUN_ID!.slice(0, 8);
    const email = `pilot.provisioned.${unique}@example.test`;
    const provisioning = page.locator("form").filter({ has: page.getByRole("button", { name: "Create user" }) });
    await provisioning.getByLabel("Display name").fill(`Pilot Provisioned ${unique}`);
    await provisioning.getByLabel("Unique email").fill(email);
    await provisioning.getByLabel("Department").selectOption({ index: 1 });
    await provisioning.locator("label").filter({ hasText: /^Role/ }).locator("select").selectOption("reviewer");
    await provisioning.getByLabel("Temporary password").fill("Pilot-Provisioned-2026!");
    await provisioning.getByRole("button", { name: "Create user" }).click();
    await expect(page.getByRole("status")).toContainText(/created|provisioned/i, { timeout: 20_000 });
    await page.getByLabel("Search users by name or email").fill(email);
    await expect(page.getByText(email)).toBeVisible({ timeout: 20_000 });
    await logout(page);
  });

  test("password-pending identity is forced through private-password setup", async ({ page }) => {
    await page.goto("/login?next=/work-orders");
    await page.getByLabel("Email").fill(pendingEmail);
    await page.getByLabel("Password").fill(pendingPassword);
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page).toHaveURL(/\/account\/password\?setup=required/, { timeout: 20_000 });
    await expect(page.getByRole("heading", { name: "Set your private password" })).toBeVisible();
    await page.getByLabel("New password", { exact: true }).fill(pendingNewPassword);
    await page.getByLabel("Confirm new password").fill(pendingNewPassword);
    await page.getByRole("button", { name: "Set password and continue" }).click();
    await expect(page).toHaveURL(/\/login(?:\?|$)/, { timeout: 20_000 });
    await login(page, pendingEmail, pendingNewPassword, "/work-orders");
    await expect(page.getByRole("heading", { name: "Work Orders" })).toBeVisible();
  });

  test("Reviewer is denied Administrator controls", async ({ page }) => {
    await login(page, reviewerEmail, reviewerPassword, "/administration/users");
    await expect(page.getByRole("heading", { name: "Access denied" })).toBeVisible();
  });

  test("Technician cannot create Work Orders or report Incidents", async ({ page }) => {
    await login(page, technicianEmail, technicianPassword, "/operations");
    await page.goto("/work-orders/new");
    await expect(page).toHaveURL(/\/work-orders(?:\?|$)/);
    await page.goto("/incidents/new");
    await expect(page).toHaveURL(/\/incidents(?:\?|$)/);
  });
});
