import { defineConfig, devices } from "@playwright/test";

const requiredGateEnvironment = ["E2E_SYNTHETIC_RUN_ID", "E2E_ADMIN_EMAIL", "E2E_ADMIN_PASSWORD", "E2E_SUPERVISOR_EMAIL", "E2E_SUPERVISOR_PASSWORD", "E2E_TECHNICIAN_EMAIL", "E2E_TECHNICIAN_PASSWORD", "E2E_FACILITY_MANAGER_EMAIL", "E2E_FACILITY_MANAGER_PASSWORD", "E2E_REVIEWER_EMAIL", "E2E_REVIEWER_PASSWORD", "E2E_PENDING_EMAIL", "E2E_PENDING_PASSWORD", "E2E_PENDING_NEW_PASSWORD"];
const missingGateEnvironment = requiredGateEnvironment.filter(name => !process.env[name]);
if (missingGateEnvironment.length) {
  throw new Error(`Authenticated browser acceptance requires isolated synthetic identities (${missingGateEnvironment.join(", ")}). Run npm run release:verify to provision them. No browser server has been started.`);
}

const baseURL =
  process.env.PLAYWRIGHT_TEST_BASE_URL ?? "http://localhost:3099";

export default defineConfig({
  testDir: "./tests/e2e",

  fullyParallel: true,

  forbidOnly: Boolean(process.env.CI),

  retries: process.env.CI ? 2 : 0,

  workers: process.env.CI ? 1 : undefined,

  reporter: process.env.CI
    ? [
        ["line"],
        ["html", { outputFolder: "playwright-report", open: "never" }],
      ]
    : [
        ["list"],
        ["html", { outputFolder: "playwright-report", open: "never" }],
      ],

  use: {
    baseURL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },

  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
      },
    },
  ],

  webServer: {
    command: "npm run dev -- --port 3099",
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    stdout: "ignore",
    stderr: "pipe",
  },

  outputDir: "test-results",
});
