import { expect, test } from "@playwright/test";
import { PUBLIC_PAGES, signIn } from "./helpers";

const LEAKS: Array<[string, RegExp]> = [
  ["gsis id", /\b00-00\d{5}\b/],
  ["NA", /(^|[\s(,:])NA([\s),.]|$)/m],
  ["NaN", /\bNaN\b/],
  ["undefined", /\bundefined\b/],
  ["null", /\bnull\b/],
  ["????", /\?\?\?\?/],
  ["[object Object]", /\[object Object\]/],
  ["Infinity", /\bInfinity\b/]
];

async function check(text: string, path: string) {
  for (const [name, re] of LEAKS) expect(re.test(text), `${name} on ${path}`).toBe(false);
}

for (const path of PUBLIC_PAGES) {
  test(`no internal ids or broken values on ${path}`, async ({ page }) => {
    await page.goto(path);
    await check(await page.locator("body").innerText(), path);
  });
}

test("no internal ids or broken values on /desk", async ({ page }) => {
  await signIn(page);
  await check(await page.locator("body").innerText(), "/desk");
});
