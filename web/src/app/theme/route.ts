import { type NextRequest, NextResponse } from "next/server";
import { parseTheme, safeBackPath, THEME_COOKIE, THEME_COOKIE_MAX_AGE } from "@/lib/theme";

/**
 * POST /theme: stores the chosen theme in a cookie and sends the browser back to the page it came
 * from. The footer's theme control is a plain form that posts here, so it works before any script
 * has run and with none, and the next page is rendered in the chosen theme from its first byte.
 * (A server action was tried first: a tap during hydration could set the cookie without the page
 * repainting.) The cookie holds a preference only, so it is readable by the server alone and
 * carries no secret; a post from another origin is refused. Hosts are compared as the browser sent
 * them (the Host header), and the redirect is a relative path, so it follows the host the reader used.
 */
export async function POST(request: NextRequest) {
  const host = request.headers.get("host");
  const origin = request.headers.get("origin");
  if (origin !== null && new URL(origin).host !== host) {
    return new NextResponse("The theme can only be changed from this site.", { status: 403 });
  }
  const form = await request.formData();
  const theme = parseTheme(String(form.get("theme") ?? ""));
  const response = new NextResponse(null, { status: 303, headers: { Location: safeBackPath(request.headers.get("referer"), host) } });
  if (theme === "system") response.cookies.delete(THEME_COOKIE);
  else response.cookies.set(THEME_COOKIE, theme, { path: "/", maxAge: THEME_COOKIE_MAX_AGE, sameSite: "lax", httpOnly: true });
  return response;
}
