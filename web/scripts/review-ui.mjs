// Visual review helper: full-page screenshots at 390/768/1440 in both themes, plus
// overflow, console and axe checks. Usage: BASE=http://127.0.0.1:3100 OUT=dir node scripts/review-ui.mjs
import { chromium } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const BASE = process.env.BASE ?? "http://127.0.0.1:3100";
const OUT = process.env.OUT ?? "e2e/screenshots";
const PAGES = ["/", "/evidence", "/methodology", "/data-health", "/props", "/games/2026_04_DEN_SF", "/login"];
const WIDTHS = [390, 768, 1440];
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM ?? undefined });
const report = [];
async function visit(context, path, width, scheme) {
  const page = await context.newPage();
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(BASE + path, { waitUntil: "networkidle" });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  const name = `${path === "/" ? "home" : path.slice(1).replace(/\//g, "_")}-${width}-${scheme}.png`;
  await page.screenshot({ path: `${OUT}/${name}`, fullPage: true });
  const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
  const serious = axe.violations.filter((v) => v.impact === "serious" || v.impact === "critical");
  const text = await page.evaluate(() => document.body.innerText);
  const leaks = ["undefined", "NaN", "????", "[object Object]"].filter((t) => text.includes(t));
  if (/\b00-00\d{5}\b/.test(text)) leaks.push("gsis id");
  report.push({ path, width, scheme, overflow, errors: errors.length, serious: serious.map((v) => `${v.id}(${v.nodes.length})`), leaks });
  await page.close();
}
for (const scheme of ["light", "dark"]) {
  for (const width of WIDTHS) {
    const context = await browser.newContext({ viewport: { width, height: 900 }, colorScheme: scheme });
    for (const p of PAGES) await visit(context, p, width, scheme);
    // desk after sign-in
    const page = await context.newPage();
    await page.goto(BASE + "/login");
    await page.fill("input[name=email]", process.env.DESK_EMAIL);
    await page.fill("input[name=password]", process.env.DESK_PASSWORD);
    await Promise.all([page.waitForURL("**/desk"), page.click("button[type=submit]")]);
    await page.close();
    await visit(context, "/desk", width, scheme);
    await context.close();
  }
}
await browser.close();
console.table(report.map((r) => ({ ...r, serious: r.serious.join(" "), leaks: r.leaks.join(" ") })));
