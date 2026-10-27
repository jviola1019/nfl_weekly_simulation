import { expect, test } from "@playwright/test";

/**
 * A game strip on the home page is one link to its game: the title link stretches over the whole
 * card, so the strip and the numbers are targets too. Before Track B2 only the title was.
 */
test("clicking the strip itself opens the game", async ({ page }) => {
  await page.goto("/");
  const card = page.locator("article[data-game]").first();
  const id = await card.getAttribute("data-game");
  expect(id).toBeTruthy();
  // the title link is stretched over the card, so the strip is covered by design: click through at its centre
  await card.locator('[role="img"]').click({ force: true });
  await expect(page).toHaveURL(new RegExp(`/games/${id}$`));
});

test("clicking the readout under the strip opens the game too", async ({ page }) => {
  await page.goto("/");
  const card = page.locator("article[data-game]").first();
  const id = await card.getAttribute("data-game");
  await card.scrollIntoViewIfNeeded();
  const box = (await card.boundingBox())!;
  await page.mouse.click(box.x + box.width / 2, box.y + box.height - 12);
  await expect(page).toHaveURL(new RegExp(`/games/${id}$`));
});

test("keyboard focus shows one ring, around the card, not around the title text", async ({ page }) => {
  await page.goto("/");
  const card = page.locator("article[data-game]").first();
  await card.getByRole("link").first().focus();
  expect(await card.evaluate((el) => getComputedStyle(el).outlineStyle)).toBe("solid");
  expect(await card.getByRole("link").first().evaluate((el) => getComputedStyle(el).outlineStyle)).toBe("none");
});
