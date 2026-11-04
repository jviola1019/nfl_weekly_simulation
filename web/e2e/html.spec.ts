import { expect, test } from "@playwright/test";
import { publicPagesOfRun } from "./helpers";

/**
 * Professional HTML (Track B2): every page names itself (a unique title and a description of its own),
 * has the landmarks a reader navigates by (one banner, one main, one contentinfo, labelled navigation),
 * one h1, a language, and machine-readable dates.
 */
test("every public page has its own title and description", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  const titles = new Map<string, string>();
  const descriptions = new Map<string, string>();
  for (const path of pages) {
    await page.goto(path);
    const title = await page.title();
    const description = (await page.locator('meta[name="description"]').getAttribute("content")) ?? "";
    expect(title.length, `${path}: title`).toBeGreaterThan(3);
    expect(title, `${path}: title ends with the site name`).toMatch(/Broadcast Line$/);
    expect(description.length, `${path}: description length`).toBeGreaterThanOrEqual(40);
    expect(description.length, `${path}: description length`).toBeLessThanOrEqual(200);
    expect(titles.get(title), `${path}: title "${title}" is also ${titles.get(title)}`).toBeUndefined();
    expect(descriptions.get(description), `${path}: description is also ${descriptions.get(description)}`).toBeUndefined();
    titles.set(title, path);
    descriptions.set(description, path);
  }
});

test("the game page's title names the matchup and the week", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  await page.goto(pages[1]!);
  expect(await page.title()).toMatch(/^[A-Z]{2,3} (at|vs) [A-Z]{2,3}, week \d+, \d{4} · Broadcast Line$/);
});

test("the private pages are not indexed", async ({ page }) => {
  await page.goto("/login");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
});

test("every public page has one banner, one main, one contentinfo, one h1 and a language", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of [...pages, "/no-such-page"]) {
    await page.goto(path);
    await expect(page.locator("html"), `${path}: lang`).toHaveAttribute("lang", "en");
    await expect(page.getByRole("banner"), `${path}: banner`).toHaveCount(1);
    await expect(page.getByRole("main"), `${path}: main`).toHaveCount(1);
    await expect(page.getByRole("contentinfo"), `${path}: contentinfo`).toHaveCount(1);
    await expect(page.getByRole("heading", { level: 1 }), `${path}: h1`).toHaveCount(1);
  }
});

test("navigation landmarks are named and no two share a name", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of pages) {
    await page.goto(path);
    const names = await page.locator("nav").evaluateAll((els) => els.map((e) => e.getAttribute("aria-label") ?? ""));
    expect(names.every((n) => n.length > 0), `${path}: every nav is named (${names.join(", ")})`).toBe(true);
    expect(new Set(names).size, `${path}: nav names are unique (${names.join(", ")})`).toBe(names.length);
  }
});

test("heading levels never skip a level", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of pages) {
    await page.goto(path);
    const levels = await page.locator("h1, h2, h3, h4").evaluateAll((els) => els.map((e) => Number(e.tagName.slice(1))));
    levels.forEach((lvl, i) => {
      if (i > 0) expect(lvl - levels[i - 1]!, `${path}: heading levels ${levels.join("")}`).toBeLessThanOrEqual(1);
    });
  }
});

test("every <time> carries a valid datetime", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  let seen = 0;
  for (const path of pages) {
    await page.goto(path);
    for (const dt of await page.locator("time").evaluateAll((els) => els.map((e) => e.getAttribute("datetime") ?? ""))) {
      expect(Number.isNaN(Date.parse(dt)), `${path}: <time datetime="${dt}">`).toBe(false);
      seen += 1;
    }
  }
  expect(seen, "dates are marked up as <time>").toBeGreaterThan(10);
});

test("every table has a caption, column headers with scope, and sits in a named scroll region", async ({ page }) => {
  await page.goto("/evidence");
  await page.locator("details > summary").first().click();
  // React appends empty hidden <table> elements to <body> while it hydrates rows; only ours are drawn
  const tables = await page.locator("table:not([hidden])").evaluateAll((els) =>
    els.map((t) => ({
      caption: t.querySelector("caption")?.textContent ?? "",
      colHeaders: [...t.querySelectorAll("thead th")].every((th) => th.getAttribute("scope") === "col"),
      region: t.parentElement?.getAttribute("role") === "region" && (t.parentElement?.getAttribute("aria-label") ?? "").length > 0
    }))
  );
  expect(tables.length).toBeGreaterThanOrEqual(3);
  for (const t of tables) {
    expect(t.caption.length).toBeGreaterThan(3);
    expect(t.colHeaders).toBe(true);
    expect(t.region).toBe(true);
  }
});
