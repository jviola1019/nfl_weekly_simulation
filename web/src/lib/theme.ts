/**
 * The colour theme. It lives in a cookie that the server reads and renders onto <html data-theme>,
 * so the first byte of every page already has the right colours: nothing waits for a script, and
 * nothing flashes. "system" is no cookie and no attribute: the colour-scheme media query decides.
 */
export const THEME_COOKIE = "bl-theme";
export const THEME_COOKIE_MAX_AGE = 60 * 60 * 24 * 365;
/** The id of the theme form in the footer: the page that sets a theme returns the reader to it. */
export const THEME_ANCHOR = "theme";

export const THEMES = [
  { value: "system", label: "System" },
  { value: "light", label: "Light" },
  { value: "dark", label: "Night game" }
] as const;

export type Theme = (typeof THEMES)[number]["value"];

/** A cookie or form value as a theme. Anything else, or nothing, follows the system. */
export function parseTheme(raw: string | null | undefined): Theme {
  return raw === "light" || raw === "dark" ? raw : "system";
}

/** The data-theme attribute for a theme: none for "system". */
export function themeAttribute(theme: Theme): "light" | "dark" | undefined {
  return theme === "system" ? undefined : theme;
}

/**
 * Where to send the browser after a theme is set: the page the form was posted from, at the theme
 * control, but only when that page is on this host (the Host header of the request). Anything else
 * (no referrer, another site, a value that is not a URL) goes to the home page, so the redirect can
 * never leave the site. The result is a path, never an absolute URL.
 */
export function safeBackPath(referer: string | null | undefined, host: string | null | undefined): string {
  const fallback = `/#${THEME_ANCHOR}`;
  if (!referer || !host) return fallback;
  try {
    const url = new URL(referer);
    if (url.host !== host) return fallback;
    // a path starting with // is protocol-relative in a Location header: another host
    if (url.pathname.startsWith("//")) return fallback;
    return `${url.pathname}${url.search}#${THEME_ANCHOR}`;
  } catch {
    return fallback;
  }
}
