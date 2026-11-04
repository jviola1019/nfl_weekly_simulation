import { expect, test } from "@playwright/test";
import { drawLazyCharts, gameHrefs } from "./helpers";

/**
 * Print (Track B2): the game and evidence pages are the ones people file. In print the page is the
 * light palette on white even when the screen is in the night-game theme, the header, the theme choice
 * and the chip controls are gone, the field keeps its colours (the blue and gold lines are background
 * colours), and the page fits the sheet.
 */
test.use({ colorScheme: "dark", viewport: { width: 1200, height: 900 } });

async function paths(page: import("@playwright/test").Page) {
  const [game] = await gameHrefs(page, 1);
  return [game!, "/evidence"];
}

test("in print the page is dark ink on white, whatever the screen theme", async ({ page }) => {
  for (const path of await paths(page)) {
    await page.goto(path);
    await drawLazyCharts(page);
    const screen = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    expect(screen, `${path}: the screen is the night game`).not.toBe("rgb(255, 255, 255)");
    await page.emulateMedia({ media: "print" });
    const print = await page.evaluate(() => ({ bg: getComputedStyle(document.body).backgroundColor, ink: getComputedStyle(document.body).color }));
    expect(print.bg, `${path}: print background`).toBe("rgb(255, 255, 255)");
    expect(print.ink, `${path}: print ink`).toBe("rgb(0, 0, 0)");
    await page.emulateMedia({ media: "screen" });
  }
});

test("in print the header, the theme choice and the chip controls are hidden and the notice stays", async ({ page }) => {
  for (const path of await paths(page)) {
    await page.goto(path);
    await page.emulateMedia({ media: "print" });
    await expect(page.locator("body > header"), `${path}: header`).toBeHidden();
    await expect(page.getByRole("button", { name: "Night game" }), `${path}: theme choice`).toBeHidden();
    await expect(page.getByRole("contentinfo"), `${path}: the responsible-gambling notice stays`).toContainText("1-800-GAMBLER");
    await expect(page.getByRole("heading", { level: 1 }), `${path}: the title stays`).toHaveCount(1);
    await page.emulateMedia({ media: "screen" });
  }
});

test("in print the field keeps its colours and nothing runs off the sheet", async ({ page }) => {
  const [game] = await gameHrefs(page, 1);
  await page.goto(game!);
  await page.emulateMedia({ media: "print" });
  const marker = page.locator('[data-marker="market"]').first();
  await expect(marker).toBeVisible();
  expect(await marker.evaluate((el) => getComputedStyle(el).getPropertyValue("print-color-adjust"))).toBe("exact");
  for (const path of await paths(page)) {
    await page.goto(path);
    await page.emulateMedia({ media: "print" });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, `${path}: horizontal overflow in print`).toBeLessThanOrEqual(0);
  }
});

test("each of the two pages prints to a PDF of a few sheets", async ({ page }) => {
  for (const path of await paths(page)) {
    await page.goto(path);
    await drawLazyCharts(page);
    const pdf = await page.pdf({ format: "A4", printBackground: true });
    expect(pdf.subarray(0, 4).toString("latin1"), `${path}: a PDF`).toBe("%PDF");
    const sheets = (pdf.toString("latin1").match(/\/Type\s*\/Page[^s]/g) ?? []).length;
    expect(sheets, `${path}: sheets`).toBeGreaterThanOrEqual(1);
    expect(sheets, `${path}: sheets`).toBeLessThanOrEqual(12);
  }
});
