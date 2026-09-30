import { expect, test } from "@playwright/test";
import { PUBLIC_PAGES } from "./helpers";

for (const path of PUBLIC_PAGES) {
  test(`no stake, EV or desk data on ${path}`, async ({ page }) => {
    await page.goto(path);
    await expect(page.locator("[data-stake], [data-desk]")).toHaveCount(0);
    await expect(page.getByRole("columnheader", { name: /stake|kelly|\bEV\b/i })).toHaveCount(0);
    const html = await page.content();
    expect(html).not.toMatch(/stake_pct|stakePct|paper only: C2/);
  });
}
