import { expect, test, type Page } from "@playwright/test";
import { publicPagesOfRun, WIDTHS } from "./helpers";

/**
 * One vertical rhythm (Track B2). The sections of every page are one --spacing-section apart, a
 * section's title is one --spacing-control above its content, and every page starts one
 * --spacing-page-top below the header. Before it, the gaps between a page's blocks were 20, 24, 28, 32,
 * 36 and 40px, and the game page started 16px higher than the others.
 */
async function tokenPx(page: Page, name: string): Promise<number> {
  return page.evaluate((n) => {
    const probe = document.createElement("div");
    probe.style.height = `var(${n})`;
    document.body.appendChild(probe);
    const h = probe.getBoundingClientRect().height;
    probe.remove();
    return h;
  }, name);
}

/** Vertical gaps between the in-flow children of a container, with their tops, in document order. */
async function gapsWithin(page: Page, selector: string): Promise<{ first: number | null; gaps: number[] }> {
  return page.evaluate((sel) => {
    const el = document.querySelector(sel);
    if (!el) return { first: null, gaps: [] as number[] };
    const kids = [...el.children].filter((c) => getComputedStyle(c).position !== "absolute" && getComputedStyle(c).display !== "none");
    const rects = kids.map((k) => k.getBoundingClientRect());
    return { first: rects[0] ? rects[0].top + window.scrollY : null, gaps: rects.slice(1).map((r, i) => Math.round((r.top - rects[i]!.bottom) * 100) / 100) };
  }, selector);
}

for (const width of WIDTHS) {
  test(`at ${width}px every page uses one section gap, one title gap and one top offset`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    const pages = await publicPagesOfRun(page);
    const sectionGap = await tokenPx(page, "--spacing-section");
    const titleGap = await tokenPx(page, "--spacing-control");
    const topOffset = await tokenPx(page, "--spacing-page-top");
    expect([sectionGap, titleGap, topOffset], "the tokens are 40, 12 and 48px").toEqual([40, 12, 48]);

    for (const path of pages) {
      await page.goto(path);
      const header = (await page.locator("body > header").boundingBox())!;
      const { first, gaps } = await gapsWithin(page, "[data-page]");
      expect(first, `${path}: the page wrapper`).not.toBeNull();
      expect(first! - (header.y + header.height), `${path}: header to the first block`).toBeCloseTo(topOffset, 0);
      expect(new Set(gaps), `${path}: gaps between sections ${JSON.stringify(gaps)}`).toEqual(new Set(gaps.length ? [sectionGap] : []));

      const titles = await page.evaluate(() =>
        [...document.querySelectorAll("[data-section-title]:not(.sr-only)")].map((t) => {
          const next = t.parentElement && t.parentElement.hasAttribute("data-section") ? t.nextElementSibling : null;
          return next ? Math.round((next.getBoundingClientRect().top - t.getBoundingClientRect().bottom) * 100) / 100 : null;
        })
      );
      for (const g of titles.filter((x): x is number => x !== null)) expect(g, `${path}: title to content`).toBeCloseTo(titleGap, 0);
    }
  });
}

test("no page keeps a hand-picked top margin on its sections", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of pages) {
    await page.goto(path);
    const margins = await page.evaluate(() => [...document.querySelectorAll("[data-page] > *")].filter((e) => getComputedStyle(e).position !== "absolute").map((e) => getComputedStyle(e).marginTop).filter((m) => m !== "0px"));
    expect(margins, `${path}: margin-top on sections`).toEqual([]);
  }
});
