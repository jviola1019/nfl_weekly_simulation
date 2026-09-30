import { expect, test } from "@playwright/test";
import { signIn } from "./helpers";

test("anonymous /desk redirects to /login", async ({ page }) => {
  const res = await page.request.get("/desk", { maxRedirects: 0 });
  expect([302, 303, 307, 308]).toContain(res.status());
  expect(res.headers()["location"]).toMatch(/\/login$/);
  await page.goto("/desk");
  await expect(page).toHaveURL(/\/login$/);
});

test("a wrong password is refused with a generic message", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Email").fill("nobody@example.test");
  await page.getByLabel("Password").fill("not-the-password-123");
  await page.getByRole("button", { name: /sign in/i }).click();
  await expect(page.getByRole("alert")).toBeVisible();
  await expect(page).toHaveURL(/\/login/);
});

test("the desk shows paper leans with zero stakes after sign-in", async ({ page }) => {
  await signIn(page);
  const table = page.locator("[data-desk=recommendations]");
  await expect(table).toBeVisible();
  const stakes = await page.locator("[data-stake]").allInnerTexts();
  expect(stakes.length).toBeGreaterThan(0);
  for (const s of stakes) expect(s.trim()).toBe("0.0%");
});
