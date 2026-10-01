// Quick screenshots for a visual check: node scripts/shot.mjs <outDir> <path> [width] [scheme] [fullPage]
import { chromium } from "@playwright/test";

const [out, path = "/", width = "1440", scheme = "dark", full = "true"] = process.argv.slice(2);
const base = process.env.BASE ?? "http://127.0.0.1:3100";
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: Number(width), height: 900 }, colorScheme: scheme });
const page = await ctx.newPage();
await page.goto(base + path, { waitUntil: "networkidle" });
const name = `${(path === "/" ? "home" : path.replace(/^\//, "").replace(/[/?=&]/g, "_"))}-${width}-${scheme}.png`;
await page.screenshot({ path: `${out}/${name}`, fullPage: full === "true" });
const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
console.log(name, "overflow px:", overflow);
await browser.close();
