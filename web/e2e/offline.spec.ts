import { expect, test } from "@playwright/test";

/**
 * Offline (A8): with every request to a non-loopback host aborted, every public page
 * still renders, nothing tries to reach the internet, no request fails, and the font
 * comes from this server. The game page is the first one the home page links to, so
 * the spec works on any published run (the fixture or a run_week.R bundle).
 */
const LOOPBACK = new Set(["127.0.0.1", "localhost", "[::1]"]);

test("every public page renders with every request served locally", async ({ page }) => {
  const external: string[] = [];
  const failed: string[] = [];
  const fonts: string[] = [];
  await page.route("**/*", (route) => {
    const url = new URL(route.request().url());
    if (LOOPBACK.has(url.hostname)) return route.continue();
    external.push(url.href);
    return route.abort();
  });
  page.on("requestfailed", (r) => {
    const error = r.failure()?.errorText ?? "";
    // a link prefetch cancelled by the next navigation is not a failure
    if (LOOPBACK.has(new URL(r.url()).hostname) && error.includes("ERR_ABORTED")) return;
    failed.push(`${r.url()} ${error}`);
  });
  page.on("response", (r) => {
    if (r.status() >= 400) failed.push(`${r.status()} ${r.url()}`);
    if (r.url().endsWith(".woff2") && r.ok()) fonts.push(r.url());
  });

  await page.goto("/", { waitUntil: "networkidle" });
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  const game = await page.locator('a[href^="/games/"]').first().getAttribute("href");
  expect(game, "a game link on the home page").toBeTruthy();
  await page.goto(game!, { waitUntil: "networkidle" });
  await expect(page.getByRole("heading", { level: 2, name: "Win probability" })).toBeVisible();
  for (const path of ["/props", "/evidence", "/methodology", "/data-health", "/login"]) {
    await page.goto(path, { waitUntil: "networkidle" });
    await expect(page.getByRole("heading", { level: 1 }), path).toBeVisible();
  }

  expect(external, "requests to the internet").toEqual([]);
  expect(failed, "failed requests").toEqual([]);
  expect(fonts.length, "a woff2 served by this app").toBeGreaterThan(0);
});
