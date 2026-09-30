/**
 * Static security headers: the single source of truth (ported from the
 * fantasy_football_dashboard). Plain ESM on purpose: next.config.mjs is loaded by
 * Node before Next's TypeScript pipeline, so this file must not need transpiling.
 * The per-request CSP (it needs a nonce) is built in csp.ts and set by src/proxy.ts.
 *
 * @type {ReadonlyArray<{ key: string, value: string }>}
 */
export const STATIC_SECURITY_HEADERS = Object.freeze([
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  { key: "Cross-Origin-Resource-Policy", value: "same-origin" }
]);
