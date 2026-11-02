import { expect, test } from "@playwright/test";
import { gameHrefs, WIDTHS } from "./helpers";

/**
 * The game page's flags name the market line and the model line above the strip. They are drawn
 * inside the Field (components/Field.tsx), in the strip's own coordinates, so each flag's edge is
 * the same x as the marker it names. Before Track B2 the flag row sat in the game page, inset 26px
 * on a phone against the strip's 58px end zones, up to 33px off.
 */
for (const width of WIDTHS) {
  test(`at ${width}px every flag edge sits on its marker within 1px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    const hrefs = await gameHrefs(page, 4);
    let measured = 0;
    for (const href of hrefs) {
      await page.goto(href);
      await page.evaluate(() => document.fonts.ready);
      const flags = page.locator("[data-flag]");
      const n = await flags.count();
      for (let i = 0; i < n; i += 1) {
        const flag = flags.nth(i);
        const kind = await flag.getAttribute("data-flag");
        const edge = await flag.getAttribute("data-flag-edge");
        const f = (await flag.boundingBox())!;
        const m = (await page.locator(`[data-marker="${kind}"]`).boundingBox())!;
        const flagX = edge === "left" ? f.x : f.x + f.width;
        const markerX = m.x + m.width / 2;
        expect(Math.abs(flagX - markerX), `${href}: the ${kind} flag's ${edge} edge against its marker`).toBeLessThanOrEqual(1);
        measured += 1;
      }
    }
    expect(measured, "flags measured across the games").toBeGreaterThanOrEqual(hrefs.length);
  });
}

test("a flag never leaves the field: it opens toward the middle", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 900 });
  const [href] = await gameHrefs(page, 1);
  await page.goto(href!);
  const strip = (await page.locator('article[data-game] [role="img"]').first().boundingBox())!;
  const flags = page.locator("[data-flag]");
  expect(await flags.count(), "the game page draws flags").toBeGreaterThan(0);
  for (let i = 0; i < (await flags.count()); i += 1) {
    const f = (await flags.nth(i).boundingBox())!;
    expect(f.x, "flag left edge inside the strip").toBeGreaterThanOrEqual(strip.x - 1);
    expect(f.x + f.width, "flag right edge inside the strip").toBeLessThanOrEqual(strip.x + strip.width + 1);
  }
});
