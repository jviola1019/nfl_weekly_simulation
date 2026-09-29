/**
 * Content Security Policy (pattern ported from the fantasy_football_dashboard).
 *
 * - connect-src 'self': the app makes no client-side external requests; every
 *   data source is read by the R engine or the ingest CLI, never the browser.
 * - font-src 'self': Archivo is self-hosted by next/font at build time.
 * - img-src 'self' data:: no remote images.
 * - style-src-attr 'unsafe-inline': charts position marks with inline style
 *   attributes; a nonce cannot cover attribute styles. Inline <style> blocks still
 *   need the nonce, so the weakening is as narrow as CSP allows.
 */
export interface CspOptions {
  nonce: string;
  isDev?: boolean;
}

export const CSP_HEADER_NAME = "Content-Security-Policy";

export function buildCsp({ nonce, isDev = false }: CspOptions): string {
  const scriptSrc = ["'self'", `'nonce-${nonce}'`, "'strict-dynamic'", isDev ? "'unsafe-eval'" : null].filter(Boolean);
  const directives: Array<[string, string]> = [
    ["default-src", "'self'"],
    ["script-src", scriptSrc.join(" ")],
    ["style-src", `'self' 'nonce-${nonce}'`],
    ["style-src-attr", "'unsafe-inline'"],
    ["img-src", "'self' data:"],
    ["font-src", "'self'"],
    ["connect-src", "'self'"],
    ["object-src", "'none'"],
    ["frame-src", "'none'"],
    ["base-uri", "'self'"],
    ["form-action", "'self'"],
    ["frame-ancestors", "'none'"]
  ];
  const tail = isDev ? [] : ["upgrade-insecure-requests"];
  return [...directives.map(([k, v]) => `${k} ${v}`), ...tail].join("; ");
}
