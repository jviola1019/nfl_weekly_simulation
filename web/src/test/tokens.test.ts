/**
 * Token ratchet (Track B2). Type, spacing, radius and measure come from the named tokens in
 * globals.css, so a page never invents a size. Two rules keep it that way:
 *   1. an arbitrary utility (text-[13px], mt-[7px], rounded-[6px], lg:grid-cols-[...]) can only
 *      become rarer. Each file has a ceiling in tokenCeilings.json; a file that is not listed has a
 *      ceiling of zero. The ceiling must equal the file's real count, so a migration that removes
 *      one has to lower the ceiling in the same commit and the room it frees cannot be reused;
 *   2. text-[Npx] is allowed only in components/ui.tsx and components/Field.tsx, the two files
 *      that draw numbers; anywhere else it is capped by the textPx ceilings, which only fall.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join, relative } from "node:path";
import { describe, expect, it } from "vitest";
import ceilings from "./tokenCeilings.json";

const SRC = join(import.meta.dirname, "..");
const CSS = readFileSync(join(SRC, "app", "globals.css"), "utf8");
/** `text-[13px]`, `mt-[7px]`, `lg:grid-cols-[minmax(0,1fr)_420px]`: a utility whose value is typed in brackets. */
const ARBITRARY = /[A-Za-z0-9:_-]+-\[[^\] ]+\]/g;
const TEXT_PX = /text-\[[0-9.]+px\]/g;
const TEXT_PX_HOMES = ["components/ui.tsx", "components/Field.tsx"];
/** The audit of 2026-10-19 counted this many arbitrary utilities on main (210f791). */
const AUDIT_TOTAL = 114;

function tsx(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return tsx(p);
    return extname(p) === ".tsx" && !/\.test\.tsx$/.test(p) ? [p] : [];
  });
}
const FILES = tsx(SRC).map((f) => ({ rel: relative(SRC, f).split("\\").join("/"), src: readFileSync(f, "utf8") }));
const count = (src: string, re: RegExp) => src.match(re)?.length ?? 0;
const arbitraryCeilings = ceilings.arbitrary as Record<string, number>;
const textPxCeilings = ceilings.textPx as Record<string, number>;

/** The type, spacing, radius, container and tracking roles that @theme static must declare. */
const STATIC_ROLES = [
  "--text-heading", "--text-figure", "--text-stat", "--text-title-sm", "--text-title", "--text-score", "--text-hero",
  "--spacing-tight", "--spacing-snug", "--spacing-control", "--spacing-stack", "--spacing-card", "--spacing-card-sm",
  "--spacing-section", "--spacing-page-top", "--spacing-gutter", "--spacing-row", "--spacing-cell",
  "--spacing-endzone", "--spacing-endzone-hero", "--spacing-turf-hero",
  "--radius-card", "--radius-field", "--radius-control", "--radius-tick",
  "--container-page", "--container-measure", "--container-aside", "--container-tabular", "--container-tabular-wide",
  "--tracking-code",
];
/** The colour role of @theme inline: its utility is border-turf-edge. */
const INLINE_ROLES = ["--color-turf-edge"];
/** The six overrides in the 40rem :root block, and gutter's override in the 80rem block. */
const RESPONSIVE_40 = ["--text-title", "--text-title-sm", "--text-score", "--text-hero", "--spacing-gutter", "--spacing-endzone"];
const RESPONSIVE_80 = ["--spacing-gutter"];
/** The endzone roles are field geometry (26, 46 and 58 px), so they are not 4px multiples. */
const FIELD_EXEMPT = ["endzone", "endzone-hero"];

/** Escapes a string for use inside a RegExp. */
const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** The text between the braces of every block whose head matches, e.g. "@theme static", ":root" or "@media (min-width: 40rem)". */
function blocks(css: string, head: string): string[] {
  return [...css.matchAll(new RegExp(`${escapeRe(head)}\\s*\\{`, "g"))].map((m) => {
    const start = (m.index ?? 0) + m[0].length;
    let depth = 1;
    let i = start;
    for (; depth > 0 && i < css.length; i++) {
      if (css[i] === "{") depth++;
      else if (css[i] === "}") depth--;
    }
    return css.slice(start, i - 1);
  });
}

/** The names that no block declares with a value. With no blocks at all, every name is reported. */
function undeclared(bodies: string[], names: readonly string[]): string[] {
  return names.filter((name) => !bodies.some((body) => new RegExp(`(?:^|[\\s;{])${escapeRe(name)}\\s*:\\s*[^;]+;`).test(body)));
}

/** Plain rem or px spacing values, as [name, px]. calc() values (turf-hero) are not plain, so they are not returned. */
function plainSpacing(css: string): Array<[string, number]> {
  return [...css.matchAll(/--spacing-([a-z-]+):\s*([0-9.]+)(rem|px);/g)].map(
    ([, name, n, unit]): [string, number] => [name ?? "", Number(n) * (unit === "rem" ? 16 : 1)],
  );
}

/** Spacing values off the 4px grid, as "name: Npx"; the endzone field roles are exempt. */
function offGrid(css: string): string[] {
  return plainSpacing(css)
    .filter(([name, px]) => !FIELD_EXEMPT.includes(name) && px % 4 !== 0)
    .map(([name, px]) => `${name}: ${px}px`);
}

describe("token ratchet", () => {
  it("the counters count (the ratchet is not vacuous)", () => {
    expect(count('className="mt-[7px] text-[13px] lg:grid-cols-[minmax(0,1fr)_420px]"', ARBITRARY)).toBe(3);
    expect(count('className="text-[13px] sm:text-[104px] text-sm text-heading"', TEXT_PX)).toBe(2);
    expect(count('className="mt-section gap-stack rounded-card text-heading"', ARBITRARY)).toBe(0);
  });

  it("scans the component and page sources", () => {
    expect(FILES.length).toBeGreaterThan(20);
    expect(FILES.map((f) => f.rel)).toContain("components/ui.tsx");
  });

  it("every file's arbitrary-utility count equals its ceiling (lower the ceiling when you remove one, never raise it)", () => {
    const off = FILES.flatMap(({ rel, src }) => {
      const n = count(src, ARBITRARY);
      const ceiling = arbitraryCeilings[rel] ?? 0;
      return n === ceiling ? [] : [`${rel}: ${n} arbitrary utilities, ceiling ${ceiling}`];
    });
    expect(off).toEqual([]);
  });

  it("no ceiling names a file that no longer exists, and the total does not exceed the audit's", () => {
    const rels = new Set(FILES.map((f) => f.rel));
    const stale = [...Object.keys(arbitraryCeilings), ...Object.keys(textPxCeilings)].filter((k) => !rels.has(k));
    expect(stale).toEqual([]);
    const total = Object.values(arbitraryCeilings).reduce((a, b) => a + b, 0);
    expect(total).toBeLessThanOrEqual(AUDIT_TOTAL);
  });

  it("text-[Npx] lives only in ui.tsx and Field.tsx, or under a textPx ceiling that only falls", () => {
    const off = FILES.filter(({ rel }) => !TEXT_PX_HOMES.includes(rel)).flatMap(({ rel, src }) => {
      const n = count(src, TEXT_PX);
      const ceiling = textPxCeilings[rel] ?? 0;
      return n === ceiling ? [] : [`${rel}: ${n} text-[Npx], ceiling ${ceiling}`];
    });
    expect(off).toEqual([]);
  });

  it("the @theme static block declares every type, spacing, radius, container and tracking role", () => {
    const bodies = blocks(CSS, "@theme static");
    expect(bodies).toHaveLength(1);
    expect(undeclared(bodies, STATIC_ROLES)).toEqual([]);
  });

  it("the @theme inline block declares the colour role that border-turf-edge uses", () => {
    expect(undeclared(blocks(CSS, "@theme inline"), INLINE_ROLES)).toEqual([]);
  });

  it("every --text role in @theme static has its --line-height in the same block", () => {
    const bodies = blocks(CSS, "@theme static");
    const roles = [...(bodies[0] ?? "").matchAll(/--text-([a-z-]+):/g)]
      .map((m) => m[1] ?? "")
      .filter((role) => !/--(line-height|letter-spacing)$/.test(role));
    expect(roles.length).toBeGreaterThanOrEqual(7);
    expect(undeclared(bodies, roles.map((role) => `--text-${role}--line-height`))).toEqual([]);
  });

  it("the responsive overrides are pinned: six in the 40rem :root block, gutter in the 80rem one", () => {
    const at40 = blocks(CSS, "@media (min-width: 40rem)").flatMap((b) => blocks(b, ":root"));
    const at80 = blocks(CSS, "@media (min-width: 80rem)").flatMap((b) => blocks(b, ":root"));
    expect(at40).toHaveLength(1);
    expect(undeclared(at40, RESPONSIVE_40)).toEqual([]);
    expect(undeclared(at80, RESPONSIVE_80)).toEqual([]);
  });

  it("no spacing or container role is named like a display keyword: Tailwind reads inline-block as inline-size: var(--spacing-block), and inline-table as inline-size: var(--container-table)", () => {
    const reserved = ["block", "flex", "grid", "table", "contents", "inline", "hidden", "flow-root", "list-item"];
    const spacing = [...CSS.matchAll(/--spacing-([a-z-]+):/g)].map((m) => m[1] ?? "");
    const containers = [...CSS.matchAll(/--container-([a-z-]+):/g)].map((m) => m[1] ?? "");
    expect(spacing.length).toBeGreaterThanOrEqual(14);
    expect(containers.length).toBeGreaterThanOrEqual(5);
    expect([...spacing, ...containers].filter((n) => reserved.includes(n))).toEqual([]);
  });

  it("every plain spacing value is a multiple of the 4px unit, px or rem (the endzone roles are exempt and calc() is not checked)", () => {
    expect(plainSpacing(CSS).length).toBeGreaterThanOrEqual(13);
    expect(offGrid(CSS)).toEqual([]);
  });
});

// The same helpers run on synthetic CSS, so each rule is shown to bite.
describe("token checks on synthetic CSS", () => {
  it("a token declared only in a :root override is missing from @theme static", () => {
    const onlyInRoot = "@theme static {\n  --text-heading: 1.5rem;\n}\n@media (min-width: 40rem) {\n  :root {\n    --text-hero: 6.5rem;\n  }\n}\n";
    expect(undeclared(blocks(onlyInRoot, "@theme static"), ["--text-heading", "--text-hero"])).toEqual(["--text-hero"]);
  });

  it("gutter's 80rem override is read from that block's :root, not from @theme static", () => {
    const staticOnly = "@theme static {\n  --spacing-gutter: 1rem;\n}\n";
    const at80 = blocks(staticOnly, "@media (min-width: 80rem)").flatMap((b) => blocks(b, ":root"));
    expect(undeclared(at80, RESPONSIVE_80)).toEqual(["--spacing-gutter"]);
  });

  it("the 4px check reads px values as well as rem", () => {
    expect(offGrid("  --spacing-odd: 13px;\n  --spacing-ok: 1rem;\n  --spacing-six: 6px;")).toEqual(["odd: 13px", "six: 6px"]);
  });
});
