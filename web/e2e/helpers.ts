import { expect, type Page } from "@playwright/test";

/** Public routes, with one game from the committed weekly fixture bundle. */
export const PUBLIC_PAGES = ["/", "/games/2026_04_DEN_SF", "/props", "/evidence", "/methodology", "/data-health", "/login"];
export const WIDTHS = [390, 768, 1440] as const;
export const SCHEMES = ["light", "dark"] as const;

export function deskCredentials() {
  const email = process.env.DESK_EMAIL;
  const password = process.env.DESK_PASSWORD;
  if (!email || !password) throw new Error("DESK_EMAIL and DESK_PASSWORD must be set for the desk specs (see npm run seed:user)");
  return { email, password };
}

export async function signIn(page: Page) {
  const { email, password } = deskCredentials();
  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await Promise.all([page.waitForURL("**/desk"), page.getByRole("button", { name: /sign in/i }).click()]);
  await expect(page.getByRole("heading", { level: 1, name: "Desk" })).toBeVisible();
}
