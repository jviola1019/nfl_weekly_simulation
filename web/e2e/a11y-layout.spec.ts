import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";
import { PUBLIC_PAGES, SCHEMES, signIn, WIDTHS } from "./helpers";

async function audit(page: Page, label: string) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow, `${label}: horizontal overflow`).toBeLessThanOrEqual(0);
  const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
  const serious = axe.violations.filter((v) => v.impact === "serious" || v.impact === "critical");
  expect(serious.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(" ")).slice(0, 3).join(", ")}`), label).toEqual([]);
}

for (const scheme of SCHEMES) {
  for (const width of WIDTHS) {
    test.describe(`${width}px ${scheme}`, () => {
      test.use({ viewport: { width, height: 900 }, colorScheme: scheme });

      for (const path of PUBLIC_PAGES) {
        test(`axe, overflow and console on ${path}`, async ({ page }) => {
          const errors: string[] = [];
          page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
          page.on("pageerror", (e) => errors.push(String(e)));
          await page.goto(path, { waitUntil: "networkidle" });
          await audit(page, path);
          expect(errors, `${path}: console errors`).toEqual([]);
        });
      }

      test("axe and overflow on /desk", async ({ page }) => {
        await signIn(page);
        await page.waitForLoadState("networkidle");
        await audit(page, "/desk");
      });
    });
  }
}
