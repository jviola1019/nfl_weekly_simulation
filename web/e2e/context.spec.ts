import { expect, test, type Page } from "@playwright/test";
import { publicPagesOfRun } from "./helpers";

/**
 * Context (Track B2): every page that shows run data says which run it is, which week and how old its
 * data is, with the date in a <time datetime>; every headline number carries its label, unit and source
 * line; every term a page links resolves to a definition on /methodology.
 */
async function contextOf(page: Page) {
  const ctx = page.locator("[data-context]");
  await expect(ctx, "one context line").toHaveCount(1);
  const labels = await ctx.locator("dt").allInnerTexts();
  const times = await ctx.locator("time").evaluateAll((els) => els.map((e) => ({ datetime: e.getAttribute("datetime") ?? "", text: e.textContent ?? "" })));
  return { labels, times };
}

test("every page with data states the run and the data date, the date as a machine-readable instant", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of pages.filter((p) => p !== "/login" && p !== "/props")) {
    await page.goto(path);
    const { labels, times } = await contextOf(page);
    expect(labels, `${path}: context labels`).toContain("Run");
    expect(labels, `${path}: context labels`).toContain("Data as of");
    expect(times.length, `${path}: a <time> in the context line`).toBeGreaterThan(0);
    for (const t of times) {
      expect(Number.isNaN(Date.parse(t.datetime)), `${path}: datetime ${t.datetime}`).toBe(false);
      expect(t.text, `${path}: the text shows the same instant`).toContain(new Date(t.datetime).toISOString().slice(0, 16).replace("T", " "));
    }
  }
});

test("the props page says that it has no run, instead of leaving the line out", async ({ page }) => {
  await page.goto("/props");
  const { labels } = await contextOf(page);
  expect(labels).toEqual(["Run"]);
  await expect(page.locator("[data-context]")).toContainText("none published");
});

test("every headline number has a label, a source line and a unit", async ({ page }) => {
  for (const path of ["/", "/evidence"]) {
    await page.goto(path);
    const tiles = page.locator("[data-stat]");
    const n = await tiles.count();
    expect(n, `${path}: stat tiles`).toBeGreaterThanOrEqual(3);
    for (let i = 0; i < n; i += 1) {
      const tile = tiles.nth(i);
      expect((await tile.locator("[data-source]").innerText()).trim().length, `${path} tile ${i}: source line`).toBeGreaterThan(8);
      expect((await tile.innerText()).trim().split("\n").length, `${path} tile ${i}: value, label and source`).toBeGreaterThanOrEqual(3);
    }
  }
});

test("every term link on the public pages lands on a definition on /methodology", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  const hashes = new Set<string>();
  for (const path of pages) {
    await page.goto(path);
    for (const href of await page.locator('a[href^="/methodology#term-"]').evaluateAll((els) => els.map((e) => e.getAttribute("href") ?? ""))) hashes.add(href.split("#")[1]!);
  }
  expect(hashes.size, "term links in use").toBeGreaterThanOrEqual(6);
  await page.goto("/methodology");
  for (const id of hashes) await expect(page.locator(`#${id}`), `definition for ${id}`).toHaveCount(1);
  const defined = await page.locator('[id^="term-"]').count();
  expect(defined, "every definition is shown").toBeGreaterThanOrEqual(hashes.size);
});

test("arriving at a definition marks it", async ({ page }) => {
  await page.goto("/methodology#term-brier");
  const outline = await page.locator("#term-brier").evaluate((el) => getComputedStyle(el).outlineStyle);
  expect(outline).toBe("solid");
});
