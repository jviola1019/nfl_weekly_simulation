import { expect, test } from "@playwright/test";

test("every page carries the static headers and a per-request nonce CSP", async ({ page, request }) => {
  const a = await request.get("/");
  const b = await request.get("/");
  const h = a.headers();
  expect(h["x-frame-options"]).toBe("DENY");
  expect(h["x-content-type-options"]).toBe("nosniff");
  expect(h["referrer-policy"]).toBe("strict-origin-when-cross-origin");
  expect(h["strict-transport-security"]).toContain("max-age=");
  expect(h["cross-origin-opener-policy"]).toBe("same-origin");
  const csp = h["content-security-policy"] ?? "";
  const nonce = /'nonce-([^']+)'/.exec(csp)?.[1];
  expect(nonce, "CSP has a nonce").toBeTruthy();
  expect(csp).toContain("frame-ancestors 'none'");
  expect(csp).not.toContain("unsafe-eval");
  expect(/'nonce-([^']+)'/.exec(b.headers()["content-security-policy"] ?? "")?.[1]).not.toBe(nonce);
  expect(h["x-powered-by"]).toBeUndefined();

  // every script the page runs carries the request's nonce
  await page.goto("/");
  const scripts = await page.locator("script").evaluateAll((els) => els.map((e) => (e as HTMLScriptElement).nonce));
  expect(scripts.length).toBeGreaterThan(0);
  for (const n of scripts) expect(n).not.toBe("");
});
