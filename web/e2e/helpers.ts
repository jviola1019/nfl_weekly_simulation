import { expect, type Page } from "@playwright/test";

/** Public routes, with one game from the committed weekly fixture bundle. */
export const PUBLIC_PAGES = ["/", "/games/2026_04_DEN_SF", "/props", "/evidence", "/methodology", "/data-health", "/login"];
export const WIDTHS = [390, 768, 1440] as const;
export const SCHEMES = ["light", "dark"] as const;

export function deskCredentials() {
  const email = process.env.DESK_EMAIL;
  const password = process.env.DESK_PASSWORD;
  if (!email || !password) throw new Error("DESK_EMAIL and DESK_PASSWORD must be set for the desk specs (see npm run seed:user)");
  return { email, password };
}

export async function signIn(page: Page) {
  const { email, password } = deskCredentials();
  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await Promise.all([page.waitForURL("**/desk"), page.getByRole("button", { name: /sign in/i }).click()]);
  await expect(page.getByRole("heading", { level: 1, name: "Desk" })).toBeVisible();
}

/**
 * The score-distribution plots load as their slots near the viewport (components/charts/
 * LazyScoreDistributionPlot.tsx). Scroll every slot into view and wait until each has drawn
 * its SVG, then return to the top, so a screenshot or an axe run sees the finished page.
 */
export async function drawLazyCharts(page: Page) {
  const slots = page.locator("[data-plot-slot]");
  const n = await slots.count();
  for (let i = 0; i < n; i += 1) await slots.nth(i).scrollIntoViewIfNeeded();
  if (n > 0) await expect(page.locator("[data-plot-slot] svg[role=img]")).toHaveCount(n);
  await page.evaluate(() => window.scrollTo(0, 0));
}

/** The game links on the home page, so a spec works on any published run (the fixture or a run_week.R bundle). */
export async function gameHrefs(page: Page, limit = 4): Promise<string[]> {
  await page.goto("/");
  const hrefs = await page
    .locator('a[href^="/games/"]')
    .evaluateAll((els, n) => [...new Set(els.map((e) => e.getAttribute("href") ?? ""))].slice(0, n), limit);
  expect(hrefs.length, "game links on the home page").toBeGreaterThan(0);
  return hrefs;
}

/** The public pages for a run-independent spec: the fixed routes plus the first game of the published run. */
export async function publicPagesOfRun(page: Page): Promise<string[]> {
  const [game] = await gameHrefs(page, 1);
  return ["/", game!, "/props", "/evidence", "/methodology", "/data-health", "/login"];
}
