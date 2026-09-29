import { describe, expect, it } from "vitest";
import { buildCsp } from "./csp";
import { STATIC_SECURITY_HEADERS } from "./securityHeaders.mjs";

const directives = (csp: string) => Object.fromEntries(csp.split("; ").map((d) => [d.split(" ")[0], d.split(" ").slice(1).join(" ")]));

describe("buildCsp", () => {
  it("production: nonce + strict-dynamic, no eval, no framing, upgrade", () => {
    const d = directives(buildCsp({ nonce: "abc123" }));
    expect(d["script-src"]).toBe("'self' 'nonce-abc123' 'strict-dynamic'");
    expect(d["style-src"]).toBe("'self' 'nonce-abc123'");
    expect(d["frame-ancestors"]).toBe("'none'");
    expect(d["object-src"]).toBe("'none'");
    expect(d["connect-src"]).toBe("'self'");
    expect(d["upgrade-insecure-requests"]).toBe("");
    expect(buildCsp({ nonce: "abc123" })).not.toContain("unsafe-eval");
  });

  it("allows inline style only on attributes (charts position marks), never inline <style> or script", () => {
    const csp = buildCsp({ nonce: "n" });
    expect(directives(csp)["style-src-attr"]).toBe("'unsafe-inline'");
    expect(directives(csp)["style-src"]).not.toContain("unsafe-inline");
    expect(directives(csp)["script-src"]).not.toContain("unsafe-inline");
  });

  it("dev adds unsafe-eval for React refresh and drops the upgrade", () => {
    const csp = buildCsp({ nonce: "n", isDev: true });
    expect(directives(csp)["script-src"]).toContain("'unsafe-eval'");
    expect(csp).not.toContain("upgrade-insecure-requests");
  });
});

describe("static security headers", () => {
  it("sets the full set once each", () => {
    const keys = STATIC_SECURITY_HEADERS.map((h) => h.key);
    expect(new Set(keys).size).toBe(keys.length);
    expect(Object.fromEntries(STATIC_SECURITY_HEADERS.map((h) => [h.key, h.value]))).toMatchObject({
      "X-Frame-Options": "DENY",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "strict-origin-when-cross-origin"
    });
    expect(Object.isFrozen(STATIC_SECURITY_HEADERS)).toBe(true);
  });
});
