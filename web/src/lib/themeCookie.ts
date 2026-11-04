import { cookies } from "next/headers";
import { parseTheme, THEME_COOKIE, type Theme } from "./theme";

/** The viewer's theme, from the request's cookie (server components only). */
export async function readTheme(): Promise<Theme> {
  return parseTheme((await cookies()).get(THEME_COOKIE)?.value);
}
