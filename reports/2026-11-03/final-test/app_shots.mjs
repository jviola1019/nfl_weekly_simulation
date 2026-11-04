// Screenshots and page text of every public page of the running local app, for the final
// end-to-end check. Each game page in the bundle is visited; lazily drawn charts are scrolled into
// view first. Writes <out>/<name>.png, <out>/<name>.txt and <out>/pages.json.
//
// Usage: node app_shots.mjs <web dir> <base url> <bundle dir> <out dir>
import { createRequire } from "node:module";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [webDir, base, bundleDir, out] = process.argv.slice(2);
const { chromium } = createRequire(join(webDir, "package.json"))("@playwright/test");
mkdirSync(out, { recursive: true });

const games = JSON.parse(readFileSync(join(bundleDir, "games.json"), "utf8"));
const pages = [
  ["home", "/"],
  ...games.map((g) => [`game-${g.game_id}`, `/games/${g.game_id}`]),
  ["props", "/props"],
  ["evidence", "/evidence"],
  ["methodology", "/methodology"],
  ["data-health", "/data-health"],
  ["desk", "/desk"]
];
// the home page also at phone width and in the dark theme
const variants = [
  ["home-390-light", "/", 390, "light"],
  ["home-1440-dark", "/", 1440, "dark"],
  [`game-${games[0].game_id}-390-dark`, `/games/${games[0].game_id}`, 390, "dark"]
];

const browser = await chromium.launch();
const report = [];
async function shoot(name, path, width = 1440, scheme = "light") {
  const ctx = await browser.newContext({ viewport: { width, height: 900 }, colorScheme: scheme });
  const page = await ctx.newPage();
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => errors.push(String(e)));
  const res = await page.goto(base + path, { waitUntil: "networkidle" });
  const slots = page.locator("[data-plot-slot]");
  const n = await slots.count();
  for (let i = 0; i < n; i += 1) await slots.nth(i).scrollIntoViewIfNeeded();
  if (n > 0) await page.waitForFunction((k) => document.querySelectorAll("[data-plot-slot] svg[role=img]").length >= k, n, { timeout: 15000 }).catch(() => {});
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(400);
  await page.screenshot({ path: join(out, `${name}.png`), fullPage: true });
  const text = await page.evaluate(() => document.body.innerText);
  writeFileSync(join(out, `${name}.txt`), text);
  const charts = await page.locator("[data-plot-slot] svg[role=img]").count();
  report.push({
    name, path, width, scheme, status: res?.status() ?? null, final_url: page.url(), title: await page.title(),
    h1: (await page.locator("h1").first().textContent().catch(() => null))?.trim() ?? null,
    plot_slots: n, charts_drawn: charts, console_errors: errors
  });
  await ctx.close();
}
for (const [name, path] of pages) await shoot(name, path);
for (const [name, path, w, s] of variants) await shoot(name, path, w, s);
await browser.close();
writeFileSync(join(out, "pages.json"), JSON.stringify(report, null, 2));
for (const r of report) {
  console.log(`${String(r.status).padEnd(4)} ${r.name.padEnd(34)} h1="${r.h1}" charts ${r.charts_drawn}/${r.plot_slots} errors ${r.console_errors.length}${r.final_url.endsWith(r.path) ? "" : ` -> ${r.final_url}`}`);
}
