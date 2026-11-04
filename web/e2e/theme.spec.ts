import { expect, test } from "@playwright/test";

/**
 * The theme is a cookie that the server reads and renders onto <html data-theme> (lib/theme.ts,
 * app/theme/route.ts), so the first byte of a page already has its colours: no flash, and no inline
 * script of ours. Before Track B2 a script applied it after hydration, which flashed.
 */
const COOKIE = "bl-theme";

test("the server renders the theme from the cookie, and ignores a value it does not know", async ({ request }) => {
  const dark = await (await request.get("/", { headers: { cookie: `${COOKIE}=dark` } })).text();
  const light = await (await request.get("/", { headers: { cookie: `${COOKIE}=light` } })).text();
  const system = await (await request.get("/")).text();
  const bogus = await (await request.get("/", { headers: { cookie: `${COOKIE}=neon` } })).text();
  expect(dark).toMatch(/<html[^>]*\sdata-theme="dark"/);
  expect(light).toMatch(/<html[^>]*\sdata-theme="light"/);
  expect(system).not.toMatch(/<html[^>]*\sdata-theme=/);
  expect(bogus).not.toMatch(/<html[^>]*\sdata-theme=/);
});

test("no inline script reads or writes the theme", async ({ request }) => {
  const html = await (await request.get("/", { headers: { cookie: `${COOKIE}=dark` } })).text();
  const inline = [...html.matchAll(/<script(?![^>]*\ssrc=)[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1] ?? "");
  expect(inline.length, "Next's own inline scripts are there").toBeGreaterThan(0);
  for (const code of inline) {
    expect(code).not.toContain("localStorage");
    expect(code).not.toContain(COOKIE);
    expect(code).not.toMatch(/setAttribute\(["']data-theme|dataset\.theme/);
  }
});

test("choosing a theme stores the cookie and returns to the same page, at the control", async ({ page, context }) => {
  await page.goto("/evidence?split=tune", { waitUntil: "networkidle" });
  await page.getByRole("contentinfo").getByRole("button", { name: "Night game" }).click();
  await expect(page).toHaveURL(/\/evidence\?split=tune#theme$/);
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  expect((await context.cookies()).find((c) => c.name === COOKIE)?.value).toBe("dark");
  await expect(page.getByRole("contentinfo").getByRole("button", { name: "Night game" })).toHaveAttribute("aria-pressed", "true");
  await page.goto("/methodology");
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await page.getByRole("contentinfo").getByRole("button", { name: "System" }).click();
  await expect(page.locator("html")).not.toHaveAttribute("data-theme", /.+/);
  expect((await context.cookies()).find((c) => c.name === COOKIE)).toBeUndefined();
});

test("a tap straight after the page starts loading is not lost", async ({ page }) => {
  for (let i = 0; i < 3; i += 1) {
    await page.context().clearCookies();
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await page.getByRole("contentinfo").getByRole("button", { name: "Night game" }).click();
    await expect(page.locator("html"), `try ${i + 1}`).toHaveAttribute("data-theme", "dark");
  }
});

test("POST /theme sets the cookie, redirects back on this site only, and refuses another origin", async ({ request, baseURL }) => {
  const set = await request.post("/theme", { form: { theme: "light" }, headers: { referer: `${baseURL}/evidence?split=tune` }, maxRedirects: 0 });
  expect(set.status()).toBe(303);
  expect(set.headers()["set-cookie"] ?? "").toMatch(/bl-theme=light/);
  expect(set.headers()["set-cookie"] ?? "").toMatch(/HttpOnly/i);
  expect(set.headers()["location"]).toBe("/evidence?split=tune#theme");

  const elsewhere = await request.post("/theme", { form: { theme: "dark" }, headers: { referer: "https://evil.example/x" }, maxRedirects: 0 });
  expect(elsewhere.status()).toBe(303);
  expect(elsewhere.headers()["location"], "never redirects off the site").toBe("/#theme");

  const unknown = await request.post("/theme", { form: { theme: "neon" }, maxRedirects: 0 });
  expect(unknown.status()).toBe(303);
  expect(unknown.headers()["set-cookie"] ?? "").toMatch(/bl-theme=;|bl-theme=\s*;|Max-Age=0|Expires=Thu, 01 Jan 1970/i);

  const foreign = await request.post("/theme", { form: { theme: "dark" }, headers: { origin: "https://evil.example" }, maxRedirects: 0 });
  expect(foreign.status()).toBe(403);
});

test("the control is three 44px targets in the footer and nothing of it is in the header", async ({ page }) => {
  await page.goto("/");
  const footer = page.getByRole("contentinfo");
  for (const name of ["System", "Light", "Night game"]) {
    const box = (await footer.getByRole("button", { name }).boundingBox())!;
    expect(box.height, `${name} button height`).toBeGreaterThanOrEqual(44);
  }
  await expect(page.locator("body > header").getByRole("button")).toHaveCount(0);
  await expect(page.locator("select")).toHaveCount(0);
});

test.describe("without JavaScript", () => {
  test.use({ javaScriptEnabled: false });

  test("the form still sets the theme, because the server does the work", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("contentinfo").getByRole("button", { name: "Night game" }).click();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  });
});
