import { expect, type Page } from "@playwright/test";

export function requiredEnvironment(name: string) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} must be supplied by the isolated release gate.`);
  if (!value.includes("example.test") && name.endsWith("_EMAIL")) {
    throw new Error(`${name} must use a synthetic example.test identity.`);
  }
  return value;
}

export async function login(page: Page, email: string, password: string, next = "/") {
  await page.goto(`/login?next=${encodeURIComponent(next)}`);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).not.toHaveURL(/\/login(?:\?|$)/, { timeout: 20_000 });
}

export async function logout(page: Page) {
  const link = page.getByRole("link", { name: /sign out|log out/i });
  const button = page.getByRole("button", { name: /sign out|log out/i });
  if (await link.isVisible().catch(() => false)) await link.click();
  else await button.click();
  await expect(page).toHaveURL(/\/login(?:\?|$)/, { timeout: 15_000 });
}

export async function selectContaining(page: Page, label: string, text: string) {
  const select = page.getByLabel(label);
  const value = await select.locator("option").filter({ hasText: text }).first().getAttribute("value");
  if (!value) throw new Error(`No ${label} option contains ${text}.`);
  await select.selectOption(value);
}
