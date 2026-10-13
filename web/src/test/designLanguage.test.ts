/**
 * One design language on every page (A8). The local app is the offline test surface, so
 * every route carries the Broadcast Line redesign (#207): wide Archivo page titles
 * (PageTitle, or the hero h1 of the home and game pages), section titles in the same face,
 * one-border cards and 44px segment chips (src/components/ui.tsx). This guards against a
 * page keeping the pre-redesign look: small semibold headings and 28px chips.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

const APP = join(import.meta.dirname, "..", "app");

function pages(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return pages(p);
    return name === "page.tsx" || name === "not-found.tsx" ? [p] : [];
  });
}
const PAGES = pages(APP);
const rel = (f: string) => relative(APP, f).split("\\").join("/");

describe("design language", () => {
  it("finds every route, the private desk and the not-found page", () => {
    expect(PAGES.map(rel).sort()).toEqual([
      "data-health/page.tsx",
      "desk/page.tsx",
      "evidence/page.tsx",
      "games/[id]/page.tsx",
      "login/page.tsx",
      "methodology/page.tsx",
      "not-found.tsx",
      "page.tsx",
      "props/page.tsx"
    ]);
  });

  it("every page titles itself in the wide Archivo face", () => {
    const plain = PAGES.filter((f) => {
      const src = readFileSync(f, "utf8");
      const titled = /import \{[^}]*\bPageTitle\b[^}]*\} from "@\/components\/ui"/.test(src) && src.includes("<PageTitle");
      const hero = /<h1 className="(?:wdth-expanded [^"]*|sr-only)"/.test(src);
      return !titled && !hero;
    });
    expect(plain.map(rel)).toEqual([]);
  });

  it("no page keeps the pre-redesign headings or chips", () => {
    const legacy = [/className="text-2xl font-semibold"/, /className="text-lg font-semibold"/, /rounded-\[3px\] border px-2 py-1 no-underline/];
    const hits = PAGES.flatMap((f) =>
      readFileSync(f, "utf8")
        .split("\n")
        .map((line, i) => [line, i] as const)
        .filter(([line]) => legacy.some((re) => re.test(line)))
        .map(([line, i]) => `${rel(f)}:${i + 1}  ${line.trim().slice(0, 90)}`)
    );
    expect(hits).toEqual([]);
  });
});
