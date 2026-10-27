import { describe, expect, it } from "vitest";
import { parseTheme, safeBackPath, THEME_COOKIE, THEMES, themeAttribute } from "./theme";

describe("theme", () => {
  it("accepts the two chosen themes and treats everything else as the system's", () => {
    expect(parseTheme("light")).toBe("light");
    expect(parseTheme("dark")).toBe("dark");
    for (const v of ["system", "", "neon", "DARK", "dark; path=/", undefined, null]) expect(parseTheme(v), String(v)).toBe("system");
  });

  it("renders no attribute for the system, so the colour-scheme query decides", () => {
    expect(themeAttribute("system")).toBeUndefined();
    expect(themeAttribute("light")).toBe("light");
    expect(themeAttribute("dark")).toBe("dark");
  });

  it("offers the system, light and the night game, in that order, with the cookie name the server reads", () => {
    expect(THEMES.map((t) => t.value)).toEqual(["system", "light", "dark"]);
    expect(THEMES.map((t) => t.label)).toEqual(["System", "Light", "Night game"]);
    expect(THEME_COOKIE).toBe("bl-theme");
  });
});

describe("safeBackPath", () => {
  const host = "127.0.0.1:3000";

  it("returns the reader to the page they posted from, at the theme control", () => {
    expect(safeBackPath("http://127.0.0.1:3000/evidence?split=tune&clv=C2", host)).toBe("/evidence?split=tune&clv=C2#theme");
    expect(safeBackPath("http://127.0.0.1:3000/", host)).toBe("/#theme");
    expect(safeBackPath("http://127.0.0.1:3000/games/2026_04_DEN_SF#prob", host)).toBe("/games/2026_04_DEN_SF#theme");
  });

  it("never leaves the site: another host, no referrer or a value that is not a URL goes home", () => {
    // a same-host referer whose path starts with // would make "Location: //evil.example#theme",
    // which the browser reads as another host (B2 final review I1)
    for (const bad of ["https://evil.example/phish", "http://127.0.0.1:3001/", "//evil.example", "http://127.0.0.1:3000//evil.example", "javascript:alert(1)", "not a url", "", null, undefined]) {
      expect(safeBackPath(bad, host), String(bad)).toBe("/#theme");
    }
    expect(safeBackPath("http://127.0.0.1:3000/evidence", null)).toBe("/#theme");
  });
});
