# Track B2: Tokens, Components, Context and Professional HTML Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Next.js app one spacing, type and component system (named tokens, one component of each kind, every page migrated), fix the Track B2 bugs with a test each, put a label, a unit and a source line on every number and the run and data date on every page, and make the HTML professional (per-page metadata, landmarks, axe best-practice rules, a print stylesheet) without slowing the first load.

**Architecture:** Tokens are a static Tailwind 4 theme block in `web/src/app/globals.css` (type roles, spacing roles on a 4px base, radii, measures), with responsive values overridden on `:root`. `web/src/components/ui.tsx` holds the one component of each kind (`Page`, `PageHeader`, `Section`, `Card`, `StatTile`, `DataTable`, `Stamp`, `Term`, `Breadcrumb`, `Grid`); every page is a `<Page>` of `<Section>`s. A ratchet test (`tokens.test.ts` and `tokenCeilings.json`) makes the arbitrary-utility count only fall, and each page migration is driven by lowering its ceiling first. The theme is a cookie that the server renders (a plain form posts to `app/theme/route.ts`), so there is no theme script and nothing flashes. Run and data-date context comes from pure helpers (`lib/context.ts`), terms from one glossary (`lib/glossary.ts`) shown on `/methodology`, and the home and game pages read the promotion gates with one cached query (`publicGates`).

**Tech Stack:** Next.js 16.3.7 (App Router), React 19.3.0, Tailwind 4.3.3, vitest 4.1.11 (with the Postgres suites), Playwright 1.63.0 with axe-core, Drizzle on Postgres. **No new dependency:** `web/package.json` and `web/package-lock.json` do not change.

**Spec:** `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` §4 (Broadcast Line) and the Track B2 section of the approved master plan (`C:/Users/jviol/.claude/plans/complete-a-full-audit-validated-zephyr.md`, "Track B2" and "Verification"). Main is `210f791`.

**Reading the code steps.** Each code step is preceded by an HTML comment `<!-- apply: Tn.k create|replace <path> -->` followed by one or two fenced blocks. `create` writes the block as the whole file. `replace` has two blocks: the exact current text (it must occur exactly once) and the new text. An implementer applies them by hand; the dry run applied them with a script (`.superpowers/research/b2-apply-plan.js`), so the plan text and the dry-run tree agree byte for byte. The blocks were generated from the dry-run tree (`b2-assemble.js`), never typed.

**Audit facts this plan fixes** (web/ at `210f791`, measured 2026-10-19 with the scripts named in the dry-run section):
- 114 arbitrary utilities, 43 of them `text-[Npx]` in 16 sizes from 11 to 104 px; six different gaps between a page's blocks (20, 24, 28, 32, 36, 40 px); a 229 px phone header of four visual rows; hand-written copies of the table (eight), the card (three), the section title (three).
- Bugs: the game page's flag row is inset 26 px against 58 px end zones; the game page starts 16 px higher than the others; the theme is applied after hydration (a flash); the theme select is not 44 px; only the strip title is a link; the Desk button is written twice; `/evidence` has four scroll regions all named "Scrollable table" (axe `landmark-unique`).

## Global Constraints

Copied from the spec and the master plan; every task's requirements include them.

- "**Market** = scrimmage blue. **Model** = first-down gold. **Edge** is the distance between them. This mapping holds on every page, chart and table." (spec §4)
- "**Themes:** light is the default. Dark is its own chosen palette, not a flip." (spec §4)
- "**Type.** Archivo variable (wdth 62–125 …) … Condensed widths for dense odds tables; expanded for team codes and scores. `tabular-nums` only in numeric columns and axes. No all-caps labels, mono micro-labels, eyebrow labels, numbered markers, glow, blur, gradients or particles." (spec §4) The committed font file is not touched (`offlineFonts.test.ts` pins its sha256).
- "Every chart is a `<figure>` with a computed text summary, a table view, and a hover/focus layer." (spec §4) The game page keeps exactly two `<figure>` elements.
- "A responsible-gambling footer appears on every page. Public content follows the evidence … stakes are never public." (spec §4)
- "Do not add any dependency." Task 13 checks that `web/package.json` and `web/package-lock.json` are unchanged, and that no file is deleted.
- Gates, as `.github/workflows/ci-web.yml` runs them: `npm run typecheck`, `npm run lint`, `TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run`, and Playwright on the fixtures served on :3100 (`--grep-invert @sim`, then `@sim` after ingesting the simulator fixture), the offline spec, and `@parity` with `E2E_PARITY_SNAPSHOTS`. `@parity` stays at zero differing pixels with only `[data-age]` masked.
- The e2e hooks stay: `data-game`, `data-line`, `data-plot-slot`, `data-age`, `data-desk`, `data-stake`; `aria-label="Model status"` on the home page's `aside`; the h2 "Win probability" and the text "Table view"; exactly one h1 per page; the game page's `tbody tr` count of bins plus one.
- The guard tests keep their meaning: slop scan, docs truth, offline fonts, design language (nine page files, no new `page.tsx`) and `ScoreDistributionChart.test.tsx` (`<tr class="border-t border-rule">` and a classless `<td>25.00%</td>`). `slopScan` and `docsTruth` slice `globals.css` by the first `:root {`, the first `@media`, `:root[data-theme="dark"]` and the first `@theme`: **never write the words `@media` or `@theme` above the first `@theme inline` block, not even in a comment.**
- No silent fallbacks (CLAUDE.md): a table row without a cell for a column throws, and a page with no run says so in its context line.
- Commits end with a blank line, then exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Pull-request bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

## Review Focus

The five failure modes most likely to bite a reader of this app that the spec does not spell out, most likely first. Each is pinned by a test in the task that owns it.

1. **A tap on the theme chips while the page is still loading, or the first paint in the wrong theme.** A server action was tried and lost a tap that landed during hydration (1 of 4 at delay 0 under 4x CPU), so the control is a plain form. Pinned in Task 4 by `e2e/theme.spec.ts`: "a tap straight after the page starts loading is not lost", the cookie rendered on the first byte, no inline theme script, no JavaScript needed, a foreign origin refused.
2. **A flag that drifts from its marker at some width.** Pinned in Task 5 by `e2e/flags.spec.ts` (within 1 px at 390, 768 and 1440 px, on every game of the run, and never outside the strip).
3. **A narrow phone (320 to 360 px).** The five navigation labels must stay on one line and the page must not scroll sideways. Pinned in Task 4 by `e2e/header.spec.ts`.
4. **A spacing role named like a Tailwind utility.** A first draft named two roles `inline` and `block`; Tailwind read `inline-block` as `inline-size: var(--spacing-block)` and every swatch became a 20 px square. Pinned in Task 1 by `tokens.test.ts` ("no spacing role is named like a display utility").
5. **A deploy with nothing ingested** (no run, no backtest). Every page must say so, keep its context line and stay valid HTML. Pinned in Tasks 6, 8 and 9 by `src/test/pages/*.test.tsx`. (A table row that lacks a cell for a column throws, pinned in Task 2 by `ui.test.tsx`.)

## File structure

| File | Responsibility | Task |
|---|---|---|
| `web/src/app/globals.css` | tokens (`@theme static`), responsive overrides, component CSS (`.data-table`, `.card-link`, the term `:target`), the print stylesheet | 1, 2, 11 |
| `web/src/test/tokens.test.ts`, `web/src/test/tokenCeilings.json` | the ratchet: per-file ceilings on arbitrary utilities, token presence, no reserved role names | 1 and every migration |
| `web/src/components/ui.tsx` | `Stamp`, `Term`, `ContextList`, `Page`, `PageHeader`, `SectionTitle`, `Section`, `Grid`, `Card`, `StatTile`, `DataTable`, `Breadcrumb`, chip and button classes | 2, 12 |
| `web/src/lib/glossary.ts`, `web/src/lib/context.ts` | the terms and the run, backtest and no-run context lines | 2 |
| `web/src/lib/data/queries.ts` | `cache()` on the shared queries and the one-query `publicGates()` | 3 |
| `web/src/lib/theme.ts`, `themeCookie.ts`, `web/src/app/theme/route.ts`, `ThemeToggle.tsx`, `SiteFooter.tsx`, `SiteHeader.tsx`, `NavLinks.tsx`, `app/layout.tsx` | the cookie theme, the two-row header, the footer control | 4 |
| `web/src/components/Field.tsx` | flags drawn inside the hero strip, the stretched card link, tokens | 5 |
| `web/src/app/**/page.tsx`, `not-found.tsx`, `error.tsx` | every page on the components | 6 to 10 |
| `web/src/components/charts/*` | `ChartFigure` and the four chart tables on `DataTable` | 7 |
| `web/e2e/*.spec.ts` | flags, theme, header, card link, html, print, context, rhythm; axe with best-practice | 4, 5, 11, 12 |
| `web/README.md` | the new checks and a "Tokens and components" section | 12 |
| `CHANGELOG.md`, `HANDOFF.md` | the B2 entry and the hand-off section, with the measured numbers | 13 |

## Owner checkpoints and decisions (every STOP in this plan)

Nothing in the plan touches `config.R`, the R engine, `contracts/` or the database schema.

1. **STOP: merging.** The agent never merges; the owner reviews the PR and the screenshots.
2. **STOP: adding a dependency.** None is added. Task 13 verifies that `web/package.json` and `web/package-lock.json` are byte-identical to `main`.
3. **STOP: deleting a file.** None is deleted. `ThemeToggle.tsx` is rewritten in place; the `PageTitle` export of `ui.tsx` is removed (an export, not a file). Task 13 verifies that the diff has no deleted file.
4. **Owner decision: no root `loading.tsx`.** The master plan asks for `loading.tsx` and `error.tsx`. React 19 holds a Suspense fallback on screen for a few hundred milliseconds even when the data is ready, so a root `loading.tsx` moved the mobile LCP from 2.67 s to 3.12 s on the game page, 2.46 s to 2.98 s on the home page and 2.78 s to 3.06 s on evidence (Lighthouse 13.5.0, five interleaved rounds, same machine), while the server answers in well under 150 ms (observed time to first byte, 17 to 143 ms across the runs). This plan ships `error.tsx` only. The file, ready to use if the owner wants it, is in the appendix.
5. **Owner decision: the theme choice moves from the header to the footer** as three 44 px chips. That is what makes the phone header two rows (wordmark and Desk, then the navigation); the old select took a row and the navigation wrapped to a fourth.
6. **Owner decision: the look.** Type sizes are consolidated from 16 sizes to the type roles (section titles 22 to 24 px, lead text 17 to 18 px, chips 13 to 14 px, strip team codes 22 to 20 px), the section gap is one value (40 px), the page starts 48 px below the header on every page, and the model status card, stat tiles and tables carry label, unit and source lines. The before and after screenshots are in the close-out section.
7. **Owner decision: the LCP gate is not met on the game page and evidence on the measuring machine** (neither tree reaches 2.5 s there: `main` is 2.65 s and 2.77 s, the B2 tree 2.75 s and 2.76 s; the B2 tree equals `main` on home and evidence, is about 0.1 s slower on the game page, and is much lighter on CPU). The levers that were measured or reasoned about, and what each costs, are in Task 13.
8. **Owner decision: "every page states its run and data date".** Home, game, evidence, methodology, data health, desk and props state it (props and the desk's empty state say "none published" and why). Login and not-found show no run data and carry no run line.

## Setup (once, before Task 1)

- [ ] **Step S1: a branch.** From a clean checkout of the current `main` (the plan was written at `210f791`; the commits since touch nothing under `web/`, which the evidence section checks, so the code blocks apply unchanged):

```bash
git switch -c feat/b2-tokens-components
cd web && npm ci
```

- [ ] **Step S2: the scratch database and server settings** (the same values CI uses, with a scratch Postgres; replace the host and port if yours differ). The unit suites that need a database use `nfl_test`; the e2e server uses its own database:

```bash
export TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1
export DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_b2
export AUTH_SECRET="$(openssl rand -base64 32)" DESK_EMAIL=desk@example.test DESK_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=')"
export NEXT_TELEMETRY_DISABLED=1 E2E_BASE_URL=http://127.0.0.1:3100
psql -h 127.0.0.1 -p 5436 -U ci -d postgres -c "create database nfl_b2"
```

- [ ] **Step S3: the e2e fixture state and the way to serve a build** (used from Task 4 on; run these from `web/`). The fixture state is what CI's first e2e run sees; the simulator state adds the `@sim` bundle:

```bash
# fixture state
npm run db:migrate
npm run ingest -- ../contracts/fixtures/bundles/weekly-2026-w04
npm run ingest -- ../contracts/fixtures/bundles/backtest-nfl-games-v1
npm run seed:user
# serve the current tree (stop the previous server first; delete .next when you switch trees, so typecheck sees no stale route types)
npm run build && (nohup npm run start -- -p 3100 > next.log 2>&1 &)
# simulator state, for the @sim run
npm run ingest -- ../contracts/fixtures/bundles/weekly-sim-2024-w15
```

Stop only the server you started (by its process id). Before Task 4 and after every task: `rm -rf .next tsconfig.tsbuildinfo` when you rebuild from a different state, so a stale `.next/types` cannot fail the typecheck.

- [ ] **Step S4: the unit gates**, run at the end of every task (`web/`):

```bash
npm run typecheck && npm run lint && npx vitest run
```

Expected after the baseline checkout: typecheck and lint exit 0, `Test Files  18 passed (18)` and `Tests  126 passed (126)` (the dry run's baseline on `main`, with the Postgres suites running).

---
### Task 1: Tokens and the ratchet [haiku]

Every later task builds on named tokens, and a test makes sure nobody goes back to typing sizes. This task adds the tokens (CSS only, nothing uses them yet) and the ratchet that counts arbitrary utilities (`text-[13px]`, `mt-[7px]`, `rounded-[6px]`, `lg:grid-cols-[...]`) per file. The ratchet starts at today's numbers (114 in 19 files) and every migration task lowers its files' ceilings first, so the failing ceiling is the test for that migration.

The roles (all multiples of the 4px unit except the field geometry):

| Type role | Phone to from `sm` | Line height | Replaces |
|---|---|---|---|
| `text-heading` | 24 px | 32 px | the 22 px section titles |
| `text-figure` | 28 px | 1 | the 26, 28 and 30 px readout and moneyline numerals |
| `text-stat` | 40 px | 1 | the stat tile values |
| `text-title-sm` | 32 to 40 px | 0.95 | the compact titles (sign in, not found) |
| `text-title` | 40 to 56 px | 0.95 | page titles and the scoreboard team codes (40 and 52) |
| `text-score` | 56 to 88 px | 0.9 | the scoreboard numerals |
| `text-hero` | 64 to 104 px | 0.9 | the home page's "Week N" |

Small type keeps Tailwind's `text-xs`, `text-sm`, `text-base`, `text-lg` and `text-xl` (12 to 20 px): the 11 px yard numbers become 12, the 13 and 15 px captions become 14, the 17 px lead becomes 18.

| Spacing role | Value | Used for |
|---|---|---|
| `tight` | 4 px | a label above its value |
| `snug` | 8 px | a swatch or icon beside text, chip gaps |
| `control` | 12 px | a section title above its content, control groups |
| `stack` | 20 px | cards and tiles in a grid, the footer's padding |
| `card`, `card-sm` | 20, 16 px | card padding (small for a game strip or an empty state) |
| `section` | 40 px | between the sections of a page |
| `page-top` | 48 px | the header to the first block, and the page's bottom padding |
| `gutter` | 16, 32 from `sm`, 64 from `xl` | the page's side padding |
| `row`, `cell` | 8, 16 px | table rows and columns |
| `endzone`, `endzone-hero`, `turf-hero` | 26 (46 from `sm`), 58, 58 + 1 px | the field: the flag row is inset by exactly the hero end zone plus the strip's border |

Radii: `card` 6, `field` 4, `control` 3, `tick` 2 px. Measures: `page` 1440, `measure` 672 (running text), `aside` 420, `tabular` 640 and `tabular-wide` 720 px (not `table`: Tailwind would read `inline-table` as an inline size, B2 Task 1 review). Two names are deliberately not used: Tailwind reads a spacing token named `inline` or `block` as an `inline-size` or `block-size` utility, so `inline-block` would silently get a width (a first draft did exactly that); the roles are `snug` and `stack`. The theme block is `static`, so every token is always emitted: plain CSS (the tables, the print rules) reads some of them without a utility.

**Files:**
- Create: `web/src/test/tokens.test.ts`, `web/src/test/tokenCeilings.json`
- Modify: `web/src/app/globals.css` (insert the tokens between the colour mapping and `html {`)

**Interfaces:**
- Produces, for every later task: the utilities `text-heading|figure|stat|title-sm|title|score|hero`; `p-card`, `p-card-sm`, `gap-stack`, `gap-snug`, `gap-control`, `gap-tight`, `mt-section`, `gap-section`, `px-gutter`, `pt-page-top`, `pb-page-top`, `w-endzone`, `w-endzone-hero`, `mx-turf-hero`; `rounded-card|field|control|tick`; `max-w-page`, `max-w-measure`, `w-aside`, `min-w-tabular`, `min-w-tabular-wide`; `tracking-code`; `border-turf-edge`. And `tokenCeilings.json`, whose per-file numbers must equal the real counts (`tokens.test.ts` fails in both directions).

- [ ] **Step 1: Write the failing tests** (the ratchet, at today's numbers, and the token check)

<!-- apply: T1.1 create web/src/test/tokens.test.ts -->
```ts
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
      "--container-page", "--container-measure", "--container-aside", "--container-tabular", "--container-tabular-wide"
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
```

<!-- apply: T1.1 create web/src/test/tokenCeilings.json -->
```json
{
  "arbitrary": {
    "app/data-health/page.tsx": 1,
    "app/desk/page.tsx": 1,
    "app/evidence/page.tsx": 5,
    "app/games/[id]/page.tsx": 29,
    "app/layout.tsx": 1,
    "app/methodology/page.tsx": 1,
    "app/page.tsx": 11,
    "components/DataUnavailable.tsx": 1,
    "components/Field.tsx": 31,
    "components/NavLinks.tsx": 1,
    "components/SiteFooter.tsx": 1,
    "components/SiteHeader.tsx": 7,
    "components/ThemeToggle.tsx": 1,
    "components/charts/ChartFigure.tsx": 1,
    "components/charts/ChartTooltip.tsx": 1,
    "components/charts/LazyScoreDistributionPlot.tsx": 2,
    "components/charts/ScoreDistributionChart.tsx": 1,
    "components/charts/ScoreDistributionPlot.tsx": 1,
    "components/ui.tsx": 17
  },
  "textPx": {
    "app/evidence/page.tsx": 2,
    "app/games/[id]/page.tsx": 15,
    "app/page.tsx": 6
  }
}
```

- [ ] **Step 2: Run the tests and see RED**

Run: `cd web && npx vitest run src/test/tokens.test.ts`
Expected: FAIL, `Tests  1 failed | 7 passed (8)`: "globals.css defines every type, spacing, radius and measure role the components use", the assertion listing 30 missing names beginning `--text-heading`. The ratchet itself passes (the ceilings equal today's counts).

- [ ] **Step 3: Add the tokens** (the comment above them must not contain the words `@media` or `@theme`, and it does not)

<!-- apply: T1.3 replace web/src/app/globals.css -->
```css
  --font-sans: var(--font-archivo), system-ui, sans-serif;
}

html {
```

```css
  --font-sans: var(--font-archivo), system-ui, sans-serif;
}

/*
 * Tokens beyond colour (Track B2): type, spacing, radius and measure come from named
 * roles, so a page never invents a size. The unit is 4px (Tailwind's --spacing, 0.25rem);
 * every role is a multiple of it, except the field geometry. Tailwind's xs, sm, base, lg
 * and xl stay the small type scale (12 to 20px); the roles below are the display sizes.
 * Roles that grow with the screen are overridden on :root by the breakpoint rules below.
 * The block is static: every token is always emitted, because plain CSS (the tables, the print
 * rules) reads some of them without a utility.
 * tokens.test.ts holds the line: no new arbitrary utility, no text-[Npx] outside the
 * components that draw numbers.
 */
@theme static {
  --text-heading: 1.5rem;
  --text-heading--line-height: 2rem;
  --text-figure: 1.75rem;
  --text-figure--line-height: 1;
  --text-stat: 2.5rem;
  --text-stat--line-height: 1;
  --text-title-sm: 2rem;
  --text-title-sm--line-height: 0.95;
  --text-title: 2.5rem;
  --text-title--line-height: 0.95;
  --text-title--letter-spacing: -0.01em;
  --text-score: 3.5rem;
  --text-score--line-height: 0.9;
  --text-hero: 4rem;
  --text-hero--line-height: 0.9;
  --text-hero--letter-spacing: -0.02em;

  --spacing-tight: 0.25rem;
  --spacing-snug: 0.5rem;
  --spacing-control: 0.75rem;
  --spacing-stack: 1.25rem;
  --spacing-card: 1.25rem;
  --spacing-card-sm: 1rem;
  --spacing-section: 2.5rem;
  --spacing-page-top: 3rem;
  --spacing-gutter: 1rem;
  --spacing-row: 0.5rem;
  --spacing-cell: 1rem;
  --spacing-endzone: 1.625rem;
  --spacing-endzone-hero: 3.625rem;
  --spacing-turf-hero: calc(3.625rem + 1px);

  --radius-card: 6px;
  --radius-field: 4px;
  --radius-control: 3px;
  --radius-tick: 2px;

  --container-page: 90rem;
  --container-measure: 42rem;
  --container-aside: 26.25rem;
  --container-tabular: 40rem;
  --container-tabular-wide: 45rem;

  --tracking-code: 0.14em;
}

@theme inline {
  --color-turf-edge: var(--turf-edge);
}

/* What each role is for (the values are above):
   tight 4: a label above its value. snug 8: a swatch or icon beside text, chip gaps.
   control 12: a title above its content, control groups. stack 20: cards and tiles in a grid.
   (Not "inline" or "block": Tailwind reads those names as inline-size and block-size utilities,
   and inline-block would pick up a width.)
   card 20 and card-sm 16: card padding (sm for a game strip or an empty state).
   section 40: between the sections of a page. page-top 48: the header to the first block.
   gutter: page side padding, 16 on a phone, 32 from sm, 64 from xl. row 8 and cell 16: tables.
   endzone: the strip's end zones (26 on a phone, 46 from sm); endzone-hero 58; turf-hero is the
   hero end zone plus the strip's 1px border, the inset of the flag row above it. */
@media (min-width: 40rem) {
  :root {
    --text-title-sm: 2.5rem;
    --text-title: 3.5rem;
    --text-score: 5.5rem;
    --text-hero: 6.5rem;
    --spacing-gutter: 2rem;
    --spacing-endzone: 2.875rem;
  }
}

@media (min-width: 80rem) {
  :root {
    --spacing-gutter: 4rem;
  }
}

html {
```

- [ ] **Step 4: Run the tests and see GREEN**

Run: `cd web && npx vitest run src/test/tokens.test.ts`
Expected: `Tests  8 passed (8)`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && rm -rf .next tsconfig.tsbuildinfo && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  19 passed (19)`, `Tests  134 passed (134)`.

```bash
git add web/src/test/tokens.test.ts web/src/test/tokenCeilings.json web/src/app/globals.css
git commit -m "feat(web): type, spacing, radius and measure tokens, and the arbitrary-utility ratchet (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: One component of each kind, the glossary and the context lines [haiku]

`ui.tsx` becomes the only place that decides how a page is built, so a page picks no size or gap of its own:

- `Page`: the column of a page's sections, one `gap-section` apart. Every page returns one.
- `PageHeader`: the h1 in wide Archivo (`size` hero, page or compact), an optional lead (`max-w-measure`), the **context line** (`ContextList`: run, week and data-as-of as a labelled `dl`, the date inside a `<time datetime>`), an `aside` card beside it on a wide screen, and `actions` for small controls (the desk's sign-out).
- `Section` and `SectionTitle`: a landmark named by its title (`aria-labelledby`) or by a `label`, the title one `gap-control` above its content, an optional `aside` on the title's row (a legend), `srTitle` for a title kept for assistive technology only.
- `Card` (surface or sunken tone, padding `card`, `sm` or none, `as` div, article, aside or section), `Grid` (the four fixed grids), `StatTile` (value, label, **source line**), `Breadcrumb`.
- `DataTable`: caption (hidden unless `showCaption`), `scope="col"` headers, an optional row-header column, cells given **by column key** (a row without a cell for a column throws, never an empty cell), rows in `border-t border-rule`, padding from the row and cell tokens, in a keyboard-scrollable region named `"<caption> (table)"` so it never shares a landmark name with its section (axe `landmark-unique`). The first column's cells are `<th scope="row">` when asked; plain cells are classless, which `ScoreDistributionChart.test.tsx` pins.
- `Stamp` (an instant as text inside `<time datetime>`), `Term` (a link to a definition on `/methodology`), `chipClass`, `BUTTON_CLASS`, `QUIET_BUTTON_CLASS`, `INPUT_CLASS`.

`lib/glossary.ts` defines thirteen terms once (no-vig, closing line, the field, gap, unvalidated, shrinkage, Brier, skill, interval, ECE, CLV, walk-forward, holdout), each restating what the methodology and evidence pages already say; `Term` takes only those ids (a type), and Task 9 renders every one on `/methodology`. `lib/context.ts` builds the context lines: `runContext(run)`, `backtestContext(...)`, `noRunContext(why)`.

Two things are deliberately temporary and end in Task 12: `ui.tsx` still exports a deprecated `PageTitle` (so the pages that have not moved yet compile), and `StatTile`'s `source` is optional. The design-language test accepts `PageHeader` beside `PageTitle` until then.

**Files:**
- Create: `web/src/lib/glossary.ts`, `web/src/lib/glossary.test.ts`, `web/src/lib/context.ts`, `web/src/lib/context.test.ts`, `web/src/components/ui.test.tsx`
- Modify: `web/src/components/ui.tsx` (rewritten in place), `web/src/components/DataUnavailable.tsx`, `web/src/app/globals.css` (the component CSS), `web/src/test/designLanguage.test.ts` (one line), `web/src/test/tokenCeilings.json`

**Interfaces:**
- Consumes: the tokens of Task 1.
- Produces: `Page({ children, className? })`; `PageHeader({ title, lead?, context?: ContextItem[], aside?, actions?, size?: "hero" | "page" | "compact" })`; `Section({ id, title, srTitle?, aside?, measure?, className?, children } | { label, ... })`; `SectionTitle({ id, children, srOnly? })`; `Grid({ kind: "tiles" | "pair" | "fields" | "sections", children })`; `Card({ as?, tone?, pad?, className?, ...div props })`; `StatTile({ value, label, source? })`; `DataTable({ caption, showCaption?, columns: { key, header, rowHeader?, nowrap? }[], rows: { key, cells: Record<string, ReactNode>, muted? }[], empty?, minWidth?, dense?, numeric?, topAligned?, ...table props })`; `Stamp({ iso })`; `Term({ id, children? })`; `ContextList({ items })`; `Breadcrumb({ items })`; `TERMS`, `TERM_IDS`, `termHref(id)`, `termAnchor(id)`; `ContextItem { label, value, iso? }`, `runContext(run, { omitWeek? })`, `backtestContext({ windowId, cycleId, dataAsofUtc })`, `noRunContext(why)`.

- [ ] **Step 1: Write the failing tests** (and lower the ceilings the new `ui.tsx` and `DataUnavailable.tsx` will meet)

<!-- apply: T2.1 create web/src/lib/glossary.test.ts -->
```ts
import { describe, expect, it } from "vitest";
import { TERM_IDS, TERMS, termAnchor, termHref } from "./glossary";

describe("glossary", () => {
  it("has a label and a one-sentence-or-two definition for every term, in plain words", () => {
    expect(TERM_IDS.length).toBeGreaterThanOrEqual(12);
    for (const id of TERM_IDS) {
      const t = TERMS[id];
      expect(t.label.length, id).toBeGreaterThan(2);
      expect(t.definition.length, id).toBeGreaterThan(40);
      expect(t.definition.length, id).toBeLessThan(260);
      expect(t.definition.endsWith("."), id).toBe(true);
    }
  });

  it("anchors are the term ids, lower-case with hyphens, and link to the methodology page", () => {
    for (const id of TERM_IDS) {
      expect(id).toMatch(/^[a-z]+(-[a-z]+)*$/);
      expect(termAnchor(id)).toBe(`term-${id}`);
      expect(termHref(id)).toBe(`/methodology#term-${id}`);
    }
  });

  it("states the numbers the pages already state (shrinkage weight, bootstrap size, the 50% Brier floor)", () => {
    expect(TERMS.shrinkage.definition).toContain("70%");
    expect(TERMS.interval.definition).toContain("10,000");
    expect(TERMS.brier.definition).toContain("0.25");
  });
});
```

<!-- apply: T2.1 create web/src/lib/context.test.ts -->
```ts
import { describe, expect, it } from "vitest";
import { backtestContext, noRunContext, runContext } from "./context";

describe("runContext", () => {
  const run = { season: 2024, week: 15, cycleId: "weekly-sim-2024-w15", dataAsofUtc: "2026-10-03 12:00:00+00" };

  it("states the week, the run and the data date, the last one as an instant", () => {
    expect(runContext(run)).toEqual([
      { label: "Week", value: "2024 season, week 15" },
      { label: "Run", value: "weekly-sim-2024-w15" },
      { label: "Data as of", value: "2026-10-03 12:00 UTC", iso: "2026-10-03 12:00:00+00" }
    ]);
  });

  it("can leave the week out for a page whose title already names it", () => {
    expect(runContext(run, { omitWeek: true }).map((i) => i.label)).toEqual(["Run", "Data as of"]);
  });

  it("does not invent a week for a run that has none", () => {
    expect(runContext({ ...run, week: null })[0]).toEqual({ label: "Week", value: "2024 season" });
    expect(runContext({ ...run, season: null, week: null })[0]).toEqual({ label: "Week", value: "not stated" });
  });
});

describe("noRunContext", () => {
  it("says there is no run and why the page has none", () => {
    expect(noRunContext("props are not priced yet")).toEqual([{ label: "Run", value: "none published (props are not priced yet)" }]);
  });
});

describe("backtestContext", () => {
  it("states the protocol, the run and the data date", () => {
    expect(backtestContext({ windowId: "nfl_games_v1", cycleId: "backtest-nfl-games-v1-7244a0bc", dataAsofUtc: "2026-09-29T20:51:29Z" })).toEqual([
      { label: "Protocol", value: "nfl_games_v1" },
      { label: "Run", value: "backtest-nfl-games-v1-7244a0bc" },
      { label: "Data as of", value: "2026-09-29 20:51 UTC", iso: "2026-09-29T20:51:29Z" }
    ]);
  });

  it("says when no protocol is recorded instead of printing nothing", () => {
    expect(backtestContext({ windowId: null, cycleId: "c", dataAsofUtc: "2026-09-29T20:51:29Z" })[0]).toEqual({ label: "Protocol", value: "not recorded" });
  });
});
```

<!-- apply: T2.1 create web/src/components/ui.test.tsx -->
```tsx
import type { ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Breadcrumb, Card, DataTable, Grid, Page, PageHeader, Section, Stamp, StatTile, Term } from "./ui";

const html = (el: ReactElement) => renderToStaticMarkup(el);

describe("Stamp", () => {
  it("draws an instant in a <time> with a machine-readable datetime", () => {
    expect(html(<Stamp iso="2026-10-03 12:00:00+00" />)).toBe('<time dateTime="2026-10-03T12:00:00.000Z">2026-10-03 12:00 UTC</time>');
  });
  it("says so when there is no instant", () => {
    expect(html(<Stamp iso={null} />)).toBe("–");
  });
});

describe("PageHeader", () => {
  const context = [
    { label: "Run", value: "weekly-sim-2024-w15" },
    { label: "Data as of", value: "ignored when iso is set", iso: "2026-10-03T12:00:00Z" }
  ];

  it("is one h1 in wide Archivo with the lead and the context line (run, week, data date)", () => {
    const out = html(<PageHeader title="Evidence" lead="What the test found." context={context} />);
    expect(out.match(/<h1/g)).toHaveLength(1);
    expect(out).toContain('<h1 class="wdth-expanded text-title font-black">Evidence</h1>');
    expect(out).toContain("max-w-measure");
    expect(out).toContain("data-context");
    expect(out).toContain("<dt>Run</dt>");
    expect(out).toContain('<time dateTime="2026-10-03T12:00:00.000Z">2026-10-03 12:00 UTC</time>');
    expect(out).not.toContain("ignored when iso is set");
  });

  it("has a hero and a compact size, and an aside beside it", () => {
    expect(html(<PageHeader title="Week 4" size="hero" />)).toContain("text-hero font-black");
    expect(html(<PageHeader title="Sign in" size="compact" />)).toContain("text-title-sm font-black");
    expect(html(<PageHeader title="Week 4" aside={<p>status</p>} />)).toContain("lg:w-aside");
    expect(html(<PageHeader title="Desk" actions={<button>Sign out</button>} />)).toContain("<button>Sign out</button>");
  });
});

describe("Section", () => {
  it("is a landmark named by its visible title", () => {
    const out = html(
      <Section id="gates" title="Promotion gates">
        <p>body</p>
      </Section>
    );
    expect(out).toContain('aria-labelledby="gates"');
    expect(out).toContain('<h2 id="gates" data-section-title="true" class="wdth-expanded text-heading font-bold">Promotion gates</h2>');
    expect(out).toContain("gap-control");
  });

  it("is named by a label when it has no title, and keeps a screen-reader-only title", () => {
    const labelled = html(
      <Section label="Sort and filter">
        <p>body</p>
      </Section>
    );
    expect(labelled).toContain('aria-label="Sort and filter"');
    expect(labelled).not.toContain("<h2");
    const hidden = html(
      <Section id="rel" title="Reliability" srTitle>
        <p>body</p>
      </Section>
    );
    expect(hidden).toContain('<h2 id="rel" data-section-title="true" class="sr-only">Reliability</h2>');
  });

  it("puts an aside on the title's row", () => {
    const out = html(
      <Section id="prob" title="Win probability" aside={<ul>legend</ul>}>
        <p>body</p>
      </Section>
    );
    expect(out).toMatch(/<div class="flex flex-wrap items-end justify-between gap-control"><h2[^>]*>Win probability<\/h2><ul>legend<\/ul><\/div>/);
  });
});

describe("Card, Grid and Page", () => {
  it("has one surface in three paddings and a sunken tone", () => {
    expect(html(<Card>x</Card>)).toBe('<div class="rounded-card border border-rule bg-surface p-card">x</div>');
    expect(html(<Card pad="sm" tone="sunken">x</Card>)).toBe('<div class="rounded-card border border-rule bg-sunken p-card-sm">x</div>');
    expect(html(<Card as="aside" aria-label="Model status">x</Card>)).toContain('<aside aria-label="Model status"');
  });

  it("fixes the grids and the page rhythm", () => {
    expect(html(<Grid kind="tiles">x</Grid>)).toContain("sm:grid-cols-3");
    expect(html(<Grid kind="fields">x</Grid>)).toContain("lg:grid-cols-2");
    expect(html(<Page>x</Page>)).toBe('<div data-page="true" class="flex flex-col gap-section">x</div>');
  });
});

describe("StatTile and Term", () => {
  it("prints the value, the label, the source line and a link to the term's definition", () => {
    const out = html(<StatTile value="0.2098" label={<>Market <Term id="brier">Brier score</Term></>} source="Backtest nfl_games_v1" />);
    expect(out).toContain("data-stat");
    expect(out).toContain("0.2098");
    expect(out).toContain('<span data-source="true" class="text-sm text-muted">Backtest nfl_games_v1</span>');
    expect(out).toContain('href="/methodology#term-brier"');
  });

  it("links a term to its definition and defaults the text to the term's label", () => {
    expect(html(<Term id="no-vig" />)).toContain('href="/methodology#term-no-vig">No-vig probability</a>');
    expect(html(<Term id="clv">CLV</Term>)).toContain(">CLV</a>");
  });
});

describe("DataTable", () => {
  const columns = [{ key: "candidate", header: "Candidate", rowHeader: true }, { key: "g1", header: "G1" }];
  const rows = [
    { key: "a", cells: { candidate: "Elo", g1: "Pass" } },
    { key: "b", cells: { candidate: "EPA", g1: "Fail" }, muted: true }
  ];

  it("has a caption, column scopes, a row header, a labelled scroll region and pass-through attributes", () => {
    const out = html(<DataTable caption="Promotion gates" columns={columns} rows={rows} data-desk="x" />);
    expect(out).toContain('<div tabindex="0" role="region" aria-label="Promotion gates (table)" class="overflow-x-auto">');
    expect(out).toContain('<caption class="sr-only">Promotion gates</caption>');
    expect(out.match(/<th scope="col"/g)).toHaveLength(2);
    expect(out).toContain('<tr class="border-t border-rule"><th scope="row">Elo</th><td>Pass</td></tr>');
    expect(out).toContain('<tr class="border-t border-rule text-ink-2"><th scope="row">EPA</th><td>Fail</td></tr>');
    expect(out).toContain('data-desk="x"');
    expect(out).toContain('class="data-table"');
  });

  it("can show its caption, scroll below a minimum width, and say so when it has no rows", () => {
    const out = html(<DataTable caption="Leans" showCaption columns={columns} rows={[]} empty={<span>No paper leans</span>} minWidth="table-wide" numeric topAligned dense />);
    expect(out).toContain('<caption class="data-table-caption">Leans</caption>');
    expect(out).toContain("min-w-tabular-wide");
    expect(out).toContain("data-table num data-table-dense data-table-top");
    expect(out).toContain('<td colSpan="2" class="text-ink-2"><span>No paper leans</span></td>');
  });

  it("keeps plain cells classless, as the chart table views have always been", () => {
    const out = html(<DataTable caption="Margin" columns={[{ key: "m", header: "Margin", rowHeader: true }, { key: "s", header: "Share" }]} rows={[{ key: "0", cells: { m: "Tie", s: "25.00%" } }]} />);
    expect(out).toContain("<td>25.00%</td>");
  });

  it("throws on a row that lacks a column's cell instead of drawing a hole", () => {
    expect(() => html(<DataTable caption="Gates" columns={columns} rows={[{ key: "x", cells: { candidate: "Elo" } }]} />)).toThrow(/row "x" has no cell for column "g1"/);
  });
});

describe("Breadcrumb", () => {
  it("links the earlier crumbs and marks the last as the current page", () => {
    const out = html(<Breadcrumb items={[{ label: "This week", href: "/" }, { label: "DEN at SF" }]} />);
    expect(out).toContain('<nav aria-label="Breadcrumb"');
    expect(out).toContain('<a class="text-ink-2" href="/">This week</a>');
    expect(out).toContain('aria-current="page"');
    expect(out.match(/aria-hidden="true">\//g)).toHaveLength(1);
  });
});
```

<!-- apply: T2.1 create web/src/test/tokenCeilings.json -->
```json
{
  "arbitrary": {
    "app/data-health/page.tsx": 1,
    "app/desk/page.tsx": 1,
    "app/evidence/page.tsx": 5,
    "app/games/[id]/page.tsx": 29,
    "app/layout.tsx": 1,
    "app/methodology/page.tsx": 1,
    "app/page.tsx": 11,
    "components/Field.tsx": 31,
    "components/NavLinks.tsx": 1,
    "components/SiteFooter.tsx": 1,
    "components/SiteHeader.tsx": 7,
    "components/ThemeToggle.tsx": 1,
    "components/charts/ChartFigure.tsx": 1,
    "components/charts/ChartTooltip.tsx": 1,
    "components/charts/LazyScoreDistributionPlot.tsx": 2,
    "components/charts/ScoreDistributionChart.tsx": 1,
    "components/charts/ScoreDistributionPlot.tsx": 1
  },
  "textPx": {
    "app/evidence/page.tsx": 2,
    "app/games/[id]/page.tsx": 15,
    "app/page.tsx": 6
  }
}
```

- [ ] **Step 2: Run the tests and see RED**

Run: `cd web && npx vitest run src/lib/glossary.test.ts src/lib/context.test.ts src/components/ui.test.tsx src/test/tokens.test.ts`
Expected: FAIL: `glossary.test.ts` and `context.test.ts` cannot import their modules, the `ui.test.tsx` cases fail, and the ratchet names `components/ui.tsx` and `components/DataUnavailable.tsx` (`Failed Tests 17` in all).

- [ ] **Step 3: Write the libraries and the components**

<!-- apply: T2.3 create web/src/lib/glossary.ts -->
```ts
/**
 * Plain-language definitions of the terms the pages use. A page links a term to its entry on
 * /methodology (the <Term> component) and the methodology page renders every entry, so a link
 * can never point at a missing definition. The sentences restate what the methodology and
 * evidence pages already say; none of them is a new claim.
 */
export const TERMS = {
  "no-vig": {
    label: "No-vig probability",
    definition:
      "The market's win probability with the bookmaker's margin removed. Each moneyline becomes an implied probability, and the two are rescaled in proportion so they add to 100%."
  },
  close: {
    label: "Closing line",
    definition:
      "The market's last price before kickoff. Here it is the nflverse consensus close, which carries no timestamp and no sportsbook name, so line movement cannot be drawn from it."
  },
  field: {
    label: "The field",
    definition:
      "A game drawn as a football field. The line splits it by win chance, so each team's side is its probability of winning. Blue is the no-vig market, gold is the model, and the hatched band is the gap between them."
  },
  gap: {
    label: "Model–market gap",
    definition: "The model's home win probability minus the no-vig market's, in percentage points (pts)."
  },
  unvalidated: {
    label: "Unvalidated",
    definition: "The line has not passed its pre-registered gates. Read it as research output, never as advice."
  },
  shrinkage: {
    label: "Shrinkage toward the market",
    definition:
      "The simulator's win probability after a 70% weight on the no-vig market (the pipeline's SHRINKAGE setting). A game without a market line shows the unshrunk value."
  },
  brier: {
    label: "Brier score",
    definition:
      "The average squared gap between a predicted win probability and the result (1 if the home team won, 0 if not). Lower is better. A forecast of 50% every time scores 0.25."
  },
  skill: {
    label: "Brier skill against the market",
    definition:
      "One minus the candidate's Brier score divided by the market's. Zero means the candidate scored exactly as well as the market; above zero is better and below zero is worse."
  },
  interval: {
    label: "95% interval",
    definition:
      "A 95% range from a paired week-block bootstrap: 10,000 resamples of whole weeks, with the candidate and the market scored on the same ones. An interval that includes zero cannot be told apart from no difference."
  },
  ece: {
    label: "Expected calibration error (ECE)",
    definition:
      "How far predicted probabilities sit from the share of games the home team actually won, averaged over ten bins that each hold the same number of games. Lower is better."
  },
  clv: {
    label: "Closing-line value (CLV)",
    definition:
      "How far the no-vig price moved toward a pick between the opener and the close, in basis points: 10,000 × (close − open), both no-vig at the same venue. Positive means the price moved toward the pick."
  },
  "walk-forward": {
    label: "Walk-forward",
    definition:
      "Each week is predicted with a model fit only on games that kicked off before that week. A guard rejects any input that finished after kickoff."
  },
  holdout: {
    label: "Sealed holdout",
    definition: "The 2025 games, kept unscored until the protocol allows one single look."
  }
} as const satisfies Record<string, { label: string; definition: string }>;

export type TermId = keyof typeof TERMS;
export const TERM_IDS = Object.keys(TERMS) as TermId[];

/** The element id of a term's definition on the methodology page. */
export function termAnchor(id: TermId): string {
  return `term-${id}`;
}

/** Where a term is defined. */
export function termHref(id: TermId): string {
  return `/methodology#${termAnchor(id)}`;
}
```

<!-- apply: T2.3 create web/src/lib/context.ts -->
```ts
import { utcStamp } from "./format";

/** One labelled fact in the line under a page title: which run, which week, how fresh the data is. */
export interface ContextItem {
  label: string;
  value: string;
  /** An instant: the value is then drawn inside a <time> element carrying this datetime. */
  iso?: string | null;
}

/** The fields of a published run that the context line needs. */
export interface RunLike {
  season: number | null;
  week: number | null;
  cycleId: string;
  dataAsofUtc: string;
}

/**
 * What a weekly run is and how old its data is; every page that shows run data states it.
 * `omitWeek` is for a page whose own title already names the week (a game's breadcrumb).
 */
export function runContext(run: RunLike, options: { omitWeek?: boolean } = {}): ContextItem[] {
  const season = run.season === null ? "" : `${run.season} season`;
  const week = run.week === null ? season : `${season}${season ? ", " : ""}week ${run.week}`;
  return [
    ...(options.omitWeek ? [] : [{ label: "Week", value: week || "not stated" }]),
    { label: "Run", value: run.cycleId },
    { label: "Data as of", value: utcStamp(run.dataAsofUtc), iso: run.dataAsofUtc }
  ];
}

/** For a page that has no run to show: say so, never leave the line out. */
export function noRunContext(what: string): ContextItem[] {
  return [{ label: "Run", value: `none published (${what})` }];
}

/** What a backtest is and how old its data is: the protocol it was scored under, the run and the data date. */
export function backtestContext(ev: { windowId: string | null; cycleId: string; dataAsofUtc: string }): ContextItem[] {
  return [
    { label: "Protocol", value: ev.windowId ?? "not recorded" },
    { label: "Run", value: ev.cycleId },
    { label: "Data as of", value: utcStamp(ev.dataAsofUtc), iso: ev.dataAsofUtc }
  ];
}
```

<!-- apply: T2.3 create web/src/components/ui.tsx -->
```tsx
/**
 * Broadcast Line layout primitives. Every page is built from these, so type, spacing and radius
 * come from the tokens in globals.css (type roles, spacing roles, radius, measure) and a page
 * never picks a size of its own: a page is a <Page> of <Section>s under one <PageHeader>, cards
 * are <Card>, tables are <DataTable>, a headline number is a <StatTile>. Colour comes only from
 * the colour tokens, so the press-box (light) and night-game (dark) themes apply everywhere.
 */
import Link from "next/link";
import type { ComponentPropsWithoutRef, ReactNode } from "react";
import type { ContextItem } from "@/lib/context";
import { utcStamp } from "@/lib/format";
import { TERMS, type TermId, termHref } from "@/lib/glossary";

/** An instant as text, inside a <time> so its machine-readable value travels with it. */
export function Stamp({ iso }: { iso: string | null | undefined }) {
  if (!iso) return <>–</>;
  return <time dateTime={new Date(iso).toISOString()}>{utcStamp(iso)}</time>;
}

/** A term, linked to its definition on /methodology. */
export function Term({ id, children }: { id: TermId; children?: ReactNode }) {
  return (
    <Link href={termHref(id)} className="decoration-dotted">
      {children ?? TERMS[id].label}
    </Link>
  );
}

/** The line under a page title: which run, which week and how fresh its data is. */
export function ContextList({ items }: { items: ContextItem[] }) {
  return (
    <dl data-context className="flex flex-wrap gap-x-stack gap-y-tight text-sm text-muted">
      {items.map((item) => (
        <div key={item.label} className="flex gap-snug">
          <dt>{item.label}</dt>
          <dd className="num text-ink-2">{item.iso ? <Stamp iso={item.iso} /> : item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

/** The sections of a page, one section gap apart. Every page returns one. */
export function Page({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div data-page className={`flex flex-col gap-section ${className}`.trim()}>
      {children}
    </div>
  );
}

const H1 = {
  hero: "text-hero font-black",
  page: "text-title font-black",
  compact: "text-title-sm font-black"
} as const;

/**
 * A page's title block: the h1 in wide Archivo, an optional lead, and the context line (run,
 * week and data date). `aside` is a card beside it on a wide screen (the home page's model
 * status); `actions` are small controls at its end (the desk's sign-out).
 */
export function PageHeader({
  title,
  lead,
  context,
  aside,
  actions,
  size = "page"
}: {
  title: ReactNode;
  lead?: ReactNode;
  context?: ContextItem[];
  aside?: ReactNode;
  actions?: ReactNode;
  size?: keyof typeof H1;
}) {
  return (
    <header data-page-header className="flex flex-col gap-section lg:flex-row lg:items-end lg:justify-between">
      <div className="flex min-w-0 flex-col gap-control">
        <h1 className={`wdth-expanded ${H1[size]}`}>{title}</h1>
        {lead ? <div className="max-w-measure text-lg text-ink-2 text-pretty">{lead}</div> : null}
        {context ? <ContextList items={context} /> : null}
      </div>
      {aside ? <div className="w-full lg:w-aside lg:shrink-0">{aside}</div> : null}
      {actions ? <div className="flex flex-wrap items-center gap-control lg:shrink-0">{actions}</div> : null}
    </header>
  );
}

/** A section's heading (h2) in wide Archivo; `srOnly` keeps it for assistive technology only. */
export function SectionTitle({ id, children, srOnly = false }: { id: string; children: ReactNode; srOnly?: boolean }) {
  return (
    <h2 id={id} data-section-title className={srOnly ? "sr-only" : "wdth-expanded text-heading font-bold"}>
      {children}
    </h2>
  );
}

type SectionProps = { children: ReactNode; className?: string; measure?: boolean } & (
  | { id: string; title: ReactNode; srTitle?: boolean; aside?: ReactNode; label?: never }
  | { label: string; id?: string; title?: never; srTitle?: never; aside?: never }
);

/**
 * One section of a page: a landmark named by its title (or by a label when it has none), the title
 * a control gap above its content. `aside` sits on the title's row (a legend, a count).
 */
export function Section(props: SectionProps) {
  const { children, className = "", measure = false } = props;
  const title =
    props.label === undefined ? (
      <SectionTitle id={props.id} srOnly={props.srTitle}>
        {props.title}
      </SectionTitle>
    ) : null;
  return (
    <section
      data-section
      aria-labelledby={title ? props.id : undefined}
      aria-label={title ? undefined : props.label}
      className={`flex flex-col gap-control ${measure ? "max-w-measure" : ""} ${className}`.trim()}
    >
      {title && props.aside ? (
        <div className="flex flex-wrap items-end justify-between gap-control">
          {title}
          {props.aside}
        </div>
      ) : (
        title
      )}
      {children}
    </section>
  );
}

const GRID = {
  tiles: "grid gap-stack sm:grid-cols-3",
  pair: "grid gap-stack md:grid-cols-2",
  fields: "grid gap-stack lg:grid-cols-2",
  sections: "grid gap-section lg:grid-cols-2"
} as const;

/** A grid of cards or sections: the column counts and gap are fixed here, not chosen per page. */
export function Grid({ kind, children }: { kind: keyof typeof GRID; children: ReactNode }) {
  return <div className={GRID[kind]}>{children}</div>;
}

const PAD = { card: "p-card", sm: "p-card-sm", none: "" } as const;

/** The one bordered surface: a card (20px padding), a dense card (16px), or a sunken empty state. */
export function Card({
  as: Tag = "div",
  tone = "surface",
  pad = "card",
  className = "",
  ...rest
}: ComponentPropsWithoutRef<"div"> & { as?: "div" | "article" | "aside" | "section"; tone?: "surface" | "sunken"; pad?: keyof typeof PAD }) {
  return <Tag {...rest} className={`rounded-card border border-rule ${tone === "sunken" ? "bg-sunken" : "bg-surface"} ${PAD[pad]} ${className}`.trim()} />;
}

/**
 * A headline number with what it counts (the label, unit included) and where it comes from (the
 * source line). A term the label uses is linked to its definition on /methodology with <Term>.
 */
export function StatTile({ value, label, source }: { value: ReactNode; label: ReactNode; source?: ReactNode }) {
  return (
    <Card data-stat className="flex flex-col gap-tight">
      <span className="num wdth-expanded text-stat font-extrabold">{value}</span>
      <span className="text-sm text-ink-2">{label}</span>
      {source ? (
        <span data-source className="text-sm text-muted">
          {source}
        </span>
      ) : null}
    </Card>
  );
}

export interface DataColumn {
  /** Names the column: a row gives its cell under this key (an object, so no array of elements needs keys). */
  key: string;
  header: ReactNode;
  /** The first column only: its cells become row headers (<th scope="row">). */
  rowHeader?: boolean;
  nowrap?: boolean;
}

export interface DataRow {
  key: string;
  /** One cell per column, under the column's key. A missing key is a mistake and throws, never an empty cell. */
  cells: Record<string, ReactNode>;
  /** A summary or remainder row drawn in secondary ink. */
  muted?: boolean;
}

/**
 * Every table. It carries a caption (hidden unless `showCaption`), column headers with scope, an
 * optional row-header column, and sits in a keyboard-scrollable region named "<caption> (table)", so
 * it never shares a landmark name with the section around it. Padding comes
 * from the row and cell tokens (`.data-table` in globals.css); dense is for long chart tables.
 */
export function DataTable({
  caption,
  showCaption = false,
  columns,
  rows,
  empty,
  minWidth,
  dense = false,
  numeric = false,
  topAligned = false,
  ...tableProps
}: {
  caption: string;
  showCaption?: boolean;
  columns: DataColumn[];
  rows: DataRow[];
  empty?: ReactNode;
  minWidth?: "table" | "table-wide";
  dense?: boolean;
  numeric?: boolean;
  topAligned?: boolean;
} & Omit<ComponentPropsWithoutRef<"table">, "children" | "className">) {
  const cls = ["data-table", numeric ? "num" : "", dense ? "data-table-dense" : "", topAligned ? "data-table-top" : "", minWidth === "table" ? "min-w-tabular" : "", minWidth === "table-wide" ? "min-w-tabular-wide" : ""]
    .filter(Boolean)
    .join(" ");
  return (
    <div tabIndex={0} role="region" aria-label={`${caption} (table)`} className="overflow-x-auto">
      <table {...tableProps} className={cls}>
        <caption className={showCaption ? "data-table-caption" : "sr-only"}>{caption}</caption>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key} scope="col" className={c.nowrap ? "whitespace-nowrap" : undefined}>
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 && empty ? (
            <tr className="border-t border-rule">
              <td colSpan={columns.length} className="text-ink-2">
                {empty}
              </td>
            </tr>
          ) : null}
          {rows.map((r) => (
            <tr key={r.key} className={r.muted ? "border-t border-rule text-ink-2" : "border-t border-rule"}>
              {columns.map((c, i) => {
                if (!(c.key in r.cells)) throw new Error(`DataTable "${caption}": row "${r.key}" has no cell for column "${c.key}"`);
                const cell = r.cells[c.key];
                return i === 0 && c.rowHeader ? (
                  <th key={c.key} scope="row" className={c.nowrap ? "whitespace-nowrap" : undefined}>
                    {cell}
                  </th>
                ) : (
                  <td key={c.key} className={c.nowrap ? "whitespace-nowrap" : undefined}>
                    {cell}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Where this page sits: the last crumb is the current page. */
export function Breadcrumb({ items }: { items: { label: ReactNode; href?: string }[] }) {
  return (
    <nav aria-label="Breadcrumb" className="text-sm text-muted">
      <ol className="flex flex-wrap items-center gap-x-snug">
        {items.map((item, i) => {
          const last = i === items.length - 1;
          return (
            <li key={i} className="flex items-center gap-snug">
              {item.href && !last ? (
                <Link href={item.href} className="text-ink-2">
                  {item.label}
                </Link>
              ) : (
                <span aria-current={last ? "page" : undefined} className={last ? "text-ink" : undefined}>
                  {item.label}
                </span>
              )}
              {last ? null : <span aria-hidden>/</span>}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

/** A 44px segment chip (sort, day, window and candidate pickers, the theme choice); `on` is the current choice. */
export function chipClass(on: boolean): string {
  return `inline-flex h-11 items-center rounded-control border px-control text-sm no-underline ${on ? "border-ink bg-ink font-semibold text-surface" : "border-rule text-ink-2 hover:border-ink-2"}`;
}

/** The ink button: the header's Desk link, the sign-in button. */
export const BUTTON_CLASS = "inline-flex h-11 items-center rounded-control border border-ink bg-ink px-4 text-sm font-semibold text-surface no-underline";

/** A quiet bordered button (secondary actions). */
export const QUIET_BUTTON_CLASS = "inline-flex h-11 items-center rounded-control border border-rule px-4 text-sm text-ink";

export const INPUT_CLASS = "mt-tight block h-11 w-full rounded-control border border-rule bg-surface px-4 text-ink";

/** @deprecated The previous page title; pages move to PageHeader and this goes in the last task of Track B2. */
export function PageTitle({ children, lead, compact = false }: { children: ReactNode; lead?: ReactNode; compact?: boolean }) {
  return <PageHeader title={children} lead={lead} size={compact ? "compact" : "page"} />;
}
```

<!-- apply: T2.3 create web/src/components/DataUnavailable.tsx -->
```tsx
import { Card } from "@/components/ui";

/** An honest empty state: what is missing, why, and what would fill it. */
export function DataUnavailable({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Card tone="sunken" pad="sm" className="flex flex-col gap-tight">
      <p className="font-medium">{title}</p>
      <div className="text-sm text-ink-2">{children}</div>
    </Card>
  );
}
```

The component CSS goes after the skip link: the table rules, the stretched-link card, and the mark on a definition you arrive at. They are unlayered or in the components layer on purpose: the global `:focus-visible` rule is unlayered, so a card's focus rule must be unlayered too to outrank it, and the table rules sit in the components layer so a utility still wins over them.

<!-- apply: T2.3 replace web/src/app/globals.css -->
```css
.skip-link:focus { transform: none; }

@media (prefers-reduced-motion: reduce) {
```

```css
.skip-link:focus { transform: none; }

/* The definition a term link lands on is marked, so a reader sees which entry they came for. */
[id^="term-"]:target { background: var(--surface-sunken); outline: 2px solid var(--rule); outline-offset: 4px; }

/* A card whose whole surface is its link (a game strip): the title link stretches over the card, and
   the card, not the title text, shows the focus ring. Unlayered, so it outranks the global focus rule. */
.card-link:hover { border-color: var(--ink-2); }
.card-link:has(a:focus-visible) { outline: 2px solid var(--focus); outline-offset: 2px; }
.card-link a:focus-visible { outline: none; }

/* Component rules. Tailwind utilities (the utilities layer) still win over them. */
@layer components {
  .data-table {
    width: 100%;
    border-collapse: collapse;
    text-align: left;
    font-size: 0.875rem;
    line-height: 1.25rem;
  }
  .data-table th,
  .data-table td {
    padding: var(--spacing-row) var(--spacing-cell) var(--spacing-row) 0;
    text-align: left;
    font-weight: 400;
  }
  .data-table th:last-child,
  .data-table td:last-child {
    padding-right: 0;
  }
  .data-table thead th {
    padding-top: 0;
    color: var(--ink-2);
  }
  .data-table-dense th,
  .data-table-dense td {
    padding-top: calc(var(--spacing-row) / 2);
    padding-bottom: calc(var(--spacing-row) / 2);
  }
  .data-table-top th,
  .data-table-top td {
    vertical-align: top;
  }
  .data-table-caption {
    padding-bottom: var(--spacing-snug);
    text-align: left;
    font-weight: 500;
  }
}

@media (prefers-reduced-motion: reduce) {
```

The design-language test accepts the new title component while pages move over (Task 12 tightens it):

<!-- apply: T2.3 replace web/src/test/designLanguage.test.ts -->
```ts
      const titled = /import \{[^}]*\bPageTitle\b[^}]*\} from "@\/components\/ui"/.test(src) && src.includes("<PageTitle");
```

```ts
      const titled = /import \{[^}]*\b(?:PageTitle|PageHeader)\b[^}]*\} from "@\/components\/ui"/.test(src) && (src.includes("<PageTitle") || src.includes("<PageHeader"));
```

- [ ] **Step 4: Run the tests and see GREEN**

Run: `cd web && npx vitest run src/lib/glossary.test.ts src/lib/context.test.ts src/components/ui.test.tsx src/test/tokens.test.ts src/test/designLanguage.test.ts`
Expected: `Test Files  5 passed (5)`, `Tests  36 passed (36)`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  22 passed (22)`, `Tests  159 passed (159)`.

```bash
git add web/src
git commit -m "feat(web): Page, PageHeader, Section, Card, StatTile and DataTable, the glossary and the context lines (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: `publicGates()` and `cache()` on the shared queries [haiku]

The home and game pages used `evidence()` (seven queries: the pointer, the backtest run, the window, the metrics, the calibration bins, the gates and the CLV picks) only to read the gates for `publicFieldLine`. `publicGates()` reads exactly that in one joined query, and React `cache()` makes `pointerRun`, `publicSlate` and `publicGame` run once per request (the layout, the page and `generateMetadata` ask for the same rows). Outside a server render `cache` is a plain call, so the tests below still see every query.

The effect on the pages is a shorter chain of round trips (counted from the code, the game page goes from ten sequential round trips to four: the slate and the gates together, the candidate list, then the lines and the distributions together). It does **not** move the simulated mobile LCP: the server answers in well under 150 ms, and Lighthouse's simulation is dominated by bytes and hydration (Task 13 has the measurements).

**Files:**
- Modify: `web/src/lib/data/queries.ts`, `web/src/lib/data/queries.test.ts`

**Interfaces:**
- Produces: `publicGates(): Promise<GateRow[]>` (`{ candidate, brierStatus }`, ordered by candidate, empty when no backtest is published); `pointerRun`, `publicSlate` and `publicGame` keep their signatures and become cached.

- [ ] **Step 1: Write the failing tests** (the two Postgres cases: one query against seven, and empty rather than an error before any backtest)

<!-- apply: T3.1 create web/src/lib/data/queries.test.ts -->
```ts
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { FIXTURE_BUNDLES, freshDb, hasDb, TEST_DATABASE_URL } from "../../test/pg";
import { ingestBundle, loadBundle } from "../ingest/ingest";

/** Every key anywhere in a value (objects and arrays, recursively). */
function keys(v: unknown, out = new Set<string>()): Set<string> {
  if (Array.isArray(v)) v.forEach((x) => keys(x, out));
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { out.add(k); keys(x, out); }
  return out;
}
const PRIVATE_KEY = /stake|^ev$|recommend|kelly|pass_?reason/i;

describe.skipIf(!hasDb)("public queries never carry stakes (Postgres)", () => {
  let q: typeof import("./queries");
  let db: typeof import("../../db");

  beforeAll(async () => {
    const { db: tdb, client } = await freshDb();
    await ingestBundle(tdb, loadBundle(join(FIXTURE_BUNDLES, "weekly-2026-w04")));
    await ingestBundle(tdb, loadBundle(join(FIXTURE_BUNDLES, "backtest-nfl-games-v1")));
    await client.end({ timeout: 5 });
    process.env.DATABASE_URL = TEST_DATABASE_URL;
    db = await import("../../db");
    q = await import("./queries");
  });
  afterAll(async () => {
    await db?.closeDb();
  });

  it("the weekly fixture really has staked-shape recommendations to leak", async () => {
    const desk = await q.deskSlate();
    expect(desk.recs.length).toBeGreaterThan(0);
    expect([...keys(desk.recs)].some((k) => PRIVATE_KEY.test(k))).toBe(true);
  });

  it("publicSlate, publicGame, candidateLines, evidence, ledger and dataHealth expose no private field", async () => {
    const slate = await q.publicSlate();
    expect(slate.games.length).toBe(16);
    const results = {
      slate,
      game: await q.publicGame(slate.games[0]!.gameId),
      lines: await q.candidateLines(slate.run!.runId, ["C0"]),
      evidence: await q.evidence(),
      ledger: await q.ledger(),
      health: await q.dataHealth()
    };
    for (const [name, value] of Object.entries(results)) {
      const leaked = [...keys(value)].filter((k) => PRIVATE_KEY.test(k));
      expect(leaked, name).toEqual([]);
    }
  });

  it("publicGates gives the field-line policy its gates in one query, where evidence() needs seven", async () => {
    const select = vi.spyOn(db.getDb(), "select");
    const gates = await q.publicGates();
    expect(select).toHaveBeenCalledTimes(1);
    select.mockClear();
    const ev = await q.evidence();
    expect(select).toHaveBeenCalledTimes(7); // pointer, backtest run, window, metrics, bins, gates, clv
    select.mockRestore();
    const byCandidate = (a: { candidate: string }, b: { candidate: string }) => a.candidate.localeCompare(b.candidate);
    expect(gates.length).toBeGreaterThan(0);
    expect([...gates].sort(byCandidate)).toEqual(ev!.gates.map((g) => ({ candidate: g.candidate, brierStatus: g.brierStatus })).sort(byCandidate));
    expect(Object.keys(gates[0]!).sort()).toEqual(["brierStatus", "candidate"]);
  });
});

describe.skipIf(!hasDb)("publicGates before any backtest is published (Postgres)", () => {
  let q: typeof import("./queries");
  let db: typeof import("../../db");

  beforeAll(async () => {
    const { db: tdb, client } = await freshDb();
    await ingestBundle(tdb, loadBundle(join(FIXTURE_BUNDLES, "weekly-2026-w04")));
    await client.end({ timeout: 5 });
    process.env.DATABASE_URL = TEST_DATABASE_URL;
    db = await import("../../db");
    q = await import("./queries");
  });
  afterAll(async () => {
    await db?.closeDb();
  });

  it("is empty, not an error, exactly as evidence() was null", async () => {
    expect(await q.publicGates()).toEqual([]);
    expect(await q.evidence()).toBeNull();
  });
});
```

- [ ] **Step 2: Run the tests and see RED**

Run: `cd web && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run src/lib/data/queries.test.ts`
Expected: FAIL, `Failed Tests 2`: `TypeError: q.publicGates is not a function` in both new cases.

- [ ] **Step 3: Write the queries**

<!-- apply: T3.3 create web/src/lib/data/queries.ts -->
```ts
/**
 * Read-side queries. Every public function selects explicit public columns: no
 * stake, EV or recommendation column is reachable from a public page (tested in
 * queries.test.ts and e2e/public-no-stakes.spec.ts). Desk functions are separate and
 * are called only after requireUser().
 */
import { and, asc, desc, eq, inArray } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import { cache } from "react";
import { getDb } from "../../db";
import * as s from "../../db/schema";
import { deskCandidate, type GateRow } from "../policy";

/*
 * React cache() makes a query that several parts of one page render ask for (the layout, the
 * page and its generateMetadata) run once per request. Outside a server render it is a plain
 * call, so the tests below see every query.
 */
export const pointerRun = cache(async (pointer: "weekly" | "backtest_games") => {
  const db = getDb();
  const rows = await db
    .select({ run: s.modelRuns })
    .from(s.publishPointers)
    .innerJoin(s.modelRuns, eq(s.modelRuns.runId, s.publishPointers.runId))
    .where(eq(s.publishPointers.pointer, pointer));
  return rows[0]?.run ?? null;
});

export interface SlateGame {
  gameId: string;
  season: number;
  week: number;
  kickoffUtc: string;
  homeTeamId: string;
  awayTeamId: string;
  homeName: string;
  awayName: string;
  homeTz: string | null;
  neutral: boolean;
  homeScore: number | null;
  awayScore: number | null;
  pMarket: number | null;
}

/** Public slate: games of the published weekly run with the no-vig market only. */
export const publicSlate = cache(async (): Promise<{ run: Awaited<ReturnType<typeof pointerRun>>; games: SlateGame[] }> => {
  const run = await pointerRun("weekly");
  if (!run) return { run: null, games: [] };
  const db = getDb();
  const home = aliasTeams("home");
  const away = aliasTeams("away");
  const rows = await db
    .select({
      gameId: s.games.gameId, season: s.games.season, week: s.games.week, kickoffUtc: s.games.kickoffUtc,
      homeTeamId: s.games.homeTeamId, awayTeamId: s.games.awayTeamId, neutral: s.games.neutral,
      homeScore: s.games.homeScore, awayScore: s.games.awayScore,
      homeName: home.fullName, awayName: away.fullName, homeTz: home.tz,
      pMarket: s.gamePredictions.pHomeMktNovig
    })
    .from(s.gamePredictions)
    .innerJoin(s.games, eq(s.games.gameId, s.gamePredictions.gameId))
    .innerJoin(home, eq(home.teamId, s.games.homeTeamId))
    .innerJoin(away, eq(away.teamId, s.games.awayTeamId))
    .where(and(eq(s.gamePredictions.runId, run.runId), eq(s.gamePredictions.candidate, "C0")))
    .orderBy(asc(s.games.kickoffUtc), asc(s.games.gameId));
  return { run, games: rows };
});

/** Candidate probabilities for games of the published weekly run (restricted list). */
export async function candidateLines(runId: string, candidates: string[], gameIds?: string[]) {
  if (!candidates.length) return [];
  const db = getDb();
  const conds = [eq(s.gamePredictions.runId, runId), inArray(s.gamePredictions.candidate, candidates)];
  if (gameIds?.length) conds.push(inArray(s.gamePredictions.gameId, gameIds));
  return db
    .select({ gameId: s.gamePredictions.gameId, candidate: s.gamePredictions.candidate, p: s.gamePredictions.pHomeFinal })
    .from(s.gamePredictions)
    .where(and(...conds));
}

/** Candidate ids a run carries (public: ids only), for the field-line policy. */
export async function runCandidates(runId: string): Promise<string[]> {
  const rows = await getDb()
    .selectDistinct({ candidate: s.gamePredictions.candidate })
    .from(s.gamePredictions)
    .where(eq(s.gamePredictions.runId, runId))
    .orderBy(asc(s.gamePredictions.candidate));
  return rows.map((r) => r.candidate);
}

/** One game's simulated score distributions in a run (public: outcomes and shares only). */
export async function gameDistributions(runId: string, gameId: string): Promise<{ margin: unknown; total: unknown }> {
  const rows = await getDb()
    .select({ kind: s.scoreDistributions.kind, bins: s.scoreDistributions.bins })
    .from(s.scoreDistributions)
    .where(and(eq(s.scoreDistributions.runId, runId), eq(s.scoreDistributions.gameId, gameId)));
  return {
    margin: rows.find((r) => r.kind === "margin")?.bins ?? null,
    total: rows.find((r) => r.kind === "total")?.bins ?? null
  };
}

export const publicGame = cache(async (gameId: string) => {
  const { run, games } = await publicSlate();
  const game = games.find((g) => g.gameId === gameId) ?? null;
  return { run, game };
});

/**
 * The promotion gates of the published backtest, as far as the public field-line policy reads
 * them (candidate and Brier status), in one query. The home and game pages need only this,
 * not the seven queries of evidence(); with no published backtest it is empty, as
 * evidence() being null was.
 */
export const publicGates = cache(async (): Promise<GateRow[]> => {
  return getDb()
    .select({ candidate: s.promotionGates.candidate, brierStatus: s.promotionGates.brierStatus })
    .from(s.publishPointers)
    .innerJoin(s.backtestRuns, eq(s.backtestRuns.runId, s.publishPointers.runId))
    .innerJoin(s.promotionGates, eq(s.promotionGates.btRunId, s.backtestRuns.btRunId))
    .where(eq(s.publishPointers.pointer, "backtest_games"))
    .orderBy(asc(s.promotionGates.candidate));
});

export async function evidence() {
  const db = getDb();
  const run = await pointerRun("backtest_games");
  if (!run) return null;
  const bt = (await db.select().from(s.backtestRuns).where(eq(s.backtestRuns.runId, run.runId)))[0];
  if (!bt) return null;
  const [window] = await db.select().from(s.evalWindows).where(eq(s.evalWindows.windowId, bt.windowId));
  const metrics = await db.select().from(s.backtestMetrics).where(eq(s.backtestMetrics.btRunId, bt.btRunId));
  const bins = await db
    .select()
    .from(s.calibrationBins)
    .where(eq(s.calibrationBins.btRunId, bt.btRunId))
    .orderBy(asc(s.calibrationBins.candidate), asc(s.calibrationBins.bin));
  const gates = await db.select().from(s.promotionGates).where(eq(s.promotionGates.btRunId, bt.btRunId));
  const clv = await db
    .select({ candidate: s.clvPicks.candidate, clvBps: s.clvPicks.clvBps, units: s.clvPicks.units })
    .from(s.clvPicks)
    .where(eq(s.clvPicks.btRunId, bt.btRunId));
  return { run, bt, window: window ?? null, metrics, bins, gates, clv };
}

export async function ledger() {
  return getDb().select().from(s.evidenceLedger).orderBy(asc(s.evidenceLedger.claimId));
}

export async function dataHealth() {
  const db = getDb();
  const run = await pointerRun("weekly");
  const sources = run ? await db.select().from(s.sourceStatus).where(eq(s.sourceStatus.runId, run.runId)).orderBy(asc(s.sourceStatus.source)) : [];
  const ingests = await db.select().from(s.bundleIngests).orderBy(desc(s.bundleIngests.ingestedAt)).limit(10);
  const runs = await db
    .select({ runId: s.modelRuns.runId, kind: s.modelRuns.kind, status: s.modelRuns.status, qaOk: s.modelRuns.qaOk,
              qaFailures: s.modelRuns.qaFailures, generatedUtc: s.modelRuns.generatedUtc, dataAsofUtc: s.modelRuns.dataAsofUtc,
              codeGitSha: s.modelRuns.codeGitSha, codeDirty: s.modelRuns.codeDirty, modelLabel: s.modelRuns.modelLabel })
    .from(s.modelRuns)
    .orderBy(desc(s.modelRuns.generatedUtc))
    .limit(10);
  return { run, sources, ingests, runs };
}

// ---------------------------------------------------------------------------
// Desk (private): call only after requireUser()
// ---------------------------------------------------------------------------

export async function deskSlate() {
  const { run, games } = await publicSlate();
  if (!run) return { run, games, candidate: null as string | null, lines: [], recs: [] };
  const candidate = deskCandidate(await runCandidates(run.runId));
  const lines = candidate ? await candidateLines(run.runId, [candidate]) : [];
  const recs = await getDb().select().from(s.recommendations).where(eq(s.recommendations.runId, run.runId));
  return { run, games, candidate, lines, recs };
}

function aliasTeams(name: string) {
  return alias(s.teams, name);
}
```

- [ ] **Step 4: Run the tests and see GREEN**

Run: `cd web && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run src/lib/data/queries.test.ts`
Expected: `Test Files  1 passed (1)`, `Tests  4 passed (4)`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  22 passed (22)`, `Tests  161 passed (161)`.

```bash
git add web/src/lib/data
git commit -m "perf(web): publicGates() in one query, cache() on the queries a page shares (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: The chrome: a two-row header, one-line navigation and a theme the server renders [sonnet]

Three bugs from the audit live in the header and the layout, and one decision sits behind them.

- **The header.** On a 390 px phone it was 229 px tall and four visual rows: the wordmark, the theme select with the Desk button, then the five navigation labels wrapped onto two lines. Now it is two rows below `lg` (the wordmark and the Desk button, then the navigation) and one row from `lg` up. The five labels are one line at every width: `justify-between` with a 10 px minimum gap fits all five at 390 px (their widths sum to 312 px of the 358 available), and a 320 or 360 px phone scrolls the row inside its own box instead of wrapping or widening the page. Each link is a 44 px target (64 px from `lg`). The Desk button now uses `BUTTON_CLASS` instead of a second copy of it (Task 12's design-language test keeps it that way).
- **The theme.** It was applied by a `useEffect` after hydration, so a viewer who chose the other theme saw a flash. Now it is a cookie (`bl-theme`) that the root layout reads (`cookies()`) and renders onto `<html data-theme>`, so the first byte already has the colours; "system" is no cookie and no attribute. The control is three 44 px chips in the footer, in a plain `<form method="post" action="/theme">`. A server action was tried first and lost a tap that landed during hydration (1 of 4 at delay 0 under 4x CPU: the cookie was set, the page did not repaint); a plain form post does not wait for hydration, works with no JavaScript, and `app/theme/route.ts` answers with a 303 back to the page the form came from (at `#theme`), after checking that the post is same-origin (the `Host` header against `Origin`: Next's `nextUrl.origin` says `localhost` whatever host the browser used) and redirecting by a relative path that `safeBackPath` has checked.
- **The layout.** `main` gets the `gutter` and `page-top` tokens (48 px above the first block on every page) and `max-w-page`.

**Files:**
- Create: `web/src/lib/theme.ts`, `web/src/lib/theme.test.ts`, `web/src/lib/themeCookie.ts`, `web/src/app/theme/route.ts`, `web/e2e/theme.spec.ts`, `web/e2e/header.spec.ts`
- Modify: `web/src/components/ThemeToggle.tsx` (rewritten as a server component, not deleted), `web/src/components/SiteFooter.tsx`, `web/src/components/SiteHeader.tsx`, `web/src/components/NavLinks.tsx`, `web/src/app/layout.tsx`, `web/src/test/tokenCeilings.json`

**Interfaces:**
- Consumes: `chipClass`, `BUTTON_CLASS` (Task 2) and the tokens.
- Produces: `THEMES`, `parseTheme`, `themeAttribute`, `safeBackPath`, `THEME_COOKIE`, `THEME_ANCHOR` (`lib/theme.ts`); `readTheme()` (server components only); `POST /theme`; `ThemeToggle({ theme })`; `SiteFooter({ theme })`.

- [ ] **Step 1: Write the failing tests** (unit, e2e and the lowered ceilings)

<!-- apply: T4.1 create web/src/lib/theme.test.ts -->
```ts
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
    for (const bad of ["https://evil.example/phish", "http://127.0.0.1:3001/", "//evil.example", "javascript:alert(1)", "not a url", "", null, undefined]) {
      expect(safeBackPath(bad, host), String(bad)).toBe("/#theme");
    }
    expect(safeBackPath("http://127.0.0.1:3000/evidence", null)).toBe("/#theme");
  });
});
```

<!-- apply: T4.1 create web/e2e/theme.spec.ts -->
```ts
import { expect, test } from "@playwright/test";

/**
 * The theme is a cookie that the server reads and renders onto <html data-theme> (lib/theme.ts,
 * app/theme/route.ts), so the first byte of a page already has its colours: no flash, and no inline
 * script of ours. Before Track B2 a script applied it after hydration, which flashed.
 */
const COOKIE = "bl-theme";

test("the server renders the theme from the cookie, and ignores a value it does not know", async ({ request }) => {
  const dark = await (await request.get("/", { headers: { cookie: `${COOKIE}=dark` } })).text();
  const light = await (await request.get("/", { headers: { cookie: `${COOKIE}=light` } })).text();
  const system = await (await request.get("/")).text();
  const bogus = await (await request.get("/", { headers: { cookie: `${COOKIE}=neon` } })).text();
  expect(dark).toMatch(/<html[^>]*\sdata-theme="dark"/);
  expect(light).toMatch(/<html[^>]*\sdata-theme="light"/);
  expect(system).not.toMatch(/<html[^>]*\sdata-theme=/);
  expect(bogus).not.toMatch(/<html[^>]*\sdata-theme=/);
});

test("no inline script reads or writes the theme", async ({ request }) => {
  const html = await (await request.get("/", { headers: { cookie: `${COOKIE}=dark` } })).text();
  const inline = [...html.matchAll(/<script(?![^>]*\ssrc=)[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1] ?? "");
  expect(inline.length, "Next's own inline scripts are there").toBeGreaterThan(0);
  for (const code of inline) {
    expect(code).not.toContain("localStorage");
    expect(code).not.toContain(COOKIE);
    expect(code).not.toMatch(/setAttribute\(["']data-theme|dataset\.theme/);
  }
});

test("choosing a theme stores the cookie and returns to the same page, at the control", async ({ page, context }) => {
  await page.goto("/evidence?split=tune", { waitUntil: "networkidle" });
  await page.getByRole("contentinfo").getByRole("button", { name: "Night game" }).click();
  await expect(page).toHaveURL(/\/evidence\?split=tune#theme$/);
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  expect((await context.cookies()).find((c) => c.name === COOKIE)?.value).toBe("dark");
  await expect(page.getByRole("contentinfo").getByRole("button", { name: "Night game" })).toHaveAttribute("aria-pressed", "true");
  await page.goto("/methodology");
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await page.getByRole("contentinfo").getByRole("button", { name: "System" }).click();
  await expect(page.locator("html")).not.toHaveAttribute("data-theme", /.+/);
  expect((await context.cookies()).find((c) => c.name === COOKIE)).toBeUndefined();
});

test("a tap straight after the page starts loading is not lost", async ({ page }) => {
  for (let i = 0; i < 3; i += 1) {
    await page.context().clearCookies();
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await page.getByRole("contentinfo").getByRole("button", { name: "Night game" }).click();
    await expect(page.locator("html"), `try ${i + 1}`).toHaveAttribute("data-theme", "dark");
  }
});

test("POST /theme sets the cookie, redirects back on this site only, and refuses another origin", async ({ request, baseURL }) => {
  const set = await request.post("/theme", { form: { theme: "light" }, headers: { referer: `${baseURL}/evidence?split=tune` }, maxRedirects: 0 });
  expect(set.status()).toBe(303);
  expect(set.headers()["set-cookie"] ?? "").toMatch(/bl-theme=light/);
  expect(set.headers()["set-cookie"] ?? "").toMatch(/HttpOnly/i);
  expect(set.headers()["location"]).toBe("/evidence?split=tune#theme");

  const elsewhere = await request.post("/theme", { form: { theme: "dark" }, headers: { referer: "https://evil.example/x" }, maxRedirects: 0 });
  expect(elsewhere.status()).toBe(303);
  expect(elsewhere.headers()["location"], "never redirects off the site").toBe("/#theme");

  const unknown = await request.post("/theme", { form: { theme: "neon" }, maxRedirects: 0 });
  expect(unknown.status()).toBe(303);
  expect(unknown.headers()["set-cookie"] ?? "").toMatch(/bl-theme=;|bl-theme=\s*;|Max-Age=0|Expires=Thu, 01 Jan 1970/i);

  const foreign = await request.post("/theme", { form: { theme: "dark" }, headers: { origin: "https://evil.example" }, maxRedirects: 0 });
  expect(foreign.status()).toBe(403);
});

test("the control is three 44px targets in the footer and nothing of it is in the header", async ({ page }) => {
  await page.goto("/");
  const footer = page.getByRole("contentinfo");
  for (const name of ["System", "Light", "Night game"]) {
    const box = (await footer.getByRole("button", { name }).boundingBox())!;
    expect(box.height, `${name} button height`).toBeGreaterThanOrEqual(44);
  }
  await expect(page.locator("body > header").getByRole("button")).toHaveCount(0);
  await expect(page.locator("select")).toHaveCount(0);
});

test.describe("without JavaScript", () => {
  test.use({ javaScriptEnabled: false });

  test("the form still sets the theme, because the server does the work", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("contentinfo").getByRole("button", { name: "Night game" }).click();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  });
});
```

<!-- apply: T4.1 create web/e2e/header.spec.ts -->
```ts
import { expect, test } from "@playwright/test";
import { WIDTHS } from "./helpers";

/**
 * The header is two rows below lg (the wordmark and the Desk button, then the navigation) and one
 * row from lg up. The five navigation labels are always one line: before Track B2 the phone header
 * was four visual rows (229px at 390px), because the theme select took a row and the nav wrapped.
 */
for (const width of WIDTHS) {
  test(`at ${width}px the header is ${width >= 1024 ? "one row" : "two rows"} and the five links share one line`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/");
    await page.evaluate(() => document.fonts.ready);
    const nav = page.getByRole("navigation", { name: "Main" });
    const links = nav.getByRole("link");
    await expect(links).toHaveCount(5);
    const boxes = await links.evaluateAll((els) => els.map((e) => ({ top: Math.round(e.getBoundingClientRect().top), height: e.getBoundingClientRect().height })));
    expect(new Set(boxes.map((b) => b.top)).size, "one line of links").toBe(1);
    for (const b of boxes) expect(b.height, "link target height").toBeGreaterThanOrEqual(44);

    const header = (await page.locator("body > header").boundingBox())!;
    expect(header.height, "header height").toBeLessThanOrEqual(width >= 1024 ? 66 : 112);

    const wordmark = (await page.getByRole("link", { name: "Broadcast Line" }).boundingBox())!;
    const desk = (await page.locator("body > header").getByRole("link", { name: "Desk" }).boundingBox())!;
    expect(Math.abs(wordmark.y + wordmark.height / 2 - (desk.y + desk.height / 2)), "wordmark and Desk on one row").toBeLessThanOrEqual(2);
    expect(desk.height, "Desk target height").toBeGreaterThanOrEqual(44);
    const navTop = (await nav.boundingBox())!.y;
    if (width < 1024) expect(navTop, "the navigation is its own row").toBeGreaterThan(wordmark.y + wordmark.height - 1);
  });
}

test("on a 390px phone the five labels fit without scrolling the row", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 900 });
  await page.goto("/");
  await page.evaluate(() => document.fonts.ready);
  const overflow = await page.getByRole("navigation", { name: "Main" }).locator("ul").evaluate((el) => el.scrollWidth - el.clientWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});

for (const width of [320, 360]) {
  test(`at ${width}px the five labels stay on one line and the page does not scroll sideways`, async ({ page }) => {
    await page.setViewportSize({ width, height: 800 });
    await page.goto("/");
    await page.evaluate(() => document.fonts.ready);
    const tops = await page.getByRole("navigation", { name: "Main" }).getByRole("link").evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().top)));
    expect(new Set(tops).size, "one line of links").toBe(1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth), "horizontal overflow").toBeLessThanOrEqual(0);
  });
}

test("the current section is marked in the navigation", async ({ page }) => {
  await page.goto("/evidence");
  await expect(page.getByRole("navigation", { name: "Main" }).locator('[aria-current="page"]')).toHaveText("Evidence");
});
```

<!-- apply: T4.1 create web/src/test/tokenCeilings.json -->
```json
{
  "arbitrary": {
    "app/data-health/page.tsx": 1,
    "app/desk/page.tsx": 1,
    "app/evidence/page.tsx": 5,
    "app/games/[id]/page.tsx": 29,
    "app/methodology/page.tsx": 1,
    "app/page.tsx": 11,
    "components/Field.tsx": 31,
    "components/charts/ChartFigure.tsx": 1,
    "components/charts/ChartTooltip.tsx": 1,
    "components/charts/LazyScoreDistributionPlot.tsx": 2,
    "components/charts/ScoreDistributionChart.tsx": 1,
    "components/charts/ScoreDistributionPlot.tsx": 1
  },
  "textPx": {
    "app/evidence/page.tsx": 2,
    "app/games/[id]/page.tsx": 15,
    "app/page.tsx": 6
  }
}
```

- [ ] **Step 2: Run the tests and see RED**

Unit: `cd web && npx vitest run src/lib/theme.test.ts src/test/tokens.test.ts`
Expected: FAIL: `theme.test.ts` cannot import `./theme`, and the ratchet names `app/layout.tsx`, `components/NavLinks.tsx`, `components/SiteFooter.tsx`, `components/SiteHeader.tsx` and `components/ThemeToggle.tsx`.

E2E: serve the tree as it stands (its UI is `main`'s; Step S3) and run `cd web && npx playwright test e2e/theme.spec.ts e2e/header.spec.ts`.
Expected: `10 failed`, `4 passed`: the header specs at 390, 768, 320 and 360 px fail (four rows, a wrapping navigation), the theme specs fail (no cookie theme, no footer control, no `/theme`); the 1440 px header, "no inline script", "the current section is marked" and "fits at 390 without scrolling" pass.

- [ ] **Step 3: Write the theme and the chrome**

<!-- apply: T4.3 create web/src/lib/theme.ts -->
```ts
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
    return `${url.pathname}${url.search}#${THEME_ANCHOR}`;
  } catch {
    return fallback;
  }
}
```

<!-- apply: T4.3 create web/src/lib/themeCookie.ts -->
```ts
import { cookies } from "next/headers";
import { parseTheme, THEME_COOKIE, type Theme } from "./theme";

/** The viewer's theme, from the request's cookie (server components only). */
export async function readTheme(): Promise<Theme> {
  return parseTheme((await cookies()).get(THEME_COOKIE)?.value);
}
```

<!-- apply: T4.3 create web/src/app/theme/route.ts -->
```ts
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
```

<!-- apply: T4.3 create web/src/components/ThemeToggle.tsx -->
```tsx
import { chipClass } from "@/components/ui";
import { THEME_ANCHOR, THEMES, type Theme } from "@/lib/theme";

/**
 * System, light or night game. Three 44px chips in a plain form that posts to /theme: the server
 * stores the choice in a cookie and renders it, so nothing flashes and no script is involved, and a
 * tap while the page is still loading is not lost (a form post does not wait for hydration).
 */
export function ThemeToggle({ theme }: { theme: Theme }) {
  return (
    <form id={THEME_ANCHOR} method="post" action="/theme" className="flex flex-wrap items-center gap-snug print:hidden">
      <span id="theme-label" className="text-sm text-ink-2">
        Theme
      </span>
      <div role="group" aria-labelledby="theme-label" className="flex flex-wrap gap-snug">
        {THEMES.map((t) => (
          <button key={t.value} type="submit" name="theme" value={t.value} aria-pressed={t.value === theme} className={chipClass(t.value === theme)}>
            {t.label}
          </button>
        ))}
      </div>
    </form>
  );
}
```

<!-- apply: T4.3 create web/src/components/SiteFooter.tsx -->
```tsx
import { ThemeToggle } from "@/components/ThemeToggle";
import type { Theme } from "@/lib/theme";

/** The responsible-gambling notice on every page, and the theme choice. */
export function SiteFooter({ theme }: { theme: Theme }) {
  return (
    <footer className="border-t border-rule bg-surface">
      <div className="mx-auto flex max-w-page flex-col gap-stack px-gutter py-stack text-sm text-ink-2">
        <div className="flex max-w-measure flex-col gap-snug">
          <p>
            Research output from an unvalidated model. Nothing here is betting advice. If gambling stops being fun, call or
            text 1-800-GAMBLER (US) for free, confidential help.
          </p>
          <p className="text-muted">
            Probabilities are for adults in jurisdictions where sports betting is legal. Stakes are never shown on public
            pages.
          </p>
        </div>
        <ThemeToggle theme={theme} />
      </div>
    </footer>
  );
}
```

<!-- apply: T4.3 create web/src/components/SiteHeader.tsx -->
```tsx
import Link from "next/link";
import { BUTTON_CLASS } from "@/components/ui";
import { NavLinks } from "./NavLinks";

/** Broadcast Line wordmark: the scrimmage (market) and first-down (model) lines. */
function Wordmark() {
  return (
    <Link href="/" className="flex items-center gap-control no-underline">
      <span className="flex h-5.5 gap-0.75" aria-hidden>
        <span className="w-1 rounded-tick" style={{ background: "var(--field-market)" }} />
        <span className="w-1 rounded-tick" style={{ background: "var(--field-model)" }} />
      </span>
      <span className="wdth-expanded text-lg font-bold">Broadcast Line</span>
    </Link>
  );
}

/**
 * Two rows below lg (the wordmark and the Desk button, then the navigation), one row from lg up.
 * The theme choice lives in the footer, so nothing here is wider than a phone.
 */
export function SiteHeader() {
  return (
    <header className="border-b border-rule bg-surface print:hidden">
      <div className="mx-auto flex max-w-page flex-wrap items-center justify-between gap-x-section px-gutter lg:flex-nowrap lg:justify-start">
        <div className="flex h-16 items-center">
          <Wordmark />
        </div>
        <NavLinks />
        <div className="flex h-16 items-center lg:ml-auto">
          <Link href="/desk" className={BUTTON_CLASS}>
            Desk
          </Link>
        </div>
      </div>
    </header>
  );
}
```

<!-- apply: T4.3 create web/src/components/NavLinks.tsx -->
```tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const NAV = [
  { href: "/", label: "This week" },
  { href: "/props", label: "Props" },
  { href: "/evidence", label: "Evidence" },
  { href: "/methodology", label: "Methodology" },
  { href: "/data-health", label: "Data health" }
];

/**
 * Main navigation; the current section is underlined in ink and marked aria-current. It is
 * one line at every width: on a phone the five labels are spread across the row with a
 * 10px minimum gap (all five fit at 390px), and a narrower phone scrolls the row.
 */
export function NavLinks() {
  const path = usePathname() ?? "/";
  const isCurrent = (href: string) => (href === "/" ? path === "/" || path.startsWith("/games") : path.startsWith(href));
  return (
    <nav aria-label="Main" className="order-last w-full lg:order-none lg:w-auto">
      <ul className="-m-1 flex flex-nowrap justify-between gap-x-2.5 overflow-x-auto p-1 text-sm sm:justify-start sm:gap-x-stack lg:overflow-visible">
        {NAV.map((n) => {
          const on = isCurrent(n.href);
          return (
            <li key={n.href}>
              <Link
                href={n.href}
                aria-current={on ? "page" : undefined}
                className={`inline-flex h-11 items-center whitespace-nowrap border-b-2 no-underline lg:h-16 ${on ? "border-ink font-semibold text-ink" : "border-transparent text-ink-2 hover:text-ink"}`}
              >
                {n.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
```

<!-- apply: T4.3 create web/src/app/layout.tsx -->
```tsx
import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { themeAttribute } from "@/lib/theme";
import { readTheme } from "@/lib/themeCookie";
import "./globals.css";

// Archivo variable (weight 100–900, width 62–125%): condensed for dense tables, expanded
// for team codes and scores (spec §4). The latin file is committed with its OFL licence
// (./fonts), so a build needs no network (A8: the app runs offline from the terminal).
const archivo = localFont({
  src: "./fonts/archivo-latin.woff2",
  weight: "100 900",
  style: "normal",
  display: "swap",
  variable: "--font-archivo",
  declarations: [{ prop: "font-stretch", value: "62% 125%" }]
});

export const metadata: Metadata = {
  title: { default: "Broadcast Line", template: "%s · Broadcast Line" },
  description: "NFL game probabilities: the no-vig market, model candidates and the pre-registered evidence behind them."
};

export const viewport: Viewport = { width: "device-width", initialScale: 1 };

// Every page carries a per-request CSP nonce (src/proxy.ts), and a statically
// prerendered page cannot: its scripts would be blocked. So nothing is static.
export const dynamic = "force-dynamic";

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // the theme is a cookie the server renders onto <html>: no flash, no inline script
  const theme = await readTheme();
  return (
    <html lang="en" className={archivo.variable} data-theme={themeAttribute(theme)}>
      <body>
        <a href="#main" className="skip-link">
          Skip to content
        </a>
        <SiteHeader />
        <main id="main" className="mx-auto max-w-page px-gutter pb-page-top pt-page-top">
          {children}
        </main>
        <SiteFooter theme={theme} />
      </body>
    </html>
  );
}
```

- [ ] **Step 4: Run the tests and see GREEN**

Unit: `cd web && npx vitest run src/lib/theme.test.ts src/test/tokens.test.ts`
Expected: `Test Files  2 passed (2)`, `Tests  13 passed (13)`.

E2E: `rm -rf .next && npm run build`, restart the server on :3100 (Step S3), then `npx playwright test e2e/theme.spec.ts e2e/header.spec.ts`.
Expected: `14 passed`. Then the whole fixture suite: `npx playwright test --grep-invert @sim`
Expected: `84 passed`, `60 skipped` (the `@parity` cases skip without `E2E_PARITY_SNAPSHOTS`). The dry run saw one transient `id-leaks` failure on the first run right after resetting the database and none in three reruns; rerun before investigating.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  23 passed (23)`, `Tests  166 passed (166)`.

```bash
git add web/src web/e2e
git commit -m "feat(web): two-row header, one-line navigation, theme in a cookie the server renders (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: The Field: flags inside the strip, and a card that is one link [sonnet]

Two audit bugs live in `Field.tsx`:

- **The flag row was off its markers.** The game page drew the flags in its own row, inset 26 px on a phone, while the hero strip's end zones are 58 px wide at every width: a flag could sit up to 33 px from the marker it names. Now the hero `Field` draws its flags itself. The flag row has the strip's turf width (it is inset by `mx-turf-hero`, the hero end zone plus the strip's 1 px border), so `left: x%` in the row is `left: x%` of the turf, and the flag's edge and the marker are the same x by construction. Each flag carries `data-flag` and `data-flag-edge`, each marker `data-marker`, which is what the spec measures. A flag opens toward the middle of the field (a marker left of centre opens right), so it never leaves the strip.
- **Only the title was a link.** The strip's title link now stretches over the whole card (`after:absolute after:inset-0 after:z-10` on the link inside a `relative` card). The `z-10` matters: the strip contains positioned children (the turf, the markers, the hatch), which paint above a plain overlay and would take the click. The card shows one focus ring (the `.card-link` rules from Task 2) instead of a ring round the title text.

The component also moves onto the tokens (`Card pad="sm"`, `rounded-field`, `w-endzone`, `text-figure`, `text-xl` for the strip's team codes so the day headings above them stay the larger type), prints the kickoff in a `<time datetime>`, and drops from 31 arbitrary utilities to 1 (the readout's grid template).

While Tasks 5 and 6 are in, the game page (still the old one) draws its own flag row as well as the Field's: two sets of flags until Task 7, which is expected.

**Files:**
- Create: `web/e2e/flags.spec.ts`, `web/e2e/card-link.spec.ts`
- Modify: `web/e2e/helpers.ts` (adds `gameHrefs` and `publicPagesOfRun`), `web/src/components/Field.tsx`, `web/src/test/tokenCeilings.json`

**Interfaces:**
- Consumes: `Card` and the tokens (Tasks 1 and 2).
- Produces: `Field` (same props), now drawing the hero's flags; `gameHrefs(page, limit)` and `publicPagesOfRun(page)` for the e2e specs that must not depend on which run is published.

- [ ] **Step 1: Write the failing tests**

<!-- apply: T5.1 create web/e2e/helpers.ts -->
```ts
import { expect, type Page } from "@playwright/test";

/** Public routes, with one game from the committed weekly fixture bundle. */
export const PUBLIC_PAGES = ["/", "/games/2026_04_DEN_SF", "/props", "/evidence", "/methodology", "/data-health", "/login"];
export const WIDTHS = [390, 768, 1440] as const;
export const SCHEMES = ["light", "dark"] as const;

export function deskCredentials() {
  const email = process.env.DESK_EMAIL;
  const password = process.env.DESK_PASSWORD;
  if (!email || !password) throw new Error("DESK_EMAIL and DESK_PASSWORD must be set for the desk specs (see npm run seed:user)");
  return { email, password };
}

export async function signIn(page: Page) {
  const { email, password } = deskCredentials();
  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await Promise.all([page.waitForURL("**/desk"), page.getByRole("button", { name: /sign in/i }).click()]);
  await expect(page.getByRole("heading", { level: 1, name: "Desk" })).toBeVisible();
}

/**
 * The score-distribution plots load as their slots near the viewport (components/charts/
 * LazyScoreDistributionPlot.tsx). Scroll every slot into view and wait until each has drawn
 * its SVG, then return to the top, so a screenshot or an axe run sees the finished page.
 */
export async function drawLazyCharts(page: Page) {
  const slots = page.locator("[data-plot-slot]");
  const n = await slots.count();
  for (let i = 0; i < n; i += 1) await slots.nth(i).scrollIntoViewIfNeeded();
  if (n > 0) await expect(page.locator("[data-plot-slot] svg[role=img]")).toHaveCount(n);
  await page.evaluate(() => window.scrollTo(0, 0));
}

/** The game links on the home page, so a spec works on any published run (the fixture or a run_week.R bundle). */
export async function gameHrefs(page: Page, limit = 4): Promise<string[]> {
  await page.goto("/");
  const hrefs = await page
    .locator('a[href^="/games/"]')
    .evaluateAll((els, n) => [...new Set(els.map((e) => e.getAttribute("href") ?? ""))].slice(0, n), limit);
  expect(hrefs.length, "game links on the home page").toBeGreaterThan(0);
  return hrefs;
}

/** The public pages for a run-independent spec: the fixed routes plus the first game of the published run. */
export async function publicPagesOfRun(page: Page): Promise<string[]> {
  const [game] = await gameHrefs(page, 1);
  return ["/", game!, "/props", "/evidence", "/methodology", "/data-health", "/login"];
}
```

<!-- apply: T5.1 create web/e2e/flags.spec.ts -->
```ts
import { expect, test } from "@playwright/test";
import { gameHrefs, WIDTHS } from "./helpers";

/**
 * The game page's flags name the market line and the model line above the strip. They are drawn
 * inside the Field (components/Field.tsx), in the strip's own coordinates, so each flag's edge is
 * the same x as the marker it names. Before Track B2 the flag row sat in the game page, inset 26px
 * on a phone against the strip's 58px end zones, up to 33px off.
 */
for (const width of WIDTHS) {
  test(`at ${width}px every flag edge sits on its marker within 1px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    const hrefs = await gameHrefs(page, 4);
    let measured = 0;
    for (const href of hrefs) {
      await page.goto(href);
      await page.evaluate(() => document.fonts.ready);
      const flags = page.locator("[data-flag]");
      const n = await flags.count();
      for (let i = 0; i < n; i += 1) {
        const flag = flags.nth(i);
        const kind = await flag.getAttribute("data-flag");
        const edge = await flag.getAttribute("data-flag-edge");
        const f = (await flag.boundingBox())!;
        const m = (await page.locator(`[data-marker="${kind}"]`).boundingBox())!;
        const flagX = edge === "left" ? f.x : f.x + f.width;
        const markerX = m.x + m.width / 2;
        expect(Math.abs(flagX - markerX), `${href}: the ${kind} flag's ${edge} edge against its marker`).toBeLessThanOrEqual(1);
        measured += 1;
      }
    }
    expect(measured, "flags measured across the games").toBeGreaterThanOrEqual(hrefs.length);
  });
}

test("a flag never leaves the field: it opens toward the middle", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 900 });
  const [href] = await gameHrefs(page, 1);
  await page.goto(href!);
  const strip = (await page.locator('article[data-game] [role="img"]').first().boundingBox())!;
  const flags = page.locator("[data-flag]");
  expect(await flags.count(), "the game page draws flags").toBeGreaterThan(0);
  for (let i = 0; i < (await flags.count()); i += 1) {
    const f = (await flags.nth(i).boundingBox())!;
    expect(f.x, "flag left edge inside the strip").toBeGreaterThanOrEqual(strip.x - 1);
    expect(f.x + f.width, "flag right edge inside the strip").toBeLessThanOrEqual(strip.x + strip.width + 1);
  }
});
```

<!-- apply: T5.1 create web/e2e/card-link.spec.ts -->
```ts
import { expect, test } from "@playwright/test";

/**
 * A game strip on the home page is one link to its game: the title link stretches over the whole
 * card, so the strip and the numbers are targets too. Before Track B2 only the title was.
 */
test("clicking the strip itself opens the game", async ({ page }) => {
  await page.goto("/");
  const card = page.locator("article[data-game]").first();
  const id = await card.getAttribute("data-game");
  expect(id).toBeTruthy();
  // the title link is stretched over the card, so the strip is covered by design: click through at its centre
  await card.locator('[role="img"]').click({ force: true });
  await expect(page).toHaveURL(new RegExp(`/games/${id}$`));
});

test("clicking the readout under the strip opens the game too", async ({ page }) => {
  await page.goto("/");
  const card = page.locator("article[data-game]").first();
  const id = await card.getAttribute("data-game");
  await card.scrollIntoViewIfNeeded();
  const box = (await card.boundingBox())!;
  await page.mouse.click(box.x + box.width / 2, box.y + box.height - 12);
  await expect(page).toHaveURL(new RegExp(`/games/${id}$`));
});

test("keyboard focus shows one ring, around the card, not around the title text", async ({ page }) => {
  await page.goto("/");
  const card = page.locator("article[data-game]").first();
  await card.getByRole("link").first().focus();
  expect(await card.evaluate((el) => getComputedStyle(el).outlineStyle)).toBe("solid");
  expect(await card.getByRole("link").first().evaluate((el) => getComputedStyle(el).outlineStyle)).toBe("none");
});
```

<!-- apply: T5.1 create web/src/test/tokenCeilings.json -->
```json
{
  "arbitrary": {
    "app/data-health/page.tsx": 1,
    "app/desk/page.tsx": 1,
    "app/evidence/page.tsx": 5,
    "app/games/[id]/page.tsx": 29,
    "app/methodology/page.tsx": 1,
    "app/page.tsx": 11,
    "components/Field.tsx": 1,
    "components/charts/ChartFigure.tsx": 1,
    "components/charts/ChartTooltip.tsx": 1,
    "components/charts/LazyScoreDistributionPlot.tsx": 2,
    "components/charts/ScoreDistributionChart.tsx": 1,
    "components/charts/ScoreDistributionPlot.tsx": 1
  },
  "textPx": {
    "app/evidence/page.tsx": 2,
    "app/games/[id]/page.tsx": 15,
    "app/page.tsx": 6
  }
}
```

- [ ] **Step 2: Run the tests and see RED**

Unit: `cd web && npx vitest run src/test/tokens.test.ts`
Expected: `Tests  1 failed | 7 passed (8)`: `components/Field.tsx: 31 arbitrary utilities, ceiling 1`.

E2E, against the server built after Task 4: `cd web && npx playwright test e2e/flags.spec.ts e2e/card-link.spec.ts`
Expected: `7 failed`: no `[data-flag]` exists, and a click on the strip or the readout does not leave the home page.

- [ ] **Step 3: Write the Field**

<!-- apply: T5.3 create web/src/components/Field.tsx -->
```tsx
import Link from "next/link";
import { Card } from "@/components/ui";
import { kickoff, pct } from "@/lib/format";
import { teamColors } from "@/lib/teams";

/**
 * The Field (Broadcast Line redesign, owner-approved 2026-10-01): each game is a
 * night-turf field between the two end zones. The line splits the field by win
 * chance, so each team's side is its probability of winning: the away team owns the
 * left share, the home team the right. Blue is the no-vig market; gold is the model
 * (validated, or the labelled research line). The hatched band is the gap. Every
 * value is printed as text beside a colour swatch, so nothing depends on colour.
 *
 * The hero (game page) also draws a flag per line above the strip. The flags live here, in the
 * strip's own coordinates: the flag row is inset by exactly the end zone and the strip's border
 * (--spacing-turf-hero), so a flag's edge and the marker it names are the same x at every width
 * (e2e/flags.spec.ts checks it to one pixel at 390, 768 and 1440).
 */
export interface FieldProps {
  gameId: string;
  awayId: string;
  homeId: string;
  awayName: string;
  homeName: string;
  kickoffUtc: string;
  neutral: boolean;
  pMarket: number | null;
  model?: { p: number; label: string; validated: boolean } | null;
  href?: string;
  final?: { home: number; away: number } | null;
  size?: "strip" | "hero";
}

const YARD_LINES = [10, 20, 30, 40, 50, 60, 70, 80, 90];
const clamp = (p: number) => Math.min(Math.max(p, 0), 1);

/** Plain-language gap between the model and the market (home probabilities). */
export function gapText(pm: number, pModel: number, awayId: string, homeId: string): string {
  const gap = (pModel - pm) * 100;
  if (Math.abs(gap) < 3) return "Model within 3 points of the market";
  const lean = gap > 0 ? homeId : awayId;
  const flips = pm >= 0.5 !== pModel >= 0.5;
  return `Model is ${Math.abs(gap).toFixed(1)} points more on ${lean}${flips ? " and makes it the favourite" : ""}`;
}

export function Field(props: FieldProps) {
  const { awayId, homeId, awayName, homeName, model } = props;
  const hero = props.size === "hero";
  const pm = props.pMarket === null ? null : clamp(props.pMarket);
  const pmod = model ? clamp(model.p) : null;
  const away = teamColors(awayId);
  const home = teamColors(homeId);
  const xMarket = pm === null ? null : (1 - pm) * 100;
  const xModel = pmod === null ? null : (1 - pmod) * 100;
  // the model's numbers are announced with or without a market line (a simulator run can
  // have a game the market never priced, audit M11)
  const summary =
    (pm === null
      ? `${awayName} at ${homeName}: no market line.`
      : `${awayName} at ${homeName}. Market: ${awayName} ${pct(1 - pm)}, ${homeName} ${pct(pm)}.`) +
    (model && pmod !== null ? ` ${model.label}${model.validated ? "" : " (unvalidated)"}: ${awayName} ${pct(1 - pmod)}, ${homeName} ${pct(pmod)}.` : "");

  const title = (
    <span className="flex items-center gap-snug">
      <TeamChip id={awayId} />
      <span className="wdth-expanded text-xl font-extrabold">{awayId}</span>
      <span className="text-sm text-muted">{props.neutral ? "vs" : "at"}</span>
      <TeamChip id={homeId} />
      <span className="wdth-expanded text-xl font-extrabold">{homeId}</span>
    </span>
  );

  const flags = [
    xMarket !== null && pm !== null ? { key: "market", x: xMarket, p: pm, name: "Market", bg: "var(--field-market)" } : null,
    xModel !== null && pmod !== null ? { key: "model", x: xModel, p: pmod, name: "Model", bg: "var(--field-model)" } : null
  ].filter((f): f is Flag => f !== null);

  const strip = (
    <div
      className={`${hero ? "h-37.5" : "h-16 sm:h-21.5"} flex overflow-hidden rounded-field border border-turf-edge`}
      role="img"
      aria-label={summary}
    >
      <EndZone id={awayId} colors={away} side="away" hero={hero} />
      <div className="relative flex-1" style={{ backgroundImage: "var(--turf-stripes)", backgroundSize: "100% 100%" }}>
        {YARD_LINES.map((y) => (
          <span key={y}>
            <span
              className="absolute top-0 bottom-0 w-0.5 -translate-x-1/2"
              style={{ left: `${y}%`, background: y === 50 ? "var(--turf-line-mid)" : "var(--turf-line)" }}
            />
            <span
              className={`num wdth-condensed absolute -translate-x-1/2 font-bold ${hero ? "bottom-1.5 text-xs sm:bottom-2.5 sm:text-xl" : "bottom-1 hidden text-xs sm:block"}`}
              style={{ left: `${y}%`, color: "var(--turf-number)" }}
              aria-hidden
            >
              {y <= 50 ? y : 100 - y}
            </span>
          </span>
        ))}
        {xModel !== null && xMarket !== null ? (
          <svg className="field-model absolute top-0 h-full" style={{ left: `${Math.min(xMarket, xModel)}%`, width: `${Math.abs(xModel - xMarket)}%` }} aria-hidden>
            <defs>
              <pattern id={`hatch-${props.gameId}`} width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
                <rect width="7" height="7" fill="var(--field-model)" fillOpacity="0.16" />
                <line x1="0" y1="0" x2="0" y2="7" stroke="var(--field-model)" strokeOpacity="0.62" strokeWidth="2" />
              </pattern>
            </defs>
            <rect width="100%" height="100%" fill={`url(#hatch-${props.gameId})`} />
          </svg>
        ) : null}
        {xModel !== null ? (
          <span
            data-marker="model"
            className="field-model absolute -top-px -bottom-px w-1.25 -translate-x-1/2"
            style={{ left: `${xModel}%`, background: "var(--field-model)", boxShadow: "0 0 0 1px var(--field-outline)" }}
          />
        ) : null}
        {xMarket !== null ? (
          <span
            data-marker="market"
            className="field-marker absolute -top-px -bottom-px w-1.25 -translate-x-1/2"
            style={{ left: `${xMarket}%`, background: "var(--field-market)", boxShadow: "0 0 0 1px var(--field-outline)" }}
          />
        ) : null}
      </div>
      <EndZone id={homeId} colors={home} side="home" hero={hero} />
    </div>
  );

  if (hero) {
    return (
      <article aria-label={summary} data-game={props.gameId}>
        <FlagRow flags={flags} awayId={awayId} homeId={homeId} />
        {strip}
      </article>
    );
  }

  return (
    <Card as="article" pad="sm" className={`relative${props.href ? " card-link" : ""}`} aria-label={summary} data-game={props.gameId}>
      <div className="flex flex-wrap items-center justify-between gap-x-stack gap-y-tight">
        <h3 className="text-base">
          {props.href ? (
            <Link href={props.href} className="no-underline hover:underline after:absolute after:inset-0 after:z-10">
              {title}
            </Link>
          ) : (
            title
          )}
          <span className="sr-only">
            {" "}
            ({awayName} at {homeName})
          </span>
        </h3>
        <p className="num text-sm text-muted">
          {props.final ? (
            `Final ${props.final.away}–${props.final.home}`
          ) : (
            <time dateTime={new Date(props.kickoffUtc).toISOString()}>{kickoff(props.kickoffUtc)}</time>
          )}
        </p>
      </div>
      <div className="mt-control">{strip}</div>
      <Readout pm={pm} pmod={pmod} awayId={awayId} homeId={homeId} model={model ?? null} />
    </Card>
  );
}

type Flag = { key: string; x: number; p: number; name: string; bg: string };

/**
 * One flag per row above the hero strip, each opening toward the middle of the field so neither
 * can leave it. The row has the strip's turf width, so `left: x%` here is `left: x%` of the turf.
 */
function FlagRow({ flags, awayId, homeId }: { flags: Flag[]; awayId: string; homeId: string }) {
  return (
    <div className="relative mx-turf-hero" aria-hidden data-flags>
      {flags.map((f) => {
        const opensRight = f.x < 50;
        return (
          <div key={f.key} className="relative h-9">
            <span
              data-flag={f.key}
              data-flag-edge={opensRight ? "left" : "right"}
              className={`absolute bottom-0 whitespace-nowrap px-control py-1.5 text-sm font-bold ${opensRight ? "rounded-t-field rounded-br-field" : "-translate-x-full rounded-t-field rounded-bl-field"}`}
              style={{ left: `${f.x}%`, background: f.bg, color: "var(--field-ink)" }}
            >
              {f.name} · {f.p > 0.5 ? homeId : awayId} {pct(Math.max(f.p, 1 - f.p))}
            </span>
          </div>
        );
      })}
    </div>
  );
}

function TeamChip({ id }: { id: string }) {
  const c = teamColors(id);
  return <span aria-hidden className="inline-block h-6.5 w-2.5 rounded-tick" style={{ background: c.primary, boxShadow: `inset -3px 0 0 ${c.accent}` }} />;
}

function EndZone({ id, colors, side, hero }: { id: string; colors: ReturnType<typeof teamColors>; side: "away" | "home"; hero: boolean }) {
  return (
    <div
      className={`${hero ? "w-endzone-hero" : "w-endzone"} flex shrink-0 items-center justify-center`}
      style={{
        background: colors.primary,
        [side === "away" ? "borderRight" : "borderLeft"]: `${hero ? 3 : 2}px solid var(--turf-edge)`
      }}
    >
      <span
        className={`wdth-expanded font-extrabold tracking-code ${hero ? "text-heading" : "hidden text-sm sm:inline"}`}
        style={{ writingMode: "vertical-rl", transform: side === "away" ? "rotate(180deg)" : undefined, color: colors.ink }}
        aria-hidden
      >
        {id}
      </span>
    </div>
  );
}

function Readout({
  pm,
  pmod,
  awayId,
  homeId,
  model
}: {
  pm: number | null;
  pmod: number | null;
  awayId: string;
  homeId: string;
  model: FieldProps["model"] | null;
}) {
  const swatch = (v: string, h: string) => <span aria-hidden className={`inline-block w-1 ${h}`} style={{ background: v }} />;
  return (
    <div className="num mt-control grid grid-cols-2 items-end gap-x-control gap-y-snug sm:grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)]">
      <div className="flex flex-col gap-tight">
        <span className="flex items-baseline gap-snug">
          <span className="self-center">{swatch("var(--field-market)", "h-5")}</span>
          <span className="wdth-expanded text-figure font-extrabold">{pm === null ? "–" : pct(1 - pm)}</span>
          <span className="text-sm text-muted">{awayId}</span>
        </span>
        {pmod !== null ? (
          <span className="flex items-center gap-snug whitespace-nowrap text-sm font-semibold text-ink-2">
            {swatch("var(--field-model)", "h-3.5")}
            {pct(1 - pmod)} model
          </span>
        ) : null}
      </div>
      <p className="order-last col-span-2 pb-1 text-sm text-ink-2 sm:order-none sm:col-span-1 sm:max-w-62.5 sm:text-center">
        {pm === null ? "No market line" : pmod !== null ? gapText(pm, pmod, awayId, homeId) : `${pm >= 0.5 ? homeId : awayId} favoured by the market`}
        {model && !model.validated ? <span className="sr-only"> (unvalidated research model)</span> : null}
      </p>
      <div className="flex flex-col items-end gap-tight">
        <span className="flex items-baseline gap-snug">
          <span className="text-sm text-muted">{homeId}</span>
          <span className="wdth-expanded text-figure font-extrabold">{pm === null ? "–" : pct(pm)}</span>
          <span className="self-center">{swatch("var(--field-market)", "h-5")}</span>
        </span>
        {pmod !== null ? (
          <span className="flex items-center gap-snug whitespace-nowrap text-sm font-semibold text-ink-2">
            model {pct(pmod)}
            {swatch("var(--field-model)", "h-3.5")}
          </span>
        ) : null}
      </div>
    </div>
  );
}

/** Series key shown above a list of fields. */
export function FieldKey({ showModel, modelLabel, validated }: { showModel: boolean; modelLabel?: string; validated?: boolean }) {
  return (
    <ul className="flex flex-wrap gap-x-stack gap-y-snug text-sm text-ink-2" aria-label="Legend">
      <li className="flex items-center gap-snug">
        <span className="inline-block h-5 w-1.25" style={{ background: "var(--field-market)" }} aria-hidden />
        Market, no-vig
      </li>
      {showModel ? (
        <>
          <li className="flex items-center gap-snug">
            <span className="inline-block h-5 w-1.25" style={{ background: "var(--field-model)" }} aria-hidden />
            {modelLabel ?? "Model"}
            {validated ? "" : ", unvalidated"}
          </li>
          <li className="flex items-center gap-snug">
            <svg width="22" height="20" aria-hidden>
              <defs>
                <pattern id="hatch-key" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
                  <rect width="7" height="7" fill="var(--field-model)" fillOpacity="0.2" />
                  <line x1="0" y1="0" x2="0" y2="7" stroke="var(--field-model)" strokeOpacity="0.7" strokeWidth="2" />
                </pattern>
              </defs>
              <rect width="22" height="20" fill="url(#hatch-key)" stroke="var(--field-model)" strokeOpacity="0.8" />
            </svg>
            Gap between them
          </li>
        </>
      ) : null}
    </ul>
  );
}
```

- [ ] **Step 4: Run the tests and see GREEN**

Unit: `cd web && npx vitest run src/test/tokens.test.ts`
Expected: `Tests  8 passed (8)`.

E2E: `rm -rf .next && npm run build`, restart the server on :3100, then `npx playwright test e2e/flags.spec.ts e2e/card-link.spec.ts`
Expected: `7 passed`. Then the whole fixture suite `npx playwright test --grep-invert @sim`
Expected: `91 passed`, `60 skipped`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  23 passed (23)`, `Tests  166 passed (166)`.

```bash
git add web/src web/e2e
git commit -m "feat(web): flags drawn inside the hero strip, the whole game strip is one link (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: The home page [haiku]

The home page moves onto the components, and its ceilings go to zero first (11 arbitrary utilities and 6 `text-[Npx]` today); that failing ceiling, plus a test of the page with nothing ingested, is the test for this task.

What changes on the page:
- `PageHeader size="hero"`: the "Week N" h1 (`text-hero`, 64 to 104 px, was written by hand with its own sizes), the lead, and a **context line** (week and season, the run, the data date as a `<time datetime>`, and the slate's dates). The model status card moves into the header's `aside` (`Card as="aside" aria-label="Model status"`, the hook the `@sim` spec uses).
- The three stat tiles carry a **source line** each, and the third links its term ("model–market gap") to `/methodology`.
- The sort and filter bar is a `Section`; each day is a `Section` with the shared 24 px title (the day label was a 16 px h2), the strips a `Grid kind="fields"`; the market note under the list links its terms and prints the data date with `Stamp`.
- One round trip for the slate and the gates (`publicSlate()` with `publicGates()`), instead of `evidence()`'s seven queries; the page has no hand-picked margin (the `Page` column spaces the sections).
- With nothing ingested the page says so ("No published weekly run") and its context line reads "none published (nothing has been ingested)".

**Files:**
- Create: `web/src/test/pages/home.test.tsx`
- Modify: `web/src/app/page.tsx`, `web/src/test/tokenCeilings.json`

**Interfaces:**
- Consumes: `Page`, `PageHeader`, `Section`, `Grid`, `Card`, `StatTile`, `Stamp`, `Term`, `chipClass` (Task 2), `runContext`, `noRunContext`, `publicGates` (Tasks 2 and 3), `Field` (Task 5).

- [ ] **Step 1: Write the failing tests** (the page with nothing ingested, and the lowered ceilings)

<!-- apply: T6.1 create web/src/test/pages/home.test.tsx -->
```tsx
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// the home page before anything has been ingested: the queries find no run and no backtest
vi.mock("@/lib/data/queries", () => ({
  publicSlate: async () => ({ run: null, games: [] }),
  publicGates: async () => [],
  runCandidates: async () => [],
  candidateLines: async () => []
}));

describe("the home page with nothing ingested", () => {
  // the first import of a page compiles its whole module graph; on a cold cache and a busy machine that takes longer than the 5 s default
  it("says there is no run, states that in its context line, and has one h1", async () => {
    const { default: ThisWeek } = await import("../../app/page");
    const html = renderToStaticMarkup(await ThisWeek({ searchParams: Promise.resolve({}) }));
    expect(html).toContain("No published weekly run");
    expect(html).toContain("none published (nothing has been ingested)");
    expect(html.match(/<h1/g)).toHaveLength(1);
    expect(html).not.toMatch(/\bnull\b|undefined|NaN/);
  }, 30_000);
});
```

<!-- apply: T6.1 create web/src/test/tokenCeilings.json -->
```json
{
  "arbitrary": {
    "app/data-health/page.tsx": 1,
    "app/desk/page.tsx": 1,
    "app/evidence/page.tsx": 5,
    "app/games/[id]/page.tsx": 29,
    "app/methodology/page.tsx": 1,
    "components/Field.tsx": 1,
    "components/charts/ChartFigure.tsx": 1,
    "components/charts/ChartTooltip.tsx": 1,
    "components/charts/LazyScoreDistributionPlot.tsx": 2,
    "components/charts/ScoreDistributionChart.tsx": 1,
    "components/charts/ScoreDistributionPlot.tsx": 1
  },
  "textPx": {
    "app/evidence/page.tsx": 2,
    "app/games/[id]/page.tsx": 15
  }
}
```

- [ ] **Step 2: Run the tests and see RED**

Run: `cd web && npx vitest run src/test/pages/home.test.tsx src/test/tokens.test.ts`
Expected: FAIL, `Failed Tests 3`: `app/page.tsx: 11 arbitrary utilities, ceiling 0`, `app/page.tsx: 6 text-[Npx], ceiling 0`, and the home test (the old page does not use the new queries).

- [ ] **Step 3: Write the page**

<!-- apply: T6.3 create web/src/app/page.tsx -->
```tsx
import Link from "next/link";
import { Age } from "@/components/Age";
import { DataUnavailable } from "@/components/DataUnavailable";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, chipClass, Grid, Page, PageHeader, Section, Stamp, StatTile, Term } from "@/components/ui";
import { noRunContext, runContext } from "@/lib/context";
import { candidateLines, publicGates, publicSlate, runCandidates } from "@/lib/data/queries";
import { sortSlate } from "@/lib/slateSort";
import { weekday } from "@/lib/format";
import { candidateLabel, fieldLineNote, fieldLineNoun, publicFieldLine } from "@/lib/policy";

export const dynamic = "force-dynamic";

const SORTS = { kickoff: "Kickoff", gap: "Biggest gap", closest: "Closest game" } as const;
type Sort = keyof typeof SORTS;

const ET = "America/New_York";
const shortDay = (iso: string) => new Intl.DateTimeFormat("en-US", { timeZone: ET, weekday: "short", month: "short", day: "numeric" }).format(new Date(iso));
const longDay = (iso: string) => new Intl.DateTimeFormat("en-US", { timeZone: ET, weekday: "long", month: "short", day: "numeric" }).format(new Date(iso));

export default async function ThisWeek({ searchParams }: { searchParams: Promise<{ sort?: string; day?: string; model?: string }> }) {
  const sp = await searchParams;
  const sort: Sort = sp.sort && sp.sort in SORTS ? (sp.sort as Sort) : "kickoff";
  const showModel = sp.model !== "off";
  // the slate and the promotion gates are independent: one round trip for both
  const [{ run, games }, gates] = await Promise.all([publicSlate(), publicGates()]);

  if (!run) {
    return (
      <Page>
        <PageHeader title="This week" context={noRunContext("nothing has been ingested")} />
        <DataUnavailable title="No published weekly run">
          Nothing has been ingested yet. A weekly bundle from the R engine appears here after <code>ingest-bundle</code>.
        </DataUnavailable>
      </Page>
    );
  }

  const line = publicFieldLine(gates, await runCandidates(run.runId));
  const label = line ? candidateLabel(line.candidate) : "Model";
  const lines = line ? await candidateLines(run.runId, [line.candidate]) : [];
  const pModel = (gameId: string) => {
    const l = lines.find((x) => x.gameId === gameId && x.p !== null);
    return l ? (l.p as number) : null;
  };

  const rows = games.map((g) => {
    const p = pModel(g.gameId);
    const gap = p !== null && g.pMarket !== null ? Math.abs(p - g.pMarket) : 0;
    const flips = p !== null && g.pMarket !== null ? g.pMarket >= 0.5 !== p >= 0.5 : false;
    return { g, m: showModel && line && p !== null ? { p, label, validated: line.validated } : null, gap, flips, hasModel: p !== null && g.pMarket !== null };
  });
  const statRows = rows.filter((r) => r.hasModel);
  const biggest = statRows.length ? statRows.reduce((a, b) => (b.gap > a.gap ? b : a)) : null;
  const flipCount = statRows.filter((r) => r.flips).length;

  const days = [...new Set(games.map((g) => weekday(g.kickoffUtc)))];
  const day = sp.day && days.includes(sp.day) ? sp.day : null;
  let list = day ? rows.filter((r) => weekday(r.g.kickoffUtc) === day) : rows;
  list = sortSlate(list, sort);
  const groups =
    sort === "kickoff"
      ? days
          .map((d) => ({ label: longDay(list.find((r) => weekday(r.g.kickoffUtc) === d)?.g.kickoffUtc ?? games[0]!.kickoffUtc), items: list.filter((r) => weekday(r.g.kickoffUtc) === d) }))
          .filter((x) => x.items.length)
      : [{ label: sort === "gap" ? "Sorted by the model–market gap" : "Sorted by the closest market line", items: list }];

  const href = (s: Sort, d: string | null, m: boolean) => {
    const q = new URLSearchParams({ sort: s });
    if (d) q.set("day", d);
    if (!m) q.set("model", "off");
    return `/?${q.toString()}`;
  };
  const first = games[0]?.kickoffUtc;
  const last = games[games.length - 1]?.kickoffUtc;
  const modelSource = line ? `${label} against the no-vig market, ${statRows.length} games with both lines` : "This run carries no model line";

  return (
    <Page>
      <PageHeader
        size="hero"
        title={run.week === null ? "This week" : `Week ${run.week}`}
        lead={
          <>
            Every game is a field. The line splits it by win chance, so each team&apos;s side of the field is its probability of winning.
            Blue is the betting market&apos;s no-vig price{line ? `; gold is ${fieldLineNoun(line)}` : ""}. <Term id="field">How to read a field</Term>.
          </>
        }
        context={[...runContext(run), { label: "Games", value: first && last ? `${shortDay(first)} – ${shortDay(last)}` : "none scheduled" }]}
        aside={
          <Card as="aside" aria-label="Model status" className="flex flex-col gap-control">
            <div className="flex items-center gap-control">
              {line ? (
                <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated"} />
              ) : (
                <StatusBadge status="unavailable" label="Market only" />
              )}
              {line ? <span className="font-semibold">{label}</span> : null}
            </div>
            <p className="text-sm text-ink-2 text-pretty">{fieldLineNote(line)}</p>
            <Link href="/evidence" className="text-sm font-semibold">
              See the evidence
            </Link>
          </Card>
        }
      />

      <Section label="This week in numbers">
        <Grid kind="tiles">
          <StatTile value={games.length} label="games on the slate" source={`Published run ${run.cycleId}`} />
          <StatTile
            value={statRows.length ? `${flipCount} of ${statRows.length}` : "–"}
            label="games where the model picks a different favourite"
            source={modelSource}
          />
          <StatTile
            value={biggest ? `${(biggest.gap * 100).toFixed(1)} pts` : "–"}
            label={
              <>
                largest <Term id="gap">model–market gap</Term>
                {biggest ? `: ${biggest.g.awayTeamId} at ${biggest.g.homeTeamId}` : ""}
              </>
            }
            source={modelSource}
          />
        </Grid>
      </Section>

      <Section label="Sort and filter" className="border-y border-rule py-card-sm lg:flex-row lg:items-center lg:justify-between">
        <FieldKey showModel={showModel && line !== null} modelLabel={label} validated={line?.validated ?? false} />
        <div className="flex flex-wrap items-center gap-x-stack gap-y-snug">
          <div className="flex flex-wrap items-center gap-snug">
            <span className="text-sm text-muted">Sort</span>
            {(Object.keys(SORTS) as Sort[]).map((s) => (
              <Link key={s} href={href(s, day, showModel)} aria-current={s === sort ? "true" : undefined} className={chipClass(s === sort)}>
                {SORTS[s]}
              </Link>
            ))}
          </div>
          <div className="flex flex-wrap items-center gap-snug">
            <span className="text-sm text-muted">Day</span>
            <Link href={href(sort, null, showModel)} aria-current={!day ? "true" : undefined} className={chipClass(!day)}>
              All
            </Link>
            {days.map((d) => (
              <Link key={d} href={href(sort, d, showModel)} aria-current={d === day ? "true" : undefined} className={chipClass(d === day)}>
                {d.slice(0, 3)}
              </Link>
            ))}
          </div>
          {line ? (
            <Link
              href={href(sort, day, !showModel)}
              aria-label={showModel ? "Model line is on. Turn it off" : "Model line is off. Turn it on"}
              className={chipClass(showModel)}
            >
              Model line {showModel ? "on" : "off"}
            </Link>
          ) : null}
        </div>
      </Section>

      {groups.map((grp, i) => (
        <Section key={grp.label} id={`group-${i}`} title={grp.label}>
          <Grid kind="fields">
            {grp.items.map(({ g, m }) => (
              <Field
                key={g.gameId}
                gameId={g.gameId}
                awayId={g.awayTeamId}
                homeId={g.homeTeamId}
                awayName={g.awayName}
                homeName={g.homeName}
                kickoffUtc={g.kickoffUtc}
                neutral={g.neutral}
                pMarket={g.pMarket}
                model={m}
                href={`/games/${g.gameId}`}
                final={g.homeScore !== null && g.awayScore !== null ? { home: g.homeScore, away: g.awayScore } : null}
              />
            ))}
          </Grid>
        </Section>
      ))}

      <p className="max-w-measure text-sm text-muted">
        Market: the nflverse consensus <Term id="close">closing line</Term>, <Term id="no-vig">devigged</Term> in proportion, as of{" "}
        <Stamp iso={run.dataAsofUtc} /> (<Age iso={run.dataAsofUtc} />). It carries no timestamp or book, so line movement is not shown here.
      </p>
    </Page>
  );
}
```

- [ ] **Step 4: Run the tests and see GREEN**

Run: `cd web && npx vitest run src/test/pages/home.test.tsx src/test/tokens.test.ts`
Expected: `Test Files  2 passed (2)`, `Tests  9 passed (9)`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  24 passed (24)`, `Tests  167 passed (167)`.

```bash
git add web/src
git commit -m "feat(web): the home page on Page, PageHeader and Section, with context and sources (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: The charts and the game page [haiku]

The game page and the chart components move together, because the page's distribution cards are `ScoreDistributionChart`. The ceilings go first again (the game page has 29 arbitrary utilities and 15 `text-[Npx]`, `ChartFigure` and the plot components one or two each); `ScoreDistributionChart.test.tsx` already pins what must survive (`<tr class="border-t border-rule">` once per bin and a classless `<td>25.00%</td>`).

What changes:
- **Charts.** `ChartFigure` spaces its parts with the `control` gap (the old `mt-4`, `mt-3`, `mt-2` stack is gone) and no longer wraps its table: the four chart tables (`ScoreDistributionChart`, `ReliabilityGrid`, `SkillIntervals`, `ClvHistogram`) are `DataTable`s, dense and numeric, each with a caption and a row-header column, inside the scroll region the table brings. `ScoreDistributionChart` is a `Card`. The tooltip and the plot slot use `rounded-control`, `min-h-60` and `sm:min-h-70`.
- **The page.** The breadcrumb is a real `nav` with an ordered list; under it the context line (run and data date; the week is already in the breadcrumb, so `omitWeek`). The scoreboard keeps its team colours and moves onto `text-title` and `text-score`. The flag row is gone from the page (Task 5 moved it into the hero `Field`). The moneyline and the spread cards are `Card`s; the market label links its term. The kickoff is a `<time datetime>`. The queries run in four sequential round trips (ten before, counted from the code): the run pointer, then the game with the gates beside it, then the candidate list, then the lines and the distributions together. The top offset is the shared 48 px (it was 32 px here: the breadcrumb was the first block and carried no padding).

**Files:**
- Modify: `web/src/components/charts/ChartFigure.tsx`, `ScoreDistributionChart.tsx`, `ReliabilityGrid.tsx`, `SkillIntervals.tsx`, `ClvHistogram.tsx`, `ChartTooltip.tsx`, `LazyScoreDistributionPlot.tsx`, `ScoreDistributionPlot.tsx` (all under `web/src/components/charts/`), `web/src/app/games/[id]/page.tsx`, `web/src/test/tokenCeilings.json`

**Interfaces:**
- Consumes: `DataTable`, `Card`, `Page`, `Section`, `Grid`, `Breadcrumb`, `ContextList`, `Term` (Task 2), `runContext` with `omitWeek`, `publicGates` (Tasks 2 and 3), the hero `Field` (Task 5).

- [ ] **Step 1: Write the failing test** (the lowered ceilings)

<!-- apply: T7.1 create web/src/test/tokenCeilings.json -->
```json
{
  "arbitrary": {
    "app/data-health/page.tsx": 1,
    "app/desk/page.tsx": 1,
    "app/evidence/page.tsx": 5,
    "app/games/[id]/page.tsx": 1,
    "app/methodology/page.tsx": 1,
    "components/Field.tsx": 1
  },
  "textPx": {
    "app/evidence/page.tsx": 2
  }
}
```

- [ ] **Step 2: Run the test and see RED**

Run: `cd web && npx vitest run src/test/tokens.test.ts`
Expected: FAIL, `Tests  2 failed | 6 passed (8)`: the ratchet names `app/games/[id]/page.tsx` (29 against 1, and 15 `text-[Npx]`) and the five chart files.

- [ ] **Step 3: Write the charts and the page**

<!-- apply: T7.3 create web/src/components/charts/ChartFigure.tsx -->
```tsx
/**
 * Every chart is a <figure> with a computed text summary, a table view (the WCAG
 * equivalent; tooltips enhance, never gate) and the plot. Dataviz rules: one axis,
 * thin marks, a legend when there are two or more series, text in ink tokens.
 * The table is a DataTable (components/ui.tsx), which brings its own labelled scroll region.
 */
export function ChartFigure({
  title,
  summary,
  legend,
  table,
  children
}: {
  title: string;
  summary: string;
  legend?: React.ReactNode;
  table: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <figure className="flex flex-col gap-control">
      <figcaption className="flex flex-col gap-tight">
        <p className="font-medium">{title}</p>
        <p className="max-w-measure text-sm text-ink-2">{summary}</p>
      </figcaption>
      {legend ? <div>{legend}</div> : null}
      <div>{children}</div>
      <details className="text-sm">
        <summary className="cursor-pointer text-ink-2">Table view</summary>
        <div className="mt-snug">{table}</div>
      </details>
    </figure>
  );
}

export function LineKey({ color, label, marker = false }: { color: string; label: string; marker?: boolean }) {
  return (
    <span className="inline-flex items-center gap-snug text-sm text-ink-2">
      {marker ? (
        <span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: color }} aria-hidden />
      ) : (
        <span className="inline-block h-0.5 w-4" style={{ background: color }} aria-hidden />
      )}
      {label}
    </span>
  );
}
```

<!-- apply: T7.3 create web/src/components/charts/ScoreDistributionChart.tsx -->
```tsx
import { StatusBadge } from "@/components/StatusBadge";
import { Card, DataTable } from "@/components/ui";
import { type Bin, coveredMass, type DistKind, distributionSummary, outcomeLabel } from "@/lib/distribution";
import { ChartFigure } from "./ChartFigure";
import { LazyScoreDistributionPlot } from "./LazyScoreDistributionPlot";

/**
 * The simulator's final margin or total points for one game (A8), laid out like the
 * approved game-page mockup: a card per chart. One series, so no legend box: the title and
 * the marker labels name everything. The summary and the table view carry every value
 * (tooltips enhance, never gate), and both are rendered by the server. The plot itself
 * (ScoreDistributionPlot: columns, ticks, median and result markers, a crosshair on pointer
 * or arrow keys) is a client component that loads as its slot nears the viewport, so its
 * script is not part of the game page's first load (final review I6: it cost mobile LCP).
 */
export function ScoreDistributionChart({
  kind,
  bins,
  homeId,
  awayId,
  nSims,
  result
}: {
  kind: DistKind;
  bins: Bin[];
  homeId: string;
  awayId: string;
  nSims: number | null;
  result: number | null;
}) {
  const label = (v: number) => outcomeLabel(kind, v, homeId, awayId);
  const share = (p: number) => `${(p * 100).toFixed(2)}%`;
  const summary = distributionSummary(kind, bins, nSims, homeId, awayId, result);
  const title = kind === "margin" ? "Simulated final margin" : "Simulated total points";

  return (
    <Card>
      <ChartFigure
        title={title}
        summary={summary}
        legend={<StatusBadge status="unvalidated" label="Simulator (unvalidated)" />}
        table={
          <DataTable
            caption={`${title}, every outcome`}
            numeric
            dense
            columns={[
              { key: "outcome", header: kind === "margin" ? `Margin (${homeId} minus ${awayId})` : "Total points", rowHeader: true },
              { key: "share", header: "Share of simulated games" }
            ]}
            rows={[
              ...bins.map((b) => ({ key: String(b.x), cells: { outcome: label(b.x), share: share(b.p) } })),
              { key: "outside", cells: { outcome: "Outside the range shown", share: share(Math.max(0, 1 - coveredMass(bins))) }, muted: true }
            ]}
          />
        }
      >
        <LazyScoreDistributionPlot kind={kind} bins={bins} homeId={homeId} awayId={awayId} nSims={nSims} result={result} />
      </ChartFigure>
    </Card>
  );
}
```

<!-- apply: T7.3 create web/src/components/charts/ReliabilityGrid.tsx -->
```tsx
"use client";

import { scaleLinear } from "@visx/scale";
import { DataTable } from "@/components/ui";
import { candidateLabel } from "@/lib/policy";
import { pct } from "@/lib/format";
import { ChartFigure, LineKey } from "./ChartFigure";
import { ChartTooltip } from "./ChartTooltip";
import { useChartWidth } from "./useChartWidth";

export interface BinRow {
  candidate: string;
  bin: number;
  pMean: number;
  yMean: number;
  n: number;
}

/**
 * Reliability diagrams as small multiples (one per candidate, same axes), ten
 * equal-mass bins each. The diagonal is perfect calibration. The market panel is
 * drawn in market blue, model candidates in model gold; each panel has one series.
 */
export function ReliabilityGrid({ bins, ece, splitLabel }: { bins: BinRow[]; ece: Record<string, number>; splitLabel: string }) {
  const order = ["C0", "C1", "C2", "E1", "K[E1]", "B1[C1]", "B1[C2]", "B1[E1]", "B2[E1]"];
  const byCand = new Map<string, BinRow[]>();
  for (const b of bins) byCand.set(b.candidate, [...(byCand.get(b.candidate) ?? []), b]);
  const cands = order.filter((c) => byCand.has(c));
  const [ref, W] = useChartWidth(720);
  const cols = W < 560 ? 2 : 3;
  const gap = 16;
  const S = Math.max(120, Math.min(320, Math.floor((W - gap * (cols - 1)) / cols)));
  const pad = 42;
  const x = scaleLinear({ domain: [0, 1], range: [pad, S - 18] });
  const y = scaleLinear({ domain: [0, 1], range: [S - pad, 12] });
  const worst = [...cands].sort((a, b) => (ece[b] ?? 0) - (ece[a] ?? 0))[0];
  const summary =
    `${splitLabel}: observed home-win rate against predicted probability in ten equal-mass bins. ` +
    `Market ECE ${pct(ece.C0 ?? NaN, 1)}; the largest ECE is ${candidateLabel(worst ?? "")} at ${pct(ece[worst ?? ""] ?? NaN, 1)}. ` +
    `Points above the diagonal mean the home team won more often than predicted.`;

  return (
    <ChartFigure
      title={`Reliability, ${splitLabel}`}
      summary={summary}
      legend={
        <div className="flex flex-wrap gap-x-stack">
          <LineKey color="var(--market)" label="Market" />
          <LineKey color="var(--model)" label="Model candidates" />
          <LineKey color="var(--neutral-mid)" label="Perfect calibration" />
        </div>
      }
      table={
        <DataTable
          caption={`Reliability, ${splitLabel}, every bin`}
          numeric
          dense
          columns={[
            { key: "candidate", header: "Candidate", rowHeader: true },
            { key: "bin", header: "Bin" },
            { key: "predicted", header: "Mean predicted" },
            { key: "observed", header: "Observed" },
            { key: "games", header: "Games" }
          ]}
          rows={cands.flatMap((c) =>
            (byCand.get(c) ?? []).map((b) => ({
              key: `${c}-${b.bin}`,
              cells: { candidate: candidateLabel(c), bin: b.bin, predicted: pct(b.pMean, 1), observed: pct(b.yMean, 1), games: b.n }
            }))
          )}
        />
      }
    >
      <ChartTooltip>
        <div ref={ref} className="grid gap-4" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
          {cands.map((c) => {
            const pts = byCand.get(c) ?? [];
            const color = c === "C0" ? "var(--market)" : "var(--model)";
            const path = pts.map((b, i) => `${i ? "L" : "M"}${x(b.pMean).toFixed(1)},${y(b.yMean).toFixed(1)}`).join(" ");
            return (
              <div key={c}>
                <p className="text-sm">
                  {candidateLabel(c)} <span className="num text-muted">ECE {pct(ece[c] ?? NaN, 1)}</span>
                </p>
                <svg width={S} height={S} viewBox={`0 0 ${S} ${S}`} className="block h-auto max-w-full" role="img" aria-label={`${candidateLabel(c)} reliability`}>
                  {[0, 0.5, 1].map((t) => (
                    <g key={t}>
                      <line x1={x(t)} x2={x(t)} y1={y(0)} y2={y(1)} stroke="var(--grid)" strokeWidth={1} />
                      <line x1={x(0)} x2={x(1)} y1={y(t)} y2={y(t)} stroke="var(--grid)" strokeWidth={1} />
                      <text x={x(t)} y={S - 12} textAnchor="middle" fontSize={12} fill="var(--ink-muted)" className="num">{pct(t)}</text>
                      <text x={pad - 6} y={y(t) + 4} textAnchor="end" fontSize={12} fill="var(--ink-muted)" className="num">{pct(t)}</text>
                    </g>
                  ))}
                  <line x1={x(0)} y1={y(0)} x2={x(1)} y2={y(1)} stroke="var(--neutral-mid)" strokeWidth={1.5} />
                  <path d={path} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
                  {pts.map((b) => (
                    <g key={b.bin}>
                      <circle cx={x(b.pMean)} cy={y(b.yMean)} r={4} fill={color} stroke="var(--surface)" strokeWidth={2} />
                      <circle
                        cx={x(b.pMean)}
                        cy={y(b.yMean)}
                        r={12}
                        fill="transparent"
                        tabIndex={0}
                        role="graphics-symbol"
                        aria-label={`${candidateLabel(c)} bin ${b.bin}: predicted ${pct(b.pMean, 1)}, observed ${pct(b.yMean, 1)}, ${b.n} games`}
                        data-tip-value={`${pct(b.yMean, 1)} observed`}
                        data-tip-label={`${candidateLabel(c)}: predicted ${pct(b.pMean, 1)}, ${b.n} games`}
                      />
                    </g>
                  ))}
                </svg>
              </div>
            );
          })}
        </div>
      </ChartTooltip>
    </ChartFigure>
  );
}
```

<!-- apply: T7.3 create web/src/components/charts/SkillIntervals.tsx -->
```tsx
"use client";

import { scaleLinear } from "@visx/scale";
import { DataTable } from "@/components/ui";
import { candidateLabel } from "@/lib/policy";
import { signedPct } from "@/lib/format";
import { ChartFigure, LineKey } from "./ChartFigure";
import { ChartTooltip } from "./ChartTooltip";
import { useChartWidth } from "./useChartWidth";

export interface SkillRow {
  candidate: string;
  skill: number;
  skillLo: number;
  skillHi: number;
  brier: number;
  n: number;
}

/**
 * Brier skill vs the no-vig market with 95% week-block bootstrap intervals. The
 * market is the zero line (blue); candidates are dots with interval whiskers in ink.
 * Positive is better than the market. One axis, one series. Below 560px the
 * candidate labels sit above their whiskers so the plot keeps the full width.
 */
export function SkillIntervals({ rows, splitLabel }: { rows: SkillRow[]; splitLabel: string }) {
  const data = rows.filter((r) => r.candidate !== "C0").sort((a, b) => b.skill - a.skill);
  const [ref, W] = useChartWidth(720);
  const stacked = W < 560;
  const rowH = stacked ? 48 : 34;
  const left = stacked ? 24 : 220;
  const right = 24;
  const top = 12;
  const H = top + data.length * rowH + 36;
  const lo = Math.min(-0.1, ...data.map((d) => d.skillLo)) * 1.05;
  const hi = Math.max(0.02, ...data.map((d) => d.skillHi)) * 1.05;
  const x = scaleLinear({ domain: [lo, hi], range: [left, W - right] });
  const ticks = x.ticks(6);
  const best = data[0];
  const beats = data.filter((d) => d.skillLo > 0);
  const summary =
    `${splitLabel}: ${data.length} candidates against the no-vig closing market (${data[0]?.n ?? 0} games). ` +
    (beats.length
      ? `${beats.map((b) => candidateLabel(b.candidate)).join(", ")} beat the market with the interval above zero.`
      : `None beats the market: no interval lies above zero. The closest is ${candidateLabel(best?.candidate ?? "")} at ${signedPct(best?.skill ?? 0)} (${signedPct(best?.skillLo ?? 0)} to ${signedPct(best?.skillHi ?? 0)}).`);

  return (
    <ChartFigure
      title={`Brier skill vs the market, ${splitLabel}`}
      summary={summary}
      legend={
        <div className="flex flex-wrap gap-x-stack">
          <LineKey color="var(--market)" label="Market (zero skill)" />
          <LineKey color="var(--ink)" label="Candidate skill, 95% interval" marker />
        </div>
      }
      table={
        <DataTable
          caption={`Brier skill vs the market, ${splitLabel}, every candidate`}
          numeric
          dense
          columns={[
            { key: "candidate", header: "Candidate", rowHeader: true },
            { key: "brier", header: "Brier" },
            { key: "skill", header: "Skill" },
            { key: "interval", header: "95% interval" }
          ]}
          rows={data.map((d) => ({
            key: d.candidate,
            cells: {
              candidate: candidateLabel(d.candidate),
              brier: d.brier.toFixed(4),
              skill: signedPct(d.skill),
              interval: `${signedPct(d.skillLo)} to ${signedPct(d.skillHi)}`
            }
          }))}
        />
      }
    >
      <ChartTooltip>
        <div ref={ref}>
        <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} className="block h-auto max-w-full" role="img" aria-label={summary}>
          {ticks.map((t) => (
            <g key={t}>
              <line x1={x(t)} x2={x(t)} y1={top} y2={H - 28} stroke="var(--grid)" strokeWidth={1} />
              <text x={x(t)} y={H - 10} textAnchor="middle" fontSize={12} fill="var(--ink-muted)" className="num">
                {signedPct(t, 0)}
              </text>
            </g>
          ))}
          <line x1={x(0)} x2={x(0)} y1={top - 4} y2={H - 28} stroke="var(--market)" strokeWidth={2} />
          {data.map((d, i) => {
            const cy = top + i * rowH + (stacked ? 32 : rowH / 2);
            return (
              <g key={d.candidate}>
                <text x={stacked ? 0 : left - 12} y={stacked ? cy - 14 : cy + 5} textAnchor={stacked ? "start" : "end"} fontSize={14} fill="var(--ink)">
                  {candidateLabel(d.candidate)}
                </text>
                <line x1={x(d.skillLo)} x2={x(d.skillHi)} y1={cy} y2={cy} stroke="var(--ink-2)" strokeWidth={2} strokeLinecap="round" />
                <circle cx={x(d.skill)} cy={cy} r={5} fill="var(--ink)" stroke="var(--surface)" strokeWidth={2} />
                <rect
                  x={left}
                  y={cy - 12}
                  width={W - left - right}
                  height={24}
                  fill="transparent"
                  tabIndex={0}
                  role="graphics-symbol"
                  aria-label={`${candidateLabel(d.candidate)}: ${signedPct(d.skill)}, interval ${signedPct(d.skillLo)} to ${signedPct(d.skillHi)}`}
                  data-tip-value={`${signedPct(d.skill)} (${signedPct(d.skillLo)} to ${signedPct(d.skillHi)})`}
                  data-tip-label={`${candidateLabel(d.candidate)}, Brier ${d.brier.toFixed(4)}`}
                />
              </g>
            );
          })}
        </svg>
        </div>
      </ChartTooltip>
    </ChartFigure>
  );
}
```

<!-- apply: T7.3 create web/src/components/charts/ClvHistogram.tsx -->
```tsx
"use client";

import { scaleLinear } from "@visx/scale";
import { DataTable } from "@/components/ui";
import { bps, signedPct } from "@/lib/format";
import { candidateLabel } from "@/lib/policy";
import { ChartFigure, LineKey } from "./ChartFigure";
import { ChartTooltip } from "./ChartTooltip";
import { useChartWidth } from "./useChartWidth";

/**
 * Distribution of per-pick closing-line value (bps) for one candidate: columns of
 * pick counts per 50-bps bin, a zero line, and the mean with its bootstrap interval.
 * Descriptive only: the betting-value gate needs 400 decision-time picks (A2).
 */
export function ClvHistogram({
  candidate,
  values,
  meanCi,
  roi
}: {
  candidate: string;
  values: number[];
  meanCi: { mean: number; lo: number; hi: number } | null;
  roi: number | null;
}) {
  const [ref, W] = useChartWidth(720);
  const H = W < 560 ? 220 : 260;
  const left = 44;
  const right = 16;
  const top = 16;
  const bottom = 40;
  const width = 50;
  const lo = Math.max(-800, Math.floor(Math.min(...values, -200) / width) * width);
  const hi = Math.min(800, Math.ceil(Math.max(...values, 200) / width) * width);
  const edges: number[] = [];
  for (let e = lo; e < hi; e += width) edges.push(e);
  const counts = edges.map((e) => values.filter((v) => (v >= e && v < e + width) || (e === lo && v < lo) || (e === hi - width && v >= hi)).length);
  const x = scaleLinear({ domain: [lo, hi], range: [left, W - right] });
  const y = scaleLinear({ domain: [0, Math.max(1, ...counts)], range: [H - bottom, top], nice: true });
  // columns fill the bin less a 2px surface gap; the rounded data-end shrinks with thin columns
  const barW = Math.max(1, Math.min(24, x(lo + width) - x(lo) - 2));
  const rr = Math.min(4, barW / 2);
  const n = values.length;
  const mean = n ? values.reduce((a, b) => a + b, 0) / n : 0;
  const summary =
    `${candidateLabel(candidate)}: ${n} decision-time picks at the 2024 ESPN BET opener. Mean CLV ${bps(mean)}` +
    (meanCi ? ` (95% interval ${bps(meanCi.lo)} to ${bps(meanCi.hi)})` : "") +
    (roi !== null ? `; flat-stake ROI ${signedPct(roi, 1)}.` : ".") +
    ` Descriptive only: fewer than the 400 picks the betting-value gate requires.`;

  return (
    <ChartFigure
      title={`Closing-line value per pick, ${candidateLabel(candidate)}`}
      summary={summary}
      legend={
        <div className="flex flex-wrap gap-x-stack">
          <LineKey color="var(--model)" label="Picks per 50-bps bin" />
          <LineKey color="var(--ink)" label="Mean and 95% interval" />
        </div>
      }
      table={
        <DataTable
          caption={`Closing-line value per pick, ${candidateLabel(candidate)}, every bin`}
          numeric
          dense
          columns={[
            { key: "bin", header: "CLV bin (bps)", rowHeader: true },
            { key: "picks", header: "Picks" }
          ]}
          rows={edges.map((e, i) => ({ key: String(e), cells: { bin: `${e} to ${e + width}`, picks: counts[i] } }))}
        />
      }
    >
      <ChartTooltip>
        <div ref={ref}>
        <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} className="block h-auto max-w-full" role="img" aria-label={summary}>
          {y.ticks(4).map((t) => (
            <g key={t}>
              <line x1={left} x2={W - right} y1={y(t)} y2={y(t)} stroke="var(--grid)" strokeWidth={1} />
              <text x={left - 8} y={y(t) + 4} textAnchor="end" fontSize={12} fill="var(--ink-muted)" className="num">{t}</text>
            </g>
          ))}
          {edges.map((e, i) => {
            const h = y(0) - y(counts[i] ?? 0);
            const cx = x(e + width / 2);
            return (
              <g key={e}>
                {h > 0 ? (
                  <path
                    d={`M${cx - barW / 2},${y(0)} v${-(h - rr)} q0,${-rr} ${rr},${-rr} h${barW - 2 * rr} q${rr},0 ${rr},${rr} v${h - rr} z`}
                    fill="var(--model)"
                  />
                ) : null}
                <rect
                  x={cx - (x(lo + width) - x(lo)) / 2}
                  y={top}
                  width={x(lo + width) - x(lo)}
                  height={H - bottom - top}
                  fill="transparent"
                  tabIndex={counts[i] ? 0 : -1}
                  role="graphics-symbol"
                  aria-label={`${e} to ${e + width} bps: ${counts[i]} picks`}
                  data-tip-value={`${counts[i]} picks`}
                  data-tip-label={`${e} to ${e + width} bps`}
                />
              </g>
            );
          })}
          <line x1={x(0)} x2={x(0)} y1={top} y2={H - bottom} stroke="var(--ink-muted)" strokeWidth={1} />
          {meanCi ? (
            <g>
              <line x1={x(meanCi.lo)} x2={x(meanCi.hi)} y1={top + 6} y2={top + 6} stroke="var(--ink)" strokeWidth={2} strokeLinecap="round" />
              <circle cx={x(meanCi.mean)} cy={top + 6} r={5} fill="var(--ink)" stroke="var(--surface)" strokeWidth={2} />
            </g>
          ) : null}
          {x.ticks(W < 560 ? 4 : 8).map((t) => (
            <text key={t} x={x(t)} y={H - 16} textAnchor="middle" fontSize={12} fill="var(--ink-muted)" className="num">{t}</text>
          ))}
          <text x={(left + W - right) / 2} y={H - 2} textAnchor="middle" fontSize={12} fill="var(--ink-2)">CLV (bps), side taken</text>
        </svg>
        </div>
      </ChartTooltip>
    </ChartFigure>
  );
}
```

<!-- apply: T7.3 create web/src/components/charts/ChartTooltip.tsx -->
```tsx
"use client";

import { useRef, useState } from "react";

/**
 * One tooltip for a chart. Marks (or their larger transparent hit areas) carry
 * data-tip-value and data-tip-label; the tooltip follows pointer and keyboard focus.
 * Values lead, labels follow; text is inserted as text, never HTML.
 */
export function ChartTooltip({ children }: { children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [tip, setTip] = useState<{ x: number; y: number; value: string; label: string } | null>(null);

  function show(target: EventTarget | null, clientX?: number, clientY?: number) {
    const el = (target as Element | null)?.closest?.("[data-tip-value]") as HTMLElement | SVGElement | null;
    const box = ref.current?.getBoundingClientRect();
    if (!el || !box) return setTip(null);
    const r = el.getBoundingClientRect();
    const x = (clientX ?? r.left + r.width / 2) - box.left;
    const y = (clientY ?? r.top) - box.top;
    setTip({ x, y, value: el.getAttribute("data-tip-value") ?? "", label: el.getAttribute("data-tip-label") ?? "" });
  }

  return (
    <div
      ref={ref}
      className="relative"
      onPointerMove={(e) => show(e.target, e.clientX, e.clientY)}
      onPointerLeave={() => setTip(null)}
      onFocus={(e) => show(e.target)}
      onBlur={() => setTip(null)}
    >
      {children}
      {tip ? (
        <div
          role="status"
          className="pointer-events-none absolute z-10 rounded-control border border-rule bg-surface px-2 py-1 text-sm"
          style={{ left: Math.max(0, tip.x + 12), top: Math.max(0, tip.y - 44) }}
        >
          <div className="num font-semibold text-ink">{tip.value}</div>
          <div className="text-ink-2">{tip.label}</div>
        </div>
      ) : null}
    </div>
  );
}
```

<!-- apply: T7.3 create web/src/components/charts/LazyScoreDistributionPlot.tsx -->
```tsx
"use client";

import dynamic from "next/dynamic";
import { type ComponentProps, useEffect, useRef, useState } from "react";
import type { ScoreDistributionPlot } from "./ScoreDistributionPlot";

// ssr: false keeps the plot (and its script) out of the server HTML and the first load; the
// figure's summary and table view are already there without it
const Plot = dynamic(() => import("./ScoreDistributionPlot").then((m) => m.ScoreDistributionPlot), { ssr: false });

/**
 * The slot a score-distribution plot draws into. It reserves the plot's height (240px on a
 * phone-wide container, 280px otherwise, as the plot picks) so nothing shifts when the plot
 * arrives, and loads the plot once the slot is within 400px of the viewport (at once where
 * IntersectionObserver is missing).
 */
export function LazyScoreDistributionPlot(props: ComponentProps<typeof ScoreDistributionPlot>) {
  const slot = useRef<HTMLDivElement>(null);
  const [near, setNear] = useState(false);
  useEffect(() => {
    const el = slot.current;
    if (!el) return;
    if (typeof IntersectionObserver === "undefined") {
      const frame = requestAnimationFrame(() => setNear(true));
      return () => cancelAnimationFrame(frame);
    }
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          setNear(true);
          io.disconnect();
        }
      },
      { rootMargin: "400px 0px" }
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return (
    <div ref={slot} data-plot-slot className="min-h-60 sm:min-h-70">
      {near ? <Plot {...props} /> : null}
    </div>
  );
}
```

<!-- apply: T7.3 create web/src/components/charts/ScoreDistributionPlot.tsx -->
```tsx
"use client";

import { useState } from "react";
import {
  type Bin,
  binQuantile,
  columnPath,
  type DistKind,
  distributionSummary,
  outcomeLabel,
  stepPaths,
  ticksEvery
} from "@/lib/distribution";
import { linearScale } from "@/lib/linearScale";
import { useChartWidth } from "./useChartWidth";

/**
 * The plot of one simulated margin or total: one-point columns, ticks on football steps (7
 * points for margins, 10 for totals) and labelled markers for the simulator's median (model
 * gold) and, once the game is final, the result (actual rose). Where a one-point column would
 * be under 5px wide (phones) a step outline with a 10% wash keeps every outcome visible. A
 * crosshair snaps to the nearest outcome on pointer or arrow keys. This is the client half of
 * ScoreDistributionChart; LazyScoreDistributionPlot loads it as the slot nears the viewport,
 * so its script is off the page's first load.
 */
export function ScoreDistributionPlot({
  kind,
  bins,
  homeId,
  awayId,
  nSims,
  result
}: {
  kind: DistKind;
  bins: Bin[];
  homeId: string;
  awayId: string;
  nSims: number | null;
  result: number | null;
}) {
  const [ref, W] = useChartWidth(720);
  const [focus, setFocus] = useState<number | null>(null);
  const H = W < 560 ? 240 : 280;
  const left = 44;
  const right = 16;
  const top = 44;
  const bottom = 30;
  const first = bins[0]!.x;
  const lo = first - 0.5;
  const hi = bins[bins.length - 1]!.x + 0.5;
  const x = linearScale({ domain: [lo, hi], range: [left, W - right] });
  const y = linearScale({ domain: [0, Math.max(...bins.map((b) => b.p))], range: [H - bottom, top], nice: true });
  const binPx = x(first + 0.5) - x(lo);
  const columns = binPx >= 5;
  const barW = Math.min(24, binPx - 2);
  const label = (v: number) => outcomeLabel(kind, v, homeId, awayId);
  const share = (p: number) => `${(p * 100).toFixed(2)}%`;
  const summary = distributionSummary(kind, bins, nSims, homeId, awayId, result);
  const median = binQuantile(bins, 0.5);
  const focused = focus === null ? null : (bins[focus] ?? null);
  // ticks on multiples of 7 (margins) or 10 (totals), widened until labels are 72px / 40px apart
  const base = kind === "margin" ? 7 : 10;
  const step = base * Math.max(1, Math.ceil((kind === "margin" ? 72 : 40) / (binPx * base)));
  const markers = [
    { v: median, text: `Median ${label(median)}`, color: "var(--model)", row: 0 },
    ...(result !== null && result >= lo && result <= hi ? [{ v: result, text: `Final ${label(result)}`, color: "var(--actual)", row: 1 }] : [])
  ];
  const anchor = (px: number) => (px > W - 130 ? "end" : px < left + 130 ? "start" : "middle");
  const nearest = (clientX: number, svg: SVGSVGElement) => {
    const v = Math.round(x.invert(clientX - svg.getBoundingClientRect().left));
    return Math.min(Math.max(v - first, 0), bins.length - 1);
  };
  const { line, area } = stepPaths(bins, x, y);

  return (
    <div ref={ref} className="relative">
      <svg
        width={W}
        height={H}
        viewBox={`0 0 ${W} ${H}`}
        className="block h-auto max-w-full"
        role="img"
        aria-label={summary}
        tabIndex={0}
        onPointerMove={(e) => setFocus(nearest(e.clientX, e.currentTarget))}
        onPointerLeave={() => setFocus(null)}
        onBlur={() => setFocus(null)}
        onKeyDown={(e) => {
          const i = focus ?? bins.findIndex((b) => b.x === median);
          if (e.key === "ArrowRight") setFocus(Math.min(i + 1, bins.length - 1));
          else if (e.key === "ArrowLeft") setFocus(Math.max(i - 1, 0));
          else if (e.key === "Home") setFocus(0);
          else if (e.key === "End") setFocus(bins.length - 1);
          else return;
          e.preventDefault();
        }}
      >
        {y.ticks(4).map((t) => (
          <g key={t}>
            <line x1={left} x2={W - right} y1={y(t)} y2={y(t)} stroke="var(--grid)" strokeWidth={1} />
            <text x={left - 8} y={y(t) + 4} textAnchor="end" fontSize={12} fill="var(--ink-muted)" className="num">
              {t === 0 ? "0%" : `${(t * 100).toFixed(t < 0.01 ? 1 : 0)}%`}
            </text>
          </g>
        ))}
        {columns ? (
          bins.map((b) => (b.p > 0 ? <path key={b.x} d={columnPath(x(b.x), y(0), y(0) - y(b.p), barW, 2)} fill="var(--ink-muted)" /> : null))
        ) : (
          <>
            <path d={area} fill="var(--ink-muted)" fillOpacity={0.1} />
            <path d={line} fill="none" stroke="var(--ink-muted)" strokeWidth={2} strokeLinejoin="round" />
          </>
        )}
        <line x1={left} x2={W - right} y1={y(0)} y2={y(0)} stroke="var(--rule)" strokeWidth={1} />
        {kind === "margin" && lo < 0 && hi > 0 ? <line x1={x(0)} x2={x(0)} y1={top} y2={y(0)} stroke="var(--ink-muted)" strokeWidth={1} /> : null}
        {markers.map((m) => (
          <g key={m.text}>
            {/* lines start below both label rows, so no marker crosses another marker's label */}
            <line x1={x(m.v)} x2={x(m.v)} y1={top - 6} y2={y(0)} stroke={m.color} strokeWidth={2} />
            <text x={x(m.v) + (anchor(x(m.v)) === "start" ? 6 : anchor(x(m.v)) === "end" ? -6 : 0)} y={10 + m.row * 16}
              textAnchor={anchor(x(m.v))} fontSize={12} fontWeight={600} fill="var(--ink-2)">{m.text}</text>
          </g>
        ))}
        {focused ? <line x1={x(focused.x)} x2={x(focused.x)} y1={top} y2={y(0)} stroke="var(--ink)" strokeWidth={1} /> : null}
        {ticksEvery(lo, hi, step).map((t) => (
          <text key={t} x={x(t)} y={H - 10} textAnchor="middle" fontSize={12} fill="var(--ink-muted)" className="num">
            {kind === "margin" ? label(t) : t}
          </text>
        ))}
      </svg>
      {focused ? (
        <div
          role="status"
          className="pointer-events-none absolute z-10 rounded-control border border-rule bg-surface px-2 py-1 text-sm"
          style={{ left: Math.min(Math.max(0, x(focused.x) + 12), Math.max(0, W - 170)), top: 40 }}
        >
          <div className="num font-semibold text-ink">{share(focused.p)} of simulated games</div>
          <div className="text-ink-2">{label(focused.x)}</div>
        </div>
      ) : null}
    </div>
  );
}
```

<!-- apply: T7.3 create web/src/app/games/[id]/page.tsx -->
```tsx
import Link from "next/link";
import { notFound } from "next/navigation";
import { DataUnavailable } from "@/components/DataUnavailable";
import { Field, FieldKey, gapText } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { ScoreDistributionChart } from "@/components/charts/ScoreDistributionChart";
import { Breadcrumb, Card, ContextList, Grid, Page, Section, Term } from "@/components/ui";
import { runContext } from "@/lib/context";
import { candidateLines, gameDistributions, publicGame, publicGates, runCandidates } from "@/lib/data/queries";
import { parseBins } from "@/lib/parseBins";
import { kickoff, pct } from "@/lib/format";
import { candidateLabel, fieldLineShortNote, publicFieldLine } from "@/lib/policy";
import { teamColors } from "@/lib/teams";

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return { title: id.replace(/_/g, " ") };
}

function TeamBlock({ id, name, big, side, winner }: { id: string; name: string; big: string; side: "away" | "home"; winner: boolean }) {
  const c = teamColors(id);
  const code = (
    <div className={`flex flex-col gap-tight ${side === "home" ? "items-end text-right" : ""}`}>
      <span className="wdth-expanded text-title font-black">{id}</span>
      <span className="text-base font-medium">{name}</span>
    </div>
  );
  const value = (
    <span className="flex items-center gap-control">
      {winner ? <span className="rounded-control px-2 py-0.5 text-sm font-bold" style={{ background: c.ink, color: c.primary }}>Won</span> : null}
      <span className="num wdth-expanded text-score font-black">{big}</span>
    </span>
  );
  return (
    <div
      className="flex items-center justify-between gap-stack p-6 sm:px-8"
      style={{ background: c.primary, color: c.ink, boxShadow: `inset ${side === "away" ? 8 : -8}px 0 0 ${c.accent}` }}
    >
      {side === "away" ? (
        <>
          {code}
          {value}
        </>
      ) : (
        <>
          {value}
          {code}
        </>
      )}
    </div>
  );
}

export default async function GamePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9]{4}_[0-9]{2}_[A-Z]{2,3}_[A-Z]{2,3}$/.test(id)) notFound();
  // the game and the promotion gates are independent: one round trip for both
  const [{ run, game }, gates] = await Promise.all([publicGame(id), publicGates()]);
  if (!run || !game) notFound();
  const line = publicFieldLine(gates, await runCandidates(run.runId));
  const label = line ? candidateLabel(line.candidate) : "Model";
  const [lines, dist] = await Promise.all([line ? candidateLines(run.runId, [line.candidate], [id]) : Promise.resolve([]), gameDistributions(run.runId, id)]);
  const pm = game.pMarket;
  const pmod = lines[0]?.p ?? null;
  const hasDist = dist.margin !== null || dist.total !== null;
  const final = game.homeScore !== null && game.awayScore !== null ? { home: game.homeScore, away: game.awayScore } : null;

  return (
    <Page>
      <div className="flex flex-col gap-control">
        <Breadcrumb
          items={[
            { label: "This week", href: "/" },
            { label: `Week ${game.week}, ${game.season}` },
            { label: `${game.awayTeamId} ${game.neutral ? "vs" : "at"} ${game.homeTeamId}` }
          ]}
        />
        <ContextList items={runContext(run, { omitWeek: true })} />
      </div>

      <h1 className="sr-only">
        {game.awayName} {game.neutral ? "vs" : "at"} {game.homeName}
      </h1>
      <section aria-label={final ? "Final score" : "Market win chance"} data-section className="grid overflow-hidden rounded-card border border-rule lg:grid-cols-[minmax(0,1fr)_16.25rem_minmax(0,1fr)]">
        <TeamBlock id={game.awayTeamId} name={game.awayName} side="away" big={final ? String(final.away) : pm === null ? "–" : pct(1 - pm)} winner={!!final && final.away > final.home} />
        <div className="flex flex-col items-center justify-center gap-snug bg-surface p-card text-center">
          <span className="wdth-expanded text-heading font-extrabold">{final ? "Final" : "Kickoff"}</span>
          <time dateTime={new Date(game.kickoffUtc).toISOString()} className="text-sm text-ink-2">
            {kickoff(game.kickoffUtc)}
          </time>
          <span className="text-sm text-muted">{final ? "Result" : <>Win chance, <Term id="no-vig">no-vig</Term> market</>}</span>
        </div>
        <TeamBlock id={game.homeTeamId} name={game.homeName} side="home" big={final ? String(final.home) : pm === null ? "–" : pct(pm)} winner={!!final && final.home > final.away} />
      </section>

      <Section id="prob" title="Win probability" aside={<FieldKey showModel={pmod !== null} modelLabel={label} validated={line?.validated ?? false} />}>
        <Field
          size="hero"
          gameId={game.gameId}
          awayId={game.awayTeamId}
          homeId={game.homeTeamId}
          awayName={game.awayName}
          homeName={game.homeName}
          kickoffUtc={game.kickoffUtc}
          neutral={game.neutral}
          pMarket={pm}
          model={pmod !== null && line ? { p: pmod, label, validated: line.validated } : null}
        />
        <p className="text-sm text-muted">
          Each team&apos;s side of the field is its chance to win.
          {pm !== null && pmod !== null ? ` ${gapText(pm, pmod, game.awayTeamId, game.homeTeamId)}.` : ""} <Term id="field">How to read the field</Term>.
        </p>
      </Section>

      <Section label="Market against model">
        <Grid kind="pair">
          <Card as="article" className="flex flex-col gap-control">
            <div className="flex items-baseline justify-between gap-control">
              <h3 className="font-bold">Moneyline · {game.homeTeamId} to win</h3>
              <span className="text-sm text-muted">nflverse consensus close</span>
            </div>
            <div className="grid grid-cols-2 gap-control">
              <div className="flex flex-col gap-tight">
                <span className="text-sm text-muted">
                  <Term id="no-vig">Market</Term>
                </span>
                <span className="num flex items-center gap-snug text-figure font-extrabold" data-line="market">
                  <span className="inline-block h-5.5 w-1" style={{ background: "var(--field-market)" }} aria-hidden />
                  {pm === null ? <span className="text-lg font-bold text-ink-2">No market line</span> : pct(pm, 1)}
                </span>
              </div>
              <div className="flex flex-col gap-tight">
                <span className="text-sm text-muted">{label}</span>
                <span className="num flex items-center gap-snug text-figure font-extrabold" data-line="model">
                  <span className="inline-block h-5.5 w-1" style={{ background: "var(--field-model)" }} aria-hidden />
                  {pct(pmod, 1)}
                </span>
              </div>
            </div>
            {line ? (
              <div className="flex flex-wrap items-center gap-snug border-t border-rule pt-control text-sm text-ink-2">
                <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated research model"} />
                <span>
                  {fieldLineShortNote(line)} <Link href="/evidence">Evidence</Link>
                </span>
              </div>
            ) : null}
          </Card>
          <Card as="article" className="flex flex-col gap-control">
            <h3 className="font-bold">Spread and total</h3>
            <p className="text-sm text-ink-2">
              In the validation sprint (Tune 2018–22) no model beat the devigged closing spread or total price, so no spread or
              total is offered here.{hasDist ? " The simulator's margin and total distributions below are research output." : ""}
            </p>
          </Card>
        </Grid>
      </Section>

      <Section id="dist" title="Simulated margin and total">
        {hasDist ? (
          <div className="flex flex-col gap-stack">
            {(["margin", "total"] as const).map((kind) => {
              const bins = parseBins(dist[kind]);
              return bins ? (
                <div key={kind} className="flex flex-col gap-snug">
                  <ScoreDistributionChart kind={kind} bins={bins} homeId={game.homeTeamId} awayId={game.awayTeamId} nSims={run.nSims}
                    result={final ? (kind === "margin" ? final.home - final.away : final.home + final.away) : null} />
                  {kind === "margin" ? <p className="text-sm text-muted">Regulation ties go to overtime, so an exact tie is rare.</p> : null}
                </div>
              ) : (
                <DataUnavailable key={kind} title={dist[kind] === null ? `No ${kind} distribution in this run` : `The ${kind} distribution is unreadable`}>
                  {dist[kind] === null
                    ? `The published run has no simulated ${kind} for this game.`
                    : `Its bins failed validation (one share per integer outcome, no gaps, shares between 0 and 1), so it is not drawn.`}
                </DataUnavailable>
              );
            })}
          </div>
        ) : (
          <DataUnavailable title="No simulator output in this run">
            The published run predicts win probabilities only. Margin and total distributions appear when the published run
            comes from the game simulator (run_week.R).
          </DataUnavailable>
        )}
      </Section>

      <Section id="moves" title="Line movement">
        <DataUnavailable title="One market snapshot">
          The nflverse consensus line has no timestamp or book, so there is nothing to plot over time. Per-venue movement,
          with kickoff and close markers, appears once forward-captured ESPN and Kalshi snapshots are ingested (Phase 2).
        </DataUnavailable>
      </Section>
    </Page>
  );
}
```

- [ ] **Step 4: Run the tests and see GREEN**

Run: `cd web && npx vitest run src/test/tokens.test.ts src/components/charts/ScoreDistributionChart.test.tsx`
Expected: `Test Files  2 passed (2)`, `Tests  11 passed (11)`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  24 passed (24)`, `Tests  167 passed (167)`.

```bash
git add web/src
git commit -m "feat(web): the game page and the chart tables on the shared components (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: The evidence page [haiku]

Evidence is the page with the most hand-copied structure (two tables, three cards, six hand-picked gaps between its blocks from 28 to 40 px). It moves onto the components, with its ceilings lowered first (5 arbitrary utilities and 2 `text-[Npx]` today; one grid template stays).

What changes:
- `PageHeader` with the backtest's context line (protocol id, run, data date) and a lead of two paragraphs, one linking "walk-forward".
- The three stat tiles each carry a source line, and their labels link "Brier score" and "skill vs market" to `/methodology`.
- The window and CLV pickers are `nav`s of 44 px chips; the skill and reliability charts sit in `Card`s under `Section`s whose titles are kept for assistive technology only (`srTitle`), as before.
- The promotion gates and the evidence ledger are `DataTable`s (captions "Promotion gates, Confirm stage" and "Evidence ledger", named as `"<caption> (table)"` regions so they do not collide with their section titles: this is the `landmark-unique` violation `main` has on this page). Controls and the protocol card sit in a `Grid kind="sections"` (two columns from `lg`, a section gap between them).
- Dates in the protocol card are `Stamp`s.
- With no backtest ingested the page says "No backtest ingested" and its context line reads "none published (no backtest has been ingested)".

**Files:**
- Create: `web/src/test/pages/evidence.test.tsx`
- Modify: `web/src/app/evidence/page.tsx`, `web/src/test/tokenCeilings.json`

**Interfaces:**
- Consumes: `Page`, `PageHeader`, `Section`, `Grid`, `Card`, `StatTile`, `DataTable`, `Stamp`, `Term`, `chipClass` (Task 2), `backtestContext`, `noRunContext` (Task 2), the chart components (Task 7).

- [ ] **Step 1: Write the failing tests**

<!-- apply: T8.1 create web/src/test/pages/evidence.test.tsx -->
```tsx
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// the evidence page before any backtest has been ingested
vi.mock("@/lib/data/queries", () => ({
  evidence: async () => null,
  ledger: async () => []
}));

describe("the evidence page with no backtest ingested", () => {
  // the first import of a page compiles its whole module graph; on a cold cache and a busy machine that takes longer than the 5 s default
  it("says so, states that in its context line, and has one h1", async () => {
    const { default: EvidencePage } = await import("../../app/evidence/page");
    const html = renderToStaticMarkup(await EvidencePage({ searchParams: Promise.resolve({}) }));
    expect(html).toContain("No backtest ingested");
    expect(html).toContain("none published (no backtest has been ingested)");
    expect(html.match(/<h1/g)).toHaveLength(1);
    expect(html).not.toMatch(/\bnull\b|undefined|NaN/);
  }, 30_000);
});
```

<!-- apply: T8.1 create web/src/test/tokenCeilings.json -->
```json
{
  "arbitrary": {
    "app/data-health/page.tsx": 1,
    "app/desk/page.tsx": 1,
    "app/evidence/page.tsx": 1,
    "app/games/[id]/page.tsx": 1,
    "app/methodology/page.tsx": 1,
    "components/Field.tsx": 1
  },
  "textPx": {}
}
```

- [ ] **Step 2: Run the tests and see RED**

Run: `cd web && npx vitest run src/test/pages/evidence.test.tsx src/test/tokens.test.ts`
Expected: FAIL, `Tests  3 failed | 6 passed (9)`: `app/evidence/page.tsx: 5 arbitrary utilities, ceiling 1`, `2 text-[Npx], ceiling 0`, and the old page's empty state lacks the context line.

- [ ] **Step 3: Write the page**

<!-- apply: T8.3 create web/src/app/evidence/page.tsx -->
```tsx
import Link from "next/link";
import { ClvHistogram } from "@/components/charts/ClvHistogram";
import { ReliabilityGrid } from "@/components/charts/ReliabilityGrid";
import { SkillIntervals } from "@/components/charts/SkillIntervals";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, chipClass, DataTable, Grid, Page, PageHeader, Section, Stamp, StatTile, Term } from "@/components/ui";
import { backtestContext, noRunContext } from "@/lib/context";
import { evidence, ledger } from "@/lib/data/queries";
import { bps, shortSha, signedPct } from "@/lib/format";
import { candidateLabel } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = { title: "Evidence" };

type Split = "confirm" | "tune";
const SPLIT_LABEL: Record<Split, string> = { confirm: "Confirm 2023–24", tune: "Tune 2018–22 (in-sample for selection)" };

interface ClvAgg {
  n: number;
  mean_clv_bps: number;
  clv_ci: [number, number];
  roi: number;
  roi_ci: [number, number];
}

export default async function EvidencePage({ searchParams }: { searchParams: Promise<{ split?: string; clv?: string }> }) {
  const sp = await searchParams;
  const split: Split = sp.split === "tune" ? "tune" : "confirm";
  const [ev, claims] = await Promise.all([evidence(), ledger()]);

  if (!ev) {
    return (
      <Page>
        <PageHeader title="Evidence" context={noRunContext("no backtest has been ingested")} />
        <DataUnavailable title="No backtest ingested">A backtest bundle appears here after ingest.</DataUnavailable>
      </Page>
    );
  }

  const pooled = ev.metrics.filter((m) => m.split === split && m.phase === "pooled");
  const market = pooled.find((m) => m.candidate === "C0");
  const confirm = ev.metrics.filter((m) => m.split === "confirm" && m.phase === "pooled" && m.candidate !== "C0");
  const confirmMarket = ev.metrics.find((m) => m.split === "confirm" && m.phase === "pooled" && m.candidate === "C0");
  const best = [...confirm].sort((a, b) => b.skill - a.skill)[0];
  const passing = ev.gates.filter((g) => g.brierStatus.startsWith("passes"));
  const clvSummary = (ev.bt.clvSummary ?? {}) as Record<string, ClvAgg | { venue: string; tau: number }>;
  const clvCands = [...new Set(ev.clv.map((c) => c.candidate))];
  const clvCand = sp.clv && clvCands.includes(sp.clv) ? sp.clv : clvCands.includes("C2") ? "C2" : clvCands[0];
  const clvAgg = clvCand ? (clvSummary[clvCand] as ClvAgg | undefined) : undefined;
  const controls = ev.bt.controls as Record<string, { passed?: boolean } & Record<string, unknown>>;
  const folds = (ev.window?.folds ?? {}) as Record<string, { seasons: number[] | string; use: string; sealed?: boolean }>;
  const q = (s: Split, c?: string) => `/evidence?split=${s}${c ? `&clv=${encodeURIComponent(c)}` : ""}`;
  const protocol = ev.window?.windowId ?? "the registered protocol";

  return (
    <Page>
      <PageHeader
        title="Evidence"
        lead={
          <div className="flex flex-col gap-snug">
            <p className="text-ink">
              {passing.length
                ? `${passing.map((g) => candidateLabel(g.candidate)).join(", ")} passed the Confirm-stage gates; the sealed 2025 holdout is still pending.`
                : "No model or blend beat the no-vig closing market in the pre-registered test."}
            </p>
            <p>
              Protocol <code className="text-sm">{ev.window?.windowId}</code> was frozen and pushed before any Confirm-window
              scoring, and every candidate was refit <Term id="walk-forward">walk-forward</Term>, week by week, on data available
              before kickoff. <Link href="/methodology">How it works</Link>
            </p>
          </div>
        }
        context={backtestContext({ windowId: ev.window?.windowId ?? null, cycleId: ev.run.cycleId, dataAsofUtc: ev.run.dataAsofUtc })}
      />

      <Section label="The test in numbers">
        <Grid kind="tiles">
          <StatTile value={confirm[0]?.n ?? "–"} label="Confirm games scored" source={`Protocol ${protocol}, Confirm 2023–24`} />
          <StatTile
            value={confirmMarket?.brier.toFixed(4) ?? "–"}
            label={
              <>
                Market <Term id="brier">Brier score</Term> (lower is better)
              </>
            }
            source="The no-vig closing market, Confirm 2023–24"
          />
          <StatTile
            value={best ? signedPct(best.skill) : "–"}
            label={
              <>
                Closest candidate, <Term id="skill">skill vs market</Term>
                {best ? `: ${candidateLabel(best.candidate)}; 95% interval ${signedPct(best.skillLo)} to ${signedPct(best.skillHi)}` : ""}
              </>
            }
            source="Confirm 2023–24, paired week-block bootstrap of 10,000 resamples"
          />
        </Grid>
      </Section>

      <nav className="flex flex-wrap items-center gap-snug border-y border-rule py-card-sm" aria-label="Window">
        <span className="text-sm text-muted">Window</span>
        {(["confirm", "tune"] as Split[]).map((s) => (
          <Link key={s} href={q(s, clvCand)} aria-current={s === split ? "true" : undefined} className={chipClass(s === split)}>
            {SPLIT_LABEL[s]}
          </Link>
        ))}
      </nav>

      <Section id="skill" title="Brier skill" srTitle>
        <Card className="flex flex-col gap-control">
          <SkillIntervals splitLabel={SPLIT_LABEL[split]} rows={pooled} />
          {market ? (
            <p className="text-sm text-muted">
              Market <Term id="brier">Brier</Term> {market.brier.toFixed(4)} on {market.n} games. <Term id="skill">Skill</Term> = 1 − Brier(candidate) / Brier(market);
              intervals from a paired week-block bootstrap (10,000 resamples).
            </p>
          ) : null}
        </Card>
      </Section>

      <Section id="rel" title="Reliability" srTitle>
        <Card>
          <ReliabilityGrid
            splitLabel={SPLIT_LABEL[split]}
            bins={ev.bins.filter((b) => b.split === split)}
            ece={Object.fromEntries(pooled.map((m) => [m.candidate, m.ece]))}
          />
        </Card>
      </Section>

      <Section id="gates" title="Promotion gates, Confirm stage">
        <p className="max-w-measure text-sm text-ink-2">
          G1: skill interval above zero. G2: Diebold–Mariano beats the market after Benjamini–Hochberg. G3: calibration
          slope interval contains 1 and <Term id="ece">ECE</Term> within 0.005 of the market. G4: every control passed. G1 and G2 must also hold
          on the sealed 2025 holdout.
        </p>
        <Card>
          <DataTable
            caption="Promotion gates, Confirm stage"
            minWidth="table"
            columns={[
              { key: "candidate", header: "Candidate", rowHeader: true },
              { key: "g1", header: "G1" },
              { key: "g2", header: "G2" },
              { key: "g3", header: "G3" },
              { key: "g4", header: "G4" },
              { key: "brier", header: "Brier status" },
              { key: "value", header: "Betting value" }
            ]}
            rows={ev.gates.map((g) => {
              const pass = (v: boolean) => <StatusBadge status={v ? "passes" : "failed"} label={v ? "Pass" : "Fail"} />;
              return {
                key: g.candidate,
                cells: {
                  candidate: candidateLabel(g.candidate),
                  g1: pass(g.g1),
                  g2: pass(g.g2),
                  g3: pass(g.g3),
                  g4: pass(g.g4),
                  brier: <StatusBadge status={g.brierStatus} />,
                  value: <span className="text-ink-2">{g.bettingValueStatus}</span>
                }
              };
            })}
          />
        </Card>
      </Section>

      <Section id="clv" title="Closing-line value at the opener">
        <nav className="flex flex-wrap items-center gap-snug" aria-label="CLV candidate">
          <span className="text-sm text-muted">Candidate</span>
          {clvCands.map((c) => (
            <Link key={c} href={q(split, c)} aria-current={c === clvCand ? "true" : undefined} className={chipClass(c === clvCand)}>
              {candidateLabel(c)}
            </Link>
          ))}
        </nav>
        <Card className="flex flex-col gap-control">
          {clvCand ? (
            <ClvHistogram
              candidate={clvCand}
              values={ev.clv.filter((c) => c.candidate === clvCand).map((c) => c.clvBps)}
              meanCi={clvAgg ? { mean: clvAgg.mean_clv_bps, lo: clvAgg.clv_ci[0], hi: clvAgg.clv_ci[1] } : null}
              roi={clvAgg?.roi ?? null}
            />
          ) : null}
          <p className="max-w-measure text-sm text-muted">
            Pick rule: the side where the model beats the ESPN BET no-vig opener by 3 points or more. <Term id="clv">CLV</Term> = 10,000 × (close −
            open), both no-vig at the same venue. Four candidates were examined and the intervals are not corrected for that.
            {clvAgg ? ` ${candidateLabel(clvCand!)}: ${clvAgg.n} picks, mean ${bps(clvAgg.mean_clv_bps)}.` : ""}
          </p>
        </Card>
      </Section>

      <Grid kind="sections">
        <Section id="controls" title="Controls">
          <Card className="flex flex-col gap-control">
            <p className="text-sm text-ink-2">Any failed control voids the run. Run status: <StatusBadge status={ev.bt.status} /></p>
            <ul className="divide-y divide-rule text-sm">
              {Object.entries(controls)
                .filter(([, v]) => v && typeof v === "object" && "passed" in v)
                .map(([k, v]) => (
                  <li key={k} className="flex items-center justify-between py-row first:pt-0 last:pb-0">
                    <span>{k.replace(/_/g, " ")}</span>
                    <StatusBadge status={v.passed ? "passes" : "failed"} label={v.passed ? "Passed" : "Failed"} />
                  </li>
                ))}
            </ul>
          </Card>
        </Section>

        <Section id="repro" title="Protocol and reproducibility">
          <Card className="flex flex-col gap-control">
            <dl className="num grid grid-cols-1 gap-x-stack gap-y-snug text-sm sm:grid-cols-[max-content_1fr]">
              <dt className="text-ink-2">Protocol sha256</dt><dd className="break-all">{ev.window?.protocolSha256}</dd>
              <dt className="text-ink-2">Frozen</dt><dd><Stamp iso={ev.window?.frozenAtUtc} /></dd>
              <dt className="text-ink-2">Result sha256</dt><dd className="break-all">{ev.bt.resultSha256}</dd>
              <dt className="text-ink-2">Code</dt><dd>{shortSha(ev.bt.codeGitSha)}</dd>
              <dt className="text-ink-2">Scored</dt><dd><Stamp iso={ev.bt.generatedUtc} /></dd>
            </dl>
            <ul className="divide-y divide-rule border-t border-rule text-sm">
              {Object.entries(folds).map(([name, f]) => (
                <li key={name} className="flex flex-wrap items-center justify-between gap-snug py-row last:pb-0">
                  <span>
                    <span className="capitalize">{name.replace("_", "-")}</span>{" "}
                    <span className="num text-ink-2">{Array.isArray(f.seasons) ? `${f.seasons[0]}–${f.seasons[f.seasons.length - 1]}` : f.seasons}</span>
                  </span>
                  <span className="text-ink-2">{f.sealed ? <StatusBadge status="pending" label="Sealed" /> : f.use}</span>
                </li>
              ))}
            </ul>
          </Card>
        </Section>
      </Grid>

      <Section id="ledger" title="Evidence ledger">
        <p className="max-w-measure text-sm text-ink-2">Every quantitative claim about the model, including withdrawn ones and negative results.</p>
        <Card>
          <DataTable
            caption="Evidence ledger"
            topAligned
            minWidth="table-wide"
            columns={[
              { key: "claim", header: "Claim" },
              { key: "status", header: "Status" },
              { key: "reason", header: "Reason" }
            ]}
            rows={claims.map((c) => ({
              key: c.claimId,
              cells: { claim: c.claim, status: <StatusBadge status={c.status} />, reason: <span className="text-ink-2">{c.reason}</span> }
            }))}
          />
        </Card>
      </Section>
    </Page>
  );
}
```

- [ ] **Step 4: Run the tests and see GREEN**

Run: `cd web && npx vitest run src/test/pages/evidence.test.tsx src/test/tokens.test.ts`
Expected: `Test Files  2 passed (2)`, `Tests  9 passed (9)`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  25 passed (25)`, `Tests  168 passed (168)`.

```bash
git add web/src
git commit -m "feat(web): the evidence page on the shared components, with a context line and sourced tiles (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Data health, methodology (with its definitions) and props [haiku]

Three pages move over in one task because each is small.

- **Data health:** `PageHeader` with the run's context line (or "none published"), the sources table a `DataTable` (the last-success cell is a `Stamp` plus the relative age, still inside `[data-age]`, so `@parity` stays at zero differing pixels), and the recent-runs and ingest-log sections in a `Grid kind="sections"`.
- **Methodology:** the page is a column of `Section`s capped at the 672 px measure (it was one `<article>` 880 px wide, about a hundred characters a line), with the terms linked inline, and a new **Definitions** section that renders every term of `lib/glossary.ts` with an id (`term-brier`, `term-no-vig`, ...). That is what every `Term` link on every page lands on; the `:target` rule from Task 2 marks the entry you arrive at.
- **Props:** the three market groups are `Section`s in a `Grid kind="tiles"` (their titles were `font-bold` with no size), and the page states that no run is published for props instead of leaving the context line out.

**Files:**
- Create: `web/src/test/pages/dataHealth.test.tsx`, `web/src/test/pages/methodology.test.tsx`
- Modify: `web/src/app/data-health/page.tsx`, `web/src/app/methodology/page.tsx`, `web/src/app/props/page.tsx`, `web/src/test/tokenCeilings.json`

**Interfaces:**
- Consumes: the components of Task 2, `runContext` and `noRunContext`, `TERMS`, `TERM_IDS` and `termAnchor` (Task 2).

- [ ] **Step 1: Write the failing tests**

<!-- apply: T9.1 create web/src/test/pages/dataHealth.test.tsx -->
```tsx
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// data health before anything has been ingested
vi.mock("@/lib/data/queries", () => ({
  dataHealth: async () => ({ run: null, sources: [], ingests: [], runs: [] })
}));

describe("the data-health page with nothing ingested", () => {
  // the first import of a page compiles its whole module graph; on a cold cache and a busy machine that takes longer than the 5 s default
  it("says there is no run, states that in its context line, and still draws every section", async () => {
    const { default: DataHealthPage } = await import("../../app/data-health/page");
    const html = renderToStaticMarkup(await DataHealthPage());
    expect(html).toContain("No published weekly run");
    expect(html).toContain("none published (nothing has been ingested)");
    for (const title of ["Sources for this run", "Recent runs", "Ingest log", "Unmatched entities"]) expect(html, title).toContain(title);
    expect(html.match(/<h1/g)).toHaveLength(1);
    expect(html).not.toMatch(/\bnull\b|undefined|NaN/);
  }, 30_000);
});
```

<!-- apply: T9.1 create web/src/test/pages/methodology.test.tsx -->
```tsx
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { TERM_IDS, termAnchor } from "../../lib/glossary";

// the methodology page before anything has been ingested: it is generated from runs, but it must still read
vi.mock("@/lib/data/queries", () => ({
  evidence: async () => null,
  pointerRun: async () => null,
  ledger: async () => []
}));

describe("the methodology page with nothing ingested", () => {
  // the first import of a page compiles its whole module graph; on a cold cache and a busy machine that takes longer than the 5 s default
  it("still defines every term, states that it has no run, and has one h1", async () => {
    const { default: MethodologyPage } = await import("../../app/methodology/page");
    const html = renderToStaticMarkup(await MethodologyPage());
    expect(html).toContain("none published (nothing has been ingested)");
    for (const id of TERM_IDS) expect(html, id).toContain(`id="${termAnchor(id)}"`);
    expect(html.match(/<h1/g)).toHaveLength(1);
    expect(html).not.toMatch(/\bnull\b|undefined|NaN/);
  }, 30_000);
});
```

<!-- apply: T9.1 create web/src/test/tokenCeilings.json -->
```json
{
  "arbitrary": {
    "app/desk/page.tsx": 1,
    "app/evidence/page.tsx": 1,
    "app/games/[id]/page.tsx": 1,
    "components/Field.tsx": 1
  },
  "textPx": {}
}
```

- [ ] **Step 2: Run the tests and see RED**

Run: `cd web && npx vitest run src/test/pages/dataHealth.test.tsx src/test/pages/methodology.test.tsx src/test/tokens.test.ts`
Expected: FAIL, `Test Files  3 failed (3)`, `Failed Tests 3`: the ratchet names `app/data-health/page.tsx` and `app/methodology/page.tsx`, and neither old page has the "none published" context line.

- [ ] **Step 3: Write the pages**

<!-- apply: T9.3 create web/src/app/data-health/page.tsx -->
```tsx
import { Age } from "@/components/Age";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, DataTable, Grid, Page, PageHeader, Section, Stamp } from "@/components/ui";
import { noRunContext, runContext } from "@/lib/context";
import { dataHealth } from "@/lib/data/queries";
import { shortSha } from "@/lib/format";

export const dynamic = "force-dynamic";
export const metadata = { title: "Data health" };

export default async function DataHealthPage() {
  const { run, sources, ingests, runs } = await dataHealth();
  return (
    <Page>
      <PageHeader
        title="Data health"
        lead={
          run ? (
            <p>
              Published weekly run generated <Stamp iso={run.generatedUtc} /> from code {shortSha(run.codeGitSha)}
              {run.codeDirty ? " (uncommitted changes)" : ""}. QA:{" "}
              <StatusBadge status={run.qaOk ? "ok" : "qa_failed"} label={run.qaOk ? "Passed" : "Failed"} />
            </p>
          ) : undefined
        }
        context={run ? runContext(run) : noRunContext("nothing has been ingested")}
      />
      {run ? null : <DataUnavailable title="No published weekly run">Nothing ingested yet.</DataUnavailable>}

      <Section id="sources" title="Sources for this run">
        <Card>
          <DataTable
            caption="Sources for this run"
            topAligned
            minWidth="table"
            columns={[
              { key: "source", header: "Source", rowHeader: true },
              { key: "status", header: "Status" },
              { key: "last", header: "Last success" },
              { key: "detail", header: "Detail" }
            ]}
            rows={sources.map((s) => ({
              key: s.source,
              cells: {
                source: s.source.replace(/_/g, " "),
                status: <StatusBadge status={s.status} />,
                last: s.lastSuccessUtc ? (
                  <span className="num">
                    <Stamp iso={s.lastSuccessUtc} /> (<Age iso={s.lastSuccessUtc} />)
                  </span>
                ) : (
                  "–"
                ),
                detail: <span className="text-ink-2">{s.detail}</span>
              }
            }))}
          />
        </Card>
      </Section>

      <Grid kind="sections">
        <Section id="runs" title="Recent runs">
          <Card>
            <ul className="divide-y divide-rule text-sm">
              {runs.map((r) => {
                const failures = r.qaFailures as string[];
                return (
                  <li key={r.runId} className="flex flex-col gap-tight py-row first:pt-0 last:pb-0">
                    <div className="flex flex-wrap items-center justify-between gap-x-stack gap-y-tight">
                      <span className="font-medium">{r.modelLabel}</span>
                      <StatusBadge status={r.status} />
                    </div>
                    <p className="num text-ink-2">
                      {r.kind} · data as of <Stamp iso={r.dataAsofUtc} /> · QA failures: {failures.length ? failures.join("; ") : "none"}
                    </p>
                  </li>
                );
              })}
            </ul>
          </Card>
        </Section>

        <Section id="ingests" title="Ingest log">
          <Card>
            <ul className="num divide-y divide-rule text-sm">
              {ingests.map((i) => (
                <li key={i.bundleSha256} className="flex flex-wrap items-center justify-between gap-snug py-row first:pt-0 last:pb-0">
                  <span>{i.cycleId}</span>
                  <span className="text-ink-2">bundle {shortSha(i.bundleSha256, 12)}</span>
                  <StatusBadge status={i.status} />
                </li>
              ))}
            </ul>
          </Card>
        </Section>
      </Grid>

      <Section id="unmatched" title="Unmatched entities">
        <DataUnavailable title="Not tracked yet">
          The unmatched-entity queue (players and teams a provider names that the ID tables cannot resolve) arrives with
          the odds layer in Phase 2. Until then joins use nflverse IDs only.
        </DataUnavailable>
      </Section>
    </Page>
  );
}
```

<!-- apply: T9.3 create web/src/app/methodology/page.tsx -->
```tsx
import Link from "next/link";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, Page, PageHeader, Section, Term } from "@/components/ui";
import { noRunContext, runContext } from "@/lib/context";
import { evidence, ledger, pointerRun } from "@/lib/data/queries";
import { shortSha } from "@/lib/format";
import { TERM_IDS, TERMS, termAnchor } from "@/lib/glossary";
import { candidateLabel } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = { title: "Methodology" };

/** Generated from the ingested runs (their config), the backtest and the evidence ledger. */
export default async function MethodologyPage() {
  const [ev, weekly, claims] = await Promise.all([evidence(), pointerRun("weekly"), ledger()]);
  const cfg = (weekly?.config ?? {}) as { selections?: Record<string, Record<string, number | string>>; paper_edge?: number; market_source?: string };
  const sel = cfg.selections ?? {};
  const counts = claims.reduce<Record<string, number>>((acc, c) => ({ ...acc, [c.status]: (acc[c.status] ?? 0) + 1 }), {});

  return (
    <Page>
      <PageHeader
        title="Methodology"
        lead="This page is generated from the published runs and the evidence ledger, so it cannot drift from what the numbers were computed with."
        context={weekly ? runContext(weekly) : noRunContext("nothing has been ingested")}
      />

      <Section id="benchmark" title="The benchmark" measure>
        <Card>
          <p>
            The market probability is the closing moneyline with the bookmaker margin removed proportionally (<Term id="no-vig">no-vig</Term>):
            p = q<sub>home</sub> / (q<sub>home</sub> + q<sub>away</sub>). {cfg.market_source ? `Source: ${cfg.market_source}.` : null}
          </p>
        </Card>
      </Section>

      <Section id="candidates" title="Registered candidates" measure>
        <Card className="flex flex-col gap-control">
          <ul className="space-y-control">
            <li>
              <span className="font-medium">{candidateLabel("C1")}</span>: FiveThirtyEight-style Elo on final scores, ratings
              since 1999{sel.c1 ? `; tuned K ${sel.c1.K}, home field ${sel.c1.hfa} Elo points, ${Number(sel.c1.regress) * 100}% regression each season` : ""}.
            </li>
            <li>
              <span className="font-medium">{candidateLabel("C2")}</span>: ridge logistic model on home-minus-away
              exponentially weighted EPA per play, success rate, pass/rush splits, the starting quarterback&apos;s EPA per
              dropback and rest{sel.c2 ? `; half-life ${sel.c2.halflife} team-games, penalty ${sel.c2.lambda}` : ""}.
            </li>
            <li><span className="font-medium">{candidateLabel("E1")}</span>: equal-weight average of the two on the log-odds scale.</li>
            <li><span className="font-medium">Market stacks (B1)</span>: logistic regression on the market&apos;s and a model&apos;s log-odds, refit every week; the market weight is learned.</li>
            <li><span className="font-medium">{candidateLabel("B2[E1]")}</span>: a fixed blend; the weight on the market was chosen on the tuning window{sel.b2_e1 ? ` (${Number(sel.b2_e1.w) * 100}%, the top of the grid)` : ""}.</li>
            <li><span className="font-medium">{candidateLabel("K[E1]")}</span>: the ensemble recalibrated on earlier out-of-fold predictions{sel.k_e1 ? ` (${sel.k_e1.method})` : ""}.</li>
          </ul>
          <p className="border-t border-rule pt-control text-sm text-ink-2">
            The Monte Carlo score simulator ({candidateLabel("C3")}) joins as its own candidate in the next protocol version, once
            its features are point-in-time. Until then a simulator run is research output: its line is the simulation&apos;s win
            probability after the production pipeline&apos;s 70% weight on the no-vig market (<code>SHRINKAGE</code>, <Term id="shrinkage">shrinkage toward the market</Term>); games
            without a market show the unshrunk value.
          </p>
        </Card>
      </Section>

      <Section id="judged" title="How candidates are judged" measure>
        <Card className="flex flex-col gap-control">
          <ul className="list-disc space-y-snug pl-5">
            <li><Term id="walk-forward">Walk-forward</Term> by NFL week: every fit uses only games that kicked off before that week, and a guard rejects any input that finished after kickoff.</li>
            <li>Tune on 2018–22, confirm on 2023–24, then score the <Term id="holdout">sealed 2025 holdout</Term> once. The protocol file is hashed and committed before scoring.</li>
            <li><Term id="brier">Brier</Term> <Term id="skill">skill</Term> against the market with paired week-block bootstrap intervals (<Term id="interval" />), Diebold–Mariano tests with Benjamini–Hochberg correction, calibration slope and <Term id="ece">ECE</Term>.</li>
            <li>Controls void a run: a leak canary, shuffled labels, a market copy that must score exactly zero, and a second process that must reproduce the result hash.</li>
            <li>Betting value is judged on <Term id="clv">closing-line value</Term> at decision-time prices, with at least 400 picks in a single look.</li>
          </ul>
          {ev?.window ? (
            <p className="border-t border-rule pt-control text-sm text-ink-2">
              Current protocol <code>{ev.window.windowId}</code>, sha256 {shortSha(ev.window.protocolSha256, 12)}; result{" "}
              {shortSha(ev.bt.resultSha256, 12)}. <Link href="/evidence">Results</Link>
            </p>
          ) : null}
        </Card>
      </Section>

      <Section id="public" title="What is shown publicly" measure>
        <Card>
          <p>
            A candidate that passed its gates is shown as validated. Until one does, the fields carry one research line,
            labelled <Term id="unvalidated">unvalidated</Term> wherever it appears: the {candidateLabel("E1")} when the published run has it, otherwise the
            game simulator. There are no public picks. Stakes are never public; the private desk tracks paper leans only
            {cfg.paper_edge ? ` (edge of ${cfg.paper_edge * 100} points or more)` : ""}.
          </p>
        </Card>
      </Section>

      <Section id="claims" title="Claims ledger" measure>
        <Card>
          <ul className="flex flex-wrap gap-x-stack gap-y-tight">
            {Object.entries(counts).map(([status, n]) => (
              <li key={status}><StatusBadge status={status} label={`${n} ${status}`} /></li>
            ))}
          </ul>
        </Card>
      </Section>

      <Section id="definitions" title="Definitions" measure>
        <Card>
          <dl className="flex flex-col gap-stack">
            {TERM_IDS.map((id) => (
              <div key={id} id={termAnchor(id)} className="flex flex-col gap-tight">
                <dt className="font-medium">{TERMS[id].label}</dt>
                <dd className="text-sm text-ink-2">{TERMS[id].definition}</dd>
              </div>
            ))}
          </dl>
        </Card>
      </Section>
    </Page>
  );
}
```

<!-- apply: T9.3 create web/src/app/props/page.tsx -->
```tsx
import Link from "next/link";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, Grid, Page, PageHeader, Section } from "@/components/ui";
import { noRunContext } from "@/lib/context";

export const metadata = { title: "Props" };

const MARKETS = [
  { group: "Touchdowns", items: ["Anytime", "First", "Two or more"] },
  { group: "Yardage", items: ["Passing yards", "Rushing yards", "Receiving yards"] },
  { group: "Counts", items: ["Receptions", "Completions", "Pass attempts", "Passing TDs", "Interceptions"] }
];

export default function PropsPage() {
  return (
    <Page>
      <PageHeader
        title="Player props"
        lead={
          <span className="flex flex-wrap items-center gap-snug">
            <StatusBadge status="unvalidated" label="Props model unvalidated" />
            <span>No prop is priced here until its market passes a pre-registered backtest.</span>
          </span>
        }
        context={noRunContext("no prop is priced yet; game probabilities are on This week")}
      />

      <Grid kind="tiles">
        {MARKETS.map((m) => (
          <Section key={m.group} id={`m-${m.group}`} title={m.group}>
            <Card pad="sm">
              <ul className="text-sm">
                {m.items.map((i) => (
                  <li key={i} className="flex items-center justify-between gap-control border-t border-rule py-row first:border-t-0 first:pt-0 last:pb-0">
                    <span>{i}</span>
                    <StatusBadge status="unvalidated" label="Not priced" />
                  </li>
                ))}
              </ul>
            </Card>
          </Section>
        ))}
      </Grid>

      <DataUnavailable title="Why this page is empty">
        <p>
          The props engine has known defects that change every row (audit P1–P13): labels are column-wide, recommendation
          and stake disagree, and anytime-TD prices never reach the output. Phase 4 fixes them and rebuilds the model
          (usage shares, a touchdown engine), and Phase 5 backtests each market separately.
        </p>
        <p className="mt-snug">
          A market is backtested only with at least 300 settled player-games that had a pre-kickoff price; below that it
          is tracked prospectively and labelled that way. What counts as a pre-kickoff price (checkpoint A5) is still an
          owner decision. See <Link href="/methodology">Methodology</Link>.
        </p>
      </DataUnavailable>
    </Page>
  );
}
```

- [ ] **Step 4: Run the tests and see GREEN**

Run: `cd web && npx vitest run src/test/pages/dataHealth.test.tsx src/test/pages/methodology.test.tsx src/test/tokens.test.ts`
Expected: `Test Files  3 passed (3)`, `Tests  10 passed (10)`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  27 passed (27)`, `Tests  170 passed (170)`.

```bash
git add web/src
git commit -m "feat(web): data health, methodology with its definitions, and props on the shared components (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: The desk, sign-in, not-found and the error boundary [haiku]

The last four pages move over, and the app gains `error.tsx`.

- **Desk:** `PageHeader` with the run's context line and the sign-out form as its `actions`; the paper-leans table is a `DataTable` (`data-desk="recommendations"` passes through to the `<table>`, the stake cell is `<span data-stake>`, the empty state is a row with `data-desk="no-leans"`), under a source line that says what model, market and edge mean; the board is a `Section` of strips.
- **Sign in** and **not found** use `PageHeader size="compact"` in a `Page` of a fixed width.
- **`error.tsx`:** a client error boundary for a page that throws while it renders: a title, a plain sentence about what to do, a "Try again" button (`reset`), a link to Data health, and the error's **digest** as a reference to quote. It never prints the error's own message or stack (they can carry internals); it logs the error to the console, and Next logs it with the same digest on the server.
- **No `loading.tsx`**, by decision (Owner decisions, item 4): React 19 holds a Suspense fallback on screen for a few hundred milliseconds even when the data is ready, and a root `loading.tsx` moved the mobile LCP up by 0.3 to 0.5 s on every page. The appendix has the file.

**Files:**
- Create: `web/src/app/error.tsx`, `web/src/app/states.test.tsx`
- Modify: `web/src/app/not-found.tsx`, `web/src/app/desk/page.tsx`, `web/src/app/login/page.tsx`, `web/src/test/tokenCeilings.json`

**Interfaces:**
- Consumes: `Page`, `PageHeader`, `Section`, `Grid`, `Card`, `DataTable`, `BUTTON_CLASS`, `QUIET_BUTTON_CLASS`, `INPUT_CLASS` (Task 2), `runContext`, `noRunContext`, the strip `Field` (Task 5).
- Produces: `app/error.tsx` (default export `ErrorPage({ error, reset })`).

- [ ] **Step 1: Write the failing tests**

<!-- apply: T10.1 create web/src/app/states.test.tsx -->
```tsx
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import ErrorPage from "./error";

describe("error state", () => {
  const error = Object.assign(new Error("password authentication failed for user ci"), { digest: "d1g3st" });
  const out = renderToStaticMarkup(<ErrorPage error={error} reset={() => {}} />);

  it("says what to do, offers a retry and quotes the digest, never the error's own message", () => {
    expect(out.match(/<h1/g)).toHaveLength(1);
    expect(out).toContain("This page could not be shown");
    expect(out).toContain('role="alert"');
    expect(out).toContain(">Try again</button>");
    expect(out).toContain("Reference d1g3st");
    expect(out).not.toContain("password authentication");
    expect(out).toContain('href="/data-health"');
  });

  it("leaves the reference out when there is no digest", () => {
    expect(renderToStaticMarkup(<ErrorPage error={new Error("x")} reset={() => {}} />)).not.toContain("Reference");
  });
});
```

<!-- apply: T10.1 create web/src/test/tokenCeilings.json -->
```json
{
  "arbitrary": {
    "app/evidence/page.tsx": 1,
    "app/games/[id]/page.tsx": 1,
    "components/Field.tsx": 1
  },
  "textPx": {}
}
```

- [ ] **Step 2: Run the tests and see RED**

Run: `cd web && npx vitest run src/app/states.test.tsx src/test/tokens.test.ts`
Expected: FAIL, `Test Files  2 failed (2)`: `states.test.tsx` cannot import `./error`, and the ratchet names `app/desk/page.tsx`.

- [ ] **Step 3: Write the pages and the boundary**

<!-- apply: T10.3 create web/src/app/not-found.tsx -->
```tsx
import Link from "next/link";
import { Page, PageHeader } from "@/components/ui";

export default function NotFound() {
  return (
    <Page className="max-w-xl">
      <PageHeader size="compact" title="Not found" lead={<>That page or game is not in the published data. <Link href="/">Back to this week</Link></>} />
    </Page>
  );
}
```

<!-- apply: T10.3 create web/src/app/error.tsx -->
```tsx
"use client";

import Link from "next/link";
import { useEffect } from "react";
import { BUTTON_CLASS, Card, Page, PageHeader } from "@/components/ui";

/**
 * The last resort for a page that threw while it rendered: what happened, what to do, and a
 * reference to quote. It never prints the error's own message or stack (those can carry
 * internals); the error is logged to the console and, with the same digest, to the server log.
 */
export default function ErrorPage({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <Page className="max-w-xl">
      <PageHeader size="compact" title="This page could not be shown" lead="Something went wrong while it loaded. No data was changed." />
      <Card role="alert" className="flex flex-col gap-control">
        <p className="text-sm text-ink-2">
          Try again. If it keeps happening, the data behind the page may be unavailable: <Link href="/data-health">Data health</Link> says
          what the last run reached.
        </p>
        {error.digest ? <p className="num text-sm text-muted">Reference {error.digest}</p> : null}
        <div>
          <button type="button" onClick={reset} className={BUTTON_CLASS}>
            Try again
          </button>
        </div>
      </Card>
    </Page>
  );
}
```

<!-- apply: T10.3 create web/src/app/desk/page.tsx -->
```tsx
import { redirect } from "next/navigation";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, DataTable, Grid, Page, PageHeader, QUIET_BUTTON_CLASS, Section } from "@/components/ui";
import { signOut } from "@/lib/auth";
import { requireUser } from "@/lib/auth/requireUser";
import { noRunContext, runContext } from "@/lib/context";
import { deskSlate } from "@/lib/data/queries";
import { pct, pts } from "@/lib/format";
import { candidateLabel, deskLead, NO_LEANS_SIMULATOR, SIMULATOR_CANDIDATE } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = { title: "Desk", robots: { index: false } };

export default async function DeskPage() {
  const user = await requireUser();
  if (!user) redirect("/login");
  const { run, games, candidate, lines, recs } = await deskSlate();
  const model = candidate ?? "";
  // in kickoff order, like the board below
  const order = new Map(games.map((g, i) => [g.gameId, i]));
  const leans = recs
    .filter((r) => r.tier !== "pass")
    .sort((a, b) => (order.get(a.gameId) ?? 0) - (order.get(b.gameId) ?? 0));

  return (
    <Page>
      <PageHeader
        title="Desk"
        lead={
          <span className="flex flex-wrap items-center gap-snug">
            <StatusBadge status="unvalidated" label="Paper only" />
            {deskLead(candidate)}
          </span>
        }
        context={run ? runContext(run) : noRunContext("nothing has been ingested")}
        actions={
          <form action={async () => { "use server"; await signOut({ redirectTo: "/" }); }} className="flex items-center gap-control">
            <span className="text-sm text-ink-2">{user.email}</span>
            <button type="submit" className={QUIET_BUTTON_CLASS}>Sign out</button>
          </form>
        }
      />

      {run ? (
        <>
          <Section id="leans" title={`Paper leans, ${candidateLabel(model)} vs market`}>
            <Card>
              <DataTable
                data-desk="recommendations"
                caption={`Paper leans, ${candidateLabel(model)} against the market`}
                numeric
                minWidth="table-wide"
                columns={[
                  { key: "game", header: "Game", rowHeader: true, nowrap: true },
                  { key: "side", header: "Side", nowrap: true },
                  { key: "model", header: "Model", nowrap: true },
                  { key: "market", header: "Market", nowrap: true },
                  { key: "edge", header: "Edge", nowrap: true },
                  { key: "price", header: "Price", nowrap: true },
                  { key: "stake", header: "Stake", nowrap: true },
                  { key: "note", header: "Note" }
                ]}
                empty={<span data-desk="no-leans">{candidate === SIMULATOR_CANDIDATE ? NO_LEANS_SIMULATOR : "No paper leans in this run."}</span>}
                rows={leans.map((r) => {
                  const g = games.find((x) => x.gameId === r.gameId);
                  const team = r.side === "home" ? g?.homeTeamId : g?.awayTeamId;
                  return {
                    key: r.recId,
                    cells: {
                      game: g ? `${g.awayTeamId} at ${g.homeTeamId}` : r.gameId,
                      side: team,
                      model: pct(r.pModel, 1),
                      market: pct(r.pMktNovig, 1),
                      edge: r.pMktNovig !== null ? pts(r.pModel - r.pMktNovig) : "–",
                      price: r.priceAmerican !== null ? (r.priceAmerican > 0 ? `+${r.priceAmerican}` : r.priceAmerican) : "–",
                      stake: <span data-stake>{pct(r.stakePct, 1)}</span>,
                      note: <span className="text-ink-2">{r.passReason}</span>
                    }
                  };
                })}
              />
            </Card>
            <p className="max-w-measure text-sm text-muted">
              Model and market are win probabilities for the side shown, in percent; the market is the no-vig nflverse close. Edge is the model minus the
              market, in percentage points. Stake is a share of the paper bankroll.
            </p>
          </Section>

          <Section id="board" title="Board">
            <FieldKey showModel={candidate !== null} modelLabel={candidateLabel(model)} validated={false} />
            <Grid kind="fields">
              {games.map((g) => {
                const l = lines.find((x) => x.gameId === g.gameId && x.candidate === model && x.p !== null);
                return (
                  <Field key={g.gameId} gameId={g.gameId} awayId={g.awayTeamId} homeId={g.homeTeamId} awayName={g.awayName}
                    homeName={g.homeName} kickoffUtc={g.kickoffUtc} neutral={g.neutral} pMarket={g.pMarket}
                    model={l ? { p: l.p as number, label: candidateLabel(model), validated: false } : null} />
                );
              })}
            </Grid>
          </Section>
        </>
      ) : null}
    </Page>
  );
}
```

<!-- apply: T10.3 create web/src/app/login/page.tsx -->
```tsx
import { BUTTON_CLASS, Card, INPUT_CLASS, Page, PageHeader } from "@/components/ui";
import { login } from "./actions";

export const metadata = { title: "Sign in", robots: { index: false } };

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  return (
    <Page className="mx-auto max-w-md">
      <PageHeader size="compact" title="Sign in to the desk" lead="The desk is private. Public pages never show stakes." />
      <Card className="flex flex-col gap-stack">
        {error ? (
          <p role="alert" className="text-crit">That email and password did not match, or sign-in is paused after repeated attempts.</p>
        ) : null}
        <form action={login} className="flex flex-col gap-stack">
          <label className="block">
            <span className="text-sm text-ink-2">Email</span>
            <input name="email" type="email" autoComplete="username" required className={INPUT_CLASS} />
          </label>
          <label className="block">
            <span className="text-sm text-ink-2">Password</span>
            <input name="password" type="password" autoComplete="current-password" required className={INPUT_CLASS} />
          </label>
          <div>
            <button type="submit" className={BUTTON_CLASS}>Sign in</button>
          </div>
        </form>
      </Card>
    </Page>
  );
}
```

- [ ] **Step 4: Run the tests and see GREEN**

Run: `cd web && npx vitest run src/app/states.test.tsx src/test/tokens.test.ts`
Expected: `Test Files  2 passed (2)`, `Tests  10 passed (10)`.

Then the end-to-end check of the whole app on this task's build (every page is now on the components): `rm -rf .next && npm run build`, restart the server on :3100 with the fixture state (Step S3), and run `npx playwright test --grep-invert @sim`
Expected: `91 passed`, `60 skipped`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  28 passed (28)`, `Tests  172 passed (172)`.

```bash
git add web/src
git commit -m "feat(web): the desk, sign-in and not-found on the shared components, and an error boundary (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: Professional HTML: metadata, landmarks, axe best-practice and print [sonnet]

- **Metadata.** Every page names itself (`<title>` ends with "· Broadcast Line") and describes itself in a description of its own (40 to 200 characters); the e2e spec requires every public page's title and description to be unique. The home page uses `title.absolute`, because the root layout's title template does not apply to the page of its own segment. The game page's `generateMetadata` reads `publicGame()` (cached, so the page reuses the query) and names the matchup and the week ("DEN at SF, week 4, 2026"); an unknown id says "Game not found". The desk and sign-in pages stay `noindex`.
- **Landmarks.** The spec requires on every public page (and on a 404): `lang="en"`, one banner, one main, one contentinfo, one h1, every `nav` named and no two navs sharing a name, heading levels that never skip, every `<time>` carrying a valid `datetime`, and every table a caption, `scope="col"` headers and a named scroll region.
- **axe.** The accessibility specs now run axe with the best-practice rules as well as WCAG A and AA, and **any** violation fails (it was "serious or critical only", which let `/evidence` ship four scroll regions all named "Scrollable table": `landmark-unique`). The `@sim` distribution spec gets the same rule.
- **Print.** The game and evidence pages are the ones people file. In print the page is the light palette on white whatever the screen theme, the header, the theme choice and the chip controls are gone (`print:hidden`), backgrounds are kept (the blue and gold lines are background colours: `print-color-adjust: exact`), cards, figures and rows are not split across sheets, and each page prints to a PDF of a few sheets.

**Files:**
- Create: `web/e2e/html.spec.ts`, `web/e2e/print.spec.ts`
- Modify: `web/e2e/a11y-layout.spec.ts`, `web/e2e/sim-bundle.spec.ts`, the `metadata` of the eight pages (`web/src/app/page.tsx`, `evidence/page.tsx`, `methodology/page.tsx`, `data-health/page.tsx`, `props/page.tsx`, `desk/page.tsx`, `login/page.tsx`, `games/[id]/page.tsx`), `web/src/app/globals.css` (the print block)

**Interfaces:**
- Consumes: `publicGame` (Task 3), the components and tokens, the e2e helpers (Task 5).

- [ ] **Step 1: Write the failing tests** (the two new specs and the stricter axe rule)

<!-- apply: T11.1 create web/e2e/html.spec.ts -->
```ts
import { expect, test } from "@playwright/test";
import { publicPagesOfRun } from "./helpers";

/**
 * Professional HTML (Track B2): every page names itself (a unique title and a description of its own),
 * has the landmarks a reader navigates by (one banner, one main, one contentinfo, labelled navigation),
 * one h1, a language, and machine-readable dates.
 */
test("every public page has its own title and description", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  const titles = new Map<string, string>();
  const descriptions = new Map<string, string>();
  for (const path of pages) {
    await page.goto(path);
    const title = await page.title();
    const description = (await page.locator('meta[name="description"]').getAttribute("content")) ?? "";
    expect(title.length, `${path}: title`).toBeGreaterThan(3);
    expect(title, `${path}: title ends with the site name`).toMatch(/Broadcast Line$/);
    expect(description.length, `${path}: description length`).toBeGreaterThanOrEqual(40);
    expect(description.length, `${path}: description length`).toBeLessThanOrEqual(200);
    expect(titles.get(title), `${path}: title "${title}" is also ${titles.get(title)}`).toBeUndefined();
    expect(descriptions.get(description), `${path}: description is also ${descriptions.get(description)}`).toBeUndefined();
    titles.set(title, path);
    descriptions.set(description, path);
  }
});

test("the game page's title names the matchup and the week", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  await page.goto(pages[1]!);
  expect(await page.title()).toMatch(/^[A-Z]{2,3} (at|vs) [A-Z]{2,3}, week \d+, \d{4} · Broadcast Line$/);
});

test("the private pages are not indexed", async ({ page }) => {
  await page.goto("/login");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
});

test("every public page has one banner, one main, one contentinfo, one h1 and a language", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of [...pages, "/no-such-page"]) {
    await page.goto(path);
    await expect(page.locator("html"), `${path}: lang`).toHaveAttribute("lang", "en");
    await expect(page.getByRole("banner"), `${path}: banner`).toHaveCount(1);
    await expect(page.getByRole("main"), `${path}: main`).toHaveCount(1);
    await expect(page.getByRole("contentinfo"), `${path}: contentinfo`).toHaveCount(1);
    await expect(page.getByRole("heading", { level: 1 }), `${path}: h1`).toHaveCount(1);
  }
});

test("navigation landmarks are named and no two share a name", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of pages) {
    await page.goto(path);
    const names = await page.locator("nav").evaluateAll((els) => els.map((e) => e.getAttribute("aria-label") ?? ""));
    expect(names.every((n) => n.length > 0), `${path}: every nav is named (${names.join(", ")})`).toBe(true);
    expect(new Set(names).size, `${path}: nav names are unique (${names.join(", ")})`).toBe(names.length);
  }
});

test("heading levels never skip a level", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of pages) {
    await page.goto(path);
    const levels = await page.locator("h1, h2, h3, h4").evaluateAll((els) => els.map((e) => Number(e.tagName.slice(1))));
    levels.forEach((lvl, i) => {
      if (i > 0) expect(lvl - levels[i - 1]!, `${path}: heading levels ${levels.join("")}`).toBeLessThanOrEqual(1);
    });
  }
});

test("every <time> carries a valid datetime", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  let seen = 0;
  for (const path of pages) {
    await page.goto(path);
    for (const dt of await page.locator("time").evaluateAll((els) => els.map((e) => e.getAttribute("datetime") ?? ""))) {
      expect(Number.isNaN(Date.parse(dt)), `${path}: <time datetime="${dt}">`).toBe(false);
      seen += 1;
    }
  }
  expect(seen, "dates are marked up as <time>").toBeGreaterThan(10);
});

test("every table has a caption, column headers with scope, and sits in a named scroll region", async ({ page }) => {
  await page.goto("/evidence");
  await page.locator("details > summary").first().click();
  // React appends empty hidden <table> elements to <body> while it hydrates rows; only ours are drawn
  const tables = await page.locator("table:not([hidden])").evaluateAll((els) =>
    els.map((t) => ({
      caption: t.querySelector("caption")?.textContent ?? "",
      colHeaders: [...t.querySelectorAll("thead th")].every((th) => th.getAttribute("scope") === "col"),
      region: t.parentElement?.getAttribute("role") === "region" && (t.parentElement?.getAttribute("aria-label") ?? "").length > 0
    }))
  );
  expect(tables.length).toBeGreaterThanOrEqual(3);
  for (const t of tables) {
    expect(t.caption.length).toBeGreaterThan(3);
    expect(t.colHeaders).toBe(true);
    expect(t.region).toBe(true);
  }
});
```

<!-- apply: T11.1 create web/e2e/print.spec.ts -->
```ts
import { expect, test } from "@playwright/test";
import { drawLazyCharts, gameHrefs } from "./helpers";

/**
 * Print (Track B2): the game and evidence pages are the ones people file. In print the page is the
 * light palette on white even when the screen is in the night-game theme, the header, the theme choice
 * and the chip controls are gone, the field keeps its colours (the blue and gold lines are background
 * colours), and the page fits the sheet.
 */
test.use({ colorScheme: "dark", viewport: { width: 1200, height: 900 } });

async function paths(page: import("@playwright/test").Page) {
  const [game] = await gameHrefs(page, 1);
  return [game!, "/evidence"];
}

test("in print the page is dark ink on white, whatever the screen theme", async ({ page }) => {
  for (const path of await paths(page)) {
    await page.goto(path);
    await drawLazyCharts(page);
    const screen = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    expect(screen, `${path}: the screen is the night game`).not.toBe("rgb(255, 255, 255)");
    await page.emulateMedia({ media: "print" });
    const print = await page.evaluate(() => ({ bg: getComputedStyle(document.body).backgroundColor, ink: getComputedStyle(document.body).color }));
    expect(print.bg, `${path}: print background`).toBe("rgb(255, 255, 255)");
    expect(print.ink, `${path}: print ink`).toBe("rgb(0, 0, 0)");
    await page.emulateMedia({ media: "screen" });
  }
});

test("in print the header, the theme choice and the chip controls are hidden and the notice stays", async ({ page }) => {
  for (const path of await paths(page)) {
    await page.goto(path);
    await page.emulateMedia({ media: "print" });
    await expect(page.locator("body > header"), `${path}: header`).toBeHidden();
    await expect(page.getByRole("button", { name: "Night game" }), `${path}: theme choice`).toBeHidden();
    await expect(page.getByRole("contentinfo"), `${path}: the responsible-gambling notice stays`).toContainText("1-800-GAMBLER");
    await expect(page.getByRole("heading", { level: 1 }), `${path}: the title stays`).toHaveCount(1);
    await page.emulateMedia({ media: "screen" });
  }
});

test("in print the field keeps its colours and nothing runs off the sheet", async ({ page }) => {
  const [game] = await gameHrefs(page, 1);
  await page.goto(game!);
  await page.emulateMedia({ media: "print" });
  const marker = page.locator('[data-marker="market"]').first();
  await expect(marker).toBeVisible();
  expect(await marker.evaluate((el) => getComputedStyle(el).getPropertyValue("print-color-adjust"))).toBe("exact");
  for (const path of await paths(page)) {
    await page.goto(path);
    await page.emulateMedia({ media: "print" });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, `${path}: horizontal overflow in print`).toBeLessThanOrEqual(0);
  }
});

test("each of the two pages prints to a PDF of a few sheets", async ({ page }) => {
  for (const path of await paths(page)) {
    await page.goto(path);
    await drawLazyCharts(page);
    const pdf = await page.pdf({ format: "A4", printBackground: true });
    expect(pdf.subarray(0, 4).toString("latin1"), `${path}: a PDF`).toBe("%PDF");
    const sheets = (pdf.toString("latin1").match(/\/Type\s*\/Page[^s]/g) ?? []).length;
    expect(sheets, `${path}: sheets`).toBeGreaterThanOrEqual(1);
    expect(sheets, `${path}: sheets`).toBeLessThanOrEqual(12);
  }
});
```

<!-- apply: T11.1 replace web/e2e/a11y-layout.spec.ts -->
```ts
async function audit(page: Page, label: string) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow, `${label}: horizontal overflow`).toBeLessThanOrEqual(0);
  const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
  const serious = axe.violations.filter((v) => v.impact === "serious" || v.impact === "critical");
  expect(serious.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(" ")).slice(0, 3).join(", ")}`), label).toEqual([]);
}
```

```ts
/**
 * WCAG 2.0/2.1 A and AA plus axe's best-practice rules (landmarks named once, one main, headings in
 * order, regions): any violation, of any impact, fails. Before Track B2 the rule was "serious or
 * critical only", which let /evidence ship four scroll regions that were all named "Scrollable table".
 */
async function audit(page: Page, label: string) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow, `${label}: horizontal overflow`).toBeLessThanOrEqual(0);
  const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "best-practice"]).analyze();
  expect(axe.violations.map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(" ")).slice(0, 3).join(", ")}`), label).toEqual([]);
}
```

<!-- apply: T11.1 replace web/e2e/sim-bundle.spec.ts -->
```ts
        const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
        expect(axe.violations.filter((v) => v.impact === "serious" || v.impact === "critical").map((v) => v.id)).toEqual([]);
```

```ts
        const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "best-practice"]).analyze();
        expect(axe.violations.map((v) => `${v.id} (${v.impact})`)).toEqual([]);
```

<!-- apply: T11.1 replace web/e2e/sim-bundle.spec.ts -->
```ts
      test(`distributions at ${width}px ${scheme}: no overflow, no serious axe issue`, async ({ page }) => {
```

```ts
      test(`distributions at ${width}px ${scheme}: no overflow, no axe violation`, async ({ page }) => {
```

- [ ] **Step 2: Run the tests and see RED**

Against the server built after Task 10 (fixture state): `cd web && npx playwright test e2e/html.spec.ts e2e/print.spec.ts`
Expected: `4 failed`, `8 passed`: "every public page has its own title and description", "the game page's title names the matchup and the week", "in print the page is dark ink on white" and "in print the field keeps its colours and nothing runs off the sheet" fail. (The stricter axe rule is already satisfied by Tasks 2 and 8. To see that it bites, serve `main` in a second worktree on :3101 and run `MSYS_NO_PATHCONV=1 E2E_BASE_URL=http://127.0.0.1:3101 npx playwright test e2e/a11y-layout.spec.ts --grep "console on /evidence"`: `6 failed`, each with `landmark-unique (moderate)` on the "Scrollable table" regions. This check is optional.)

- [ ] **Step 3: Write the metadata and the print stylesheet**

<!-- apply: T11.3 replace web/src/app/page.tsx -->
```tsx
export const dynamic = "force-dynamic";

const SORTS = { kickoff: "Kickoff", gap: "Biggest gap", closest: "Closest game" } as const;
```

```tsx
export const dynamic = "force-dynamic";
export const metadata = {
  // the root layout's title template does not apply to the page of its own segment
  title: { absolute: "This week · Broadcast Line" },
  description: "Every NFL game of the week drawn as a field: the no-vig market's win probability against the model's, with the run and the date of the data stated."
};

const SORTS = { kickoff: "Kickoff", gap: "Biggest gap", closest: "Closest game" } as const;
```

<!-- apply: T11.3 replace web/src/app/evidence/page.tsx -->
```tsx
export const metadata = { title: "Evidence" };
```

```tsx
export const metadata = {
  title: "Evidence",
  description: "The pre-registered test of every model against the no-vig closing market: Brier skill, calibration, promotion gates and closing-line value."
};
```

<!-- apply: T11.3 replace web/src/app/methodology/page.tsx -->
```tsx
export const metadata = { title: "Methodology" };
```

```tsx
export const metadata = {
  title: "Methodology",
  description: "How the market probability is built, which models are registered, how they are judged, what is shown publicly, and what each term means."
};
```

<!-- apply: T11.3 replace web/src/app/data-health/page.tsx -->
```tsx
export const metadata = { title: "Data health" };
```

```tsx
export const metadata = {
  title: "Data health",
  description: "When each data source last succeeded, whether the published run passed its checks, and the log of recent runs and ingests."
};
```

<!-- apply: T11.3 replace web/src/app/props/page.tsx -->
```tsx
export const metadata = { title: "Props" };
```

```tsx
export const metadata = {
  title: "Props",
  description: "Player props by market. None is priced here until its market passes a pre-registered backtest, and the page says why."
};
```

<!-- apply: T11.3 replace web/src/app/desk/page.tsx -->
```tsx
export const metadata = { title: "Desk", robots: { index: false } };
```

```tsx
export const metadata = { title: "Desk", description: "The private desk: paper leans and the board for the published run.", robots: { index: false } };
```

<!-- apply: T11.3 replace web/src/app/login/page.tsx -->
```tsx
export const metadata = { title: "Sign in", robots: { index: false } };
```

```tsx
export const metadata = { title: "Sign in", description: "Sign in to the private desk, where paper leans and the board for the published run are kept.", robots: { index: false } };
```

<!-- apply: T11.3 replace web/src/app/games/[id]/page.tsx -->
```tsx
export async function generateMetadata({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return { title: id.replace(/_/g, " ") };
}
```

```tsx
export async function generateMetadata({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9]{4}_[0-9]{2}_[A-Z]{2,3}_[A-Z]{2,3}$/.test(id)) return { title: "Game not found" };
  // publicGame is cached per request, so the page below reuses this query
  const { game } = await publicGame(id);
  if (!game) return { title: "Game not found" };
  const matchup = `${game.awayTeamId} ${game.neutral ? "vs" : "at"} ${game.homeTeamId}`;
  return {
    title: `${matchup}, week ${game.week}, ${game.season}`,
    description: `Win probability for ${matchup} in week ${game.week} of ${game.season}: the no-vig market against the model, and the simulated margin and total when the run has them.`
  };
}
```

The print block goes at the end of the stylesheet. It overrides the colour tokens with `:root:root`, which outranks both `:root:not([data-theme="light"])` (the system dark scheme) and `:root[data-theme="dark"]`:

<!-- apply: T11.3 replace web/src/app/globals.css -->
```css
@media (forced-colors: active) {
  .field-marker, .field-model { forced-color-adjust: none; }
}
```

```css
@media (forced-colors: active) {
  .field-marker, .field-model { forced-color-adjust: none; }
}

/*
 * Print (the game and evidence pages are the ones people file): always the light palette on white,
 * whatever theme the screen is in; no header, no chips, no theme control (print:hidden in the
 * markup); backgrounds and the field's colours are kept, because the blue and gold lines are
 * background colours; cards, figures and rows are not split across pages.
 */
@media print {
  @page { margin: 14mm; }
  :root:root {
    color-scheme: light;
    --surface: #ffffff;
    --surface-sunken: #ffffff;
    --ink: #000000;
    --ink-2: #2b2b2b;
    --ink-muted: #4d4d4d;
    --rule: #b8b8b8;
    --grid: #dddddd;
    --market: #2563d1;
    --model: #b98600;
    --actual: #d4456f;
    --neutral-mid: #c7cdc9;
    --good: #1d7a46;
    --warn: #8a5a00;
    --crit: #b3261e;
  }
  html, body { background: #ffffff; color: #000000; }
  * { print-color-adjust: exact; -webkit-print-color-adjust: exact; }
  .skip-link { display: none; }
  main { padding: 0; max-width: none; }
  figure, article, tr, .rounded-card { break-inside: avoid; }
  [data-section-title] { break-after: avoid; }
}
```

- [ ] **Step 4: Run the tests and see GREEN**

`rm -rf .next && npm run build`, restart the server on :3100 (fixture state), then `cd web && npx playwright test e2e/html.spec.ts e2e/print.spec.ts`
Expected: `12 passed`. Then the whole fixture suite `npx playwright test --grep-invert @sim`
Expected: `103 passed`, `60 skipped`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  28 passed (28)`, `Tests  172 passed (172)`.

```bash
git add web/src web/e2e
git commit -m "feat(web): per-page metadata, landmark and axe best-practice checks, print stylesheet (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: Close the contract: required sources, one title component, context and rhythm specs, README [sonnet]

Everything is migrated, so the transitional pieces of Task 2 are removed and the two properties that span the whole app get their specs.

- **`ui.tsx`:** `StatTile`'s `source` becomes required (a number without its source is now a type error) and the deprecated `PageTitle` is removed.
- **`designLanguage.test.ts`** (replaced): every page is a `<Page>` under a `<PageHeader>` (or the game page's screen-reader h1 over its scoreboard), no page keeps the old headings or `PageTitle`, no page file writes a `<table>` or an `<h2>`, only `ui.tsx` writes a `<table>`, the section title's markup is written once, and the dark button's class is written once (the header's Desk link used to carry its own copy; against `main`'s sources the guard fails and names `components/SiteHeader.tsx`). **`uiContract.test.tsx`** (new) pins the two removals: a `// @ts-expect-error` on a `StatTile` without a source (so `npm run typecheck` fails if `source` ever becomes optional again) and `"PageTitle" in ui` being false.
- **`e2e/context.spec.ts`:** every page with data states the run and the data date with a machine-readable instant (the text shows the same instant as the `datetime`); the props page says "none published" instead of leaving the line out; every stat tile has a source line; every term link on the public pages lands on a definition on `/methodology`; arriving at a definition marks it.
- **`e2e/rhythm.spec.ts`:** at 390, 768 and 1440 px the sections of every page are one `--spacing-section` apart (40 px), a section's title is one `--spacing-control` above its content (12 px), the first block is `--spacing-page-top` below the header (48 px), and no section carries a hand-picked top margin. The token values are read from the page, so the spec follows the tokens.
- **README:** the checks table names the new tests and specs, and a "Tokens and components" section explains the system.

**Files:**
- Create: `web/src/components/uiContract.test.tsx`, `web/e2e/context.spec.ts`, `web/e2e/rhythm.spec.ts`
- Modify: `web/src/components/ui.tsx`, `web/src/test/designLanguage.test.ts`, `web/README.md`

**Interfaces:**
- Consumes: everything above. Produces: nothing new for later tasks; Task 13 only measures and documents.

- [ ] **Step 1: Write the failing tests**

<!-- apply: T12.1 create web/src/test/designLanguage.test.ts -->
```ts
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
```

<!-- apply: T12.1 create web/src/components/uiContract.test.tsx -->
```tsx
import { describe, expect, it } from "vitest";
import * as ui from "./ui";
import { StatTile } from "./ui";

/** What Track B2 closed: no number without its source line, and one page-title component. */
describe("the ui contract", () => {
  it("a headline number cannot be drawn without its source line (a type error, so `npm run typecheck` fails)", () => {
    // @ts-expect-error source is required: every number says where it comes from
    const tile = <StatTile value="1" label="games" />;
    expect(tile.props.source).toBeUndefined();
  });

  it("the previous PageTitle is gone: a page's title is a PageHeader", () => {
    expect("PageTitle" in ui).toBe(false);
    expect("PageHeader" in ui).toBe(true);
  });
});
```

<!-- apply: T12.1 create web/e2e/context.spec.ts -->
```ts
import { expect, test, type Page } from "@playwright/test";
import { publicPagesOfRun } from "./helpers";

/**
 * Context (Track B2): every page that shows run data says which run it is, which week and how old its
 * data is, with the date in a <time datetime>; every headline number carries its label, unit and source
 * line; every term a page links resolves to a definition on /methodology.
 */
async function contextOf(page: Page) {
  const ctx = page.locator("[data-context]");
  await expect(ctx, "one context line").toHaveCount(1);
  const labels = await ctx.locator("dt").allInnerTexts();
  const times = await ctx.locator("time").evaluateAll((els) => els.map((e) => ({ datetime: e.getAttribute("datetime") ?? "", text: e.textContent ?? "" })));
  return { labels, times };
}

test("every page with data states the run and the data date, the date as a machine-readable instant", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of pages.filter((p) => p !== "/login" && p !== "/props")) {
    await page.goto(path);
    const { labels, times } = await contextOf(page);
    expect(labels, `${path}: context labels`).toContain("Run");
    expect(labels, `${path}: context labels`).toContain("Data as of");
    expect(times.length, `${path}: a <time> in the context line`).toBeGreaterThan(0);
    for (const t of times) {
      expect(Number.isNaN(Date.parse(t.datetime)), `${path}: datetime ${t.datetime}`).toBe(false);
      expect(t.text, `${path}: the text shows the same instant`).toContain(new Date(t.datetime).toISOString().slice(0, 16).replace("T", " "));
    }
  }
});

test("the props page says that it has no run, instead of leaving the line out", async ({ page }) => {
  await page.goto("/props");
  const { labels } = await contextOf(page);
  expect(labels).toEqual(["Run"]);
  await expect(page.locator("[data-context]")).toContainText("none published");
});

test("every headline number has a label, a source line and a unit", async ({ page }) => {
  for (const path of ["/", "/evidence"]) {
    await page.goto(path);
    const tiles = page.locator("[data-stat]");
    const n = await tiles.count();
    expect(n, `${path}: stat tiles`).toBeGreaterThanOrEqual(3);
    for (let i = 0; i < n; i += 1) {
      const tile = tiles.nth(i);
      expect((await tile.locator("[data-source]").innerText()).trim().length, `${path} tile ${i}: source line`).toBeGreaterThan(8);
      expect((await tile.innerText()).trim().split("\n").length, `${path} tile ${i}: value, label and source`).toBeGreaterThanOrEqual(3);
    }
  }
});

test("every term link on the public pages lands on a definition on /methodology", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  const hashes = new Set<string>();
  for (const path of pages) {
    await page.goto(path);
    for (const href of await page.locator('a[href^="/methodology#term-"]').evaluateAll((els) => els.map((e) => e.getAttribute("href") ?? ""))) hashes.add(href.split("#")[1]!);
  }
  expect(hashes.size, "term links in use").toBeGreaterThanOrEqual(6);
  await page.goto("/methodology");
  for (const id of hashes) await expect(page.locator(`#${id}`), `definition for ${id}`).toHaveCount(1);
  const defined = await page.locator('[id^="term-"]').count();
  expect(defined, "every definition is shown").toBeGreaterThanOrEqual(hashes.size);
});

test("arriving at a definition marks it", async ({ page }) => {
  await page.goto("/methodology#term-brier");
  const outline = await page.locator("#term-brier").evaluate((el) => getComputedStyle(el).outlineStyle);
  expect(outline).toBe("solid");
});
```

<!-- apply: T12.1 create web/e2e/rhythm.spec.ts -->
```ts
import { expect, test, type Page } from "@playwright/test";
import { publicPagesOfRun, WIDTHS } from "./helpers";

/**
 * One vertical rhythm (Track B2). The sections of every page are one --spacing-section apart, a
 * section's title is one --spacing-control above its content, and every page starts one
 * --spacing-page-top below the header. Before it, the gaps between a page's blocks were 20, 24, 28, 32,
 * 36 and 40px, and the game page started 16px higher than the others.
 */
async function tokenPx(page: Page, name: string): Promise<number> {
  return page.evaluate((n) => {
    const probe = document.createElement("div");
    probe.style.height = `var(${n})`;
    document.body.appendChild(probe);
    const h = probe.getBoundingClientRect().height;
    probe.remove();
    return h;
  }, name);
}

/** Vertical gaps between the in-flow children of a container, with their tops, in document order. */
async function gapsWithin(page: Page, selector: string): Promise<{ first: number | null; gaps: number[] }> {
  return page.evaluate((sel) => {
    const el = document.querySelector(sel);
    if (!el) return { first: null, gaps: [] as number[] };
    const kids = [...el.children].filter((c) => getComputedStyle(c).position !== "absolute" && getComputedStyle(c).display !== "none");
    const rects = kids.map((k) => k.getBoundingClientRect());
    return { first: rects[0] ? rects[0].top + window.scrollY : null, gaps: rects.slice(1).map((r, i) => Math.round((r.top - rects[i]!.bottom) * 100) / 100) };
  }, selector);
}

for (const width of WIDTHS) {
  test(`at ${width}px every page uses one section gap, one title gap and one top offset`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    const pages = await publicPagesOfRun(page);
    const sectionGap = await tokenPx(page, "--spacing-section");
    const titleGap = await tokenPx(page, "--spacing-control");
    const topOffset = await tokenPx(page, "--spacing-page-top");
    expect([sectionGap, titleGap, topOffset], "the tokens are 40, 12 and 48px").toEqual([40, 12, 48]);

    for (const path of pages) {
      await page.goto(path);
      const header = (await page.locator("body > header").boundingBox())!;
      const { first, gaps } = await gapsWithin(page, "[data-page]");
      expect(first, `${path}: the page wrapper`).not.toBeNull();
      expect(first! - (header.y + header.height), `${path}: header to the first block`).toBeCloseTo(topOffset, 0);
      expect(new Set(gaps), `${path}: gaps between sections ${JSON.stringify(gaps)}`).toEqual(new Set(gaps.length ? [sectionGap] : []));

      const titles = await page.evaluate(() =>
        [...document.querySelectorAll("[data-section-title]:not(.sr-only)")].map((t) => {
          const next = t.parentElement && t.parentElement.hasAttribute("data-section") ? t.nextElementSibling : null;
          return next ? Math.round((next.getBoundingClientRect().top - t.getBoundingClientRect().bottom) * 100) / 100 : null;
        })
      );
      for (const g of titles.filter((x): x is number => x !== null)) expect(g, `${path}: title to content`).toBeCloseTo(titleGap, 0);
    }
  });
}

test("no page keeps a hand-picked top margin on its sections", async ({ page }) => {
  const pages = await publicPagesOfRun(page);
  for (const path of pages) {
    await page.goto(path);
    const margins = await page.evaluate(() => [...document.querySelectorAll("[data-page] > *")].filter((e) => getComputedStyle(e).position !== "absolute").map((e) => getComputedStyle(e).marginTop).filter((m) => m !== "0px"));
    expect(margins, `${path}: margin-top on sections`).toEqual([]);
  }
});
```

- [ ] **Step 2: Run the tests and see RED**

Run: `cd web && npx vitest run src/components/uiContract.test.tsx src/test/designLanguage.test.ts`
Expected: FAIL, `Test Files  1 failed | 1 passed (2)`: "the previous PageTitle is gone: a page's title is a PageHeader" (`PageTitle` is still exported).

Run: `cd web && npm run typecheck`
Expected: exit 2 with `src/components/uiContract.test.tsx(8,5): error TS2578: Unused '@ts-expect-error' directive.` (a `StatTile` without a source still compiles).

The two e2e specs already pass on the Task 11 build (the pages comply); to see that they bite, serve `main` in a second worktree on :3101 and run `MSYS_NO_PATHCONV=1 E2E_BASE_URL=http://127.0.0.1:3101 npx playwright test e2e/context.spec.ts e2e/rhythm.spec.ts`: `8 failed`, `1 passed` (no context line, no source lines, no definitions, six different section gaps). This check is optional.

- [ ] **Step 3: Remove the transitional code and document the system**

<!-- apply: T12.3 replace web/src/components/ui.tsx -->
```tsx
export function StatTile({ value, label, source }: { value: ReactNode; label: ReactNode; source?: ReactNode }) {
```

```tsx
export function StatTile({ value, label, source }: { value: ReactNode; label: ReactNode; source: ReactNode }) {
```

<!-- apply: T12.3 replace web/src/components/ui.tsx -->
```tsx
      {source ? (
        <span data-source className="text-sm text-muted">
          {source}
        </span>
      ) : null}
    </Card>
```

```tsx
      <span data-source className="text-sm text-muted">
        {source}
      </span>
    </Card>
```

<!-- apply: T12.3 replace web/src/components/ui.tsx -->
```tsx
export const INPUT_CLASS = "mt-tight block h-11 w-full rounded-control border border-rule bg-surface px-4 text-ink";

/** @deprecated The previous page title; pages move to PageHeader and this goes in the last task of Track B2. */
export function PageTitle({ children, lead, compact = false }: { children: ReactNode; lead?: ReactNode; compact?: boolean }) {
  return <PageHeader title={children} lead={lead} size={compact ? "compact" : "page"} />;
}
```

```tsx
export const INPUT_CLASS = "mt-tight block h-11 w-full rounded-control border border-rule bg-surface px-4 text-ink";
```

<!-- apply: T12.3 replace web/README.md -->
```markdown
| `npm test` | vitest: contract drift, shared row fixtures, CSP, passwords, policy, slop scan, docs truth, offline fonts, design language, the local runner's rules, score distributions |
```

```markdown
| `npm test` | vitest: contract drift, shared row fixtures, CSP, passwords, policy, slop scan, docs truth, offline fonts, design language, the token ratchet, the ui components, the theme and the glossary, the local runner's rules, score distributions |
```

<!-- apply: T12.3 replace web/README.md -->
```markdown
| `npm run e2e -- --grep-invert @sim` | Playwright against a running server (`E2E_BASE_URL`, default `http://127.0.0.1:3100`) with the fixture bundles: axe, overflow, security headers, `/desk` redirect, stakes never public, ID leaks, reduced motion, and offline rendering (every request served by this server) |
```

```markdown
| `npm run e2e -- --grep-invert @sim` | Playwright against a running server (`E2E_BASE_URL`, default `http://127.0.0.1:3100`) with the fixture bundles: axe, overflow, security headers, `/desk` redirect, stakes never public, ID leaks, reduced motion, offline rendering (every request served by this server), axe with the best-practice rules (any violation fails), and the Track B2 specs: flag geometry (`e2e/flags.spec.ts`), the theme cookie (`e2e/theme.spec.ts`), the two-row header (`e2e/header.spec.ts`), the stretched game link (`e2e/card-link.spec.ts`), run and data-date context (`e2e/context.spec.ts`), one vertical rhythm (`e2e/rhythm.spec.ts`), page structure and metadata (`e2e/html.spec.ts`) and print (`e2e/print.spec.ts`) |
```

<!-- apply: T12.3 replace web/README.md -->
```markdown
## The contract
```

```markdown
## Tokens and components

Type, spacing, radius and measure are named tokens in `src/app/globals.css`, in a static theme block: the type roles heading, figure, stat, title, score and hero; the spacing roles tight, snug, control, stack, card, section, page-top and gutter; the radii card, field, control and tick; the measure and table widths. A page is a `<Page>` of `<Section>`s under one `<PageHeader>`, built from the components in `src/components/ui.tsx` (`Card`, `StatTile`, `DataTable`, `Stamp`, `Term`, `Breadcrumb`), and picks no size of its own. `src/test/tokens.test.ts` is the ratchet: `src/test/tokenCeilings.json` caps the arbitrary utilities (`text-[13px]`, `mt-[7px]`) in each file, the caps only fall, and `text-[Npx]` is allowed only in `src/components/ui.tsx` and `src/components/Field.tsx`. Each term a page uses is defined once in `src/lib/glossary.ts` and shown on /methodology. The theme is a cookie that the server renders (`src/app/theme/route.ts`, `src/lib/theme.ts`), so there is no theme script and nothing flashes.

## The contract
```

- [ ] **Step 4: Run the tests and see GREEN**

Run: `cd web && npx vitest run src/components/uiContract.test.tsx src/test/designLanguage.test.ts src/test/docsTruth.test.ts && npm run typecheck`
Expected: `Test Files  3 passed (3)`, `Tests  17 passed (17)`, typecheck exit 0.

E2E: `rm -rf .next && npm run build`, restart the server on :3100 (fixture state), then `npx playwright test e2e/context.spec.ts e2e/rhythm.spec.ts`
Expected: `9 passed`. Then the whole fixture suite `npx playwright test --grep-invert @sim`
Expected: `112 passed`, `60 skipped`.

- [ ] **Step 5: Gates and commit**

Run: `cd web && npm run typecheck && npm run lint && npx vitest run`
Expected: typecheck and lint exit 0, `Test Files  29 passed (29)`, `Tests  179 passed (179)`.

```bash
git add web/src web/e2e web/README.md
git commit -m "test(web): StatTile needs its source, one title component, context and rhythm specs, README (B2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 13: Close-out: contract checks, final gates, parity, first-load measurement, screenshots, docs and the draft PR [sonnet]

This task writes no source file. It proves the contract (no dependency, no deletion), runs every gate once more on the finished branch, measures the first load against `main`, takes the before and after screenshots, records the results in the CHANGELOG and the HANDOFF, and opens a draft PR. Nothing is merged.

**Files:**
- Modify: `CHANGELOG.md`, `HANDOFF.md`
- Scratch, never committed: the two Lighthouse scripts below, the Lighthouse JSON, the screenshot folders, the parity snapshots

**Interfaces:**
- Consumes: Tasks 1 to 12. Produces: the evidence the PR quotes and the owner reviews.

- [ ] **Step 1: The contract (owner checkpoints 2 and 3)**

```bash
git diff --exit-code main -- web/package.json web/package-lock.json
git diff --name-status main | grep '^D' || echo "no deleted file"
```

Expected: the first prints nothing and exits 0 (no dependency was added); the second prints `no deleted file`.

- [ ] **Step 2: The unit gates and the whole fixture suite**

Run (`web/`): `npm run typecheck && npm run lint && npx vitest run`
Expected: exit 0, `Test Files  29 passed (29)`, `Tests  179 passed (179)` (the baseline on `main` is 18 files and 126 tests).

Then the whole fixture suite on a fresh build, with the database in the fixture state (Setup S3: recreate it, migrate, ingest `weekly-2026-w04` and `backtest-nfl-games-v1`, seed the user):

```bash
rm -rf .next tsconfig.tsbuildinfo && npm run build
# serve it on :3100 as in Setup S3, then
npx playwright test --grep-invert @sim
```

Expected: `112 passed`, `60 skipped` (the baseline is `70 passed`, `60 skipped`; the 60 skipped are `@parity`, which waits for `E2E_PARITY_SNAPSHOTS`).

- [ ] **Step 3: The simulator state**

```bash
npm run ingest -- ../contracts/fixtures/bundles/weekly-sim-2024-w15
npx playwright test --grep @sim
npx playwright test e2e/flags.spec.ts e2e/context.spec.ts e2e/rhythm.spec.ts e2e/html.spec.ts e2e/print.spec.ts e2e/card-link.spec.ts e2e/header.spec.ts
```

Expected: `11 passed`, then `35 passed`. The new specs read the published run (`gameHrefs`, `publicPagesOfRun`), so they must hold on the simulator's run as well as on the fixture's. After this step the newest run is the simulator's, so the fixture game `2026_04_DEN_SF` is a 404 and the fixture-only specs (`a11y-layout`, `id-leaks`) no longer apply: recreate the database in the fixture state before running the whole suite again.

- [ ] **Step 4: Pixel parity, offline against online**

The procedure is the `parity` job of `.github/workflows/ci-web.yml` and `web/README.md` ("Offline and online parity"): build once; the online path is `next start -p 3100` over a database fed with `db:migrate` and `ingest` of `weekly-2026-w04`, `backtest-nfl-games-v1` and `weekly-sim-2024-w15` (oldest first) and `seed:user`; the offline path is `npm run local` on :3000 with `NFL_LOCAL_BUNDLES` and `NFL_LOCAL_PGDATA` pointing at scratch copies of the same bundles, `DATABASE_URL` unset and `PG_BIN` naming the PostgreSQL `bin` directory (its own cluster listens on :5434). Then, with a scratch directory for the snapshots:

```bash
export E2E_PARITY_SNAPSHOTS=<scratch dir>
E2E_BASE_URL=http://127.0.0.1:3000 npx playwright test --grep @parity --update-snapshots
E2E_BASE_URL=http://127.0.0.1:3100 npx playwright test --grep @parity
```

Expected: `60 passed` for each (3 widths, 2 colour schemes, ten pages), at `maxDiffPixels: 0` and `threshold: 0`, with only `[data-age]` masked. A negative control proves the comparison bites: copy `login-390-light.png` over `home-390-light.png` in the snapshot directory and run `E2E_BASE_URL=http://127.0.0.1:3100 npx playwright test --grep "390px light @parity home"`. It must fail with `expect(page).toHaveScreenshot(expected) failed` and a count of different pixels (the dry run: `Expected an image 390px by 900px, received 390px by 2775px. 861178 pixels (ratio 0.80 of all image pixels) are different.`). Restore the snapshot (run the first command again) and the same command passes. Stop the offline server (`npm run local:stop`) and the online one by their process ids.

- [ ] **Step 5: The first load, against `main`**

Serve `main` beside the branch, each on its own database fed the same three bundles, so the two differ only in code:

```bash
git worktree add --detach ../nfl-main-ab main
cd ../nfl-main-ab/web && npm ci && npm run build
# a database nfl_main_ab, then with DATABASE_URL pointing at it:
#   npm run db:migrate; the three ingests of Step 4 (oldest first); npm run seed:user
(nohup npm run start -- -p 3101 > next.log 2>&1 &)
# the branch: its own database fed the same way, served with `npm run start -- -p 3100`
```

Save the two scripts below in a scratch folder outside the repository. `lh-ab.sh` runs Lighthouse 13.5.0 (mobile, its default profile) against `main` and the branch in turns, so a slow minute on the machine hits both; `lh-summary.mjs` prints the medians. (`npx` fetches Lighthouse; it is not a dependency of the repository.)

`lh-ab.sh`:

```bash
#!/bin/sh
# Interleaved Lighthouse 13.5.0 mobile A/B: `main` (:3101) against the branch (:3100), N rounds, same machine.
# Usage: sh lh-ab.sh <out dir> <rounds> <label for :3100> [pages...]
# CHROME_PATH picks the browser (any Chromium; the one Playwright installed works). On Windows give <out dir> as C:/...
OUT="$1"; RUNS="$2"; AFTER="$3"; shift 3
PAGES="${*:-/ /games/2024_15_LA_SF /evidence}"
CHROME="${CHROME_PATH:-$(ls -d "$HOME"/AppData/Local/ms-playwright/chromium-*/chrome-win*/chrome.exe "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome 2>/dev/null | sort | tail -1)}"
mkdir -p "$OUT"
export MSYS_NO_PATHCONV=1
i=1
while [ "$i" -le "$RUNS" ]; do
  for page in $PAGES; do
    slug=$(echo "$page" | sed 's#^/$#home#; s#^/##; s#/#_#g')
    for pair in "main:3101" "$AFTER:3100"; do
      label="${pair%%:*}"; port="${pair##*:}"
      CHROME_PATH="$CHROME" npx -y lighthouse@13.5.0 "http://127.0.0.1:$port$page" --quiet \
        --only-categories=performance,accessibility,best-practices \
        --chrome-flags="--headless=new --no-sandbox" \
        --output=json --output-path="$OUT/${label}.${slug}.run${i}.json" > /dev/null 2>&1
      echo "$label $slug run $i done"
    done
  done
  i=$((i + 1))
done
```

`lh-summary.mjs`:

```js
// Lighthouse A/B summary: medians per label and page. node lh-summary.mjs <dir>
// File names: <label>.<page>.run<N>.json. Prints the median of each metric over the runs, and every run's LCP.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2];
const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const groups = new Map();
for (const f of readdirSync(dir).filter((n) => /\.run\d+\.json$/.test(n))) {
  const [label, page] = f.split(".");
  const r = JSON.parse(readFileSync(join(dir, f), "utf8"));
  const key = `${page}|${label}`;
  const g = groups.get(key) ?? { n: 0, perf: [], a11y: [], bp: [], lcp: [], cls: [], tbt: [], fcp: [], ver: r.lighthouseVersion };
  g.n += 1;
  g.perf.push(r.categories.performance.score);
  g.a11y.push(r.categories.accessibility.score);
  g.bp.push(r.categories["best-practices"].score);
  g.lcp.push(r.audits["largest-contentful-paint"].numericValue / 1000);
  g.cls.push(r.audits["cumulative-layout-shift"].numericValue);
  g.tbt.push(r.audits["total-blocking-time"].numericValue);
  g.fcp.push(r.audits["first-contentful-paint"].numericValue / 1000);
  groups.set(key, g);
}
const rows = [...groups.entries()].sort().map(([key, g]) => {
  const [page, label] = key.split("|");
  return {
    page,
    label,
    runs: g.n,
    lh: g.ver,
    perf: median(g.perf).toFixed(2),
    a11y: median(g.a11y).toFixed(2),
    bestPractices: median(g.bp).toFixed(2),
    "LCP s (median)": median(g.lcp).toFixed(2),
    "LCP s (all runs)": g.lcp.map((x) => x.toFixed(2)).join(" "),
    CLS: median(g.cls).toFixed(3),
    "TBT ms": Math.round(median(g.tbt)),
    "FCP s": median(g.fcp).toFixed(2)
  };
});
console.table(rows);
```

Run them (the first argument of `lh-ab.sh` is the folder for the JSON, the second the number of rounds, the third the label of the branch):

```bash
sh lh-ab.sh C:/tmp/b2-lh 5 b2        # a C:/ path on Windows; any directory elsewhere
node lh-summary.mjs C:/tmp/b2-lh
```

Expected on the dry-run machine (Lighthouse 13.5.0, mobile, medians of five rounds, the fixture bundles including the simulator run; all runs of the LCP are in the evidence section):

| Page | LCP `main` / branch | Performance `main` / branch | Total blocking time `main` / branch |
|---|---|---|---|
| Home `/` | 2.45 s / 2.44 s | 0.89 / 0.96 | 352 ms / 139 ms |
| Game `/games/2024_15_LA_SF` | 2.65 s / 2.75 s | 0.87 / 0.94 | 404 ms / 164 ms |
| Evidence `/evidence` | 2.77 s / 2.76 s | 0.84 / 0.88 | 439 ms / 344 ms |

Accessibility and best practices are 1.00 and the layout shift is 0.000 on both trees on every page. The browser's own LCP is earlier on the branch (229 against 344 ms on the home page, 377 against 524 ms on the game page, 316 against 363 ms on evidence).

How to read your numbers: one tree's runs spread by about 0.2 s, so the acceptance rule is relative. On every page the branch's median LCP is within 0.25 s of `main`'s, and its performance score and blocking time are no worse. If a page is slower than that, look first for a Suspense boundary or a client component pulled into a server page. The master plan's gate is a mobile LCP under 2.5 s. The dry run meets it on the home page only: the game page (2.75 s) and evidence (2.76 s) miss it on `main` as well (2.65 s and 2.77 s), so the branch does not regress the gate and does not meet it either. Do not write that it is met unless your own medians say so; put yours in the PR.

What was tried, so nobody repeats it (five interleaved rounds each, same machine):

| Lever | Result | Decision |
|---|---|---|
| `publicGates()` and `Promise.all` (Task 3) | The server answers in 17 to 80 ms, so the queries are not on the simulated LCP path: Lighthouse's model charges bytes (18 KB of HTML, an 89 KB font, 8 KB of CSS, about 150 KB of gzipped JavaScript) and the CPU of hydration | Kept: the home and game pages run 1 query instead of 7 for the gates, and a page and its metadata share cached queries |
| A root `loading.tsx` | Home 2.46 to 2.98 s, game 2.67 to 3.12 s, evidence 2.78 to 3.06 s: React 19 keeps the skeleton on screen for 300 to 500 ms although the data arrives in about 20 ms | Rejected (owner checkpoint 4); the file is in the appendix |
| `experimental.inlineCss` | Removes the render-blocking stylesheet, but Next 16.3.7 emits the inlined `<style>` without the CSP nonce, so the nonce policy blocks it and the page renders unstyled | Rejected |
| A `browserslist` entry | Next's polyfill block is 1.3 KB and not conditional | No effect; not applied |
| Subsetting the font (about 30 KB less, an estimate) | Not measured. It replaces the committed font file, whose sha256 `offlineFonts.test.ts` pins, and spec §4 names the font | Owner decision |
| Less chart JavaScript on `/evidence` | Not measured | Open |

- [ ] **Step 6: CHANGELOG and HANDOFF**

The text below holds the dry run's numbers. If your own differ (the Lighthouse medians, the counts), replace them with yours before you commit; keep the structure.

<!-- apply: T13.6 replace CHANGELOG.md -->
```markdown
## [Unreleased]
```

```markdown
## [Unreleased]

### B2: one token and component system, context on every number, professional HTML (web app only; no R, contract or schema change)

- **Tokens.** `web/src/app/globals.css` gains a static Tailwind 4 theme: type roles (`heading`, `figure`, `stat`, `title-sm`, `title`, `score`, `hero`, responsive at 40 and 80 rem), spacing roles on a 4 px base (`tight` 4, `snug` 8, `control` 12, `stack` 20, `card` 20, `card-sm` 16, `section` 40, `page-top` 48, gutters 16/32/64), radii and measures. `web/src/test/tokens.test.ts` with `tokenCeilings.json` is a ratchet: a file's arbitrary utilities can only fall (114 became 3; `text-[Npx]`, 43 of them in 16 sizes, became 0), and a spacing role named like a Tailwind display utility fails the test (a first draft's `inline` and `block` turned every `inline-block` into a 20 px square).
- **Components.** `web/src/components/ui.tsx` is the one `Page`, `PageHeader`, `Section`, `Card`, `StatTile`, `DataTable`, `Stamp`, `Term`, `Breadcrumb` and `Grid`. All nine page files and the four chart tables use them, and `designLanguage.test.ts` fails if a page writes its own table, heading or card. A table row without a cell for a column throws, and a `StatTile` without a source does not compile.
- **Bugs fixed, each with a test.**
  - The game page's flags were inset 26 px against 58 px end zones. They are drawn inside the hero strip and sit within 1 px of their markers at 390, 768 and 1440 px (`e2e/flags.spec.ts`).
  - The game page started 16 px higher than the others, and the blocks of a page were 20, 24, 28, 32, 36 or 40 px apart. Every page now starts 48 px below the header and keeps one 40 px gap between sections (`e2e/rhythm.spec.ts`).
  - The theme was applied after hydration, so the other theme flashed. It is a cookie the server renders, set by a plain form post to `/theme`: no inline script, a tap during load is kept, a foreign origin is refused (`e2e/theme.spec.ts`).
  - The phone header was 229 px of four rows; it is 109 px of two, with the five labels on one line (a 320 or 360 px phone scrolls the row inside its box; `e2e/header.spec.ts`).
  - The header's Desk link carried its own copy of the dark button's class; the class is written once, in `ui.tsx`, and `designLanguage.test.ts` fails on a second copy.
  - Only a strip's title was a link; the whole strip is one link with one focus ring (`e2e/card-link.spec.ts`).
  - `/evidence` had four scroll regions all named "Scrollable table" (axe `landmark-unique`); a table's region is named after its caption.
- **Context.** Every page that shows data states the run and the data date (a `<time datetime>`), every headline number has a label, a unit and a source line, and terms link to thirteen definitions on `/methodology` (`web/src/lib/glossary.ts`). A page with no run or backtest says so and stays valid (`e2e/context.spec.ts`, `web/src/test/pages/`). Login and not-found show no run data and carry no run line.
- **Professional HTML.** Every public page has its own title and description, one banner, one main, one contentinfo, one h1, named navigation landmarks and `<time datetime>` (`e2e/html.spec.ts`). The accessibility specs run axe with the best-practice rules and fail on any violation. The game and evidence pages print as dark ink on white with the blue and gold lines kept (`e2e/print.spec.ts`). `error.tsx` is the app's error boundary.
- **First load.** `publicGates()` reads the promotion gates in one cached query where `evidence()` needed seven, and a page and its metadata share cached queries. Lighthouse 13.5.0 mobile, five interleaved rounds on one machine, `main` against this branch, median LCP: home 2.45 s against 2.44 s, game 2.65 s against 2.75 s, evidence 2.77 s against 2.76 s; performance 0.89, 0.87, 0.84 against 0.96, 0.94, 0.88; total blocking time 352, 404, 439 ms against 139, 164, 344 ms. The 2.5 s gate holds on the home page only; neither tree meets it on the game page or evidence on that machine.
- **Owner decisions** (also in the PR): no root `loading.tsx` (React 19 holds a Suspense fallback on screen for a few hundred milliseconds, which moved LCP up by 0.3 to 0.5 s on every page; the file is in the plan's appendix); the theme choice moved from the header to the footer; type sizes consolidated (section titles 22 to 24 px, lead text 17 to 18 px, chips 13 to 14 px, strip team codes 22 to 20 px); `experimental.inlineCss` rejected (the nonce CSP blocks the inlined style); font subsetting left to the owner (`offlineFonts.test.ts` pins the committed font file).
- **Gates** (dry-run tree, 2026-10-20): typecheck and lint exit 0; vitest 29 files and 179 tests with `REQUIRE_DB_TESTS=1` (baseline 18 and 126); Playwright on the fixtures 112 passed and 60 skipped (baseline 70 and 60), `@sim` 11 passed, `@parity` 60 passed offline and 60 online at zero differing pixels; axe with best-practice rules 0 violations on every page, width and scheme; `verify_repo_integrity.R` 63 passed, 0 failed. No dependency added, no file deleted. The other R gates were not run: no R file changed.
```

<!-- apply: T13.6 replace HANDOFF.md -->
```markdown
## Current state — A8 (feat/a8-local-app)
```

```markdown
## Track B2 (feat/b2-tokens-components): tokens, components, context and professional HTML

2026-10-20. Branch `feat/b2-tokens-components` from `main` at `210f791` (`web/` is identical at `4c1c377`), draft PR against `main` (never merged by the agent). Web app only: no R, `contracts/` or schema file changed, no dependency added, no file deleted. What changed is in CHANGELOG "B2"; the plan is `docs/superpowers/plans/2026-10-19-b2-tokens-components.md` (13 tasks, each with its RED and GREEN).

**Gate results (the dry-run tree, the plan applied verbatim):**
- Web: typecheck and lint exit 0; vitest 29 files, 179 tests with `REQUIRE_DB_TESTS=1` (baseline 18 files, 126 tests); Playwright on the fixtures `112 passed`, `60 skipped` (baseline 70 passed); `@sim` 11 passed; `@parity` offline writes 60 snapshots and online matches all 60 at maxDiffPixels 0 / threshold 0, and a wrong baseline fails as it should; axe with the best-practice rules finds 0 violations on every page, width and scheme (`main` fails `/evidence` in all six); review-ui 48 rows, overflow 0, errors 0, no serious axe rule, no leaks, on both trees and both data states.
- R: `verify_repo_integrity.R` exit 0, `Total: 63 passed, 0 failed`. The other R gates were not run: no R file changed.
- Lighthouse 13.5.0 mobile, five interleaved rounds, one machine, `main` against the branch, median LCP: home 2.45 s against 2.44 s, game 2.65 s against 2.75 s, evidence 2.77 s against 2.76 s; performance 0.89, 0.87, 0.84 against 0.96, 0.94, 0.88; total blocking time 352, 404, 439 ms against 139, 164, 344 ms.

**Open items:**
- The 2.5 s mobile LCP gate holds on the home page only. Neither tree meets it on the game page or evidence on this machine, and the run spread (about 0.2 s) hides the game page's +0.10 s. Confirm on CI or a reference machine. The levers left (font subsetting, less chart code on evidence) are owner decisions; `loading.tsx` and `experimental.inlineCss` were measured and rejected.
- One full Playwright run, right after a database reset, failed `e2e/id-leaks.spec.ts` once on the game page. It passed in three reruns and in every later full run; the cause was not found. If it recurs, run that spec alone and read its message.
- Login and not-found show no run data and carry no run line (the plan's reading of "every page states its run").

**Owner decisions pending:** merge approval; no root `loading.tsx`; the theme choice in the footer; the consolidated type sizes (22 to 24, 17 to 18, 13 to 14 px, strip team codes 22 to 20 px); font subsetting.

**Context-reset packet:** objective: one token and component system, context on every number, professional HTML, with no slower first load. Done: Tasks 1 to 13 with every gate above. Not done: the owner's merge; the LCP gate on the game page and evidence. Confirmed facts: the gates above. Open risks: LCP on a reference machine; the `id-leaks` flake. Next target: the owner's review of the draft PR and its screenshots; B3 (React Bits) and B4 (editing and offline features) are separate tracks.

## Current state — A8 (feat/a8-local-app)
```

- [ ] **Step 7: The before and after screenshots**

Both trees, both data states (the fixture state, then the simulator state), 390, 768 and 1440 px, both themes, the seven public pages and the desk. The script also prints overflow, console errors, serious axe rules and leaked values for each page:

```bash
# fixture state (default game), then, after ingesting the simulator run, GAME=2024_15_LA_SF
BASE=http://127.0.0.1:3101 OUT=C:/tmp/b2-shots/before node scripts/review-ui.mjs
BASE=http://127.0.0.1:3100 OUT=C:/tmp/b2-shots/after node scripts/review-ui.mjs
```

(`DESK_EMAIL` and `DESK_PASSWORD` must be set, as in Setup S2. Run it from the branch's `web/` for both: the script is the same on both trees.)

Expected: each run prints 48 rows, every row `overflow 0`, `errors 0`, no serious axe rule, no leaked value, on both trees. The screenshots are not committed; attach them to the PR. Look at them side by side. The dry run showed, at 390, 768 and 1440 px in both themes (the market stays scrimmage blue, the model first-down gold, and the dark theme is its own palette in both trees):

- **Header.** On a phone 229 px of four rows (wordmark; theme select and Desk; the navigation wrapped onto two lines) becomes 109 px of two (wordmark and Desk; one line of five labels). At 768 px it goes from 115 to 109 px and at 1440 px it stays 65 px, one row. The theme select is gone from the header.
- **Top of the page.** The first block was 32 px under the header (the visible title at 48 px, or 32 px on the game page); it is 48 px on every page, the game page included.
- **Context.** Under each page's title a line states the run and the data date, with the week, the protocol or the game days where they apply (`Week 2024 season, week 15`, `Run weekly-sim-2024-w15`, `Data as of 2026-10-03 12:00 UTC`); the old pages had none (the home page had only a date range above the title). The props page says that no run is published.
- **Tiles.** Every headline number keeps its label and gains a source line (`Published run ...`, `Simulator against the no-vig market, 2 games with both lines`, `Protocol nfl_games_v1, Confirm 2023-24`). Tiles in a row are one height.
- **Rhythm.** Sections are one 40 px apart (they were 20, 24, 28, 32, 36 and 40), a section title is 24 px (was 22) and sits 12 px above its content, the lead is 18 px (was 17). Pages are a little taller (`main` against the branch): evidence 5290 px against 5537 px at 1440 px, the home page 2607 px against 2775 px at 390 px (simulator state).
- **Game page.** The flag of the market and of the model starts on its marker's line (the pole is the flag's edge), inside the strip; the whole strip is one link with one focus ring.
- **Footer.** Three 44 px chips (System, Light, Night game) under the responsible-gambling text carry the theme choice.
- **Methodology.** A 672 px column (it was 880 px) with the definitions at the bottom; evidence tables carry captions.

- [ ] **Step 8: Commit and open the draft PR**

```bash
git diff --name-only main | grep -v '^web/'
```

Expected: `CHANGELOG.md` and `HANDOFF.md`, and nothing else outside `web/`.

```bash
git add CHANGELOG.md HANDOFF.md
git commit -m "docs: B2 tokens, components, context and professional HTML (CHANGELOG, HANDOFF)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin feat/b2-tokens-components
```

Save the PR text below as a scratch file `pr-body.md` with the file-writing tool (not a shell heredoc), replace the numbers with yours if they differ, and open the PR as a draft against `main`. **Do not merge it.**

```bash
gh pr create --draft --base main --title "B2: tokens, components, context and professional HTML" --body-file pr-body.md
```

```markdown
## Summary

One token system and one component of each kind in `web/`, every page migrated; the audit's bugs fixed, each with a test; a label, a unit and a source on every number and the run and data date on every page; professional HTML (metadata, landmarks, axe best-practice, print). Web only: no R, contract or schema change, no dependency added, no file deleted.

## Evidence

| Gate | Before (`main`) | After |
|---|---|---|
| vitest (Postgres suites running) | 18 files, 126 tests | 29 files, 179 tests |
| Playwright, fixtures | 70 passed, 60 skipped | 112 passed, 60 skipped |
| `@sim` | 11 passed | 11 passed |
| `@parity` (offline against online) | zero differing pixels | 60 and 60 passed, zero differing pixels |
| axe, WCAG and best-practice | `/evidence` fails (four scroll regions named alike) | 0 violations on every page, width and scheme |
| Arbitrary utilities (`text-[Npx]`) | 114 (43) | 3 (0) |
| Phone header | 229 px, four rows | 109 px, two rows |
| Section gap | 20, 24, 28, 32, 36, 40 px | 40 px |
| LCP, mobile median (home, game, evidence) | 2.45, 2.65, 2.77 s | 2.44, 2.75, 2.76 s |

## For the owner

- The 2.5 s LCP gate holds on the home page only; neither tree meets it on the game page or evidence on the measuring machine. Please confirm on a reference machine.
- Decisions: no root `loading.tsx` (it cost 0.3 to 0.5 s of LCP); the theme choice moved to the footer; type sizes consolidated; font subsetting (not done: it changes the pinned font file).
- Screenshots before and after, both themes, 390, 768 and 1440 px, are attached.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Stop the servers you started, by their process ids, and remove the extra worktree (`git worktree remove ../nfl-main-ab`) once the PR is open.

## Dry-run evidence (2026-10-19 and 2026-10-20, by the B2 planner)

The dry-run tree is `C:/Users/jviol/Downloads/nfl-worktrees/b2dry`: a worktree detached at `210f791`, uncommitted. Its dependencies are the lockfile's (`npm ci`); its servers were `next start` builds on :3100 (the branch) and :3101 (`main`, in a second worktree), each on its own database in a scratch Postgres on 127.0.0.1:5436.

**How the plan and the tree agree.** The plan's code blocks were generated from the dry-run tree, never typed (`.superpowers/research/b2-gen-src.cjs`, then `b2-assemble.js` expands the directives in `b2-parts/`). The check is a replay: `b2-reset.sh` returns the tree to `main`, `b2-apply-plan.js <plan> <tree> T1.1 T1.3 ... T13.6` applies every block of this file in order (a `replace` fails unless its old text occurs exactly once), and every file is compared with `cmp` against the tree the gates ran on. Result: the 86 apply blocks of this file, applied to a clean checkout of `210f791`, produce 61 changed files (35 modified, 26 new); 0 differ from the tree the gates ran on, except the four unit tests named in the next paragraph. The two files outside `web/` are `CHANGELOG.md` and `HANDOFF.md`, which only Task 13 writes. The red and green runs below were made step by step on that replay (a task's tests were written, run against the previous task's tree and seen to fail, then the task's code was applied and they passed).

**Per task** (`web/`, Postgres suites running, `REQUIRE_DB_TESTS=1`; typecheck and lint exit 0 at the end of every task):

| Task | RED | GREEN | Unit gates after the task |
|---|---|---|---|
| 1 | `tokens.test.ts`: 1 failed (30 tokens missing) | 8 passed | 19 files, 134 tests |
| 2 | 17 failed and 2 modules missing | 5 files, 36 tests | 22 files, 159 tests |
| 3 | 2 failed (`q.publicGates is not a function`) | 4 passed | 22 files, 161 tests |
| 4 | unit: the theme module is missing and the ceilings are too high; e2e against `main`: 10 failed, 4 passed | unit 13 passed; e2e 14 passed | 23 files, 166 tests; whole suite 84 passed (see the flake below) |
| 5 | unit: `Field.tsx` has 31 arbitrary utilities against a ceiling of 1; e2e: 6 failed | 8 and 7 passed | 23 files, 166 tests; whole suite 91 passed |
| 6 | 3 failed | 9 passed | 24 files, 167 tests |
| 7 | 2 failed (the ceilings of the game page and the charts) | 11 passed | 24 files, 167 tests |
| 8 | 3 failed | 9 passed | 25 files, 168 tests |
| 9 | 3 failed | 10 passed | 27 files, 170 tests |
| 10 | 1 failed (the desk's ceiling) | 10 passed | 28 files, 172 tests; whole suite 91 passed |
| 11 | e2e on the Task 10 build: 4 failed, 8 passed | 12 passed | 28 files, 172 tests; whole suite 103 passed |
| 12 | `uiContract`: 1 failed; `npm run typecheck`: TS2578; context and rhythm against `main`: 8 failed, 1 passed | 3 files, 17 tests; 9 passed | 29 files, 179 tests; whole suite 112 passed |

**Final gates** (the tree after Task 12, then the close-out):

| Gate | Result |
|---|---|
| Baseline on `main` (before any edit) | `npm run typecheck` exit 0; `npm run lint` exit 0; `Test Files  18 passed (18)`, `Tests  126 passed (126)`; Playwright `70 passed`, `60 skipped`; `@sim` `11 passed`; review-ui 48 rows clean |
| `npm run typecheck`, `npm run lint` | exit 0, exit 0 |
| the button guard of `designLanguage.test.ts`, run against `main`'s `web/src` | fails: `AssertionError: expected [ 'components/SiteHeader.tsx' ] to deeply equal []` |
| `npx vitest run` | `Test Files  29 passed (29)`, `Tests  179 passed (179)`, exit 0 |
| `npx playwright test --grep-invert @sim` (fixture state) | `112 passed`, `60 skipped` |
| `npx playwright test --grep @sim` (simulator state) | `11 passed` |
| flags, context, rhythm, html, print, card-link and header specs on the simulator state | `35 passed` |
| `@parity`, offline `--update-snapshots` | `60 passed (52.2s)` |
| `@parity`, online, `maxDiffPixels: 0`, `threshold: 0` | `60 passed (36.9s)` |
| `@parity` negative control (a wrong snapshot) | fails: `Expected an image 390px by 900px, received 390px by 2775px. 861178 pixels (ratio 0.80 of all image pixels) are different.`; restored, it passes |
| axe with WCAG A, AA and the best-practice rules, any violation fails | 0 violations on every page, width and scheme; against `main`, `/evidence` fails in all six combinations (`landmark-unique (moderate)` on the "Scrollable table" regions) |
| `scripts/review-ui.mjs`, both trees, fixture and simulator state | 48 rows each, `overflow 0`, `errors 0`, no serious axe rule, no leaked value |
| `Rscript scripts/verify_repo_integrity.R` (fresh HOME) | `Total: 63 passed, 0 failed`, `[VERIFICATION PASSED]`, exit 0 |
| `git diff --exit-code main -- web/package.json web/package-lock.json` | no output, exit 0 (`git diff` against `210f791`, the base of the dry-run tree) |
| deleted files in the diff | `no deleted file`; 35 files modified and 26 added, and the only files outside `web/` are `CHANGELOG.md` and `HANDOFF.md` |

**Layout, measured on both trees** (`measure-layout.mjs`, fixture state; header height, then the distance from the header to the first block):

| Width | Header `main` | Header branch | First block under the header `main` / branch |
|---|---|---|---|
| 390 px | 229 px, four visual rows | 109 px, two rows | 32 px (title at 48 or 32) / 48 px on all 7 pages |
| 768 px | 115 px | 109 px | 32 px / 48 px |
| 1440 px | 65 px | 65 px | 32 px / 48 px |

The gaps between a page's blocks on `main` were `28,28,28,28,28,24` (home), `-1,20,36,32,40,40` (game), `32,32` (props), `28,28,28,32,40,40,40,40` (evidence) and `40,40,40` (data health). On the branch `e2e/rhythm.spec.ts` measures one 40 px section gap, one 12 px title gap and one 48 px top offset on every page at the three widths.

**Lighthouse 13.5.0, mobile, five interleaved rounds** (`main` on :3101 against the branch on :3100, one machine, both databases fed the three bundles; LCP of each round, in seconds):

| Page | Tree | Rounds | Median LCP | Performance | Total blocking time | FCP |
|---|---|---|---|---|---|---|
| Home | `main` | 2.46 2.47 2.44 2.45 1.85 | 2.45 | 0.89 | 352 ms | 0.77 s |
| Home | branch | 2.56 2.47 2.44 2.44 2.44 | 2.44 | 0.96 | 139 ms | 0.77 s |
| Game | `main` | 2.69 2.79 2.65 2.63 2.58 | 2.65 | 0.87 | 404 ms | 0.92 s |
| Game | branch | 2.83 2.66 2.76 2.67 2.75 | 2.75 | 0.94 | 164 ms | 0.92 s |
| Evidence | `main` | 2.88 2.77 2.82 2.13 2.76 | 2.77 | 0.84 | 439 ms | 0.92 s |
| Evidence | branch | 2.93 2.75 2.76 2.83 2.27 | 2.76 | 0.88 | 344 ms | 0.95 s |

Accessibility 1.00, best practices 1.00 and layout shift 0.000 on every row. The same comparison with a root `loading.tsx` on the branch gave 2.98, 3.12 and 3.06 s (Appendix).

**Not run, and why.**
- GitHub Actions: nothing was pushed; the gates are CI's own commands, run locally. The `parity` job's procedure was followed by hand.
- The R test suite and the matrix: no R file, `config.R` or contract file changes, and the one R check that could read these files, `verify_repo_integrity.R`, passed.
- A real phone. The 320 and 360 px behaviour is a Playwright viewport (`e2e/header.spec.ts`).
- The Lighthouse gate on a reference machine: see the owner decisions.

**Two unit-test changes after the browser runs.** First, the button guard in `designLanguage.test.ts` (Task 12) was added when the audit's bug list was checked against the tests: the duplicated Desk button had none (the totals above include it: 179 tests). Second, the four page tests (`home`, `evidence`, `dataHealth` and `methodology` under `web/src/test/pages/`) import their page inside the test, and the final replay on a cold cache, while the machine was busy with other work, timed the evidence one out at vitest's 5 s default (`Error: Test timed out in 5000ms`; 28 of 29 files passed). Each now passes a 30 s timeout. No application file changed, so the e2e, parity, Lighthouse and screenshot runs above still describe this tree; the unit gates were run again on the replayed tree after the change (the `npx vitest run` row above is that run).

**One flake, not explained.** The first full Playwright run after a database reset (Task 4's build) failed `id-leaks.spec.ts` once on the game page (`83 passed`, `1 failed`). Three reruns of that spec passed, and every later full run passed (84, 91, 91, 103, 112). If it recurs, run it alone and read its message before blaming the plan.

**The base moved.** `main` is now `4c1c377` (A0 capture, PRs #213 and #214). `git diff 210f791 main -- web` is empty, and the only file this plan edits that changed is `CHANGELOG.md` (26 lines added elsewhere); its `## [Unreleased]` anchor is still unique, so Task 13's `replace` still applies.

**Where the evidence lives** (not committed): `.superpowers/research/b2-planner-log.md` (the step log), `b2-parts/` (the plan's text), `b2-src/` (every block's source), `b2-final/` (the final tree's files), `b2-measure/` (the Lighthouse and layout scripts), `b2-shots/` (the before and after screenshots, 48 per tree and data state, and the clips cited in Task 13).
## Appendix: the optional root `loading.tsx` (not applied)

The master plan asks for a `loading.tsx`. It was written, tested and measured, and **not shipped**: a root `loading.tsx` wraps every page in a Suspense boundary, and React 19 keeps a fallback on screen for a few hundred milliseconds even when the content is ready (it avoids flashing a skeleton), so the first paint is the skeleton (observed FCP 176 ms) and the real content, which is the LCP, moves from about 410 to 600 ms. Lighthouse 13.5.0 mobile, five interleaved rounds per session on one machine, the fixture bundles including the simulator run; median LCP. In each session `main` and the B2 tree ran in turns, so a slow minute hit both:

| Page | Session 1: `main` | Session 1: B2 with `loading.tsx` | Final session: `main` | Final session: B2 without `loading.tsx` |
|---|---|---|---|---|
| Home | 2.46 s | 2.98 s | 2.45 s | 2.44 s |
| Game (`/games/2024_15_LA_SF`) | 2.67 s | 3.12 s | 2.65 s | 2.75 s |
| Evidence | 2.78 s | 3.06 s | 2.77 s | 2.76 s |

A middle session (home and game only, before the last small changes) put `main` at 2.45 and 2.60 s against 2.46 and 2.67 s for the B2 tree without the file. The file costs 0.3 to 0.5 s on every page. The rest of the branch costs 0.00 to 0.10 s: home and evidence equal `main`, and the game page was 0.07 and 0.10 s slower in the two sessions that measured it, inside the run-to-run spread (about 0.2 s) but in the same direction both times (the branch ships about 4 KiB more HTML and CSS and 21 more DOM nodes on that page: the context line and the source lines).

If the owner wants a loading state anyway (it would show while a slow database answers; here the server answers in well under 150 ms), create `web/src/app/loading.tsx` with the file below and add a case for it to `web/src/app/states.test.tsx`; expect the LCP cost above. The file is static, never animates, and is as tall as the screen so the page does not jump when it arrives:

```tsx
import { Page } from "@/components/ui";

/**
 * Shown while a page's data loads: the shape of a page (a title, a lead, three cards) in the
 * sunken surface, static, and as tall as the screen, so nothing jumps when the page arrives.
 * It never animates, so reduced motion needs no special case.
 */
export default function Loading() {
  return (
    <Page className="min-h-svh">
      <div role="status" aria-live="polite" className="flex flex-col gap-stack">
        <span className="sr-only">Loading</span>
        <div aria-hidden className="h-14 max-w-measure rounded-card border border-rule bg-sunken" />
        <div aria-hidden className="h-12 max-w-measure rounded-card border border-rule bg-sunken" />
        <div aria-hidden className="grid gap-stack sm:grid-cols-3">
          <div className="h-28 rounded-card border border-rule bg-sunken" />
          <div className="h-28 rounded-card border border-rule bg-sunken" />
          <div className="h-28 rounded-card border border-rule bg-sunken" />
        </div>
      </div>
    </Page>
  );
}
```

```tsx
// a case for web/src/app/states.test.tsx: import Loading from "./loading"
describe("loading state", () => {
  const out = renderToStaticMarkup(<Loading />);
  it("announces itself politely, draws only static blocks and fills the screen", () => {
    expect(out).toContain('role="status"');
    expect(out).toContain('aria-live="polite"');
    expect(out).toContain('<span class="sr-only">Loading</span>');
    expect(out).toContain("min-h-svh");
    expect(out).not.toMatch(/animate-|transition/);
  });
});
```

Also tried and rejected in the dry run, for the record: `experimental.inlineCss` (it would remove the render-blocking stylesheet request, which is the one lever the Next docs name for LCP) emits the inlined `<style>` **without** the CSP nonce, so the app's `style-src 'self' 'nonce-…'` blocks it and the page renders unstyled (measured: body background transparent, h1 32 px, a CSP console error). It cannot be used without weakening the CSP.
## Self-review

**Spec coverage (master plan, Track B2 scope; the brief's seven items).**
1. Tokens: type, spacing, radius, measure and section-gap tokens on a 4px base with named roles, and the ratchet: Task 1 (`tokens.test.ts` forbids a spacing role named like a display utility, requires every token, keeps every role a multiple of 4px, and holds each file's ceiling exact).
2. One component of each kind, every page migrated: Task 2 builds `Page`, `PageHeader` (with the run, week and data-as-of context line), `Section`, `SectionTitle`, `Card` variants, `StatTile`, `DataTable` (caption, `scope`, `<time dateTime>` through `Stamp`), `Term`, `Breadcrumb`; Tasks 6 to 10 move all nine page files; Task 12 removes the transitional `PageTitle` and makes `source` required.
3. The bugs, each with a test: flags inside `Field` and the geometry spec at 390, 768 and 1440 px (Task 5); the game page's top offset (Tasks 7 and 12, `rhythm.spec.ts`); the two-row header with a one-line navigation (Task 4, `header.spec.ts`, also at 320 and 360 px); the 44 px theme control and the server-rendered cookie theme with no inline script (Task 4, `theme.spec.ts`); only-the-title-is-a-link (Task 5, `card-link.spec.ts`); the duplicated Desk button (Task 4: `BUTTON_CLASS`; Task 12: the design-language test fails on a second copy of the class); `error.tsx` (Task 10, `states.test.tsx`); `loading.tsx` is an owner decision with its measurement (Appendix), because it costs 0.3 to 0.5 s of LCP; `@parity` stays at zero differing pixels (Task 13).
4. Context: a label, unit and source line on every headline number (`StatTile` requires `source`, `context.spec.ts`), terms linked to `/methodology` (`Term`, the Definitions section, `context.spec.ts`), the run and data date on every page that shows data (`ContextList`, `context.spec.ts`, the empty-state page tests).
5. LCP: `publicGates()` in one cached query and `Promise.all` (Task 3 and the pages), measured as five-round Lighthouse medians against `main` on one machine (Task 13). The target is not met on two pages; the measurements, the cause and the levers are in Task 13 and the owner decisions.
6. Professional HTML: per-page metadata, the landmark audit, axe with the best-practice rules (any violation fails), a print stylesheet for the game and evidence pages: Task 11.
7. Out of scope and untouched: the validation banner (B1), React Bits (B3), editing and offline features (B4); no dependency is added.

**Placeholder scan.** Every code step is a generated block from the dry-run tree (`<!-- apply: ... -->`); there is no "TBD", "similar to Task N" or "add appropriate handling". The two optional checks (the stricter axe rule and the context and rhythm specs against `main`) say they are optional and give the command and the expected result.

**Type and name consistency.** `DataTable`'s `columns[].key` and `rows[].cells` keys are the same strings at every call site (a mismatch throws, `ui.test.tsx`); `Term` takes `TermId`; `runContext(run, { omitWeek })`, `backtestContext` and `noRunContext` are used with the signatures Task 2 defines; the spacing roles are `snug` and `stack` everywhere (`inline` and `block` appear nowhere as a role, and the ratchet test forbids them); `tokenCeilings.json` is rewritten in the same task as every migration, with the numbers the dry run computed.

**Review Focus.** Each of the five lines names its test and the task that owns it (1: Task 4 `theme.spec.ts`; 2: Task 5 `flags.spec.ts`; 3: Task 4 `header.spec.ts`; 4: Task 1 `tokens.test.ts`; 5: Tasks 6, 8 and 9 `src/test/pages`).

**Global Constraints and checkpoints.** The constraints are copied from the spec and the master plan. The font file is never touched (no task lists it, and `offlineFonts.test.ts` is part of every task's full vitest run); `globals.css` carries no `@media` or `@theme` above the first `@theme inline` block (the docs-truth and slop-scan tests slice the file by them and run at every task end); the game page keeps exactly two figures (its spec and the chart tests); and no task adds a dependency or deletes a file (Task 13 proves both with `git diff`). The eight owner checkpoints are all in the checkpoint list; the four that need evidence (2, 3, 6 and 7) are checked or measured in Task 13.

**Models.** Eight tasks are mechanical (the code blocks are complete and generated, the steps are apply, run and commit): 1, 2, 3, 6, 7, 8, 9 and 10 are marked haiku. Five need judgment (a server restart and a browser spec, the print and metadata choices, the lock-down, and the measurements and PR text): 4, 5, 11, 12 and 13 are marked sonnet.

**Known gaps, stated rather than hidden.**
- The LCP gate is met on the home page only. The plan does not claim otherwise; Task 13 says how to read the numbers and the owner decisions say what the remaining levers cost.
- One unexplained flake in the dry run (`id-leaks.spec.ts`, once, after a database reset). The evidence section names it.
- The e2e specs need a server restarted at Tasks 4, 5, 11 and 12 (a build and a start, in the steps); a forgotten rebuild shows up as a RED where GREEN is expected, not as a false GREEN, because each GREEN step names the build it needs.
- `main` moved after the plan's base commit; `web/` did not, and the evidence section says which anchors were checked.
