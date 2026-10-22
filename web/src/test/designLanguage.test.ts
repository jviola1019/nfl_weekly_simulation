/**
 * One design language on every page (A8, tightened in Track B2). The local app is the offline test
 * surface, so every route carries the Broadcast Line redesign (#207): a <Page> of <Section>s under one
 * <PageHeader> (wide Archivo title, lead, and the run and data date), one-border <Card>s, <DataTable>s
 * and 44px chips (src/components/ui.tsx). This guards against a page keeping the pre-redesign look
 * (small semibold headings, 28px chips) or drifting from the shared components: no page draws its own
 * table, section title or h2, none uses the removed PageTitle, and the dark button's class is written
 * once.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

const SRC = join(import.meta.dirname, "..");
const APP = join(SRC, "app");

function pages(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return pages(p);
    return name === "page.tsx" || name === "not-found.tsx" ? [p] : [];
  });
}
function sources(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return sources(p);
    return /\.tsx$/.test(p) && !/\.test\.tsx$/.test(p) ? [p] : [];
  });
}
const PAGES = pages(APP);
const rel = (f: string) => relative(APP, f).split("\\").join("/");
const relSrc = (f: string) => relative(SRC, f).split("\\").join("/");

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
      const titled = /import \{[^}]*\bPageHeader\b[^}]*\} from "@\/components\/ui"/.test(src) && src.includes("<PageHeader");
      const hero = /<h1 className="sr-only">/.test(src); // the game page: the scoreboard is its visible title
      return !titled && !hero;
    });
    expect(plain.map(rel)).toEqual([]);
  });

  it("every page is a <Page>, so its sections are one section gap apart", () => {
    const loose = PAGES.filter((f) => {
      const src = readFileSync(f, "utf8");
      return !(/import \{[^}]*\bPage\b[^}]*\} from "@\/components\/ui"/.test(src) && src.includes("<Page"));
    });
    expect(loose.map(rel)).toEqual([]);
  });

  it("no page keeps the pre-redesign headings or chips, or the removed PageTitle", () => {
    const legacy = [/className="text-2xl font-semibold"/, /className="text-lg font-semibold"/, /rounded-\[3px\] border px-2 py-1 no-underline/, /\bPageTitle\b/];
    const hits = PAGES.flatMap((f) =>
      readFileSync(f, "utf8")
        .split("\n")
        .map((line, i) => [line, i] as const)
        .filter(([line]) => legacy.some((re) => re.test(line)))
        .map(([line, i]) => `${rel(f)}:${i + 1}  ${line.trim().slice(0, 90)}`)
    );
    expect(hits).toEqual([]);
  });

  it("the page files draw no table and no h2 of their own: DataTable and Section do", () => {
    const hits = PAGES.flatMap((f) =>
      readFileSync(f, "utf8")
        .split("\n")
        .map((line, i) => [line, i] as const)
        .filter(([line]) => /<table\b|<h2\b/.test(line))
        .map(([line, i]) => `${rel(f)}:${i + 1}  ${line.trim().slice(0, 90)}`)
    );
    expect(hits).toEqual([]);
  });

  it("only ui.tsx writes a <table>", () => {
    const hits = sources(SRC)
      .filter((f) => relSrc(f) !== "components/ui.tsx" && /<table\b/.test(readFileSync(f, "utf8")))
      .map(relSrc);
    expect(hits).toEqual([]);
  });

  it("the section title is written once, in ui.tsx", () => {
    const hits = sources(SRC)
      .filter((f) => relSrc(f) !== "components/ui.tsx" && readFileSync(f, "utf8").includes("wdth-expanded text-heading font-bold"))
      .map(relSrc);
    expect(hits).toEqual([]);
  });

  it("the dark filled button is written once, in ui.tsx (BUTTON_CLASS)", () => {
    // the header's Desk link used to carry its own copy of the class, and a second copy drifts from the first
    const hits = sources(SRC)
      .filter((f) => relSrc(f) !== "components/ui.tsx" && readFileSync(f, "utf8").includes("border-ink bg-ink"))
      .map(relSrc);
    expect(hits).toEqual([]);
  });
});
