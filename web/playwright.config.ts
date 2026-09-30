import { defineConfig, devices } from "@playwright/test";

/**
 * E2E runs against an already running server (CI starts `next start` after
 * migrating and ingesting the fixture bundles). PW_CHROMIUM points at a preinstalled
 * Chromium when the Playwright browser download is unavailable.
 */
export default defineConfig({
  testDir: "e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://127.0.0.1:3100",
    trace: "retain-on-failure",
    launchOptions: process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {}
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }]
});
