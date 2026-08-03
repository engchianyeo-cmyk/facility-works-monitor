import { expect, test } from "@playwright/test";

test.describe("Public access and protected-route smoke tests", () => {
  test("home page responds", async ({ page }) => {
    const response = await page.goto("/");
    expect(response).not.toBeNull();
    expect(response?.status()).toBeLessThan(500);
    await expect(page.locator("body")).toBeVisible();
  });

  test("login page loads", async ({ page }) => {
    const response = await page.goto("/login");
    expect(response).not.toBeNull();
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/login/);
    await expect(page.locator("body")).toBeVisible();
  });

  test("registration without a role redirects to first-time access", async ({ page }) => {
    const response = await page.goto("/register");
    expect(response).not.toBeNull();
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/first-time(?:\?|$)/);
    await expect(page.locator("body")).toBeVisible();
  });

  test("reviewer registration page loads when a valid role is supplied", async ({ page }) => {
    const response = await page.goto("/register?role=reviewer");
    expect(response).not.toBeNull();
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/register\?role=reviewer$/);
    await expect(page.getByRole("heading", { name: "Register as a Reviewer" })).toBeVisible();
  });

  test("unauthenticated visitor can load the work-order list shell", async ({ page }) => {
    const response = await page.goto("/works");
    expect(response).not.toBeNull();
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/works(?:\?|$)/);
    await expect(page.getByRole("heading", { name: "Work Orders" })).toBeVisible();
  });

  test("unauthenticated visitor is redirected from new work-order page", async ({ page }) => {
    await page.goto("/works/new");
    await expect(page).toHaveURL(/\/login(?:\?|$)/);
  });

  test("unauthenticated visitor sees access denied on administration page", async ({ page }) => {
    const response = await page.goto("/administration/users");
    expect(response).not.toBeNull();
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/administration\/users(?:\?|$)/);
    await expect(page.getByRole("heading", { name: "Access denied" })).toBeVisible();
    await expect(page.getByText("An active Administrator account is required to manage users.")).toBeVisible();
  });

  test("health endpoint does not return a server error", async ({ request }) => {
    const response = await request.get("/api/health");
    expect(response.status()).toBeLessThan(500);
  });
});
