import { expect, test } from "@playwright/test";
import { WIDTHS } from "./helpers";

/**
 * The header is two rows below lg (the wordmark and the Desk button, then the navigation) and one
 * row from lg up. The five navigation labels are always one line: before Track B2 the phone header
 * was four visual rows (229px at 390px), because the theme select took a row and the nav wrapped.
 */
for (const width of WIDTHS) {
  test(`at ${width}px the header is ${width >= 1024 ? "one row" : "two rows"} and the five links share one line`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/");
    await page.evaluate(() => document.fonts.ready);
    const nav = page.getByRole("navigation", { name: "Main" });
    const links = nav.getByRole("link");
    await expect(links).toHaveCount(5);
    const boxes = await links.evaluateAll((els) => els.map((e) => ({ top: Math.round(e.getBoundingClientRect().top), height: e.getBoundingClientRect().height })));
    expect(new Set(boxes.map((b) => b.top)).size, "one line of links").toBe(1);
    for (const b of boxes) expect(b.height, "link target height").toBeGreaterThanOrEqual(44);

    const header = (await page.locator("body > header").boundingBox())!;
    expect(header.height, "header height").toBeLessThanOrEqual(width >= 1024 ? 66 : 112);

    const wordmark = (await page.getByRole("link", { name: "Broadcast Line" }).boundingBox())!;
    const desk = (await page.locator("body > header").getByRole("link", { name: "Desk" }).boundingBox())!;
    expect(Math.abs(wordmark.y + wordmark.height / 2 - (desk.y + desk.height / 2)), "wordmark and Desk on one row").toBeLessThanOrEqual(2);
    expect(desk.height, "Desk target height").toBeGreaterThanOrEqual(44);
    const navTop = (await nav.boundingBox())!.y;
    if (width < 1024) expect(navTop, "the navigation is its own row").toBeGreaterThan(wordmark.y + wordmark.height - 1);
  });
}

test("on a 390px phone the five labels fit without scrolling the row", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 900 });
  await page.goto("/");
  await page.evaluate(() => document.fonts.ready);
  const overflow = await page.getByRole("navigation", { name: "Main" }).locator("ul").evaluate((el) => el.scrollWidth - el.clientWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});

for (const width of [320, 360]) {
  test(`at ${width}px the five labels stay on one line and the page does not scroll sideways`, async ({ page }) => {
    await page.setViewportSize({ width, height: 800 });
    await page.goto("/");
    await page.evaluate(() => document.fonts.ready);
    const tops = await page.getByRole("navigation", { name: "Main" }).getByRole("link").evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().top)));
    expect(new Set(tops).size, "one line of links").toBe(1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth), "horizontal overflow").toBeLessThanOrEqual(0);
  });
}

test("the current section is marked in the navigation", async ({ page }) => {
  await page.goto("/evidence");
  await expect(page.getByRole("navigation", { name: "Main" }).locator('[aria-current="page"]')).toHaveText("Evidence");
});
