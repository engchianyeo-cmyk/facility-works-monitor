import { expect, test } from "@playwright/test";

const reviewerEmail = process.env.E2E_REVIEWER_EMAIL;
const reviewerPassword = process.env.E2E_REVIEWER_PASSWORD;

test.describe("Reviewer authentication", () => {
  test.beforeEach(() => {
    if (!reviewerEmail || !reviewerPassword) {
      throw new Error(
        "E2E_REVIEWER_EMAIL and E2E_REVIEWER_PASSWORD must be configured.",
      );
    }
  });

  test("reviewer can sign in and reach the work-order page", async ({
    page,
  }) => {
    await page.goto("/login?next=/works");

    await page.getByLabel("Email").fill(reviewerEmail!);
    await page.getByLabel("Password").fill(reviewerPassword!);
    await page.getByRole("button", { name: "Sign in" }).click();

    await expect(page).toHaveURL(/\/works(?:\?|$)/, {
      timeout: 15_000,
    });

    await expect(
      page.getByRole("heading", {
        name: "Work Orders",
      }),
    ).toBeVisible();
  });

  test("invalid password displays an authentication error", async ({
    page,
  }) => {
    await page.goto("/login");

    await page.getByLabel("Email").fill(reviewerEmail!);
    await page
      .getByLabel("Password")
      .fill("deliberately-wrong-password");

    await page.getByRole("button", { name: "Sign in" }).click();

    await expect(page.getByRole("alert")).toBeVisible({
      timeout: 15_000,
    });

    await expect(page).toHaveURL(/\/login(?:\?|$)/);
  });

  test("reviewer cannot access administrator user management", async ({
    page,
  }) => {
    await page.goto("/login?next=/administration/users");

    await page.getByLabel("Email").fill(reviewerEmail!);
    await page.getByLabel("Password").fill(reviewerPassword!);
    await page.getByRole("button", { name: "Sign in" }).click();

    await page.goto("/administration/users");

    await expect(
      page.getByRole("heading", {
        name: "Access denied",
      }),
    ).toBeVisible({
      timeout: 15_000,
    });
  });

  test("reviewer can sign out and loses the authenticated session", async ({
    page,
  }) => {
    await page.goto("/login?next=/works");

    await page.getByLabel("Email").fill(reviewerEmail!);
    await page.getByLabel("Password").fill(reviewerPassword!);
    await page.getByRole("button", { name: "Sign in" }).click();

    await expect(page).toHaveURL(/\/works(?:\?|$)/, {
      timeout: 15_000,
    });

    const signOutLink = page.getByRole("link", {
      name: /sign out|log out/i,
    });
    const signOutButton = page.getByRole("button", {
      name: /sign out|log out/i,
    });

    if (await signOutLink.isVisible().catch(() => false)) {
      await signOutLink.click();
    } else {
      await signOutButton.click();
    }

    await expect(page).toHaveURL(/\/login(?:\?|$)/, {
      timeout: 15_000,
    });

    await page.goto("/works/new");

    await expect(page).toHaveURL(/\/login(?:\?|$)/);
  });
});