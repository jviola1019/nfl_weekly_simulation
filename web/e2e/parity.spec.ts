import { expect, test, type Page } from "@playwright/test";
import { SCHEMES, signIn, WIDTHS } from "./helpers";

/**
 * Offline and online look exactly the same (owner, 2026-10-13). The offline app (`npm run
 * local`) and the deployed app run the same `next build`, so the same bundles must give the
 * same pixels. Procedure (web/README.md "Offline and online parity"):
 *   1. serve the offline path (A) and the online path (B) from the same bundles;
 *   2. E2E_BASE_URL=<A> E2E_PARITY_SNAPSHOTS=<dir> npx playwright test --grep @parity --update-snapshots
 *   3. E2E_BASE_URL=<B> E2E_PARITY_SNAPSHOTS=<dir> npx playwright test --grep @parity
 * Zero differing pixels (maxDiffPixels 0, threshold 0). The snapshots live in the scratch
 * directory the variable names and are never committed; without it the spec skips.
 * The only mask is [data-age]: "x min ago" reads the request-time clock (components/Age.tsx),
 * so two servers asked at different moments legitimately differ there and nowhere else.
 * E2E_PARITY_GAMES (comma-separated game ids) names the game pages to compare; the default
 * is the committed simulator fixture: one game with distributions and one without a market.
 */
const SNAPSHOTS = process.env.E2E_PARITY_SNAPSHOTS;
const GAMES = (process.env.E2E_PARITY_GAMES ?? "2024_15_LA_SF,2024_15_BUF_DET").split(",").map((g) => g.trim()).filter(Boolean);
const PAGES: { name: string; path: string }[] = [
  { name: "home", path: "/" },
  ...GAMES.map((g) => ({ name: `game-${g}`, path: `/games/${g}` })),
  { name: "evidence", path: "/evidence" },
  { name: "methodology", path: "/methodology" },
  { name: "data-health", path: "/data-health" },
  { name: "props", path: "/props" },
  { name: "login", path: "/login" },
  { name: "not-found", path: "/no-such-page" }
];

async function settle(page: Page) {
  await page.evaluate(() => document.fonts.ready);
  // charts measure their container after hydration; two frames let them draw at the final width
  await page.evaluate(() => new Promise<void>((done) => requestAnimationFrame(() => requestAnimationFrame(() => done()))));
}

async function shoot(page: Page, name: string) {
  await settle(page);
  await expect(page).toHaveScreenshot(`${name}.png`, {
    fullPage: true,
    maxDiffPixels: 0,
    threshold: 0,
    mask: [page.locator("[data-age]")]
  });
}

test.describe("@parity offline and online render the same pixels", () => {
  test.skip(!SNAPSHOTS, "LIVE: set E2E_PARITY_SNAPSHOTS to a scratch directory (see the header of e2e/parity.spec.ts)");

  for (const scheme of SCHEMES) {
    for (const width of WIDTHS) {
      test.describe(`${width}px ${scheme}`, () => {
        test.use({ viewport: { width, height: 900 }, colorScheme: scheme, reducedMotion: "reduce" });

        for (const p of PAGES) {
          test(`@parity ${p.name}`, async ({ page }) => {
            await page.goto(p.path, { waitUntil: "networkidle" });
            await shoot(page, `${p.name}-${width}-${scheme}`);
          });
        }

        test("@parity desk after login", async ({ page }) => {
          await signIn(page);
          await page.waitForLoadState("networkidle");
          await shoot(page, `desk-${width}-${scheme}`);
        });
      });
    }
  }
});
