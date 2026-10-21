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

  it("no ceiling names a file that no longer exists, and the total is below the audit's", () => {
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

  it("globals.css defines every type, spacing, radius and measure role the components use", () => {
    const roles = [
      "--text-heading", "--text-figure", "--text-stat", "--text-title-sm", "--text-title", "--text-score", "--text-hero",
      "--spacing-tight", "--spacing-snug", "--spacing-control", "--spacing-stack", "--spacing-card", "--spacing-card-sm",
      "--spacing-section", "--spacing-page-top", "--spacing-gutter", "--spacing-row", "--spacing-cell",
      "--spacing-endzone", "--spacing-endzone-hero", "--spacing-turf-hero",
      "--radius-card", "--radius-field", "--radius-control", "--radius-tick",
      "--container-page", "--container-measure", "--container-aside", "--container-table", "--container-table-wide"
    ];
    const missing = roles.filter((r) => !new RegExp(`${r}:\\s*[^;]+;`).test(CSS));
    expect(missing).toEqual([]);
  });

  it("no spacing role is named like a display utility: Tailwind reads inline-block as inline-size: var(--spacing-block)", () => {
    const reserved = ["inline", "block", "flex", "grid", "table", "contents", "flow-root", "hidden", "list-item"];
    const named = [...CSS.matchAll(/--spacing-([a-z-]+):/g)].map((m) => m[1]!);
    expect(named.filter((n) => reserved.includes(n))).toEqual([]);
  });

  it("every spacing role is a multiple of the 4px unit (the field's 1px border inset aside)", () => {
    const px = (v: string) => (v.endsWith("rem") ? Number.parseFloat(v) * 16 : Number.NaN);
    const bad = [...CSS.matchAll(/--spacing-([a-z-]+):\s*([0-9.]+rem);/g)]
      .filter(([, name]) => name !== "endzone" && name !== "endzone-hero")
      .filter(([, , v]) => px(v!) % 4 !== 0)
      .map(([, name, v]) => `${name}: ${v}`);
    expect(bad).toEqual([]);
  });
});
