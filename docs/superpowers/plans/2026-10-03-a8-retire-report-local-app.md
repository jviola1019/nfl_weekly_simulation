# A8: Retire the Legacy HTML Report; the Next.js App Is the Only UI, Offline and Online — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `run_week.R` stops writing the orange `NFLvsmarket_report.html` and instead writes a weekly web bundle that the Next.js app shows everywhere: offline through `npm run local` (http://127.0.0.1:3000, no internet), online through a workflow that checks the same bundle and ingests it into the deployed database once one exists; every page carries the Broadcast Line redesign, and every gate is run.

**Architecture:** A new R builder (`R/sim_bundle.R`) turns the simulator's `final` table and its score draws into a `weekly` bundle (`R/bundle_writer.R` contract: C0 market and C3 simulator predictions, margin and total distributions, source status). A tsx runner (`web/scripts/local.ts`) creates a private loopback PostgreSQL cluster, migrates, ingests every bundle and serves the existing Next.js app, whose font is now committed so a build needs no network. The game page draws the distributions, the field line falls back to the simulator (labelled unvalidated), `.github/workflows/weekly-sim.yml` carries the same bundle online, and the legacy exporter, its fallback copy and its tests are deleted after a call-graph check proves no computation depends on them.

**Tech Stack:** R 4.5 (renv, testthat 3, jsonlite, digest), Next.js 16 / React 19 / Tailwind 4, Drizzle + postgres.js on PostgreSQL 17 (local binaries), visx scales, zod 4, vitest 4, Playwright 1.63 + axe.

**Spec:** `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` — §3 (R → web contract: bundles, ingest, publish pointer), §4 (Broadcast Line design system, charts, pages), §5 Phase 7/8 (A8: delete `export_moneyline_comparison_html` and the gt report path), §6 (verification gates). Brief: the controller's A8 planning brief (owner decision 2026-10-01) and the owner's two additions of 2026-10-03, quoted under Global Constraints.

## Global Constraints

- **Owner decision 2026-10-01 (verbatim):** "Retire; allow for offline usage (if app can be ran offline in terminal, go with this). but remove. If needed, restyle for offline testing."
- **Owner addition 2026-10-03 (verbatim):** "Continue with all full access and testing, probabilities." The close-out tests that the C3 and market probabilities rendered on the game page equal the bundle's `p_home_final` and `p_home_mkt_novig` for that game, at the displayed precision.
- **Owner addition 2026-10-03 (verbatim):** "Continue. Complete full UI/UX changes above for HTML if used for offline testing purposes." Controller ruling: the legacy HTML file is removed with no static replacement; the local app is the offline test surface, so `/evidence`, `/methodology`, `/data-health`, `/props`, `/login`, `/desk` (and the not-found page) get the same design language as #207's header, footer, home slate and game page; no invented content (re-lay the existing data and copy); verify with screenshots at 390/768/1440 in both themes, axe with 0 serious/critical issues, the slop-scan and docs-truth tests.
- **Owner addition 2026-10-03, repeated 2026-10-04 (verbatim):** "Make sure UI/UX is switched for both offline and online to the Next.js script. Make sure all accuracy, testing is maxed." Controller ruling: the Next.js app is the only UI everywhere, and nothing reads or writes the legacy HTML (not `run_week.R`, `NFLsimulation.R`, `NFLmarket.R`, scripts, tests, CI workflows, `artifacts/` copies or docs); offline = `npm run local`; online = the deployed app fed by the same simulator bundle through `.github/workflows/weekly-sim.yml` (Task 9: run the simulation, write, check and upload the bundle, ingest into `DATABASE_URL` only when that secret exists, `contents: read`, setup-r 4.5.1, setup-renv, Node from `web/package.json` engines); deployment itself waits for the owner (Vercel/Neon not authorized); "testing maxed" = every gate in Task 10.
- **Mockup artboards are design references, data only:** `Main.dc.html`, `Game.dc.html` (2024 week-15 KC at CLE, the reference for the C3 line and its score distributions), `Phone.dc.html`, `Light.dc.html` in the controller scratchpad's `artifact-files/09000966-773c-468c-b672-cda6017045b2/project/`.
- **Worktree:** `C:/Users/jviol/Downloads/nfl-worktrees/a8`, branch `feat/a8-local-app`, base `main` at `4f9aad3`. Copy `C:/Users/jviol/Downloads/nfl/.Rprofile` into the worktree if it is missing (it is gitignored).
- **No new npm or R dependencies:** `web/package.json` dependencies and `renv.lock` stay byte-identical (only `package.json` `scripts` change). `gt`, `htmltools`, `scales` stay in `renv.lock`/`DESCRIPTION`; the close-out lists them as removal candidates for the owner.
- **No 2025 data.** Do not edit `backtest/eval_windows/*.json` or any frozen `PROTOCOL.md`.
- **Windows and Git Bash:** write and edit files with the file tools (heredocs collapse backslashes); pass `C:/` paths to R and node; list a directory before deleting anything; MSYS rewrites `/c/...` arguments, so use `C:/...`.
- **Deletions the A8 decision authorizes, and no others:** `R/report_banner.R`, `tests/testthat/test-html-report-alignment.R`, `tests/testthat/test-moneyline-report-schema.R`, `tests/testthat/test-report-banner.R`, and the `NFLmarket.R`/`NFLsimulation.R` code listed in Task 7. Any other deletion is a CLAUDE.md STOP item: ask.
- **`NFLsimulation.R` and Plan 1b-1 (`fix/phase1b-1-explicit-model`):** never edit its regions (`:42-69`, `:2697-2772`, `:3139-3340`, `:3563-3610`, `:4075-4110`, `:4590-4600`, `:5070-5125`, `:5218-5250`, `:5355-5480`, `:6110-6125`, `:6265-6290`, `:8459-8462` at `4f9aad3`). A8 deletes only `:1368-2131`, `:2286-2314`, `:2363-2373`, `:8155-8159`, `:8190`, `:8252-8326`, `:8328-8391`, `:8399-8453`, `:8472-8525`; the three blank lines `:8469-8471` after `saveRDS(games_ready, ...)` stay, so 1b-1's added `saveRDS(mu_terms, ...)` line merges cleanly (proved in Task 7 Step 8).
- **Unchanged:** `config.R` defaults; the `R/data_validation.R` API (`generate_quality_badge_html` stays: `scripts/verify_requirements.R` and `test-data-validation.R` call it); `build_moneyline_comparison_table` and the CSV exports `artifacts/baseline_games.csv` and `artifacts/baseline_props.csv`; the run-log saves of `final` and `games_ready`; the export of `last_simulation_results`.
- **Public pages:** no stake, EV or recommendation column (existing invariant and tests). A model line is labelled unvalidated unless its candidate passed its gates; C3 is labelled "Simulator". No silent fill: a game without a market keeps NA market fields (audit M11); every bundle problem is a QA failure in the manifest.
- **Design:** colours only from the tokens in `web/src/app/globals.css` (slop scan); Archivo only; 3px controls and 6px cards, one border level; sentence case; every chart is a `<figure>` with a computed summary and a table view (spec §4, dataviz rules).
- **New copy is limited to what A8's behaviour needs:** the simulator notes in `policy.ts`, the methodology sentences about the simulator line, the game page's distribution and spread sentences, and the README/CLAUDE.md/GETTING_STARTED text about the bundle and `npm run local`. Restyled pages re-lay their existing copy.
- **Secrets:** `web/.env.local` and `<repo>/.local/` are gitignored; passwords and `AUTH_SECRET` are generated locally and never printed or committed.
- **Per task:** one commit, message = subject line, blank line, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Every task ends with `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R` both exiting 0, plus `npm run typecheck`, `npm run lint` and `npx vitest run` (with `TEST_DATABASE_URL` and `REQUIRE_DB_TESTS=1`, so the pg suites run) when `web/` changes. Push and the draft PR only in Task 10; merging needs the owner.
- **Golden master:** predict "no differences" for every A8 commit (no removed line reads or modifies `final` before `saveRDS(final, ...)`); any difference is investigated, not explained away.
- **Live data:** the committed golden master (`reports/2026-09-29/golden-master/2024-w15`) no longer matches `main` itself (live nflverse inputs drifted; 10 games differ in the blend columns, max 0.0094 in `home_p_2w_blend`, measured on `4f9aad3` on 2026-10-03). A8 attributes its own effect against a same-day base recording (Task 7) and does not re-record the committed one.
- **Ports:** local app `127.0.0.1:3000`, local PostgreSQL `127.0.0.1:5434`, e2e fixture server `127.0.0.1:3100`, scratch test PostgreSQL `127.0.0.1:5436`.

## Review Focus

1. **The simulator's draws are missing** (`NFLsimulation.R`'s export `tryCatch` returned NULL, or never ran): `run_week.R` must still write a bundle, flag every game as a QA failure and keep serving the last good run, not crash. Pinned by Task 3's "draws were never exported" test and `get0(...)` in the `run_week.R` call.
2. **A game with no kickoff time** (late-season flex games have an empty `gametime`): it is shown at 1:00 PM ET, as `backtest/build_inputs.R` does, but `source_status` names the game, so the fill is not silent. Pinned by Task 3's kickoff test.
3. **The durable local cluster already holds runs from earlier sessions** while `bundles/` is empty or partial: `npm run local`'s "nothing published" hints must come from the database's publish pointers, not from the folder. Pinned by Task 2's `missingPointers` test.
4. **The distribution charts at tablet width** (768px) in both themes, which the fixture e2e never visited: no overflow and no serious axe issue. Pinned by Task 5's @sim spec looping over `WIDTHS` (390, 768, 1440) and `SCHEMES`.
5. **A page other than home or game loading something from the internet** (a font, a chart asset): with every non-loopback request aborted, every public page still renders. Pinned by Task 1's offline spec visiting all public pages.

---

## Setup (once, before Task 1)

- [ ] **S1: R library.** In the worktree: `Rscript -e "library(testthat); cat('ok\n')"`. If it fails with "there is no package called 'testthat'", run `Rscript -e "renv::restore(prompt = FALSE)"` (packages link from the renv cache; `renv.lock` must stay unchanged: `git diff --exit-code renv.lock`).
- [ ] **S2: Web packages.** `cd web && npm ci` (needs the network once). Expected: `added ... packages`, no `package-lock.json` change (`git diff --exit-code package-lock.json`).
- [ ] **S3: Scratch PostgreSQL for the pg test suites and the fixture e2e.** If `"C:/Program Files/PostgreSQL/17/bin/psql.exe" -h 127.0.0.1 -p 5436 -U ci -d postgres -Atc "select 1"` prints `1` (the dry run left such a cluster), skip to the last line. Otherwise, with `<scratch>` your scratchpad directory:
  ```bash
  PGBIN="C:/Program Files/PostgreSQL/17/bin"
  "$PGBIN/initdb.exe" -D "<scratch>/pg-test" -U ci --auth=trust -E UTF8 --no-locale
  "$PGBIN/pg_ctl.exe" start -D "<scratch>/pg-test" -l "<scratch>/pg-test.log" -o "-p 5436 -h 127.0.0.1" -w
  ```
  Then (always): `"C:/Program Files/PostgreSQL/17/bin/createdb.exe" -h 127.0.0.1 -p 5436 -U ci nfl_test` (ignore "already exists") and use `TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test` for every `npx vitest run` below. Trust auth on 127.0.0.1 only; it holds fixtures, no secrets.
- [ ] **S4: Baseline.** Record on the untouched branch: `Rscript scripts/run_tests.R` → `tests=394 passed=1502 failed=0 errors=0 skipped=1 unapproved_skips=0`, exit 0; `Rscript scripts/verify_repo_integrity.R` → `Total: 60 passed, 0 failed`, exit 0 (both measured at `4f9aad3` on 2026-10-03).

## File map

| File | Task | Responsibility |
|---|---|---|
| `web/src/app/fonts/archivo-latin.woff2`, `web/src/app/fonts/OFL.txt` | 1 | Archivo variable (latin, wght 100–900, wdth 62–125) and its SIL OFL licence, committed |
| `web/src/app/layout.tsx` | 1 | `next/font/local` instead of `next/font/google` |
| `web/src/test/offlineFonts.test.ts` | 1 | no `next/font/google`; pinned font hash; licence; CSP `font-src 'self'` |
| `web/e2e/offline.spec.ts` | 1 | every public page renders with all non-loopback requests aborted |
| `web/scripts/local/config.ts`, `config.test.ts` | 2 | pure rules of the runner: config, URL, `.env.local` additions, bundle order, rebuild, missing pointers |
| `web/scripts/local.ts` | 2 | `npm run local` / `npm run local:stop` (cluster, env, migrate, ingest, build, serve) |
| `R/sim_bundle.R` | 3 | builds and writes the simulator's weekly bundle |
| `scripts/write_sim_fixture.R`, `contracts/fixtures/bundles/weekly-sim-2024-w15/` | 3 | deterministic web test fixture written by the production builder |
| `tests/testthat/test-sim-bundle.R`, `tests/testthat/test-run-week-outputs.R` | 3, 7 | builder rules; `run_week.R` writes the bundle and no HTML |
| `web/src/lib/policy.ts` (+ test) | 4 | field line: validated → E1 → C3 → market only; copy for each |
| `web/src/lib/data/queries.ts` | 4, 5 | `runCandidates`, `gameDistributions` (public columns only) |
| `web/src/lib/data/simRun.test.ts`, `web/e2e/sim-bundle.spec.ts` | 4, 5 | page probabilities equal the bundle's; distributions render |
| `web/src/lib/distribution.ts` (+ test), `web/src/components/charts/ScoreDistributionChart.tsx` (+ test) | 5 | bin parsing, quantiles, summary, geometry; the chart |
| `web/src/components/ui.tsx`, `web/src/test/designLanguage.test.ts` | 6 | shared Broadcast Line primitives; every page uses them |
| `tests/testthat/test-report-retired.R` | 7 | the retired code cannot come back; computations stay; CI anchors still match |
| `NFLmarket.R`, `NFLsimulation.R`, `run_week.R`, `scripts/verify_repo_integrity.R`, `scripts/audit_verify.sh` | 3, 7 | removal and wiring |
| `CLAUDE.md`, `README.md`, `GETTING_STARTED.md`, `DOCUMENTATION.md`, `docs/API.md`, `docs/ARCHITECTURE.md`, `docs/modeling.md` | 8 | docs follow the code |
| `.github/workflows/weekly-sim.yml`, `tests/testthat/test-workflows.R` | 9 | online path: the same bundle, checked, kept, ingested only with `DATABASE_URL`; YAML parse and job-graph tests for every workflow |
| `web/scripts/check-bundle.ts`, `web/scripts/check-bundle/report.ts` (+ test) | 9 | `npm run check-bundle`: the ingest's validation without a database |
| `CHANGELOG.md`, `HANDOFF.md` | 10 | close-out |

## Call-graph evidence (what Task 7 deletes and what it keeps)

Produced by the scratch tool `a8_callgraph2.R` (Task 7 Step 7 gives its full code and the command), which parses every `.R` file at `4f9aad3` and in the finished worktree, takes the deleted lines from `git diff -U0 4f9aad3`, and lists (1) every top-level definition on a deleted line that no file defines any more, with the references left to it outside the two guard files that name the retired functions on purpose (`scripts/verify_repo_integrity.R`, `tests/testthat/test-report-retired.R`), and (2) every repo function the deleted lines called that is still defined, with its remaining references. Dry-run output (2026-10-03):

```
Deleted lines vs 4f9aad3: NFLmarket.R 2215; NFLsimulation.R 1055; R/report_banner.R 35; run_week.R 88; ...

== Removed top-level definitions and the references left to them ==
 NFLmarket.R        2685 moneyline_report_schema_contract 0
 NFLmarket.R        2726 validate_moneyline_report_schema 0
 NFLmarket.R        2774 export_moneyline_comparison_html 0
 NFLmarket.R        4746 open_moneyline_report            0
 NFLmarket.R        4786 moneyline_report                 0
 NFLsimulation.R    2286 xfun_meets_min                   0
 NFLsimulation.R    2294 has_namespace                    0
 NFLsimulation.R    2301 gt_available                     0
 NFLsimulation.R    2302 reactable_available              0
 NFLsimulation.R    2364 pal_fav                          0
 NFLsimulation.R    2369 pal_total                        0
 NFLsimulation.R    8159 primary_report_tbl               0
 NFLsimulation.R    8261 backtest_seasons                 0
 NFLsimulation.R    8272 sched_has_seasons                0
 NFLsimulation.R    8275 sched_for_backtest               0
 NFLsimulation.R    8292 report_tbl                       0
 NFLsimulation.R    8329 pretty_df                        0
 NFLsimulation.R    8378 rt_df                            0
 NFLsimulation.R    8473 report_schedule                  0
 R/report_banner.R     6 html_escape_cell                 0
 R/report_banner.R    12 render_model_status_banner       0
 tests/.../test-moneyline-report-schema.R 11 sample_moneyline_report_row 0

== Kept: repo functions the deleted lines called, still defined and used ==
 standardize_join_keys            NFLbrier_logloss.R NFLmarket.R R/utils.R     31 refs
 expected_value_units             NFLbrier_logloss.R NFLsimulation.R R/utils.R 28 refs
 apply_bet_governance             R/utils.R                                     7 refs (R/correlated_props.R:1446, tests)
 build_moneyline_comparison_table NFLmarket.R NFLsimulation.R                   6 refs (run_week.R, NFLsimulation.R snapshot)
 generate_quality_badge_html      R/data_validation.R                           5 refs (scripts/verify_requirements.R, tests)
 ensure_columns_with_defaults     NFLmarket.R R/utils.R                         5 refs

Removed definitions with references left: 0
```

Also established by hand:
- The `NFLsimulation.R` fallback exporter (`:1368-2131`) never runs: it sits in `if (!exists("export_moneyline_comparison_html", inherits = FALSE))`, and `NFLmarket.R` is sourced first and always defines it.
- `evaluate_market_vs_blend()`'s `html_*` parameters are passed by no caller (`grep -n "html_output_path\|evaluate_market_vs_blend(" *.R R/*.R` finds only its own definition), so removing them and the HTML branch changes no call.
- The `moneyline_report_inputs$backtest` slot and the backtest `report_tbl` fed only the deleted `moneyline_report()` call; `run_week.R` reads only `$comparison` and `$join_keys`, and the no-snapshot fallback (`comparison = cmp_blend`) is kept, now logged.
- Removing `sched_for_backtest` also removes a `nflreadr::load_schedules()` network call that only the deleted report table used.
- `scripts/audit_verify.sh` (CI job `audit-verify`) grepped six display labels that lived only in the deleted exporter (`Market Home Win % (Fair, Devig=proportional)`, `ML Implied Home % (Raw)`, `EV Edge (Raw)`, `EV Edge (Displayed, Capped)`, `Min Stake (%)`, `MODEL ERROR / REVIEW`); left alone, CI would fail. Task 7 drops those six lines and keeps the three `R/utils.R` governance anchors, with a test that every remaining anchor matches.
- The golden master cannot move: it compares `run_logs/final_*.rds`, and no deleted line reads or modifies `final` before `saveRDS(final, ...)`. Measured: a8dry against a base recording made the same day prints `golden master: no differences`.

### Task 1: Offline fonts (the app builds and renders with no network)

**Files:**
- Create: `web/src/app/fonts/archivo-latin.woff2` (binary, 90,104 bytes), `web/src/app/fonts/OFL.txt`
- Create: `web/src/test/offlineFonts.test.ts`, `web/e2e/offline.spec.ts`
- Modify: `web/src/app/layout.tsx:2,8-9`, `web/src/lib/security/csp.ts:6`, `.gitattributes` (append one line)

**Interfaces:**
- Consumes: nothing.
- Produces: the CSS variable `--font-archivo` (unchanged name, so `globals.css` and every component keep working); `font-src 'self'` in the CSP (unchanged).

Why: `next/font/google` downloads Archivo at build time. Proven on 2026-10-03: with `HTTPS_PROXY=http://127.0.0.1:9` (a dead proxy) `next build` exits 1 with `Failed to fetch Archivo from Google Fonts.`; with the committed font it exits 0.

- [ ] **Step 1: Write the failing test.** Create `web/src/test/offlineFonts.test.ts`:

```ts
/**
 * Offline build (A8): the app must build and render with no network. The only build-time
 * download was next/font/google; Archivo is now committed and loaded with next/font/local.
 */
import { createHash } from "node:crypto";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildCsp } from "../lib/security/csp";

const SRC = join(import.meta.dirname, "..");
const FONTS = join(SRC, "app", "fonts");
// fonts.gstatic.com/s/archivo/v25/k3kQo8UDI-1M0wlSfdnoLg.woff2 (latin; wght 100-900, wdth 62-125), fetched 2026-10-01
const ARCHIVO_SHA256 = "e3a28eade21a900c7155a247757f4b2834c07bb7ef07ad7efa55cebaac1e8f5e";

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? files(join(dir, n)) : [join(dir, n)]));
}

describe("offline fonts", () => {
  it("the layout loads Archivo with next/font/local and nothing imports next/font/google", () => {
    const layout = readFileSync(join(SRC, "app", "layout.tsx"), "utf8");
    expect(layout).toContain('import localFont from "next/font/local"');
    expect(layout).toContain('src: "./fonts/archivo-latin.woff2"');
    const sources = files(SRC).filter((f) => [".ts", ".tsx"].includes(extname(f)) && !/\.test\.tsx?$/.test(f));
    expect(sources.filter((f) => readFileSync(f, "utf8").includes("next/font/google"))).toEqual([]);
  });

  it("the committed font is the pinned Archivo variable woff2", () => {
    const font = readFileSync(join(FONTS, "archivo-latin.woff2"));
    expect(font.subarray(0, 4).toString("latin1")).toBe("wOF2");
    expect(createHash("sha256").update(font).digest("hex")).toBe(ARCHIVO_SHA256);
  });

  it("the font ships with its SIL Open Font License", () => {
    const ofl = readFileSync(join(FONTS, "OFL.txt"), "utf8");
    expect(ofl).toContain("The Archivo Project Authors");
    expect(ofl).toContain("SIL Open Font License, Version 1.1");
  });

  it("the CSP still allows fonts from this origin only", () => {
    const fontSrc = buildCsp({ nonce: "n" }).split("; ").find((d) => d.startsWith("font-src "));
    expect(fontSrc).toBe("font-src 'self'");
  });
});
```

- [ ] **Step 2: Run it and watch it fail.**
  - Run: `cd web && npx vitest run src/test/offlineFonts.test.ts`
  - Expected: 3 failed, 1 passed (the CSP test passes): the layout still imports `next/font/google`, and `src/app/fonts/archivo-latin.woff2` / `OFL.txt` do not exist (`ENOENT`).

- [ ] **Step 3: Commit the font and its licence.** Mark woff2 as binary first: append to `.gitattributes` (after `*.gz binary`)

```
*.woff2 binary
```

  Copy the two files the dry run fetched (from `fonts.gstatic.com/s/archivo/v25/k3kQo8UDI-1M0wlSfdnoLg.woff2` and the Archivo repository's `OFL.txt`):

```bash
SRC="C:/Users/jviol/AppData/Local/Temp/claude/c--Users-jviol-Downloads-nfl/2759f8fe-ea25-4f57-87c6-e922ee1b1cb2/scratchpad"
mkdir -p web/src/app/fonts
cp "$SRC/archivo-latin.woff2" web/src/app/fonts/archivo-latin.woff2
cp "$SRC/OFL.txt" web/src/app/fonts/OFL.txt
sha256sum web/src/app/fonts/archivo-latin.woff2
```

  Expected: `e3a28eade21a900c7155a247757f4b2834c07bb7ef07ad7efa55cebaac1e8f5e`. If the scratch copy is gone, download it once with `curl -fsSL -o web/src/app/fonts/archivo-latin.woff2 https://fonts.gstatic.com/s/archivo/v25/k3kQo8UDI-1M0wlSfdnoLg.woff2` and `curl -fsSL -o web/src/app/fonts/OFL.txt https://raw.githubusercontent.com/Omnibus-Type/Archivo/master/OFL.txt`, then require the same sha256 and that `OFL.txt` starts with `Copyright 2020 The Archivo Project Authors (https://github.com/Omnibus-Type/Archivo)`; any other hash is a stop.

- [ ] **Step 4: Load it with `next/font/local`.** In `web/src/app/layout.tsx` replace

```tsx
import { Archivo } from "next/font/google";
```

with

```tsx
import localFont from "next/font/local";
```

  and replace

```tsx
// Archivo variable with the width axis: condensed for dense tables, expanded for
// team codes and scores (spec §4). Self-hosted by next/font at build time.
const archivo = Archivo({ subsets: ["latin"], axes: ["wdth"], variable: "--font-archivo", display: "swap" });
```

with

```tsx
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
```

  In `web/src/lib/security/csp.ts` replace

```ts
 * - font-src 'self': Archivo is self-hosted by next/font at build time.
```

with

```ts
 * - font-src 'self': Archivo is committed (src/app/fonts) and served by next/font/local.
```

- [ ] **Step 5: Add the offline e2e spec** (it runs in Task 10 against a live server). Create `web/e2e/offline.spec.ts`:

```ts
import { expect, test } from "@playwright/test";

/**
 * Offline (A8): with every request to a non-loopback host aborted, every public page
 * still renders, nothing tries to reach the internet, no request fails, and the font
 * comes from this server. The game page is the first one the home page links to, so
 * the spec works on any published run (the fixture or a run_week.R bundle).
 */
const LOOPBACK = new Set(["127.0.0.1", "localhost", "[::1]"]);

test("every public page renders with every request served locally", async ({ page }) => {
  const external: string[] = [];
  const failed: string[] = [];
  const fonts: string[] = [];
  await page.route("**/*", (route) => {
    const url = new URL(route.request().url());
    if (LOOPBACK.has(url.hostname)) return route.continue();
    external.push(url.href);
    return route.abort();
  });
  page.on("requestfailed", (r) => {
    const error = r.failure()?.errorText ?? "";
    // a link prefetch cancelled by the next navigation is not a failure
    if (LOOPBACK.has(new URL(r.url()).hostname) && error.includes("ERR_ABORTED")) return;
    failed.push(`${r.url()} ${error}`);
  });
  page.on("response", (r) => {
    if (r.status() >= 400) failed.push(`${r.status()} ${r.url()}`);
    if (r.url().endsWith(".woff2") && r.ok()) fonts.push(r.url());
  });

  await page.goto("/", { waitUntil: "networkidle" });
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  const game = await page.locator('a[href^="/games/"]').first().getAttribute("href");
  expect(game, "a game link on the home page").toBeTruthy();
  await page.goto(game!, { waitUntil: "networkidle" });
  await expect(page.getByRole("heading", { level: 2, name: "Win probability" })).toBeVisible();
  for (const path of ["/props", "/evidence", "/methodology", "/data-health", "/login"]) {
    await page.goto(path, { waitUntil: "networkidle" });
    await expect(page.getByRole("heading", { level: 1 }), path).toBeVisible();
  }

  expect(external, "requests to the internet").toEqual([]);
  expect(failed, "failed requests").toEqual([]);
  expect(fonts.length, "a woff2 served by this app").toBeGreaterThan(0);
});
```

- [ ] **Step 6: Run the test and watch it pass.**
  - Run: `cd web && npx vitest run src/test/offlineFonts.test.ts`
  - Expected: `Tests  4 passed (4)`.

- [ ] **Step 7: Prove the build needs no network.**
  - Run (in `web/`): `HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 NEXT_TELEMETRY_DISABLED=1 npx next build`
  - Expected: exit 0 and the route table (`ƒ /`, `ƒ /games/[id]`, … `ƒ /props`). Before Step 4 the same command exits 1 with `Failed to fetch Archivo from Google Fonts.` (dry run, 2026-10-03).

- [ ] **Step 8: Full gates.**
  - `cd web && npm run typecheck && npm run lint && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run` → exit 0, 0 failed.
  - `Rscript scripts/run_tests.R` → exit 0 (`failed=0 errors=0 unapproved_skips=0`); `Rscript scripts/verify_repo_integrity.R` → exit 0, `Total: 60 passed, 0 failed`.

- [ ] **Step 9: Commit.**

```bash
git add .gitattributes web/src/app/fonts/archivo-latin.woff2 web/src/app/fonts/OFL.txt web/src/app/layout.tsx web/src/lib/security/csp.ts web/src/test/offlineFonts.test.ts web/e2e/offline.spec.ts
git commit -F- <<'EOF'
feat(web): commit Archivo and load it with next/font/local so the app builds offline (A8)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

  (The heredoc holds no backslashes, so Git Bash passes it intact.) Golden master: no R change, "no differences".

---

### Task 2: The offline local runner (`npm run local`, `npm run local:stop`)

**Files:**
- Create: `web/scripts/local/config.ts`, `web/scripts/local/config.test.ts`, `web/scripts/local.ts`
- Modify: `web/package.json` (`scripts`), `.gitignore` (append), `web/README.md` (new first section, vitest row)

**Interfaces:**
- Consumes: the existing `ingestBundle`, `loadBundle`, `BundleRejected` (`web/src/lib/ingest/ingest.ts`), `schema.publishPointers` (`web/src/db/schema.ts`), the Drizzle migrations in `web/drizzle/`.
- Produces (`web/scripts/local/config.ts`): `resolveLocalConfig(env, platform, repoRoot): LocalConfig`, `pgExecutable(pgBin, name, platform): string`, `databaseUrl(cfg, password, db?): string`, `redactUrl(url): string`, `parseEnvFile(text): Record<string,string>`, `envAdditions(existing, wanted): string[]`, `selectBundleDirs(entries: {name, manifest}[]): {ingest: string[]; skipped: string[]}`, `missingPointers(published: readonly string[]): {pointer, hint}[]`, `needsBuild(buildIdMtimeMs: number | null, newestSourceMtimeMs: number): boolean`; constants `DEFAULT_WINDOWS_PG_BIN = "C:/Program Files/PostgreSQL/17/bin"`, `DEFAULT_PG_PORT = 5434`, `APP_HOST = "127.0.0.1"`, `APP_PORT = 3000`, `APP_POINTERS = ["weekly", "backtest_games"]`. Task 10 runs `npm run local`.

Behaviour (`npm run local`, idempotent, no network after `npm ci`): resolve `PG_BIN` (env; Windows default above; PATH elsewhere) → create `<repo>/.local/pgdata` (env `NFL_LOCAL_PGDATA`) with `initdb --auth=scram-sha-256` and a random 24-byte password, loopback only, no Unix socket → append `DATABASE_URL` and a random `AUTH_SECRET` to `web/.env.local` only if absent → `pg_ctl start` on 127.0.0.1:5434 (env `NFL_LOCAL_PGPORT`) → create database `nfl_local` → run the migrations → ingest every bundle under `<repo>/bundles/` (env `NFL_LOCAL_BUNDLES`) oldest first by `generated_utc`, so the newest weekly bundle is published (ingest is idempotent on the bundle sha) → print a hint for each publish pointer the database still lacks → `next build` only when there is no build or a source is newer → `next start -H 127.0.0.1 -p 3000`. `npm run local:stop` stops the cluster. Passwords live only in the cluster directory and `web/.env.local`; URLs are printed redacted.

- [ ] **Step 1: Write the failing test.** Create `web/scripts/local/config.test.ts`:

```ts
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  databaseUrl,
  DEFAULT_WINDOWS_PG_BIN,
  envAdditions,
  missingPointers,
  needsBuild,
  parseEnvFile,
  pgExecutable,
  redactUrl,
  resolveLocalConfig,
  selectBundleDirs
} from "./config";

const ROOT = join("repo-root");

describe("resolveLocalConfig", () => {
  it("defaults: a private cluster under .local/pgdata on port 5434, bundles/ at the repo root", () => {
    const cfg = resolveLocalConfig({}, "win32", ROOT);
    expect(cfg.pgBin).toBe(DEFAULT_WINDOWS_PG_BIN);
    expect(cfg.pgData).toBe(join(ROOT, ".local", "pgdata"));
    expect(cfg.pgPort).toBe(5434);
    expect(cfg.bundlesDir).toBe(join(ROOT, "bundles"));
    expect(cfg.envFile).toBe(join(ROOT, "web", ".env.local"));
    expect(cfg.credentialsFile).toBe(join(ROOT, ".local", "pgdata", "nfl_local_credentials.json"));
    expect([cfg.dbName, cfg.dbUser]).toEqual(["nfl_local", "nfl_local"]);
  });

  it("finds PostgreSQL on PATH outside Windows", () => {
    expect(resolveLocalConfig({}, "linux", ROOT).pgBin).toBeNull();
    expect(resolveLocalConfig({}, "darwin", ROOT).pgBin).toBeNull();
  });

  it("takes PG_BIN, NFL_LOCAL_PGDATA, NFL_LOCAL_PGPORT and NFL_LOCAL_BUNDLES from the environment", () => {
    const cfg = resolveLocalConfig(
      { PG_BIN: "/opt/pg/bin", NFL_LOCAL_PGDATA: "/data/pg", NFL_LOCAL_PGPORT: "5440", NFL_LOCAL_BUNDLES: "/b" },
      "linux",
      ROOT
    );
    expect([cfg.pgBin, cfg.pgData, cfg.pgPort, cfg.bundlesDir]).toEqual(["/opt/pg/bin", "/data/pg", 5440, "/b"]);
    expect(cfg.serverLog).toBe(join("/data/pg", "nfl_local_server.log"));
  });

  it("refuses a port that is not a whole number from 1024 to 65535", () => {
    for (const bad of ["80", "70000", "54x4", "5434.5"]) {
      expect(() => resolveLocalConfig({ NFL_LOCAL_PGPORT: bad }, "linux", ROOT), bad).toThrow("NFL_LOCAL_PGPORT");
    }
  });
});

describe("executables and URLs", () => {
  it("adds .exe on Windows and uses the bare name on PATH", () => {
    expect(pgExecutable(DEFAULT_WINDOWS_PG_BIN, "pg_ctl", "win32")).toBe(join(DEFAULT_WINDOWS_PG_BIN, "pg_ctl.exe"));
    expect(pgExecutable(null, "pg_ctl", "linux")).toBe("pg_ctl");
  });

  it("encodes the password in the URL and never prints it", () => {
    const cfg = resolveLocalConfig({}, "linux", ROOT);
    const url = databaseUrl(cfg, "p@ss/w:rd");
    expect(url).toBe("postgres://nfl_local:p%40ss%2Fw%3Ard@127.0.0.1:5434/nfl_local");
    expect(databaseUrl(cfg, "x", "postgres")).toBe("postgres://nfl_local:x@127.0.0.1:5434/postgres");
    expect(redactUrl(url)).toBe("postgres://nfl_local:***@127.0.0.1:5434/nfl_local");
  });
});

describe(".env.local", () => {
  it("parses KEY=value lines, ignoring comments, `export` and quotes", () => {
    expect(parseEnvFile('# c\nexport A=1\r\nB="two words"\n  C = \'3\'\nnot a line\n')).toEqual({ A: "1", B: "two words", C: "3" });
  });

  it("adds only the keys that are absent", () => {
    expect(envAdditions({ AUTH_SECRET: "s" }, { DATABASE_URL: "u", AUTH_SECRET: "new" })).toEqual(["DATABASE_URL=u"]);
    expect(envAdditions({ DATABASE_URL: "mine", AUTH_SECRET: "s" }, { DATABASE_URL: "u", AUTH_SECRET: "new" })).toEqual([]);
  });
});

describe("selectBundleDirs", () => {
  const m = (generated_utc: string, bundle_kind = "weekly") => ({ generated_utc, bundle_kind });

  it("ingests oldest first, so the newest weekly bundle ends up published", () => {
    const { ingest } = selectBundleDirs([
      { name: "2026-w04-x", manifest: m("2026-10-03T12:00:00Z") },
      { name: "backtest-nfl-games-v1-7244a0bc", manifest: m("2026-09-29T21:00:00Z", "backtest") },
      { name: "2024-w15-sim-20261001T120000Z", manifest: m("2026-10-01T12:00:00Z") }
    ]);
    expect(ingest).toEqual(["backtest-nfl-games-v1-7244a0bc", "2024-w15-sim-20261001T120000Z", "2026-w04-x"]);
  });

  it("breaks ties by name and reports directories without a readable manifest", () => {
    const out = selectBundleDirs([
      { name: "b", manifest: m("2026-10-01T00:00:00Z") },
      { name: "a", manifest: m("2026-10-01T00:00:00Z") },
      { name: "notes", manifest: null },
      { name: "half", manifest: { generated_utc: "2026-10-01T00:00:00Z" } }
    ]);
    expect(out).toEqual({ ingest: ["a", "b"], skipped: ["half", "notes"] });
  });
});

describe("missingPointers", () => {
  it("names what the database does not publish yet and what writes it", () => {
    expect(missingPointers(["weekly", "backtest_games"])).toEqual([]);
    expect(missingPointers(["backtest_games"]).map((m) => m.pointer)).toEqual(["weekly"]);
    expect(missingPointers([]).map((m) => m.pointer)).toEqual(["weekly", "backtest_games"]);
    expect(missingPointers([])[0]!.hint).toContain("Rscript run_week.R <week> <season>");
    expect(missingPointers(["weekly"])[0]!.hint).toContain("Rscript scripts/write_backtest_bundle.R");
  });
});

describe("needsBuild", () => {
  it("builds when there is no build or a source is newer, and not otherwise", () => {
    expect(needsBuild(null, 1)).toBe(true);
    expect(needsBuild(2000, 1000)).toBe(false);
    expect(needsBuild(1000, 2000)).toBe(true);
  });
});
```

- [ ] **Step 2: Run it and watch it fail.**
  - Run: `cd web && npx vitest run scripts/local/config.test.ts`
  - Expected: FAIL, `Failed to resolve import "./config"` (no tests run).

- [ ] **Step 3: Write the pure rules.** Create `web/scripts/local/config.ts`:

```ts
/**
 * Pure parts of the offline runner (npm run local, A8): configuration, the database URL,
 * .env.local additions, which bundles to ingest and whether to rebuild. No I/O here, so
 * every rule is unit-tested (config.test.ts); scripts/local.ts does the work.
 */
import { join } from "node:path";

export const DEFAULT_WINDOWS_PG_BIN = "C:/Program Files/PostgreSQL/17/bin";
export const DEFAULT_PG_PORT = 5434;
export const APP_HOST = "127.0.0.1";
export const APP_PORT = 3000;

export interface LocalConfig {
  repoRoot: string;
  webDir: string;
  /** null: find the PostgreSQL executables on PATH */
  pgBin: string | null;
  pgData: string;
  pgPort: number;
  dbName: string;
  dbUser: string;
  bundlesDir: string;
  envFile: string;
  credentialsFile: string;
  serverLog: string;
}

export function resolveLocalConfig(env: Record<string, string | undefined>, platform: string, repoRoot: string): LocalConfig {
  const rawPort = env.NFL_LOCAL_PGPORT?.trim();
  const pgPort = rawPort ? Number(rawPort) : DEFAULT_PG_PORT;
  if (!Number.isInteger(pgPort) || pgPort < 1024 || pgPort > 65535) {
    throw new Error(`NFL_LOCAL_PGPORT must be a whole number from 1024 to 65535 (got "${rawPort}")`);
  }
  const pgData = env.NFL_LOCAL_PGDATA?.trim() || join(repoRoot, ".local", "pgdata");
  const webDir = join(repoRoot, "web");
  return {
    repoRoot,
    webDir,
    pgBin: env.PG_BIN?.trim() || (platform === "win32" ? DEFAULT_WINDOWS_PG_BIN : null),
    pgData,
    pgPort,
    dbName: "nfl_local",
    dbUser: "nfl_local",
    bundlesDir: env.NFL_LOCAL_BUNDLES?.trim() || join(repoRoot, "bundles"),
    envFile: join(webDir, ".env.local"),
    credentialsFile: join(pgData, "nfl_local_credentials.json"),
    serverLog: join(pgData, "nfl_local_server.log")
  };
}

export function pgExecutable(pgBin: string | null, name: string, platform: string): string {
  const file = platform === "win32" ? `${name}.exe` : name;
  return pgBin ? join(pgBin, file) : file;
}

export function databaseUrl(cfg: Pick<LocalConfig, "dbUser" | "pgPort" | "dbName">, password: string, db: string = cfg.dbName): string {
  return `postgres://${cfg.dbUser}:${encodeURIComponent(password)}@127.0.0.1:${cfg.pgPort}/${db}`;
}

/** The URL with its password masked, for messages (secrets are never printed). */
export function redactUrl(url: string): string {
  return url.replace(/^(postgres(?:ql)?:\/\/[^:/@]+:)[^@]*@/, "$1***@");
}

/** KEY=value lines of a dotenv file (comments, `export` and surrounding quotes allowed). */
export function parseEnvFile(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*#/.test(line)) continue;
    const m = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (m) out[m[1]!] = m[2]!.replace(/^(['"])(.*)\1$/, "$2");
  }
  return out;
}

/** Lines to append to .env.local: only the keys it does not already set. */
export function envAdditions(existing: Record<string, string>, wanted: Record<string, string>): string[] {
  return Object.entries(wanted)
    .filter(([key]) => !(key in existing))
    .map(([key, value]) => `${key}=${value}`);
}

export interface BundleEntry {
  name: string;
  manifest: unknown;
}

/**
 * Bundle directories to ingest, oldest first by manifest generated_utc, so the newest
 * weekly bundle is ingested last and ends up published. Directories without a readable
 * manifest are skipped and reported.
 */
export function selectBundleDirs(entries: BundleEntry[]): { ingest: string[]; skipped: string[] } {
  const stamp = (m: unknown): string | null => {
    if (typeof m !== "object" || m === null) return null;
    const r = m as Record<string, unknown>;
    return typeof r.generated_utc === "string" && typeof r.bundle_kind === "string" ? r.generated_utc : null;
  };
  const ok = entries.filter((e) => stamp(e.manifest) !== null);
  ok.sort((a, b) => stamp(a.manifest)!.localeCompare(stamp(b.manifest)!) || a.name.localeCompare(b.name));
  return {
    ingest: ok.map((e) => e.name),
    skipped: entries.filter((e) => stamp(e.manifest) === null).map((e) => e.name).sort()
  };
}

/** Publish pointers the pages read: "weekly" fills the slate and game pages, "backtest_games" /evidence. */
export const APP_POINTERS = ["weekly", "backtest_games"] as const;

const POINTER_HINTS: Record<(typeof APP_POINTERS)[number], string> = {
  weekly: "no weekly run published yet: `Rscript run_week.R <week> <season>` writes one to bundles/",
  backtest_games: "no backtest published yet, so /evidence is empty: `Rscript scripts/write_backtest_bundle.R` writes one to bundles/"
};

/**
 * What the database does not publish yet, and what writes it. Read from the database, not
 * from bundles/: the cluster keeps every run ingested in earlier sessions.
 */
export function missingPointers(published: readonly string[]): { pointer: string; hint: string }[] {
  return APP_POINTERS.filter((p) => !published.includes(p)).map((pointer) => ({ pointer, hint: POINTER_HINTS[pointer] }));
}

/** next build is needed when there is no build or any source is newer than it. */
export function needsBuild(buildIdMtimeMs: number | null, newestSourceMtimeMs: number): boolean {
  return buildIdMtimeMs === null || newestSourceMtimeMs > buildIdMtimeMs;
}
```

- [ ] **Step 4: Run the test and watch it pass.**
  - Run: `cd web && npx vitest run scripts/local/config.test.ts`
  - Expected: `Tests  12 passed (12)`.

- [ ] **Step 5: Write the runner.** Create `web/scripts/local.ts`:

```ts
/**
 * The offline local app (A8): `npm run local` starts it, `npm run local:stop` stops the database.
 *
 * Idempotent, and needs no network once `npm ci` has run:
 *   1. a private PostgreSQL cluster in <repo>/.local/pgdata (NFL_LOCAL_PGDATA), on
 *      127.0.0.1 only, port 5434 (NFL_LOCAL_PGPORT), scram auth with a random password;
 *   2. DATABASE_URL and a random AUTH_SECRET appended to web/.env.local only if absent;
 *   3. the cluster started, the nfl_local database created, the migrations applied;
 *   4. every bundle under <repo>/bundles (NFL_LOCAL_BUNDLES) ingested, oldest first, so the
 *      newest weekly run is the one published (ingest is idempotent on the bundle sha).
 *      run_week.R writes the weekly bundles; `Rscript scripts/write_backtest_bundle.R`
 *      writes the backtest bundle the evidence page reads;
 *   5. next build only when there is no build or a source is newer; then
 *      next start -H 127.0.0.1 -p 3000.
 * The password lives in the cluster directory and web/.env.local (both gitignored) and is
 * never printed. PG_BIN points at PostgreSQL's bin directory (default on Windows:
 * C:/Program Files/PostgreSQL/17/bin; elsewhere: PATH).
 */
import { spawn, spawnSync, type SpawnSyncOptions } from "node:child_process";
import { randomBytes } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import * as schema from "../src/db/schema";
import { BundleRejected, ingestBundle, loadBundle } from "../src/lib/ingest/ingest";
import {
  APP_HOST,
  APP_PORT,
  databaseUrl,
  envAdditions,
  missingPointers,
  needsBuild,
  parseEnvFile,
  pgExecutable,
  redactUrl,
  resolveLocalConfig,
  selectBundleDirs
} from "./local/config";

const WEB = fileURLToPath(new URL("..", import.meta.url));
const cfg = resolveLocalConfig(process.env, process.platform, join(WEB, ".."));
const pg = (name: string) => pgExecutable(cfg.pgBin, name, process.platform);
const nextBin = () => createRequire(import.meta.url).resolve("next/dist/bin/next");

function run(file: string, args: string[], opts: SpawnSyncOptions = {}): number {
  const r = spawnSync(file, args, { stdio: "inherit", ...opts });
  if (r.error) throw new Error(`${file}: ${r.error.message}`);
  return r.status ?? 1;
}

/** pg_ctl status: 0 = running, 3 = stopped, 4 = no cluster */
const clusterStatus = () => spawnSync(pg("pg_ctl"), ["status", "-D", cfg.pgData], { stdio: "ignore" }).status;

/** Create the cluster on first use; return its password. */
function ensureCluster(): string {
  if (existsSync(join(cfg.pgData, "PG_VERSION"))) {
    if (!existsSync(cfg.credentialsFile)) {
      throw new Error(
        `${cfg.pgData} holds a cluster that npm run local did not create (no nfl_local_credentials.json). ` +
          "Set NFL_LOCAL_PGDATA to another directory, or delete that one: every bundle is ingested again."
      );
    }
    return (JSON.parse(readFileSync(cfg.credentialsFile, "utf8")) as { password: string }).password;
  }
  mkdirSync(dirname(cfg.pgData), { recursive: true });
  const password = randomBytes(24).toString("base64url");
  const pwfile = join(tmpdir(), `nfl-local-${process.pid}-${randomBytes(4).toString("hex")}`);
  writeFileSync(pwfile, password, { mode: 0o600 });
  try {
    const r = spawnSync(pg("initdb"), ["-D", cfg.pgData, "-U", cfg.dbUser, `--pwfile=${pwfile}`, "--auth=scram-sha-256", "-E", "UTF8", "--no-locale"], { encoding: "utf8" });
    if (r.error) throw new Error(`initdb not found (${r.error.message}); set PG_BIN to PostgreSQL's bin directory`);
    if (r.status !== 0) throw new Error(`initdb failed (exit ${r.status}):\n${r.stderr}`);
  } finally {
    rmSync(pwfile, { force: true });
  }
  appendFileSync(join(cfg.pgData, "postgresql.conf"), "\n# npm run local: loopback only, no Unix socket\nlisten_addresses = '127.0.0.1'\nunix_socket_directories = ''\n");
  writeFileSync(cfg.credentialsFile, JSON.stringify({ user: cfg.dbUser, password }), { mode: 0o600 });
  console.log(`created a local PostgreSQL cluster in ${cfg.pgData}`);
  return password;
}

/** Append DATABASE_URL and AUTH_SECRET to web/.env.local if absent; return the AUTH_SECRET to use. */
function ensureEnvLocal(url: string): string {
  const text = existsSync(cfg.envFile) ? readFileSync(cfg.envFile, "utf8") : "";
  const existing = parseEnvFile(text);
  const authSecret = existing.AUTH_SECRET ?? randomBytes(32).toString("base64");
  const add = envAdditions(existing, { DATABASE_URL: url, AUTH_SECRET: authSecret });
  if (add.length) {
    appendFileSync(cfg.envFile, `${text && !text.endsWith("\n") ? "\n" : ""}# written by npm run local\n${add.join("\n")}\n`, { mode: 0o600 });
    console.log(`web/.env.local: added ${add.map((l) => l.split("=")[0]).join(" and ")}`);
  }
  if (existing.DATABASE_URL && existing.DATABASE_URL !== url) {
    console.log(`note: web/.env.local sets its own DATABASE_URL; npm run local serves from ${redactUrl(url)}`);
  }
  return authSecret;
}

function startCluster() {
  if (clusterStatus() === 0) return console.log(`PostgreSQL already running (127.0.0.1:${cfg.pgPort})`);
  // stdio ignored: on Windows an inherited pipe would keep this process waiting on the server
  const code = spawnSync(pg("pg_ctl"), ["start", "-D", cfg.pgData, "-l", cfg.serverLog, "-w", "-t", "60", "-o", `-p ${cfg.pgPort}`], { stdio: "ignore" }).status;
  if (code !== 0) {
    const tail = existsSync(cfg.serverLog) ? readFileSync(cfg.serverLog, "utf8").split(/\r?\n/).slice(-15).join("\n") : "";
    throw new Error(`pg_ctl start failed (exit ${code}). Is port ${cfg.pgPort} free? NFL_LOCAL_PGPORT changes it.\n${tail}`);
  }
  console.log(`PostgreSQL started on 127.0.0.1:${cfg.pgPort}`);
}

async function ensureDatabase(password: string) {
  const admin = postgres(databaseUrl(cfg, password, "postgres"), { max: 1, onnotice: () => {} });
  try {
    const found = await admin`select 1 from pg_database where datname = ${cfg.dbName}`;
    if (!found.length) {
      await admin.unsafe(`create database ${cfg.dbName}`);
      console.log(`created database ${cfg.dbName}`);
    }
  } finally {
    await admin.end({ timeout: 5 });
  }
}

function readManifest(dir: string): unknown {
  try {
    return JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8"));
  } catch {
    return null;
  }
}

async function migrateAndIngest(url: string) {
  const client = postgres(url, { max: 1, onnotice: () => {} });
  try {
    await migrate(drizzle(client), { migrationsFolder: join(WEB, "drizzle") });
    console.log("migrations applied");
    const db = drizzle(client, { schema });
    const dirs = existsSync(cfg.bundlesDir) ? readdirSync(cfg.bundlesDir, { withFileTypes: true }).filter((d) => d.isDirectory()) : [];
    const { ingest, skipped } = selectBundleDirs(dirs.map((d) => ({ name: d.name, manifest: readManifest(join(cfg.bundlesDir, d.name)) })));
    for (const name of skipped) console.log(`skipped    ${name}: no readable manifest.json`);
    if (!ingest.length) console.log(`no bundles in ${cfg.bundlesDir}`);
    let rejected = 0;
    for (const name of ingest) {
      try {
        const bundle = loadBundle(join(cfg.bundlesDir, name));
        const res = await ingestBundle(db, bundle);
        console.log(`${res.status.padEnd(10)} ${name}`);
        if (res.status === "qa_failed") console.log(`           QA failures: ${bundle.manifest.qa.failures.join("; ")}`);
      } catch (e) {
        if (!(e instanceof BundleRejected)) throw e;
        rejected += 1;
        console.log(`rejected   ${name}: ${e.message}`);
      }
    }
    if (rejected) console.log(`${rejected} bundle(s) rejected (see above); the app serves the others`);
    const published = await db.select({ pointer: schema.publishPointers.pointer }).from(schema.publishPointers);
    for (const m of missingPointers(published.map((p) => p.pointer))) console.log(m.hint);
  } finally {
    await client.end({ timeout: 5 });
  }
}

function newestMtime(path: string): number {
  const st = statSync(path);
  if (!st.isDirectory()) return st.mtimeMs;
  return Math.max(st.mtimeMs, ...readdirSync(path).map((n) => newestMtime(join(path, n))));
}

function buildIfNeeded(env: NodeJS.ProcessEnv) {
  const buildId = join(WEB, ".next", "BUILD_ID");
  const sources = ["src", "public", "next.config.mjs", "package.json", "package-lock.json", "postcss.config.mjs", "tsconfig.json"]
    .map((p) => join(WEB, p))
    .filter((p) => existsSync(p));
  if (!needsBuild(existsSync(buildId) ? statSync(buildId).mtimeMs : null, Math.max(...sources.map(newestMtime)))) {
    return console.log("the build is current");
  }
  console.log("building the app (next build)...");
  const code = run(process.execPath, [nextBin(), "build"], { cwd: WEB, env });
  if (code !== 0) throw new Error(`next build failed (exit ${code})`);
}

function serve(env: NodeJS.ProcessEnv) {
  console.log(`\nBroadcast Line, offline: http://${APP_HOST}:${APP_PORT}\nCtrl+C stops the web server; npm run local:stop stops the database.\n`);
  const child = spawn(process.execPath, [nextBin(), "start", "-H", APP_HOST, "-p", String(APP_PORT)], { cwd: WEB, stdio: "inherit", env });
  for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => child.kill(signal));
  child.on("exit", (code) => process.exit(code ?? 0));
}

async function start() {
  const password = ensureCluster();
  const url = databaseUrl(cfg, password);
  const authSecret = ensureEnvLocal(url);
  startCluster();
  await ensureDatabase(password);
  await migrateAndIngest(url);
  const env = { ...process.env, DATABASE_URL: url, AUTH_SECRET: authSecret, NEXT_TELEMETRY_DISABLED: "1" };
  buildIfNeeded(env);
  serve(env);
}

function stop() {
  const status = clusterStatus();
  if (status === 4 || !existsSync(join(cfg.pgData, "PG_VERSION"))) return console.log(`no local cluster in ${cfg.pgData}`);
  if (status !== 0) return console.log("PostgreSQL is not running");
  const code = spawnSync(pg("pg_ctl"), ["stop", "-D", cfg.pgData, "-m", "fast", "-w"], { stdio: "ignore" }).status;
  if (code !== 0) throw new Error(`pg_ctl stop failed (exit ${code})`);
  console.log("PostgreSQL stopped");
}

const command = process.argv[2] ?? "start";
try {
  if (command === "start") await start();
  else if (command === "stop") stop();
  else {
    console.error("usage: tsx scripts/local.ts [start|stop]");
    process.exit(2);
  }
} catch (e) {
  console.error(`npm run local: ${(e as Error).message}`);
  process.exit(1);
}
```

- [ ] **Step 6: Wire the scripts and ignore the cluster.** In `web/package.json` replace

```json
    "seed:user": "tsx scripts/seed-user.ts"
```

with

```json
    "seed:user": "tsx scripts/seed-user.ts",
    "local": "tsx scripts/local.ts start",
    "local:stop": "tsx scripts/local.ts stop"
```

  Append to `.gitignore` (after the `/bundles/` block)

```

# The offline local app's PostgreSQL cluster (npm run local in web/)
/.local/
```

- [ ] **Step 7: Document it.** In `web/README.md` replace

```markdown
## Run it locally

You need Node 20.9+ and a Postgres 16+ you can create databases on.
```

with

````markdown
## Run it offline (the results viewer)

This is how you look at a model run. `Rscript run_week.R <week> <season>` writes a weekly bundle to `bundles/<season>-w<WW>-sim-<UTC stamp>/` (the HTML report was retired at checkpoint A8). Then:

```bash
cd web
npm ci                      # once, with a network
npm run local               # http://127.0.0.1:3000, no network needed
npm run local:stop          # stops the local database (Ctrl+C stops the web server)
```

`npm run local` (`scripts/local.ts`) creates a private PostgreSQL cluster in <repo>/.local/pgdata on 127.0.0.1:5434 with a random password, adds `DATABASE_URL` and `AUTH_SECRET` to web/.env.local if they are missing, applies the migrations, ingests every bundle under `bundles/` oldest first (so the newest weekly run is published), builds only when the sources changed, and serves on 127.0.0.1:3000. Secrets are never printed. The evidence page needs the backtest bundle: run `Rscript scripts/write_backtest_bundle.R` once. Settings: `PG_BIN` (PostgreSQL's bin directory; default `C:/Program Files/PostgreSQL/17/bin` on Windows, PATH elsewhere), `NFL_LOCAL_PGDATA`, `NFL_LOCAL_PGPORT`, `NFL_LOCAL_BUNDLES`. The font is committed (`src/app/fonts/archivo-latin.woff2`, SIL OFL), so a build needs no network either.

## Run it locally (development)

You need Node 20.9+ and a Postgres 16+ you can create databases on.
````

  and replace

```markdown
| `npm test` | vitest: contract drift, shared row fixtures, CSP, passwords, policy, slop scan, docs truth |
```

with

```markdown
| `npm test` | vitest: contract drift, shared row fixtures, CSP, passwords, policy, slop scan, docs truth, offline fonts, design language, the local runner's rules, score distributions |
```

  (`src/test/docsTruth.test.ts` checks that every `npm run <script>` the README names exists and every backticked path exists; `.local/pgdata` and `web/.env.local` are written without backticks because they do not exist in a clean checkout.)

- [ ] **Step 8: Smoke-test the runner's argument handling** (no database is touched): `cd web && npx tsx scripts/local.ts nope; echo "exit=$?"` → prints `usage: tsx scripts/local.ts [start|stop]`, `exit=2`. The full start/serve/stop cycle runs in Task 10 Step 6, after there is a bundle to serve.

- [ ] **Step 9: Full gates.** Web: `npm run typecheck && npm run lint && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run` → exit 0 (the docs-truth suite passes with the new README text). R: `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R` → exit 0, integrity `Total: 60 passed, 0 failed`.

- [ ] **Step 10: Commit.**

```bash
git add web/scripts/local.ts web/scripts/local/config.ts web/scripts/local/config.test.ts web/package.json web/README.md .gitignore
git commit -F- <<'EOF'
feat(web): npm run local serves the app offline from a private loopback PostgreSQL (A8)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: The simulator's weekly bundle (R) and the `run_week.R` wiring

**Files:**
- Create: `R/sim_bundle.R`, `tests/testthat/test-sim-bundle.R`, `scripts/write_sim_fixture.R`, `tests/testthat/test-run-week-outputs.R`
- Create (generated by the script): `contracts/fixtures/bundles/weekly-sim-2024-w15/{manifest,teams,games,game_predictions,score_distributions,source_status}.json`
- Modify: `run_week.R:57-58` and before the `ANALYSIS COMPLETE` banner (`:236`), `scripts/verify_repo_integrity.R:60-61`, `scripts/run_matrix.R:171-172`, `web/src/lib/contracts/bundle.test.ts:51-54`

**Interfaces:**
- Consumes: `bw_write_bundle(out_root, kind, meta, tables, extra_qa_failures, contracts_dir, renv_lock)`, `bw_utc()`, `bw_validate_rows()` (`R/bundle_writer.R`); `contracts/schema/bundle_kinds.json` (`weekly` requires `teams, games, game_predictions, source_status`; `score_distributions` optional); `data/reference/teams.csv`; from `NFLsimulation.R`: `final` (columns `game_id, home_p_2w_model, home_p_2w_blend, home_p_2w_mkt, market_available, margin_median, total_median`), `last_simulation_results` (per `game_id`: integer vectors `home, away, total, margin`), `sched`, `get_data_quality()`.
- Produces: `build_sim_bundle_tables(final, sims, schedule, quality, teams_csv, now) -> list(tables, qa)`; `write_sim_bundle(final, sims, schedule, quality, season, week, seed, n_sims, out_root = "bundles", now, git = sb_git_state(), cycle_id = "<season>-w<WW>-sim-<YYYYMMDDTHHMMSSZ>", teams_csv, contracts_dir, renv_lock) -> manifest` (with `$dir`, `$bundle_sha256`, `$qa$ok`, `$qa$failures`); `report_sim_bundle(manifest)`; `sb_git_state() -> list(code_git_sha, code_dirty)`; `sb_bins(draws, mass = 0.999) -> data.frame(x, p)`; `SB_MODEL_LABEL = "Game simulator C3 (unvalidated)"`. Bundle rows the web reads (Tasks 4–5): per game a `C0` row (`p_home_raw = p_home_final = p_home_mkt_novig` = the no-vig market, NA without a market) and a `C3` row (`p_home_raw` = simulator two-way, `p_home_final` = after its market blend, `p_home_mkt_novig` = market or NA, `margin_q50`, `total_q50`); `score_distributions` rows `{game_id, kind: "margin"|"total", bins: [{x, p}]}`. The fixture `contracts/fixtures/bundles/weekly-sim-2024-w15` (3 games; BUF @ DET without a market) is what Tasks 4–5 test against.

Key rules (from the brief, as built): bins cover the central 99.9% of draws with one row per integer outcome and `p` the share of all draws (so `sum(p)` is the covered share); the market is used only where `market_available` is TRUE, because `NFLsimulation.R` leaves the model probability in `home_p_2w_mkt` when a line is missing (audit M11); every problem (duplicate ids, game not in the schedule, missing draws, non-integer draws, missing C3 probability, unknown team) is a QA failure in the manifest, never a silent fix; a `final` without a required column stops (programming error); relocated franchises map like `backtest/build_inputs.R` (`OAK→LV, SD→LAC, STL→LA`); the git state is read before the run because `run_week.R` rewrites the tracked `artifacts/*.csv`, which `sb_git_state()` therefore excludes.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-sim-bundle.R`:

```r
# =============================================================================
# R/sim_bundle.R: the simulator's weekly bundle (checkpoint A8; spec §3). The web
# fixture contracts/fixtures/bundles/weekly-sim-2024-w15 is written by
# scripts/write_sim_fixture.R with this builder, and must match what it writes.
# =============================================================================

sb_teams_csv <- file.path(.test_project_root, "data", "reference", "teams.csv")
sb_contracts <- file.path(.test_project_root, "contracts", "schema")

sb_test_inputs <- function() {
  final <- data.frame(
    game_id = c("2024_15_LA_SF", "2024_15_BUF_DET"), season = 2024L, week = 15L,
    home_team = c("SF", "DET"), away_team = c("LA", "BUF"),
    home_p_2w_model = c(0.48, 0.58), home_p_2w_blend = c(0.56, 0.55),
    # BUF_DET: the engine's M11 fill (the model probability) flagged market_available = FALSE
    home_p_2w_mkt = c(0.583, 0.58), market_available = c(TRUE, FALSE),
    margin_median = c(-1, 3), total_median = c(43, 54), stringsAsFactors = FALSE
  )
  draws <- function(h, a) list(home = h, away = a, total = h + a, margin = h - a, n_trials = length(h))
  sims <- list("2024_15_LA_SF" = draws(c(20, 24, 17, 27, 21, 10), c(17, 24, 20, 13, 21, 30)),
               "2024_15_BUF_DET" = draws(c(31, 28, 24, 35, 21, 17), c(27, 30, 24, 20, 38, 24)))
  schedule <- data.frame(
    game_id = c("2024_15_LA_SF", "2024_15_BUF_DET", "2024_15_BAL_NYG"), season = 2024L, week = 15L,
    game_type = "REG", gameday = c("2024-12-12", "2024-12-15", "2024-12-15"),
    gametime = c("20:15", "16:25", "13:00"), home_team = c("SF", "DET", "NYG"), away_team = c("LA", "BUF", "BAL"),
    roof = c("outdoors", "dome", "outdoors"), location = "Home",
    home_score = c(6L, 42L, 14L), away_score = c(12L, 48L, 35L), stringsAsFactors = FALSE
  )
  quality <- list(injury = list(status = "full", missing_seasons = character()),
                  weather = list(status = "partial_fallback", fallback_games = "2024_15_LA_SF"),
                  market = list(status = "partial", missing_games = "2024_15_BUF_DET"),
                  calibration = list(method = "none", leakage_free = FALSE))
  list(final = final, sims = sims, schedule = schedule, quality = quality)
}

sb_build <- function(i) build_sim_bundle_tables(i$final, i$sims, i$schedule, i$quality, teams_csv = sb_teams_csv)

test_that("sb_bins has one row per integer outcome over the central 99.9% of draws", {
  set.seed(1)
  d <- c(rep(0L, 5), stats::rpois(9990, 20), 200L, -150L, 75L, 80L, 90L)
  b <- sb_bins(d)
  expect_named(b, c("x", "p"))
  expect_identical(b$x, seq.int(min(b$x), max(b$x)))
  expect_gte(sum(b$p), 0.999)
  expect_lte(sum(b$p), 1)
  expect_false(any(c(-150, 75, 80, 90, 200) %in% b$x))
  expect_equal(b$p[b$x == 20], mean(d == 20))
})

test_that("sb_bins refuses draws that are not finite integers", {
  expect_error(sb_bins(c(1.5, 2)), "integers")
  expect_error(sb_bins(c(1, NA)), "finite")
  expect_error(sb_bins(numeric()), "non-empty")
})

test_that("C0 carries the market and C3 the simulator; a game without a market keeps NA market fields (M11)", {
  i <- sb_test_inputs()
  b <- sb_build(i)
  gp <- b$tables$game_predictions
  expect_setequal(paste(gp$game_id, gp$candidate),
                  c("2024_15_LA_SF C0", "2024_15_BUF_DET C0", "2024_15_LA_SF C3", "2024_15_BUF_DET C3"))
  row <- function(id, cand) gp[gp$game_id == id & gp$candidate == cand, ]
  sf0 <- row("2024_15_LA_SF", "C0"); sf3 <- row("2024_15_LA_SF", "C3")
  det0 <- row("2024_15_BUF_DET", "C0"); det3 <- row("2024_15_BUF_DET", "C3")
  expect_equal(c(sf0$p_home_raw, sf0$p_home_final, sf0$p_home_mkt_novig), rep(0.583, 3))
  expect_equal(c(sf3$p_home_raw, sf3$p_home_final, sf3$p_home_mkt_novig, sf3$margin_q50, sf3$total_q50),
               c(0.48, 0.56, 0.583, -1, 43))
  expect_true(all(is.na(c(det0$p_home_raw, det0$p_home_final, det0$p_home_mkt_novig, det3$p_home_mkt_novig))))
  expect_equal(det3$p_home_final, 0.55)
  expect_identical(b$qa, character())
})

test_that("games come from the schedule: UTC kickoff, roof, neutral flag, scores", {
  g <- sb_build(sb_test_inputs())$tables$games
  expect_identical(g$game_id, c("2024_15_LA_SF", "2024_15_BUF_DET"))
  expect_identical(g$kickoff_utc, c("2024-12-13T01:15:00Z", "2024-12-15T21:25:00Z"))
  expect_identical(c(g$home_team_id, g$away_team_id), c("SF", "DET", "LA", "BUF"))
  expect_identical(g$roof, c("outdoors", "dome"))
  expect_identical(g$neutral, c(FALSE, FALSE))
  expect_identical(c(g$home_score, g$away_score), c(6L, 42L, 12L, 48L))
})

test_that("relocated franchises map to current team ids and neutral sites are flagged", {
  s <- sb_test_inputs()$schedule
  s$home_team[1] <- "STL"
  s$location[2] <- "Neutral"
  g <- sb_games_table(s, c("2024_15_LA_SF", "2024_15_BUF_DET"))
  expect_identical(g$home_team_id[1], "LA")
  expect_identical(g$neutral, c(FALSE, TRUE))
})

test_that("score distributions: margin and total for every game, as {x, p} bins of all draws", {
  sd <- sb_build(sb_test_inputs())$tables$score_distributions
  expect_identical(paste(sd$game_id, sd$kind),
                   c("2024_15_LA_SF margin", "2024_15_LA_SF total", "2024_15_BUF_DET margin", "2024_15_BUF_DET total"))
  m <- sd$bins[[1]]   # LA_SF margins: 3, 0, -3, 14, 0, -20
  expect_named(m, c("x", "p"))
  expect_identical(range(m$x), c(-20L, 14L))
  expect_length(m$x, 35L)
  expect_equal(m$p[m$x == 0], 2 / 6)
  expect_equal(sum(m$p), 1)
})

test_that("source_status maps the data-quality tracker and names the games behind a partial status", {
  i <- sb_test_inputs()
  ss <- sb_build(i)$tables$source_status
  expect_identical(ss$source, c("nflverse_schedules", "injury_reports", "weather", "market_lines"))
  expect_identical(ss$status, c("ok", "ok", "stale", "stale"))
  expect_match(ss$detail[3], "fallback weather for 2024_15_LA_SF", fixed = TRUE)
  expect_match(ss$detail[4], "no market line for 2024_15_BUF_DET", fixed = TRUE)
  q <- i$quality
  q$injury$status <- "unknown"
  q$weather$status <- "all_fallback"
  q$market$status <- "unavailable"
  st <- sb_source_status(q)
  expect_identical(st$status, c("ok", "failed", "failed", "unavailable"))
  expect_true(all(is.na(st$last_success_utc[-1])))
})

test_that("every problem becomes a QA failure instead of a silent fix", {
  i <- sb_test_inputs()
  i$sims[["2024_15_BUF_DET"]] <- NULL
  i$schedule <- i$schedule[i$schedule$game_id != "2024_15_LA_SF", ]
  i$final$home_p_2w_blend[2] <- NA
  qa <- sb_build(i)$qa
  expect_true(any(grepl("no simulated draws for 2024_15_BUF_DET", qa, fixed = TRUE)))
  expect_true(any(grepl("not in the schedule: 2024_15_LA_SF", qa, fixed = TRUE)))
  expect_true(any(grepl("C3 p_home_final missing for 2024_15_BUF_DET", qa, fixed = TRUE)))
  i <- sb_test_inputs()
  i$sims[["2024_15_LA_SF"]]$margin <- i$sims[["2024_15_LA_SF"]]$margin + 0.5
  expect_true(any(grepl("2024_15_LA_SF margin: sb_bins: draws must be integers", sb_build(i)$qa, fixed = TRUE)))
})

test_that("a run whose draws were never exported is written with every game flagged, not a crash", {
  i <- sb_test_inputs()
  b <- build_sim_bundle_tables(i$final, NULL, i$schedule, i$quality, teams_csv = sb_teams_csv)
  expect_identical(nrow(b$tables$score_distributions), 0L)
  expect_true(any(grepl("no simulated draws for 2024_15_LA_SF, 2024_15_BUF_DET", b$qa, fixed = TRUE)))
  out <- withr::local_tempdir()
  m <- write_sim_bundle(i$final, NULL, i$schedule, i$quality, season = 2024, week = 15, seed = 1, n_sims = 6,
                        out_root = out, git = list(code_git_sha = "0123456789abcdef", code_dirty = FALSE),
                        teams_csv = sb_teams_csv, contracts_dir = sb_contracts,
                        renv_lock = file.path(.test_project_root, "renv.lock"))
  expect_false(m$qa$ok)
  expect_true(file.exists(file.path(m$dir, "manifest.json")))
})

test_that("a game without a kickoff time is shown at 1:00 PM ET and named in source_status, not filled silently", {
  i <- sb_test_inputs()
  i$schedule$gametime[2] <- NA
  b <- sb_build(i)
  expect_identical(b$tables$games$kickoff_utc[2], "2024-12-15T18:00:00Z")
  expect_match(b$tables$source_status$detail[1], "no kickoff time for 2024_15_BUF_DET (shown as 1:00 PM ET)", fixed = TRUE)
  expect_identical(sb_build(sb_test_inputs())$tables$source_status$detail[1],
                   "schedule, scores and consensus closing lines via nflreadr")
  expect_identical(b$qa, character())
})

test_that("a final without a required column stops loudly", {
  i <- sb_test_inputs()
  i$final$market_available <- NULL
  expect_error(sb_build(i), "final lacks market_available")
})

test_that("write_sim_bundle writes a valid weekly bundle named <season>-w<WW>-sim-<UTC stamp>", {
  out <- withr::local_tempdir()
  i <- sb_test_inputs()
  m <- write_sim_bundle(i$final, i$sims, i$schedule, i$quality, season = 2024, week = 15, seed = 471, n_sims = 6,
                        out_root = out, now = as.POSIXct("2026-10-03 12:00:00", tz = "UTC"),
                        git = list(code_git_sha = "0123456789abcdef", code_dirty = FALSE),
                        teams_csv = sb_teams_csv, contracts_dir = sb_contracts,
                        renv_lock = file.path(.test_project_root, "renv.lock"))
  expect_true(m$qa$ok)
  expect_identical(basename(m$dir), "2024-w15-sim-20261003T120000Z")
  man <- jsonlite::read_json(file.path(m$dir, "manifest.json"))
  expect_identical(man$model_label, "Game simulator C3 (unvalidated)")
  expect_equal(c(man$seed, man$n_sims), c(471, 6))
  expect_identical(man$data_asof_utc, "2026-10-03T12:00:00Z")
  expect_setequal(vapply(man$files, `[[`, "", "name"),
                  c("teams.json", "games.json", "game_predictions.json", "score_distributions.json", "source_status.json"))
  sd <- jsonlite::read_json(file.path(m$dir, "score_distributions.json"))
  expect_named(sd[[1]]$bins[[1]], c("x", "p"))
  gp <- jsonlite::read_json(file.path(m$dir, "game_predictions.json"))
  det_c0 <- Filter(function(r) r$game_id == "2024_15_BUF_DET" && r$candidate == "C0", gp)[[1]]
  expect_null(det_c0$p_home_mkt_novig)   # absent, never the model's number (M11)
})

test_that("report_sim_bundle prints the bundle path, its QA and how to view it offline", {
  ok <- list(dir = "bundles/2024-w15-sim-20261003T120000Z", qa = list(ok = TRUE, failures = list()))
  out <- capture.output(report_sim_bundle(ok))
  expect_identical(out, c("  Web bundle: bundles/2024-w15-sim-20261003T120000Z", "  QA: passed",
                          "  View it offline: cd web && npm run local   (then open http://127.0.0.1:3000)"))
  bad <- list(dir = "b", qa = list(ok = FALSE, failures = list("games: not in the schedule: X")))
  out <- capture.output(report_sim_bundle(bad))
  expect_match(out[2], "QA: FAILED (1)", fixed = TRUE)
  expect_identical(out[3], "    - games: not in the schedule: X")
})

test_that("sb_git_state ignores the tracked run outputs under artifacts/ but not code", {
  repo <- withr::local_tempdir()
  withr::with_dir(repo, {
    git <- function(...) system2("git", c(...), stdout = TRUE, stderr = TRUE)
    git("init", "-q")
    git("config", "user.email", "test@example.test")
    git("config", "user.name", "test")
    dir.create("artifacts")
    writeLines("a", "code.R")
    writeLines("1", file.path("artifacts", "baseline_games.csv"))
    git("add", ".")
    git("commit", "-q", "-m", "base")
    writeLines("2", file.path("artifacts", "baseline_games.csv"))
    s <- sb_git_state()
    expect_match(s$code_git_sha, "^[0-9a-f]{40}$")
    expect_false(s$code_dirty)
    writeLines("b", "code.R")
    expect_true(sb_git_state()$code_dirty)
  })
})

test_that("the committed web fixture holds exactly what scripts/write_sim_fixture.R writes", {
  committed <- file.path(.test_project_root, "contracts", "fixtures", "bundles", "weekly-sim-2024-w15")
  env <- new.env()
  withr::with_dir(.test_project_root, sys.source(file.path("scripts", "write_sim_fixture.R"), envir = env))
  out <- withr::local_tempdir()
  m <- withr::with_dir(.test_project_root, env$sf_write(out))
  expect_true(m$qa$ok)
  for (f in c("teams", "games", "game_predictions", "score_distributions", "source_status")) {
    expect_equal(jsonlite::read_json(file.path(m$dir, paste0(f, ".json"))),
                 jsonlite::read_json(file.path(committed, paste0(f, ".json"))), tolerance = 1e-12, info = f)
  }
  man <- jsonlite::read_json(file.path(committed, "manifest.json"))
  expect_true(man$qa$ok)
  expect_identical(c(man$bundle_kind, man$model_label), c("weekly", "Game simulator C3 (unvalidated)"))
})
```

  Create `tests/testthat/test-run-week-outputs.R` (Task 7 appends two more tests):

```r
# =============================================================================
# run_week.R outputs (checkpoint A8): a web bundle for the local app and the two
# audit CSVs; no HTML report and no browser. run_week.R runs the whole engine, so
# these checks read its source; the end-to-end run is the close-out demo.
# =============================================================================

run_week_code <- function() {
  src <- readLines(file.path(.test_project_root, "run_week.R"), warn = FALSE, encoding = "UTF-8")
  src[!grepl("^\\s*#", src)]
}

test_that("run_week.R writes the web bundle once, after the simulation, and reports it", {
  code <- run_week_code()
  expect_equal(sum(grepl("write_sim_bundle(", code, fixed = TRUE)), 1L)
  expect_equal(sum(grepl("report_sim_bundle(sim_bundle)", code, fixed = TRUE)), 1L)
  expect_lt(grep('source("NFLsimulation.R")', code, fixed = TRUE), grep("write_sim_bundle(", code, fixed = TRUE))
  # git state is read before the run rewrites the tracked artifacts/*.csv
  expect_lt(grep("run_git <- sb_git_state()", code, fixed = TRUE), grep('source("NFLsimulation.R")', code, fixed = TRUE))
})
```

- [ ] **Step 2: Run them and watch them fail.**
  - Run: `Rscript -e "testthat::test_file('tests/testthat/test-sim-bundle.R')"` and `Rscript -e "testthat::test_file('tests/testthat/test-run-week-outputs.R')"`
  - Expected: errors `could not find function "sb_bins"` / `"build_sim_bundle_tables"` / `"write_sim_bundle"` (the fixture test also fails: `scripts/write_sim_fixture.R` does not exist), and the run-week test fails on `expect_equal(sum(grepl("write_sim_bundle(", ...)), 1L)` (actual 0).

- [ ] **Step 3: Write the builder.** Create `R/sim_bundle.R` (`tests/testthat/setup.R` sources every `R/*.R`, so the tests see it with no other change):

```r
# =============================================================================
# Simulator bundle: NFLsimulation.R's results as a weekly R -> web bundle (spec §3)
# =============================================================================
# Replaces the retired HTML report (checkpoint A8). run_week.R writes this bundle and
# the local web app (cd web && npm run local) ingests and serves it with no network.
#   - game_predictions: per game a C0 row (the no-vig market) and a C3 row (the
#     simulator: p_home_raw = simulator two-way, p_home_final = after its market blend).
#   - score_distributions: margin and total, one bin per integer outcome over the
#     central SB_MASS of the simulated draws; p is the share of ALL draws.
#   - source_status: the run's data-quality tracker (R/data_validation.R) plus nflverse.
# Every problem found is a QA failure in the manifest (the ingest then stores the run
# as qa_failed and keeps the last good run); nothing is filled in silently. A game
# without a market line keeps NA market fields (audit M11).
# Needs R/bundle_writer.R.
# =============================================================================

SB_MASS <- 0.999
SB_MODEL_LABEL <- "Game simulator C3 (unvalidated)"
SB_FINAL_COLUMNS <- c("game_id", "home_p_2w_model", "home_p_2w_blend", "home_p_2w_mkt",
                      "market_available", "margin_median", "total_median")
# Relocated franchises share one team id, as backtest/build_inputs.R bt_franchise() maps them
SB_FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA")
# Data-quality tracker status -> source_status status (contract: ok | stale | failed | unavailable)
SB_STATUS <- list(
  injury = c(full = "ok", partial = "stale", unavailable = "unavailable"),
  weather = c(full = "ok", partial_fallback = "stale", all_fallback = "failed"),
  market = c(full = "ok", partial = "stale", unavailable = "unavailable")
)

sb_franchise <- function(team) {
  out <- unname(SB_FRANCHISE[team])
  ifelse(is.na(out), team, out)
}

# nflverse gameday/gametime are US Eastern; kickoff_utc is ISO-8601 UTC
sb_kickoff_utc <- function(gameday, gametime) {
  gametime[is.na(gametime) | !nzchar(gametime)] <- "13:00"
  lt <- as.POSIXct(paste(gameday, gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")
  format(lt, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

sb_col <- function(df, col) if (col %in% names(df)) df[[col]] else rep(NA, nrow(df))

#' Integer-outcome histogram of simulated draws over their central `mass`:
#' data.frame(x, p), x every integer from the lower to the upper type-1 quantile and p
#' the share of ALL draws at x, so sum(p) is the covered share (at least `mass`).
sb_bins <- function(draws, mass = SB_MASS) {
  draws <- as.numeric(draws)
  if (!length(draws) || any(!is.finite(draws))) stop("sb_bins: draws must be finite and non-empty", call. = FALSE)
  if (any(abs(draws - round(draws)) > 1e-9)) stop("sb_bins: draws must be integers", call. = FALSE)
  draws <- round(draws)
  tail <- (1 - mass) / 2
  lo <- as.integer(stats::quantile(draws, tail, type = 1, names = FALSE))
  hi <- as.integer(stats::quantile(draws, 1 - tail, type = 1, names = FALSE))
  x <- seq.int(lo, hi)
  counts <- tabulate(as.integer(draws[draws >= lo & draws <= hi]) - lo + 1L, nbins = length(x))
  data.frame(x = x, p = counts / length(draws))
}

#' The games table (contract `games`) for `game_ids`, from nflverse schedule rows
sb_games_table <- function(schedule, game_ids) {
  s <- as.data.frame(schedule)[match(game_ids, schedule$game_id), , drop = FALSE]
  location <- sb_col(s, "location")
  data.frame(
    game_id = game_ids,
    season = as.integer(s$season),
    week = as.integer(s$week),
    game_type = as.character(sb_col(s, "game_type")),
    home_team_id = sb_franchise(as.character(s$home_team)),
    away_team_id = sb_franchise(as.character(s$away_team)),
    kickoff_utc = sb_kickoff_utc(as.character(s$gameday), as.character(sb_col(s, "gametime"))),
    roof = as.character(sb_col(s, "roof")),
    neutral = !is.na(location) & location == "Neutral",
    home_score = as.integer(sb_col(s, "home_score")),
    away_score = as.integer(sb_col(s, "away_score")),
    stringsAsFactors = FALSE
  )
}

#' C0 (market) and C3 (simulator) rows per game. The market is used only where the
#' engine flagged it available: NFLsimulation.R leaves the model probability in
#' home_p_2w_mkt when a line is missing (attach_market_probs), and that is not a market.
sb_predictions <- function(final) {
  f <- as.data.frame(final)
  mkt <- ifelse(f$market_available %in% TRUE, f$home_p_2w_mkt, NA_real_)
  c0 <- data.frame(game_id = f$game_id, candidate = "C0", p_home_raw = mkt, p_home_final = mkt,
                   p_home_mkt_novig = mkt, margin_q50 = NA_real_, total_q50 = NA_real_, stringsAsFactors = FALSE)
  c3 <- data.frame(game_id = f$game_id, candidate = "C3", p_home_raw = f$home_p_2w_model,
                   p_home_final = f$home_p_2w_blend, p_home_mkt_novig = mkt,
                   margin_q50 = f$margin_median, total_q50 = f$total_median, stringsAsFactors = FALSE)
  rbind(c0, c3)
}

#' Margin and total bins per game; a game whose draws cannot be binned is a QA failure
sb_distributions <- function(sims, game_ids, mass = SB_MASS) {
  rows <- list()
  qa <- character()
  for (id in game_ids) {
    for (kind in c("margin", "total")) {
      bins <- tryCatch(sb_bins(sims[[id]][[kind]], mass), error = function(e) {
        qa <<- c(qa, sprintf("score_distributions: %s %s: %s", id, kind, conditionMessage(e)))
        NULL
      })
      if (!is.null(bins)) rows[[length(rows) + 1]] <- list(game_id = id, kind = kind, bins = bins)
    }
  }
  table <- data.frame(game_id = vapply(rows, `[[`, "", "game_id"), kind = vapply(rows, `[[`, "", "kind"),
                      stringsAsFactors = FALSE)
  table$bins <- lapply(rows, `[[`, "bins")
  list(table = table, qa = qa)
}

sb_detail <- function(what, status, ids_label, ids) {
  base <- sprintf("%s: tracker status '%s'", what, status)
  if (length(ids)) sprintf("%s; %s %s", base, ids_label, paste(sort(as.character(ids)), collapse = ", ")) else base
}

#' source_status rows from get_data_quality(); a status the map does not know
#' (including "unknown": the run never recorded one) becomes "failed". Games whose
#' schedule row has no kickoff time are named, because sb_kickoff_utc() shows them at
#' 1:00 PM ET (as backtest/build_inputs.R does) and that must not pass silently.
sb_source_status <- function(quality, now = Sys.time(), kickoff_assumed = character()) {
  map <- function(kind, s) {
    st <- unname(SB_STATUS[[kind]][s])
    if (length(st) != 1 || is.na(st)) "failed" else st
  }
  status <- c("ok", map("injury", quality$injury$status), map("weather", quality$weather$status),
              map("market", quality$market$status))
  data.frame(
    source = c("nflverse_schedules", "injury_reports", "weather", "market_lines"),
    status = status,
    last_success_utc = ifelse(status %in% c("ok", "stale"), bw_utc(now), NA_character_),
    detail = c(
      paste0("schedule, scores and consensus closing lines via nflreadr",
             if (length(kickoff_assumed)) sprintf("; no kickoff time for %s (shown as 1:00 PM ET)",
                                                  paste(sort(as.character(kickoff_assumed)), collapse = ", ")) else ""),
      sb_detail("injury reports", quality$injury$status, "seasons missing", quality$injury$missing_seasons),
      sb_detail("game-day weather", quality$weather$status, "fallback weather for", quality$weather$fallback_games),
      sb_detail("closing moneylines", quality$market$status, "no market line for", quality$market$missing_games)
    ),
    stringsAsFactors = FALSE
  )
}

#' All tables of a simulator bundle plus the QA failures found while building them.
#' A `final` missing a required column is a programming error and stops.
build_sim_bundle_tables <- function(final, sims, schedule, quality,
                                    teams_csv = file.path("data", "reference", "teams.csv"), now = Sys.time()) {
  missing <- setdiff(SB_FINAL_COLUMNS, names(final))
  if (length(missing)) stop("build_sim_bundle_tables: final lacks ", paste(missing, collapse = ", "), call. = FALSE)
  ids <- as.character(final$game_id)
  flag <- function(cond_ids, fmt) if (length(cond_ids)) sprintf(fmt, paste(cond_ids, collapse = ", ")) else character()
  qa <- c(
    flag(unique(ids[duplicated(ids)]), "game_predictions: duplicate game_id %s"),
    flag(setdiff(ids, schedule$game_id), "games: not in the schedule: %s"),
    flag(setdiff(ids, names(sims)), "score_distributions: no simulated draws for %s"),
    flag(setdiff(names(sims), ids), "score_distributions: draws for games not in final: %s"),
    flag(ids[!is.finite(final$home_p_2w_model)], "game_predictions: C3 p_home_raw missing for %s"),
    flag(ids[!is.finite(final$home_p_2w_blend)], "game_predictions: C3 p_home_final missing for %s")
  )
  teams <- utils::read.csv(teams_csv, stringsAsFactors = FALSE)[, c("team_id", "full_name", "division", "tz")]
  games <- sb_games_table(schedule, ids)
  gametime <- as.character(sb_col(as.data.frame(schedule), "gametime"))[match(ids, schedule$game_id)]
  kickoff_assumed <- ids[ids %in% schedule$game_id & (is.na(gametime) | !nzchar(gametime))]
  unknown <- setdiff(stats::na.omit(c(games$home_team_id, games$away_team_id)), teams$team_id)
  qa <- c(qa, flag(unknown, "games: team ids not in data/reference/teams.csv: %s"))
  dist <- sb_distributions(sims, intersect(ids, names(sims)))
  list(
    tables = list(teams = teams, games = games, game_predictions = sb_predictions(final),
                  score_distributions = dist$table, source_status = sb_source_status(quality, now, kickoff_assumed)),
    qa = c(qa, dist$qa)
  )
}

#' git provenance for the bundle. run_week.R rewrites the tracked artifacts/*.csv on
#' every run; they are outputs, not code, so they do not mark the code dirty.
sb_git_state <- function() {
  sha <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  status <- tryCatch(system2("git", c("status", "--porcelain", "--untracked-files=no", "--", ".", ":(exclude)artifacts"),
                             stdout = TRUE, stderr = FALSE), error = function(e) NULL)
  list(code_git_sha = if (length(sha)) sha[1] else NA_character_,
       code_dirty = if (is.null(status)) NA else length(status) > 0)
}

#' Write the simulator's weekly bundle to <out_root>/<cycle_id>/ and return its manifest
#' (bw_write_bundle; qa$ok is FALSE when anything above was flagged)
write_sim_bundle <- function(final, sims, schedule, quality, season, week, seed, n_sims,
                             out_root = "bundles", now = Sys.time(), git = sb_git_state(),
                             cycle_id = sprintf("%d-w%02d-sim-%s", as.integer(season), as.integer(week),
                                                format(now, "%Y%m%dT%H%M%SZ", tz = "UTC")),
                             teams_csv = file.path("data", "reference", "teams.csv"),
                             contracts_dir = file.path("contracts", "schema"), renv_lock = "renv.lock") {
  built <- build_sim_bundle_tables(final, sims, schedule, quality, teams_csv = teams_csv, now = now)
  meta <- list(
    cycle_id = cycle_id, season = as.integer(season), week = as.integer(week),
    model_label = SB_MODEL_LABEL, data_asof_utc = bw_utc(now),
    code_git_sha = git$code_git_sha, code_dirty = git$code_dirty,
    config = list(
      engine = "NFLsimulation.R (Monte Carlo: negative binomial scores, Gaussian copula)",
      candidates = list(C0 = "no-vig market", C3 = "simulator two-way home win probability; p_home_final after its market blend"),
      market_source = "nflverse consensus close: moneylines devigged proportionally (the spread mapped to a probability where a game has no moneyline)",
      calibration_method = quality$calibration$method,
      distribution_mass = SB_MASS
    ),
    seed = if (is.null(seed)) NULL else as.integer(seed),
    n_sims = as.integer(n_sims)
  )
  bw_write_bundle(out_root, "weekly", meta, built$tables, extra_qa_failures = built$qa,
                  contracts_dir = contracts_dir, renv_lock = renv_lock)
}

#' Console lines for run_week.R: where the bundle went, its QA and how to view it
report_sim_bundle <- function(manifest) {
  failures <- unlist(manifest$qa$failures)
  lines <- c(
    sprintf("  Web bundle: %s", manifest$dir),
    if (isTRUE(manifest$qa$ok)) "  QA: passed" else c(
      sprintf("  QA: FAILED (%d); the app stores this run as qa_failed and keeps showing the last good run:", length(failures)),
      paste0("    - ", failures)
    ),
    "  View it offline: cd web && npm run local   (then open http://127.0.0.1:3000)"
  )
  cat(paste0(lines, "\n"), sep = "")
  invisible(lines)
}
```

- [ ] **Step 4: Write the fixture script.** Create `scripts/write_sim_fixture.R`:

```r
#!/usr/bin/env Rscript
# =============================================================================
# Web test fixture: a simulator bundle, contracts/fixtures/bundles/weekly-sim-2024-w15
#
#   Rscript scripts/write_sim_fixture.R [out_root]   (default contracts/fixtures/bundles)
#
# NOT model output. Three 2024 week-15 games from the committed backtest inputs
# (backtest/data/games.csv) get synthetic score draws: negative-binomial quantiles at
# fixed means, paired by a fixed permutation, so the fixture is the same on every OS
# and needs no RNG or network. BUF @ DET loses its market the way NFLsimulation.R
# flags a missing line (market_available = FALSE with the model probability left in
# home_p_2w_mkt), so the web tests cover the no-market path (audit M11).
# Written by the production builder (R/sim_bundle.R); test-sim-bundle.R checks that
# the committed tables equal what this script writes. Exit 1 when QA fails.
# =============================================================================

source("R/bundle_writer.R")
source("R/sim_bundle.R")

SF_CYCLE <- "weekly-sim-2024-w15"
SF_NOW <- as.POSIXct("2026-10-03 12:00:00", tz = "UTC")
SF_N <- 20000L
SF_SIZE <- 6
# synthetic expected points (home, away), not estimates
SF_MEANS <- list("2024_15_LA_SF" = c(23, 21), "2024_15_BAL_NYG" = c(16, 27), "2024_15_BUF_DET" = c(28, 26))
SF_NO_MARKET <- "2024_15_BUF_DET"
SF_MARKET_WEIGHT <- 0.7   # synthetic blend: 70% market

sf_draws <- function(mu_home, mu_away) {
  u <- stats::ppoints(SF_N)
  home <- stats::qnbinom(u, size = SF_SIZE, mu = mu_home)
  # 7919 is prime and coprime with SF_N, so this is a permutation of 1..SF_N
  away <- stats::qnbinom(u, size = SF_SIZE, mu = mu_away)[(seq_len(SF_N) * 7919L) %% SF_N + 1L]
  list(home = home, away = away, total = home + away, margin = home - away, n_trials = SF_N)
}

sf_novig_home <- function(home_ml, away_ml) {
  q <- function(ml) ifelse(ml < 0, -ml / (-ml + 100), 100 / (ml + 100))
  q(home_ml) / (q(home_ml) + q(away_ml))
}

sf_inputs <- function(games_csv = file.path("backtest", "data", "games.csv")) {
  ids <- names(SF_MEANS)
  all_games <- utils::read.csv(games_csv, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  schedule <- all_games[match(ids, all_games$game_id), ]
  sims <- lapply(SF_MEANS, function(m) sf_draws(m[1], m[2]))
  final <- do.call(rbind, lapply(ids, function(id) {
    s <- schedule[schedule$game_id == id, ]
    d <- sims[[id]]
    p_model <- sum(d$margin > 0) / sum(d$margin != 0)
    p_mkt <- sf_novig_home(s$home_moneyline, s$away_moneyline)
    has_mkt <- id != SF_NO_MARKET
    data.frame(game_id = id, season = s$season, week = s$week, home_team = s$home_team, away_team = s$away_team,
               home_p_2w_model = p_model,
               home_p_2w_blend = if (has_mkt) (1 - SF_MARKET_WEIGHT) * p_model + SF_MARKET_WEIGHT * p_mkt else p_model,
               home_p_2w_mkt = if (has_mkt) p_mkt else p_model,
               market_available = has_mkt,
               margin_median = stats::median(d$margin), total_median = stats::median(d$total),
               stringsAsFactors = FALSE)
  }))
  quality <- list(injury = list(status = "full", missing_seasons = character()),
                  weather = list(status = "partial_fallback", fallback_games = "2024_15_BAL_NYG"),
                  market = list(status = "partial", missing_games = SF_NO_MARKET),
                  calibration = list(method = "none", leakage_free = FALSE))
  list(final = final, sims = sims, schedule = schedule, quality = quality)
}

sf_write <- function(out_root = file.path("contracts", "fixtures", "bundles")) {
  i <- sf_inputs()
  write_sim_bundle(i$final, i$sims, i$schedule, i$quality, season = 2024L, week = 15L, seed = NULL,
                   n_sims = SF_N, out_root = out_root, now = SF_NOW, cycle_id = SF_CYCLE)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  m <- sf_write(if (length(a)) a[[1]] else file.path("contracts", "fixtures", "bundles"))
  cat(sprintf("fixture %s -> %s (qa ok: %s)\n", substr(m$bundle_sha256, 1, 12), m$dir, m$qa$ok))
  if (!isTRUE(m$qa$ok)) {
    cat(paste(" -", unlist(m$qa$failures)), sep = "\n")
    quit(status = 1)
  }
}
```

- [ ] **Step 5: Generate and check the fixture.**
  - Run: `Rscript scripts/write_sim_fixture.R`
  - Expected: `fixture <12 hex> -> contracts/fixtures/bundles/weekly-sim-2024-w15 (qa ok: TRUE)`, exit 0.
  - Run: `sha256sum contracts/fixtures/bundles/weekly-sim-2024-w15/*.json`
  - Expected (the five tables are deterministic; `manifest.json` records `generated_utc` and the git state, so its hash varies):
    ```
    198f91dc709f07efb555c5c7579868b2e044ddcdf0b441d58f2f13f98f592bfe  game_predictions.json
    9b2b5e11ba2929439e18754629e583b7023ee81946ff9991dfa0c2978171f86b  games.json
    7cbc94b6764ef81ee55d23f4c8073d61055995efc36760695718563020602650  score_distributions.json
    f82b5db859ac76c7aebe18e613c49f4611e6c8a751106f4180cd801c28f1d195  source_status.json
    225d156d67369e7884f5ee5d94602329d759cb670628ee5f7345883868e29fdc  teams.json
    ```
  - What it holds: C0 market 0.5830 (LA @ SF), 0.0876 (BAL @ NYG), none (BUF @ DET); C3 final 0.5748, 0.1248, 0.5464; 20,000 synthetic draws per game; weather `stale` for BAL_NYG and market `stale` for BUF_DET.

- [ ] **Step 6: Wire it into `run_week.R`.** Replace

```r
tryCatch({
  source("NFLsimulation.R")
```

with

```r
tryCatch({
  # Bundle writer, and the code's git state before this run rewrites artifacts/
  source("R/bundle_writer.R")
  source("R/sim_bundle.R")
  run_git <- sb_git_state()

  source("NFLsimulation.R")
```

  and replace

```r
  cat("\n")
  cat("=================================================================\n")
  cat("  ANALYSIS COMPLETE\n")
```

with

```r
  # Web bundle: the results the local app shows (replaces the retired HTML report, A8)
  cat("\n")
  # draws missing (NFLsimulation.R's export failed) -> every game is a QA failure, not a crash
  sim_bundle <- write_sim_bundle(
    final = final, sims = get0("last_simulation_results", ifnotfound = NULL), schedule = sched, quality = get_data_quality(),
    season = SEASON, week = WEEK_TO_SIM, seed = SEED, n_sims = N_TRIALS, git = run_git
  )
  report_sim_bundle(sim_bundle)

  cat("\n")
  cat("=================================================================\n")
  cat("  ANALYSIS COMPLETE\n")
```

  (The HTML report still runs until Task 7; this task only adds the bundle.)

- [ ] **Step 7: Integrity, matrix and the TypeScript contract check.** In `scripts/verify_repo_integrity.R` replace

```r
  "R/correlated_props.R",
  "DESCRIPTION",
```

with

```r
  "R/correlated_props.R",
  "R/bundle_writer.R",
  "R/sim_bundle.R",
  "DESCRIPTION",
```

  In `scripts/run_matrix.R` replace

```r
    timeout_secs = 800
  ),

  # Test suite
```

with

```r
    timeout_secs = 800
  ),

  # The simulator's web bundle (A8), built offline from committed inputs by the production
  # builder (R/sim_bundle.R); the script exits 1 when the bundle fails the contract
  list(
    name = "sim-bundle",
    category = "pipeline",
    command = "system2('Rscript', c('scripts/write_sim_fixture.R', shQuote(tempdir()))) -> st; quit(status = st)"
  ),

  # Test suite
```

  In `web/src/lib/contracts/bundle.test.ts` replace

```ts
  const backtest = join(CONTRACTS, "fixtures", "bundles", "backtest-nfl-games-v1");

  it("the committed fixture bundles load and validate end to end", () => {
    for (const dir of [weekly, backtest]) {
```

with

```ts
  const backtest = join(CONTRACTS, "fixtures", "bundles", "backtest-nfl-games-v1");
  const simulator = join(CONTRACTS, "fixtures", "bundles", "weekly-sim-2024-w15");

  it("the committed fixture bundles load and validate end to end", () => {
    for (const dir of [weekly, backtest, simulator]) {
```

- [ ] **Step 8: Run the tests and watch them pass.**
  - `Rscript -e "testthat::test_file('tests/testthat/test-sim-bundle.R')"` → `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 70 ]`.
  - `Rscript -e "testthat::test_file('tests/testthat/test-run-week-outputs.R')"` → `[ FAIL 0 | ... | PASS 4 ]`.
  - The matrix artifact by itself: `Rscript -e "st <- system2('Rscript', c('scripts/write_sim_fixture.R', shQuote(tempdir()))); quit(status = st)"` → prints `fixture ... (qa ok: TRUE)`, exit 0.
  - `cd web && npx vitest run src/lib/contracts/bundle.test.ts` → all passed (the simulator fixture loads, its hashes verify and its rows validate in TypeScript too).

- [ ] **Step 9: Full gates.** `Rscript scripts/run_tests.R` → exit 0, `failed=0 errors=0 unapproved_skips=0`; `Rscript scripts/verify_repo_integrity.R` → exit 0, `Total: 62 passed, 0 failed` (two new required files). Web: `npm run typecheck && npm run lint && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run` → exit 0. Golden master: the bundle is written after `saveRDS(final, ...)` and reads only, "no differences".

- [ ] **Step 10: Commit.**

```bash
git add R/sim_bundle.R scripts/write_sim_fixture.R tests/testthat/test-sim-bundle.R tests/testthat/test-run-week-outputs.R contracts/fixtures/bundles/weekly-sim-2024-w15 run_week.R scripts/verify_repo_integrity.R scripts/run_matrix.R web/src/lib/contracts/bundle.test.ts
git commit -F- <<'EOF'
feat(model): run_week.R writes the simulator's weekly bundle (C0 market, C3 simulator, score distributions) (A8)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: The simulator line on public pages, and the probability test

**Files:**
- Modify (whole file): `web/src/lib/policy.ts`, `web/src/lib/policy.test.ts`
- Modify: `web/src/lib/data/queries.ts:74` (two new public queries), `web/src/app/page.tsx` (field line), `web/src/app/games/[id]/page.tsx` (field line, `data-line` hooks), `web/src/components/Field.tsx:49-53`, `web/src/app/methodology/page.tsx:47-50,68-72` (copy for the new rule), `.github/workflows/ci-web.yml`, `web/README.md` (e2e rows)
- Create: `web/src/lib/data/simRun.test.ts`, `web/e2e/sim-bundle.spec.ts` (Task 5 extends it)

**Interfaces:**
- Consumes: the fixture `contracts/fixtures/bundles/weekly-sim-2024-w15` (Task 3); `ingestBundle`, `loadBundle`; `freshDb`, `hasDb`, `FIXTURE_BUNDLES`, `TEST_DATABASE_URL` (`web/src/test/pg.ts`); `pct(p, digits)` (`web/src/lib/format.ts`).
- Produces: `publicFieldLine(gates: GateRow[], available: readonly string[]): FieldLine | null` (validated candidate the run carries → else `E1` if carried → else `C3` if carried → else `null` = market only); `interface FieldLine { candidate: string; validated: boolean }`; `fieldLineNoun(line)`, `fieldLineNote(line | null)`, `fieldLineShortNote(line)`; `SIMULATOR_CANDIDATE = "C3"`; `CANDIDATE_LABELS.C3 = "Simulator"`; `runCandidates(runId): Promise<string[]>`; `gameDistributions(runId, gameId): Promise<{ margin: unknown; total: unknown }>` (raw JSON or null; Task 5 parses it); page hooks `[data-line="market"]` and `[data-line="model"]` on the game page's two big numbers.

The owner's probability requirement lives here at two levels: `simRun.test.ts` proves the values the pages read (`publicSlate().pMarket`, `candidateLines(...).p`) are the bundle's `p_home_mkt_novig` and C3 `p_home_final` exactly; `e2e/sim-bundle.spec.ts` proves the rendered text equals `pct(value, 1)` on the game page and `pct(value)` in each field's accessible summary. Task 10 runs the spec against the real `run_week.R` bundle.

- [ ] **Step 1: Write the failing tests.** Replace `web/src/lib/policy.test.ts` with:

```ts
import { describe, expect, it } from "vitest";
import {
  candidateLabel,
  fieldLineNote,
  fieldLineNoun,
  fieldLineShortNote,
  publicFieldLine,
  publicModelCandidates,
  RESEARCH_LINE_CANDIDATE,
  SIMULATOR_CANDIDATE
} from "./policy";

const V1 = ["C0", "C1", "C2", "E1", "B1[E1]", "B2[E1]", "K[E1]"];   // a prospective nfl_games_v1 run
const SIM = ["C0", "C3"];                                          // a run_week.R simulator run (A8)
const failing = (cands: string[]) => cands.map((candidate) => ({ candidate, brierStatus: "not better than market" }));

describe("public display policy", () => {
  it("shows a model line only for candidates that passed Confirm", () => {
    const gates = [
      { candidate: "C1", brierStatus: "not better than market" },
      { candidate: "C2", brierStatus: "passes Confirm; Holdout pending" },
      { candidate: "E1", brierStatus: "failed controls" }
    ];
    expect(publicModelCandidates(gates)).toEqual(["C2"]);
  });

  it("with nfl_games_v1 (every candidate not better than market) nothing is public", () => {
    expect(publicModelCandidates(failing(["C1", "C2", "E1", "K[E1]", "B1[E1]", "B2[E1]"]))).toEqual([]);
  });

  it("the field shows a validated candidate when one passed its gates and the run carries it", () => {
    const gates = [
      { candidate: "E1", brierStatus: "not better than market" },
      { candidate: "C2", brierStatus: "passes Confirm; Holdout pending" }
    ];
    expect(publicFieldLine(gates, V1)).toEqual({ candidate: "C2", validated: true });
    expect(publicFieldLine(gates, SIM)).toEqual({ candidate: SIMULATOR_CANDIDATE, validated: false });
  });

  it("otherwise the research line E1, marked unvalidated (owner decision 2026-10-01)", () => {
    expect(publicFieldLine(failing(["C1", "C2", "E1"]), V1)).toEqual({ candidate: RESEARCH_LINE_CANDIDATE, validated: false });
    expect(publicFieldLine([], V1)).toEqual({ candidate: "E1", validated: false });
    expect(RESEARCH_LINE_CANDIDATE).toBe("E1");
  });

  it("a simulator run shows the simulator line, marked unvalidated (A8)", () => {
    expect(publicFieldLine([], SIM)).toEqual({ candidate: "C3", validated: false });
    expect(publicFieldLine(failing(["C1", "C2", "E1"]), SIM)).toEqual({ candidate: "C3", validated: false });
    expect(publicFieldLine([], [...SIM, "E1"])).toEqual({ candidate: "E1", validated: false });
  });

  it("a run with no model candidate shows the market alone", () => {
    expect(publicFieldLine([], ["C0"])).toBeNull();
    expect(publicFieldLine([], [])).toBeNull();
  });

  it("the copy names what the gold line is and how far to trust it", () => {
    const sim = { candidate: "C3", validated: false };
    const e1 = { candidate: "E1", validated: false };
    const ok = { candidate: "C2", validated: true };
    expect(fieldLineNoun(sim)).toBe("the game simulator");
    expect(fieldLineNoun(e1)).toBe("our research model");
    expect(fieldLineNoun(ok)).toBe("a validated model");
    expect(fieldLineNote(sim)).toContain("has not been through the pre-registered test");
    expect(fieldLineNote(e1)).toContain("570 games");
    expect(fieldLineNote(ok)).toContain("passed its pre-registered gates");
    expect(fieldLineNote(null)).toContain("market alone");
    expect(fieldLineShortNote(sim)).toBe("Not yet in the pre-registered test.");
    expect(fieldLineShortNote(e1)).toBe("No model beat the closing market in the pre-registered test.");
  });

  it("labels registered candidates and the simulator, and passes unknown ids through", () => {
    expect(candidateLabel("B2[E1]")).toBe("95% market, 5% ensemble");
    expect(candidateLabel("C3")).toBe("Simulator");
    expect(candidateLabel("Z9")).toBe("Z9");
  });
});
```

  Create `web/src/lib/data/simRun.test.ts`:

```ts
/**
 * A simulator run (A8): the probabilities the pages read are the bundle's numbers,
 * exactly. Ingests the committed fixtures with the simulator bundle last, so it is the
 * published weekly run, as after `Rscript run_week.R` and `npm run local`.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { FIXTURE_BUNDLES, freshDb, hasDb, TEST_DATABASE_URL } from "../../test/pg";
import { ingestBundle, loadBundle } from "../ingest/ingest";

const SIM = join(FIXTURE_BUNDLES, "weekly-sim-2024-w15");
type Pred = { game_id: string; candidate: string; p_home_final?: number; p_home_mkt_novig?: number };
const preds = JSON.parse(readFileSync(join(SIM, "game_predictions.json"), "utf8")) as Pred[];
const row = (gameId: string, candidate: string) => preds.find((p) => p.game_id === gameId && p.candidate === candidate);
const PRIVATE_KEY = /stake|^ev$|recommend|kelly|pass_?reason/i;

function keys(v: unknown, out = new Set<string>()): Set<string> {
  if (Array.isArray(v)) v.forEach((x) => keys(x, out));
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { out.add(k); keys(x, out); }
  return out;
}

describe.skipIf(!hasDb)("a published simulator run (Postgres)", () => {
  let q: typeof import("./queries");
  let db: typeof import("../../db");

  beforeAll(async () => {
    const { db: tdb, client } = await freshDb();
    for (const b of ["weekly-2026-w04", "backtest-nfl-games-v1", "weekly-sim-2024-w15"]) {
      await ingestBundle(tdb, loadBundle(join(FIXTURE_BUNDLES, b)));
    }
    await client.end({ timeout: 5 });
    process.env.DATABASE_URL = TEST_DATABASE_URL;
    db = await import("../../db");
    q = await import("./queries");
  });
  afterAll(async () => {
    await db?.closeDb();
  });

  it("is the published weekly run and carries the market (C0) and the simulator (C3)", async () => {
    const { run, games } = await q.publicSlate();
    expect(run?.modelLabel).toBe("Game simulator C3 (unvalidated)");
    expect(games.map((g) => g.gameId).sort()).toEqual(["2024_15_BAL_NYG", "2024_15_BUF_DET", "2024_15_LA_SF"]);
    expect(await q.runCandidates(run!.runId)).toEqual(["C0", "C3"]);
  });

  it("the market each page reads is the bundle's p_home_mkt_novig, exactly, and null without a line (M11)", async () => {
    const { games } = await q.publicSlate();
    for (const g of games) expect(g.pMarket, g.gameId).toBe(row(g.gameId, "C0")?.p_home_mkt_novig ?? null);
    expect(games.find((g) => g.gameId === "2024_15_BUF_DET")?.pMarket).toBeNull();
  });

  it("the simulator line each page reads is the bundle's C3 p_home_final, exactly", async () => {
    const { run } = await q.publicSlate();
    const lines = await q.candidateLines(run!.runId, ["C3"]);
    expect(lines).toHaveLength(3);
    for (const l of lines) expect(l.p, l.gameId).toBe(row(l.gameId, "C3")!.p_home_final!);
  });

  it("each game has margin and total distributions, and no public read carries a private field", async () => {
    const { run, games } = await q.publicSlate();
    for (const g of games) {
      const d = await q.gameDistributions(run!.runId, g.gameId);
      expect(Array.isArray(d.margin) && Array.isArray(d.total), g.gameId).toBe(true);
      expect([...keys(d)].filter((k) => PRIVATE_KEY.test(k))).toEqual([]);
    }
    expect([...keys(await q.runCandidates(run!.runId))].filter((k) => PRIVATE_KEY.test(k))).toEqual([]);
  });
});
```

- [ ] **Step 2: Run them and watch them fail.**
  - Run: `cd web && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run src/lib/policy.test.ts src/lib/data/simRun.test.ts`
  - Expected: `policy.test.ts` fails to import `fieldLineNote`/`fieldLineNoun`/`fieldLineShortNote`/`SIMULATOR_CANDIDATE` (and `publicFieldLine(gates, V1)` still returns E1 for a simulator run); `simRun.test.ts` fails with `q.runCandidates is not a function` and `q.gameDistributions is not a function` (the market and C3 equality tests pass already: ingest stores the bundle's numbers).

- [ ] **Step 3: The policy.** Replace `web/src/lib/policy.ts` with:

```ts
/**
 * Public display policy (spec §4 "Public content follows the evidence"; shootout
 * design "Candidates that fail stay in the report ... the public site shows
 * market-equivalent probabilities for them, and no picks").
 *
 * A model line appears on public pages only for a candidate whose promotion gates
 * put it at "passes Confirm; Holdout pending" or better. Stakes are never public.
 * Checkpoint A7 confirms the final policy against actual results.
 */
export interface GateRow {
  candidate: string;
  brierStatus: string;
}

export function publicModelCandidates(gates: GateRow[]): string[] {
  return gates.filter((g) => g.brierStatus.startsWith("passes")).map((g) => g.candidate);
}

/**
 * The gold line on public fields (owner decision 2026-10-01, with the Broadcast Line
 * redesign; extended at A8). A candidate that passed its gates is shown as validated.
 * Otherwise one research line, labelled unvalidated everywhere it appears: the Elo + EPA
 * ensemble when the published run has it, else the game simulator (run_week.R bundles).
 * Only candidates the run actually carries count. Stakes stay private.
 */
export const RESEARCH_LINE_CANDIDATE = "E1";
export const SIMULATOR_CANDIDATE = "C3";

export interface FieldLine {
  candidate: string;
  validated: boolean;
}

/** The gold line for a run with `available` candidates; null means the market alone. */
export function publicFieldLine(gates: GateRow[], available: readonly string[]): FieldLine | null {
  const have = new Set(available);
  const passed = publicModelCandidates(gates).find((c) => have.has(c));
  if (passed) return { candidate: passed, validated: true };
  const research = [RESEARCH_LINE_CANDIDATE, SIMULATOR_CANDIDATE].find((c) => have.has(c));
  return research ? { candidate: research, validated: false } : null;
}

/** What the gold line is, for "Blue is the market; gold is …". */
export function fieldLineNoun(line: FieldLine): string {
  if (line.validated) return "a validated model";
  return line.candidate === SIMULATOR_CANDIDATE ? "the game simulator" : "our research model";
}

/** How far to trust the gold line, in one or two sentences (home page). */
export function fieldLineNote(line: FieldLine | null): string {
  if (!line) return "This run has no model line, so the fields show the market alone.";
  if (line.validated) return "This model passed its pre-registered gates. It is still not betting advice.";
  if (line.candidate === RESEARCH_LINE_CANDIDATE) {
    return "In the pre-registered test on 2023–24 (570 games), no model or blend beat the closing market's Brier score. Read the gold line as research output, never as advice.";
  }
  if (line.candidate === SIMULATOR_CANDIDATE) {
    return "The game simulator has not been through the pre-registered test yet. Read the gold line as research output, never as advice.";
  }
  return "This line has not been validated. Read it as research output, never as advice.";
}

/** The short form beside a model's number (game page). */
export function fieldLineShortNote(line: FieldLine): string {
  if (line.validated) return "Passed its pre-registered gates.";
  if (line.candidate === RESEARCH_LINE_CANDIDATE) return "No model beat the closing market in the pre-registered test.";
  if (line.candidate === SIMULATOR_CANDIDATE) return "Not yet in the pre-registered test.";
  return "Not validated.";
}

export const MARKET_CANDIDATE = "C0";

/** Short human labels for registered candidates (nfl_games_v1) and the simulator (A8). */
export const CANDIDATE_LABELS: Record<string, string> = {
  C0: "Market (no-vig close)",
  C1: "Elo",
  C2: "EPA model",
  C3: "Simulator",
  E1: "Elo + EPA ensemble",
  "B1[C1]": "Market stack with Elo",
  "B1[C2]": "Market stack with EPA",
  "B1[E1]": "Market stack with ensemble",
  "B2[E1]": "95% market, 5% ensemble",
  "K[E1]": "Calibrated ensemble"
};

export function candidateLabel(id: string): string {
  return CANDIDATE_LABELS[id] ?? id;
}
```

- [ ] **Step 4: The queries.** In `web/src/lib/data/queries.ts` replace

```ts
    .select({ gameId: s.gamePredictions.gameId, candidate: s.gamePredictions.candidate, p: s.gamePredictions.pHomeFinal })
    .from(s.gamePredictions)
    .where(and(...conds));
}

export async function publicGame(gameId: string) {
```

with

```ts
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

export async function publicGame(gameId: string) {
```

- [ ] **Step 5: Run the unit tests and watch them pass.**
  - Same command as Step 2. Expected: `Tests  12 passed (12)` (8 policy, 4 simulator-run).

- [ ] **Step 6: The home page.** In `web/src/app/page.tsx` make these replacements, in order. Replace

```tsx
import { candidateLines, evidence, publicSlate } from "@/lib/data/queries";
import { age, utcStamp, weekday } from "@/lib/format";
import { candidateLabel, publicFieldLine } from "@/lib/policy";
```

with

```tsx
import { candidateLines, evidence, publicSlate, runCandidates } from "@/lib/data/queries";
import { age, utcStamp, weekday } from "@/lib/format";
import { candidateLabel, fieldLineNote, fieldLineNoun, publicFieldLine } from "@/lib/policy";
```

  Replace

```tsx
  const line = publicFieldLine(ev?.gates ?? []);
  const label = candidateLabel(line.candidate);
  const lines = await candidateLines(run.runId, [line.candidate]);
```

with

```tsx
  const line = publicFieldLine(ev?.gates ?? [], await runCandidates(run.runId));
  const label = line ? candidateLabel(line.candidate) : "Model";
  const lines = line ? await candidateLines(run.runId, [line.candidate]) : [];
```

  Replace

```tsx
    return { g, m: showModel && p !== null ? { p, label, validated: line.validated } : null, gap, flips, hasModel: p !== null && g.pMarket !== null };
```

with

```tsx
    return { g, m: showModel && line && p !== null ? { p, label, validated: line.validated } : null, gap, flips, hasModel: p !== null && g.pMarket !== null };
```

  Replace

```tsx
            Blue is the betting market&apos;s no-vig price; gold is {line.validated ? "a validated model" : "our research model"}.
```

with

```tsx
            Blue is the betting market&apos;s no-vig price{line ? `; gold is ${fieldLineNoun(line)}` : ""}.
```

  Replace

```tsx
          <div className="flex items-center gap-3">
            <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated"} />
            <span className="font-semibold">{label}</span>
          </div>
          <p className="text-sm leading-relaxed text-ink-2 [text-wrap:pretty]">
            {line.validated
              ? "This model passed its pre-registered gates. It is still not betting advice."
              : "In the pre-registered test on 2023–24 (570 games), no model or blend beat the closing market's Brier score. Read the gold line as research output, never as advice."}
          </p>
```

with

```tsx
          <div className="flex items-center gap-3">
            {line ? (
              <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated"} />
            ) : (
              <StatusBadge status="unavailable" label="Market only" />
            )}
            {line ? <span className="font-semibold">{label}</span> : null}
          </div>
          <p className="text-sm leading-relaxed text-ink-2 [text-wrap:pretty]">{fieldLineNote(line)}</p>
```

  Replace

```tsx
        <FieldKey showModel={showModel} modelLabel={label} validated={line.validated} />
```

with

```tsx
        <FieldKey showModel={showModel && line !== null} modelLabel={label} validated={line?.validated ?? false} />
```

  Replace

```tsx
          <Link
            href={href(sort, day, !showModel)}
            aria-label={showModel ? "Model line is on. Turn it off" : "Model line is off. Turn it on"}
            className={chip(showModel)}
          >
            Model line {showModel ? "on" : "off"}
          </Link>
```

with

```tsx
          {line ? (
            <Link
              href={href(sort, day, !showModel)}
              aria-label={showModel ? "Model line is on. Turn it off" : "Model line is off. Turn it on"}
              className={chip(showModel)}
            >
              Model line {showModel ? "on" : "off"}
            </Link>
          ) : null}
```

- [ ] **Step 7: The game page.** In `web/src/app/games/[id]/page.tsx` replace

```tsx
import { candidateLines, evidence, publicGame } from "@/lib/data/queries";
import { kickoff, pct } from "@/lib/format";
import { candidateLabel, publicFieldLine } from "@/lib/policy";
```

with

```tsx
import { candidateLines, evidence, publicGame, runCandidates } from "@/lib/data/queries";
import { kickoff, pct } from "@/lib/format";
import { candidateLabel, fieldLineShortNote, publicFieldLine } from "@/lib/policy";
```

  Replace

```tsx
  const line = publicFieldLine(ev?.gates ?? []);
  const label = candidateLabel(line.candidate);
  const lines = await candidateLines(run.runId, [line.candidate], [id]);
```

with

```tsx
  const line = publicFieldLine(ev?.gates ?? [], await runCandidates(run.runId));
  const label = line ? candidateLabel(line.candidate) : "Model";
  const lines = line ? await candidateLines(run.runId, [line.candidate], [id]) : [];
```

  Replace

```tsx
          <FieldKey showModel={pmod !== null} modelLabel={label} validated={line.validated} />
```

with

```tsx
          <FieldKey showModel={pmod !== null} modelLabel={label} validated={line?.validated ?? false} />
```

  Replace

```tsx
          model={pmod !== null ? { p: pmod, label, validated: line.validated } : null}
```

with

```tsx
          model={pmod !== null && line ? { p: pmod, label, validated: line.validated } : null}
```

  Replace

```tsx
              <span className="text-[13px] text-muted">Market</span>
              <span className="num flex items-center gap-2 text-[30px] font-extrabold">
```

with

```tsx
              <span className="text-[13px] text-muted">Market</span>
              <span className="num flex items-center gap-2 text-[30px] font-extrabold" data-line="market">
```

  Replace

```tsx
              <span className="text-[13px] text-muted">{label}</span>
              <span className="num flex items-center gap-2 text-[30px] font-extrabold">
```

with

```tsx
              <span className="text-[13px] text-muted">{label}</span>
              <span className="num flex items-center gap-2 text-[30px] font-extrabold" data-line="model">
```

  Replace

```tsx
          <div className="flex flex-wrap items-center gap-2 border-t border-rule pt-3 text-sm text-ink-2">
            <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated research model"} />
            <span>
              {line.validated ? "Passed its pre-registered gates." : "No model beat the closing market in the pre-registered test."}{" "}
              <Link href="/evidence">Evidence</Link>
            </span>
          </div>
```

with

```tsx
          {line ? (
            <div className="flex flex-wrap items-center gap-2 border-t border-rule pt-3 text-sm text-ink-2">
              <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated research model"} />
              <span>
                {fieldLineShortNote(line)} <Link href="/evidence">Evidence</Link>
              </span>
            </div>
          ) : null}
```

- [ ] **Step 8: The field's accessible summary** keeps the model's numbers when there is no market line (BUF @ DET in the fixture). In `web/src/components/Field.tsx` replace

```tsx
  const summary =
    pm === null
      ? `${awayName} at ${homeName}: no market line`
      : `${awayName} at ${homeName}. Market: ${awayName} ${pct(1 - pm)}, ${homeName} ${pct(pm)}.` +
        (model && pmod !== null ? ` ${model.label}${model.validated ? "" : " (unvalidated)"}: ${awayName} ${pct(1 - pmod)}, ${homeName} ${pct(pmod)}.` : "");
```

with

```tsx
  // the model's numbers are announced with or without a market line (a simulator run can
  // have a game the market never priced, audit M11)
  const summary =
    (pm === null
      ? `${awayName} at ${homeName}: no market line.`
      : `${awayName} at ${homeName}. Market: ${awayName} ${pct(1 - pm)}, ${homeName} ${pct(pm)}.`) +
    (model && pmod !== null ? ` ${model.label}${model.validated ? "" : " (unvalidated)"}: ${awayName} ${pct(1 - pmod)}, ${homeName} ${pct(pmod)}.` : "");
```

- [ ] **Step 9: The methodology copy follows the new rule** (its old text said the site shows the market alone until a candidate passes, which stopped being true on 2026-10-01). In `web/src/app/methodology/page.tsx` replace

```tsx
      <p className="mt-3 text-sm text-ink-2">
        The Monte Carlo score simulator joins as its own candidate in the next protocol version, once its features are
        point-in-time.
      </p>
```

with

```tsx
      <p className="mt-3 text-sm text-ink-2">
        The Monte Carlo score simulator ({candidateLabel("C3")}) joins as its own candidate in the next protocol version, once
        its features are point-in-time. Until then a simulator run is research output: its line is the simulator&apos;s two-way
        home win probability after its market blend.
      </p>
```

  Replace

```tsx
      <p className="mt-2">
        A model line appears on public pages only for a candidate that passed its gates. Until then the site shows the
        market alone and no picks. Stakes are never public; the private desk tracks paper leans only
        {cfg.paper_edge ? ` (edge of ${cfg.paper_edge * 100} points or more)` : ""}.
      </p>
```

with

```tsx
      <p className="mt-2">
        A candidate that passed its gates is shown as validated. Until one does, the fields carry one research line,
        labelled unvalidated wherever it appears: the {candidateLabel("E1")} when the published run has it, otherwise the
        game simulator. There are no public picks. Stakes are never public; the private desk tracks paper leans only
        {cfg.paper_edge ? ` (edge of ${cfg.paper_edge * 100} points or more)` : ""}.
      </p>
```

- [ ] **Step 10: The e2e probability spec.** Create `web/e2e/sim-bundle.spec.ts`:

```ts
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";
import { pct } from "../src/lib/format";

/**
 * A published simulator run (A8). CI ingests the committed fixture after the main e2e
 * run and then runs `--grep @sim`; locally, point E2E_SIM_BUNDLE at the bundle that
 * `npm run local` published (the newest one under bundles/). The probabilities on the
 * pages must equal the bundle's numbers at the precision each place displays them.
 */
const BUNDLE = process.env.E2E_SIM_BUNDLE ?? fileURLToPath(new URL("../../contracts/fixtures/bundles/weekly-sim-2024-w15", import.meta.url));
const read = <T,>(name: string) => JSON.parse(readFileSync(join(BUNDLE, `${name}.json`), "utf8")) as T;
type Pred = { game_id: string; candidate: string; p_home_final?: number; p_home_mkt_novig?: number };
type Game = { game_id: string; home_team_id: string; away_team_id: string };
type Team = { team_id: string; full_name: string };

const preds = read<Pred[]>("game_predictions");
const games = read<Game[]>("games");
const teams = read<Team[]>("teams");
const name = (id: string) => teams.find((t) => t.team_id === id)!.full_name;
const market = (id: string) => preds.find((p) => p.game_id === id && p.candidate === "C0")?.p_home_mkt_novig ?? null;
const sim = (id: string) => preds.find((p) => p.game_id === id && p.candidate === "C3")!.p_home_final!;

/** The Field's accessible summary, built from the bundle with the display rounding (pct). */
function fieldSummary(g: Game): string {
  const away = name(g.away_team_id);
  const home = name(g.home_team_id);
  const m = market(g.game_id);
  const s = sim(g.game_id);
  const marketPart = m === null ? `${away} at ${home}: no market line.` : `${away} at ${home}. Market: ${away} ${pct(1 - m)}, ${home} ${pct(m)}.`;
  return `${marketPart} Simulator (unvalidated): ${away} ${pct(1 - s)}, ${home} ${pct(s)}.`;
}

test.describe("@sim simulator run", () => {
  test("the home page shows the simulator line, labelled unvalidated, with the bundle's numbers", async ({ page }) => {
    await page.goto("/");
    const status = page.getByRole("complementary", { name: "Model status" });
    await expect(status).toContainText("Unvalidated");
    await expect(status).toContainText("Simulator");
    for (const g of games) {
      await expect(page.locator(`article[data-game="${g.game_id}"]`), g.game_id).toHaveAttribute("aria-label", fieldSummary(g));
    }
  });

  for (const g of games) {
    test(`game ${g.game_id}: market and simulator probabilities equal the bundle at the displayed precision`, async ({ page }) => {
      await page.goto(`/games/${g.game_id}`);
      await expect(page.locator('[data-line="market"]')).toHaveText(pct(market(g.game_id), 1));
      await expect(page.locator('[data-line="model"]')).toHaveText(pct(sim(g.game_id), 1));
      await expect(page.locator(`article[data-game="${g.game_id}"]`)).toHaveAttribute("aria-label", fieldSummary(g));
    });
  }
});
```

  In `.github/workflows/ci-web.yml` replace

```yaml
      - "R/bundle_writer.R"
      - ".github/workflows/ci-web.yml"
```

with

```yaml
      - "R/bundle_writer.R"
      - "R/sim_bundle.R"
      - ".github/workflows/ci-web.yml"
```

  Replace

```yaml
      - name: E2E (axe, overflow, headers, desk auth, stakes never public, ID leaks, reduced motion)
        run: npm run e2e
```

with

```yaml
      - name: E2E (axe, overflow, headers, desk auth, stakes never public, ID leaks, reduced motion, offline)
        run: npm run e2e -- --grep-invert @sim

      - name: E2E on a published simulator run (probabilities equal the bundle; distributions)
        run: |
          # the simulator fixture becomes the published weekly run (A8: run_week.R's bundle)
          npm run ingest -- ../contracts/fixtures/bundles/weekly-sim-2024-w15
          npx playwright test --grep @sim
```

  In `web/README.md` replace

```markdown
| `npm run e2e` | Playwright against a running server (`E2E_BASE_URL`, default `http://127.0.0.1:3100`): axe, overflow, security headers, `/desk` redirect, stakes never public, ID leaks, reduced motion |
```

with

```markdown
| `npm run e2e -- --grep-invert @sim` | Playwright against a running server (`E2E_BASE_URL`, default `http://127.0.0.1:3100`) with the fixture bundles: axe, overflow, security headers, `/desk` redirect, stakes never public, ID leaks, reduced motion, and offline rendering (every request served by this server) |
| `npx playwright test --grep @sim` | with a simulator run published (the committed `weekly-sim-2024-w15` fixture, or `E2E_SIM_BUNDLE` pointing at a run's bundle): the market and simulator probabilities on the pages equal the bundle's at the displayed precision, and the margin and total distributions render with no axe issue |
```

- [ ] **Step 11: Full gates.** Web: `npm run typecheck && npm run lint && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run` → exit 0, 0 failed (the existing `queries.test.ts` "no stake column" checks still pass: the new queries select `candidate`, `kind` and `bins` only). R: `Rscript scripts/run_tests.R`, `Rscript scripts/verify_repo_integrity.R` → exit 0 (62/62). The e2e spec runs in Task 10.

- [ ] **Step 12: Commit.**

```bash
git add web/src/lib/policy.ts web/src/lib/policy.test.ts web/src/lib/data/queries.ts web/src/lib/data/simRun.test.ts web/src/app/page.tsx "web/src/app/games/[id]/page.tsx" web/src/components/Field.tsx web/src/app/methodology/page.tsx web/e2e/sim-bundle.spec.ts .github/workflows/ci-web.yml web/README.md
git commit -F- <<'EOF'
feat(web): the field shows the simulator (C3, unvalidated) when the published run carries it; pages read the bundle's probabilities exactly (A8)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: The simulated margin and total on the game page

**Files:**
- Create: `web/src/lib/distribution.ts`, `web/src/lib/distribution.test.ts`, `web/src/components/charts/ScoreDistributionChart.tsx`, `web/src/components/charts/ScoreDistributionChart.test.tsx`
- Modify: `web/src/app/games/[id]/page.tsx` (imports, distribution read, spread copy, distribution section), `web/e2e/sim-bundle.spec.ts` (whole file: adds the chart and layout tests)

**Interfaces:**
- Consumes: `gameDistributions(runId, gameId)` (Task 4), `run.nSims` (`model_runs.n_sims`), `ChartFigure` and `useChartWidth` (`web/src/components/charts/`), `StatusBadge`, `@visx/scale`'s `scaleLinear`.
- Produces: `parseBins(raw: unknown): Bin[] | null` (sorted, contiguous integer `x`, `0 ≤ p ≤ 1`, `0 < Σp ≤ 1`, else null), `coveredMass`, `binQuantile(bins, q)` (uncovered share split evenly between the tails), `marginLabel`, `outcomeLabel`, `distributionSummary(kind, bins, nSims, homeId, awayId, result)`, `stepPaths`, `columnPath`, `ticksEvery`; `type Bin = { x: number; p: number }`, `type DistKind = "margin" | "total"`; `<ScoreDistributionChart kind bins homeId awayId nSims result />`.

Design (spec §4 charts, dataviz rules, the `Game.dc.html` reference): one card per chart; a `<figure>` with a title, the computed text summary ("Simulator (unvalidated): median margin KC by 6. In 90% of the 100,000 simulated games …. Final: KC by 14."), a "Simulator (unvalidated)" status label instead of a legend (one series), and a table view with one row per outcome plus the share outside the range; one series in the muted ink token (one-point columns, or a step outline with a 10% wash where a column would be under 5px wide); labelled markers for the median (model gold) and, once final, the result (actual rose); ticks on football steps (7 points for margins, 10 for totals); a crosshair on pointer and arrow keys; colours only from tokens. The bundle stores no spread or total price, so unlike the mockup there is no market marker; the copy says so.

- [ ] **Step 1: Write the failing tests.** Create `web/src/lib/distribution.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
  binQuantile,
  columnPath,
  coveredMass,
  distributionSummary,
  marginLabel,
  outcomeLabel,
  parseBins,
  stepPaths,
  ticksEvery
} from "./distribution";

const SYM = [
  { x: -1, p: 0.25 },
  { x: 0, p: 0.5 },
  { x: 1, p: 0.25 }
];

describe("parseBins", () => {
  it("accepts contiguous integer bins and sorts them", () => {
    expect(parseBins([{ x: 1, p: 0.25 }, { x: -1, p: 0.25 }, { x: 0, p: 0.5 }])).toEqual(SYM);
  });

  it("rejects anything that is not one share per integer outcome", () => {
    expect(parseBins(null)).toBeNull();
    expect(parseBins([])).toBeNull();
    expect(parseBins({ x: 0, p: 1 })).toBeNull();
    expect(parseBins([{ x: 0.5, p: 1 }])).toBeNull();                     // not an integer outcome
    expect(parseBins([{ x: 0, p: -0.1 }])).toBeNull();                    // negative share
    expect(parseBins([{ x: 0, p: 0.6 }, { x: 0, p: 0.4 }])).toBeNull();   // duplicate x
    expect(parseBins([{ x: 0, p: 0.5 }, { x: 2, p: 0.5 }])).toBeNull();   // a gap
    expect(parseBins([{ x: 0, p: 0.7 }, { x: 1, p: 0.7 }])).toBeNull();   // more than all the games
    expect(parseBins([{ x: 0, p: 0 }])).toBeNull();                       // nothing covered
  });
});

describe("quantiles and labels", () => {
  it("reads quantiles from the full distribution, splitting the uncovered share between the tails", () => {
    expect(coveredMass(SYM)).toBe(1);
    expect(binQuantile(SYM, 0.5)).toBe(0);
    expect(binQuantile(SYM, 0.05)).toBe(-1);
    expect(binQuantile(SYM, 0.95)).toBe(1);
    const covered = [{ x: 10, p: 0.4 }, { x: 11, p: 0.4 }];   // 20% uncovered: 10% in each tail
    expect(binQuantile(covered, 0.45)).toBe(10);
    expect(binQuantile(covered, 0.55)).toBe(11);
  });

  it("names a margin by the team it favours and a total in points", () => {
    expect(marginLabel(3, "SF", "LA")).toBe("SF by 3");
    expect(marginLabel(-7, "SF", "LA")).toBe("LA by 7");
    expect(marginLabel(0, "SF", "LA")).toBe("Tie");
    expect(outcomeLabel("total", 41, "SF", "LA")).toBe("41 points");
  });

  it("summarises the median, the central 90% and the result in words", () => {
    expect(distributionSummary("margin", SYM, 100000, "SF", "LA", -6)).toBe(
      "Simulator (unvalidated): median margin Tie. In 90% of the 100,000 simulated games the margin falls between LA by 1 and SF by 1. Final: LA by 6."
    );
    expect(distributionSummary("total", [{ x: 40, p: 0.5 }, { x: 41, p: 0.5 }], null, "SF", "LA", null)).toBe(
      "Simulator (unvalidated): median total 40 points. In 90% of the simulated games the total falls between 40 and 41 points."
    );
  });
});

describe("geometry", () => {
  it("draws each bin as a flat step from x - 0.5 to x + 0.5 and closes the area on the baseline", () => {
    const x = (v: number) => v * 10;
    const y = (v: number) => 100 - v * 100;
    const { line, area } = stepPaths([{ x: 1, p: 0.25 }, { x: 2, p: 0.5 }], x, y);
    expect(line).toBe("M5,75L15,75L15,50L25,50");
    expect(area).toBe("M5,100L5,75L15,75L15,50L25,50L25,100Z");
  });

  it("rounds a column's data end and keeps it square at the baseline, even when it is shorter than the radius", () => {
    expect(columnPath(10, 100, 40, 8, 2)).toBe("M6,100v-38q0,-2 2,-2h4q2,0 2,2v38z");
    expect(columnPath(10, 100, 1, 8, 2)).toBe("M6,100v0q0,-1 1,-1h6q1,0 1,1v0z");
  });

  it("puts ticks on football-sized steps", () => {
    expect(ticksEvery(-20.5, 14.5, 7)).toEqual([-14, -7, 0, 7, 14]);
    expect(ticksEvery(9.5, 80.5, 10)).toEqual([10, 20, 30, 40, 50, 60, 70, 80]);
  });
});
```

  Create `web/src/components/charts/ScoreDistributionChart.test.tsx`:

```tsx
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ScoreDistributionChart } from "./ScoreDistributionChart";

const P = [0.1, 0.2, 0.25, 0.2, 0.15, 0.1];
const bins = [-2, -1, 0, 1, 2, 3].map((x, i) => ({ x, p: P[i]! }));

describe("ScoreDistributionChart (server render)", () => {
  it("is a card with a figure, a computed summary, labelled median and result, and one table row per outcome", () => {
    const html = renderToStaticMarkup(<ScoreDistributionChart kind="margin" bins={bins} homeId="SF" awayId="LA" nSims={100000} result={-2} />);
    expect(html).toContain("<figure");
    expect(html).toContain("Simulated final margin");
    expect(html).toContain("Simulator (unvalidated)");
    expect(html).toContain(
      "Simulator (unvalidated): median margin Tie. In 90% of the 100,000 simulated games the margin falls between LA by 2 and SF by 3. Final: LA by 2."
    );
    expect(html).toContain("Median Tie");
    expect(html).toContain("Final LA by 2");
    expect((html.match(/<tr class="border-t border-rule">/g) ?? []).length).toBe(bins.length);
    expect(html).toContain("<td>25.00%</td>");
    expect(html).toContain("Outside the range shown");
    expect(html).toContain('stroke="var(--model)"');
    expect(html).toContain('stroke="var(--actual)"');
    expect(html).not.toMatch(/#[0-9a-f]{3,6}\b/i);   // colours come from the tokens
  });

  it("labels a total in points and leaves the result out until the game is final", () => {
    const totals = [40, 41, 42].map((x, i) => ({ x, p: [0.3, 0.4, 0.3][i]! }));
    const html = renderToStaticMarkup(<ScoreDistributionChart kind="total" bins={totals} homeId="SF" awayId="LA" nSims={null} result={null} />);
    expect(html).toContain("Simulated total points");
    expect(html).toContain("Median 41 points");
    expect(html).toContain("median total 41 points");
    expect(html).not.toContain("Final ");
    expect(html).not.toContain('stroke="var(--actual)"');
  });
});
```

- [ ] **Step 2: Run them and watch them fail.**
  - Run: `cd web && npx vitest run src/lib/distribution.test.ts src/components/charts/ScoreDistributionChart.test.tsx`
  - Expected: both files fail to resolve `./distribution` / `./ScoreDistributionChart`.

- [ ] **Step 3: The distribution helpers.** Create `web/src/lib/distribution.ts`:

```ts
/**
 * Simulated score distributions (A8). The bundle's score_distributions.bins are one row
 * per integer outcome, {x, p}, over the central 99.9% of the simulator's draws, with p
 * the share of ALL draws (R/sim_bundle.R). The column is free JSON, so it is parsed and
 * checked here before anything is drawn; an unreadable distribution is reported on the
 * page, never guessed at.
 */
import { z } from "zod";

export interface Bin {
  x: number;
  p: number;
}

export type DistKind = "margin" | "total";

const BinsSchema = z.array(z.object({ x: z.number().int(), p: z.number().min(0).max(1) })).min(1);

/** Sorted bins, or null unless every x is an integer one apart and the shares sum to at most 1. */
export function parseBins(raw: unknown): Bin[] | null {
  const r = BinsSchema.safeParse(raw);
  if (!r.success) return null;
  const bins = [...r.data].sort((a, b) => a.x - b.x);
  for (let i = 1; i < bins.length; i++) if (bins[i]!.x !== bins[i - 1]!.x + 1) return null;
  const mass = coveredMass(bins);
  return mass > 0 && mass <= 1 + 1e-9 ? bins : null;
}

/** The share of all simulated games the bins cover. */
export function coveredMass(bins: Bin[]): number {
  return bins.reduce((a, b) => a + b.p, 0);
}

/** Quantile q of the full distribution; the uncovered share is split evenly between the tails. */
export function binQuantile(bins: Bin[], q: number): number {
  let cum = (1 - coveredMass(bins)) / 2;
  for (const b of bins) {
    cum += b.p;
    if (cum >= q - 1e-12) return b.x;
  }
  return bins[bins.length - 1]!.x;
}

/** A home-minus-away margin in words. */
export function marginLabel(x: number, homeId: string, awayId: string): string {
  if (x > 0) return `${homeId} by ${x}`;
  if (x < 0) return `${awayId} by ${-x}`;
  return "Tie";
}

/** An outcome in words: a margin by the team it favours, a total in points. */
export function outcomeLabel(kind: DistKind, x: number, homeId: string, awayId: string): string {
  return kind === "margin" ? marginLabel(x, homeId, awayId) : `${x} points`;
}

/** The chart's text summary: median, the central 90% of simulated games, and the result once final. */
export function distributionSummary(
  kind: DistKind,
  bins: Bin[],
  nSims: number | null,
  homeId: string,
  awayId: string,
  result: number | null
): string {
  const label = (v: number) => outcomeLabel(kind, v, homeId, awayId);
  const games = nSims ? `the ${nSims.toLocaleString("en-US")} simulated games` : "the simulated games";
  const final = result === null ? "" : ` Final: ${label(result)}.`;
  const med = binQuantile(bins, 0.5);
  const lo = binQuantile(bins, 0.05);
  const hi = binQuantile(bins, 0.95);
  if (kind === "margin") {
    return `Simulator (unvalidated): median margin ${label(med)}. In 90% of ${games} the margin falls between ${label(lo)} and ${label(hi)}.${final}`;
  }
  return `Simulator (unvalidated): median total ${med} points. In 90% of ${games} the total falls between ${lo} and ${hi} points.${final}`;
}

const r2 = (v: number) => Math.round(v * 100) / 100;

/** SVG paths of a step outline and its filled area; each bin spans x - 0.5 to x + 0.5. */
export function stepPaths(bins: Bin[], x: (v: number) => number, y: (v: number) => number): { line: string; area: string } {
  const steps = bins.flatMap((b) => [`${r2(x(b.x - 0.5))},${r2(y(b.p))}`, `${r2(x(b.x + 0.5))},${r2(y(b.p))}`]);
  const first = bins[0]!;
  const last = bins[bins.length - 1]!;
  return {
    line: `M${steps.join("L")}`,
    area: `M${r2(x(first.x - 0.5))},${r2(y(0))}L${steps.join("L")}L${r2(x(last.x + 0.5))},${r2(y(0))}Z`
  };
}

/** A column grown from the baseline with a rounded data end of radius r (square at the base). */
export function columnPath(cx: number, base: number, h: number, w: number, r: number): string {
  const rr = Math.min(r, w / 2, h);
  return `M${r2(cx - w / 2)},${r2(base)}v${r2(-(h - rr))}q0,${r2(-rr)} ${r2(rr)},${r2(-rr)}h${r2(w - 2 * rr)}q${r2(rr)},0 ${r2(rr)},${r2(rr)}v${r2(h - rr)}z`;
}

/** Multiples of step between lo and hi: football-sized ticks (7 points for margins, 10 for totals). */
export function ticksEvery(lo: number, hi: number, step: number): number[] {
  const out: number[] = [];
  for (let t = Math.ceil(lo / step) * step; t <= hi; t += step) out.push(t === 0 ? 0 : t);
  return out;
}
```

- [ ] **Step 4: The chart.** Create `web/src/components/charts/ScoreDistributionChart.tsx`:

```tsx
"use client";

import { scaleLinear } from "@visx/scale";
import { useState } from "react";
import { StatusBadge } from "@/components/StatusBadge";
import {
  type Bin,
  binQuantile,
  columnPath,
  coveredMass,
  type DistKind,
  distributionSummary,
  outcomeLabel,
  stepPaths,
  ticksEvery
} from "@/lib/distribution";
import { ChartFigure } from "./ChartFigure";
import { useChartWidth } from "./useChartWidth";

/**
 * The simulator's final margin or total points for one game (A8), laid out like the
 * approved game-page mockup: a card per chart, one-point columns, ticks on football
 * steps (7 points for margins, 10 for totals) and labelled markers for the simulator's
 * median (model gold) and, once the game is final, the result (actual rose). One series,
 * so no legend box: the title and the marker labels name everything. Where a one-point
 * column would be under 5px wide (phones) a step outline with a 10% wash keeps every
 * outcome visible. A crosshair snaps to the nearest outcome on pointer or arrow keys;
 * the summary and the table view carry every value (tooltips enhance, never gate).
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
  const x = scaleLinear({ domain: [lo, hi], range: [left, W - right] });
  const y = scaleLinear({ domain: [0, Math.max(...bins.map((b) => b.p))], range: [H - bottom, top], nice: true });
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
    <section className="mt-4 rounded-[6px] border border-rule bg-surface px-5 pb-4 pt-1">
      <ChartFigure
        title={kind === "margin" ? "Simulated final margin" : "Simulated total points"}
        summary={summary}
        legend={<StatusBadge status="unvalidated" label="Simulator (unvalidated)" />}
        table={
          <table className="num w-full text-left">
            <thead className="text-ink-2">
              <tr>
                <th className="py-1 pr-4 font-normal">{kind === "margin" ? `Margin (${homeId} minus ${awayId})` : "Total points"}</th>
                <th className="font-normal">Share of simulated games</th>
              </tr>
            </thead>
            <tbody>
              {bins.map((b) => (
                <tr key={b.x} className="border-t border-rule">
                  <td className="py-1 pr-4">{label(b.x)}</td>
                  <td>{share(b.p)}</td>
                </tr>
              ))}
              <tr className="border-t border-rule text-ink-2">
                <td className="py-1 pr-4">Outside the range shown</td>
                <td>{share(Math.max(0, 1 - coveredMass(bins)))}</td>
              </tr>
            </tbody>
          </table>
        }
      >
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
              className="pointer-events-none absolute z-10 rounded-[3px] border border-rule bg-surface px-2 py-1 text-sm"
              style={{ left: Math.min(Math.max(0, x(focused.x) + 12), Math.max(0, W - 170)), top: 40 }}
            >
              <div className="num font-semibold text-ink">{share(focused.p)} of simulated games</div>
              <div className="text-ink-2">{label(focused.x)}</div>
            </div>
          ) : null}
        </div>
      </ChartFigure>
    </section>
  );
}
```

- [ ] **Step 5: Run the tests and watch them pass.**
  - Same command as Step 2. Expected: `Tests  10 passed (10)` (8 distribution, 2 chart).

- [ ] **Step 6: Draw it on the game page.** In `web/src/app/games/[id]/page.tsx` replace

```tsx
import { StatusBadge } from "@/components/StatusBadge";
import { candidateLines, evidence, publicGame, runCandidates } from "@/lib/data/queries";
import { kickoff, pct } from "@/lib/format";
```

with

```tsx
import { StatusBadge } from "@/components/StatusBadge";
import { ScoreDistributionChart } from "@/components/charts/ScoreDistributionChart";
import { candidateLines, evidence, gameDistributions, publicGame, runCandidates } from "@/lib/data/queries";
import { parseBins } from "@/lib/distribution";
import { kickoff, pct } from "@/lib/format";
```

  Replace

```tsx
  const pmod = lines[0]?.p ?? null;
```

with

```tsx
  const pmod = lines[0]?.p ?? null;
  const dist = await gameDistributions(run.runId, id);
  const hasDist = dist.margin !== null || dist.total !== null;
```

  Replace (the old sentence said the bundle carries moneylines only, which a simulator run no longer is)

```tsx
            The weekly bundle carries moneyline probabilities only. In the validation sprint (Tune 2018–22) no model beat the
            devigged closing spread or total price, so none is shown.
```

with

```tsx
            In the validation sprint (Tune 2018–22) no model beat the devigged closing spread or total price, so no spread or
            total is offered here.{hasDist ? " The simulator's margin and total distributions below are research output." : ""}
```

  Replace

```tsx
        <div className="mt-3">
          <DataUnavailable title="No simulator output in this cycle">
            This week&apos;s bundle comes from the backtest candidates, which predict a win probability only. The score
            simulator&apos;s margin and total distributions appear here once a simulator bundle is ingested (Phase 1b makes it
            point-in-time).
          </DataUnavailable>
        </div>
```

with

```tsx
        {hasDist ? (
          (["margin", "total"] as const).map((kind) => {
            const bins = parseBins(dist[kind]);
            return bins ? (
              <ScoreDistributionChart key={kind} kind={kind} bins={bins} homeId={game.homeTeamId} awayId={game.awayTeamId} nSims={run.nSims}
                result={final ? (kind === "margin" ? final.home - final.away : final.home + final.away) : null} />
            ) : (
              <div key={kind} className="mt-3">
                <DataUnavailable title={dist[kind] === null ? `No ${kind} distribution in this run` : `The ${kind} distribution is unreadable`}>
                  {dist[kind] === null
                    ? `The published run has no simulated ${kind} for this game.`
                    : `Its bins failed validation (one share per integer outcome, no gaps, shares between 0 and 1), so it is not drawn.`}
                </DataUnavailable>
              </div>
            );
          })
        ) : (
          <div className="mt-3">
            <DataUnavailable title="No simulator output in this run">
              The published run predicts win probabilities only. Margin and total distributions appear when the published run
              comes from the game simulator (run_week.R).
            </DataUnavailable>
          </div>
        )}
```

- [ ] **Step 7: Extend the e2e spec.** Replace `web/e2e/sim-bundle.spec.ts` with (adds the distribution test and the 390/768/1440 × light/dark overflow and axe loop):

```ts
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { pct } from "../src/lib/format";
import { SCHEMES, WIDTHS } from "./helpers";

/**
 * A published simulator run (A8). CI ingests the committed fixture after the main e2e
 * run and then runs `--grep @sim`; locally, point E2E_SIM_BUNDLE at the bundle that
 * `npm run local` published (the newest one under bundles/). The probabilities on the
 * pages must equal the bundle's numbers at the precision each place displays them.
 */
const BUNDLE = process.env.E2E_SIM_BUNDLE ?? fileURLToPath(new URL("../../contracts/fixtures/bundles/weekly-sim-2024-w15", import.meta.url));
const read = <T,>(name: string) => JSON.parse(readFileSync(join(BUNDLE, `${name}.json`), "utf8")) as T;
type Pred = { game_id: string; candidate: string; p_home_final?: number; p_home_mkt_novig?: number };
type Game = { game_id: string; home_team_id: string; away_team_id: string };
type Team = { team_id: string; full_name: string };
type Dist = { game_id: string; kind: "margin" | "total"; bins: { x: number; p: number }[] };

const preds = read<Pred[]>("game_predictions");
const games = read<Game[]>("games");
const teams = read<Team[]>("teams");
const name = (id: string) => teams.find((t) => t.team_id === id)!.full_name;
const market = (id: string) => preds.find((p) => p.game_id === id && p.candidate === "C0")?.p_home_mkt_novig ?? null;
const sim = (id: string) => preds.find((p) => p.game_id === id && p.candidate === "C3")!.p_home_final!;

/** The Field's accessible summary, built from the bundle with the display rounding (pct). */
function fieldSummary(g: Game): string {
  const away = name(g.away_team_id);
  const home = name(g.home_team_id);
  const m = market(g.game_id);
  const s = sim(g.game_id);
  const marketPart = m === null ? `${away} at ${home}: no market line.` : `${away} at ${home}. Market: ${away} ${pct(1 - m)}, ${home} ${pct(m)}.`;
  return `${marketPart} Simulator (unvalidated): ${away} ${pct(1 - s)}, ${home} ${pct(s)}.`;
}

test.describe("@sim simulator run", () => {
  test("the home page shows the simulator line, labelled unvalidated, with the bundle's numbers", async ({ page }) => {
    await page.goto("/");
    const status = page.getByRole("complementary", { name: "Model status" });
    await expect(status).toContainText("Unvalidated");
    await expect(status).toContainText("Simulator");
    for (const g of games) {
      await expect(page.locator(`article[data-game="${g.game_id}"]`), g.game_id).toHaveAttribute("aria-label", fieldSummary(g));
    }
  });

  for (const g of games) {
    test(`game ${g.game_id}: market and simulator probabilities equal the bundle at the displayed precision`, async ({ page }) => {
      await page.goto(`/games/${g.game_id}`);
      await expect(page.locator('[data-line="market"]')).toHaveText(pct(market(g.game_id), 1));
      await expect(page.locator('[data-line="model"]')).toHaveText(pct(sim(g.game_id), 1));
      await expect(page.locator(`article[data-game="${g.game_id}"]`)).toHaveAttribute("aria-label", fieldSummary(g));
    });
  }

  test("the game page draws margin and total distributions, each with a summary and a full table view", async ({ page }) => {
    const g = games[0]!;
    const dists = read<Dist[]>("score_distributions").filter((d) => d.game_id === g.game_id);
    await page.goto(`/games/${g.game_id}`);
    for (const [kind, title] of [["margin", "Simulated final margin"], ["total", "Simulated total points"]] as const) {
      const fig = page.locator("figure").filter({ hasText: title });
      await expect(fig).toHaveCount(1);
      await expect(fig.locator("figcaption")).toContainText("median");
      await fig.getByText("Table view").click();
      const bins = dists.find((d) => d.kind === kind)!.bins;
      await expect(fig.locator("tbody tr")).toHaveCount(bins.length + 1);   // every outcome, plus the share outside the range
    }
  });

  for (const scheme of SCHEMES) {
    for (const width of WIDTHS) {
      test(`distributions at ${width}px ${scheme}: no overflow, no serious axe issue`, async ({ page }) => {
        await page.setViewportSize({ width, height: 900 });
        await page.emulateMedia({ colorScheme: scheme });
        await page.goto(`/games/${games[0]!.game_id}`, { waitUntil: "networkidle" });
        await expect(page.locator("figure")).toHaveCount(2);
        const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        expect(overflow).toBeLessThanOrEqual(0);
        const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
        expect(axe.violations.filter((v) => v.impact === "serious" || v.impact === "critical").map((v) => v.id)).toEqual([]);
      });
    }
  }
});
```

- [ ] **Step 8: Full gates.** Web: `npm run typecheck && npm run lint && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run` → exit 0 (the slop scan passes: no hex colours, no gradients in the chart). R: `Rscript scripts/run_tests.R`, `Rscript scripts/verify_repo_integrity.R` → exit 0 (62/62).

- [ ] **Step 9: Commit.**

```bash
git add web/src/lib/distribution.ts web/src/lib/distribution.test.ts web/src/components/charts/ScoreDistributionChart.tsx web/src/components/charts/ScoreDistributionChart.test.tsx "web/src/app/games/[id]/page.tsx" web/e2e/sim-bundle.spec.ts
git commit -F- <<'EOF'
feat(web): the game page draws the simulator's margin and total distributions with summaries and table views (A8)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: The Broadcast Line on every page

**Files:**
- Create: `web/src/components/ui.tsx`, `web/src/test/designLanguage.test.ts`
- Modify (whole file): `web/src/app/evidence/page.tsx`, `web/src/app/methodology/page.tsx`, `web/src/app/data-health/page.tsx`, `web/src/app/props/page.tsx`, `web/src/app/login/page.tsx`, `web/src/app/desk/page.tsx`, `web/src/app/not-found.tsx`
- Modify: `web/src/app/page.tsx` (shared primitives, empty-state title), `web/scripts/review-ui.mjs:8`, `web/README.md` (review line)

**Interfaces:**
- Consumes: the tokens and utilities of `web/src/app/globals.css` (`wdth-expanded`, `num`, `text-ink`, `text-ink-2`, `text-muted`, `border-rule`, `bg-surface`), `StatusBadge`, `DataUnavailable`, the existing queries; nothing new from the database.
- Produces: `PageTitle({ children, lead?, compact? })`, `SectionTitle({ id, children })`, `Card({ children, className? })`, `StatTile({ value, label })`, `chipClass(on: boolean): string`, `BUTTON_CLASS`, `QUIET_BUTTON_CLASS`, `INPUT_CLASS` — taken from #207's home and game pages, so every page shares one language: wide Archivo titles, 22px section titles, one-border 6px cards on the surface token, 44px segment chips, stat tiles.

Rules (owner 2026-10-03, controller ruling): re-lay each page's existing data and copy in #207's design language; no invented content (the only copy change on these pages is Task 4's methodology rule text); colours from tokens only; both themes come from the tokens. `designLanguage.test.ts` fails on any page that keeps the pre-redesign `text-2xl font-semibold` / `text-lg font-semibold` headings or the old 28px chips, or that titles itself outside `PageTitle` / #207's hero `h1`.

- [ ] **Step 1: Write the failing test.** Create `web/src/test/designLanguage.test.ts`:

```ts
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
```

- [ ] **Step 2: Run it and watch it fail.**
  - Run: `cd web && npx vitest run src/test/designLanguage.test.ts`
  - Expected: 2 failed, 1 passed. "every page titles itself" lists `data-health/page.tsx, desk/page.tsx, evidence/page.tsx, login/page.tsx, methodology/page.tsx, not-found.tsx, props/page.tsx`; "no page keeps the pre-redesign headings or chips" lists every old heading and chip line, starting `data-health/page.tsx:13  <h1 className="text-2xl font-semibold">Data health</h1>` and including the home page's empty-state `h1` (dry run, 2026-10-03).

- [ ] **Step 3: The shared primitives.** Create `web/src/components/ui.tsx`:

```tsx
/**
 * Broadcast Line layout primitives (A8), taken from the redesigned home and game pages
 * (#207, from the approved mockup) so every page shares one design language: wide Archivo
 * titles, one-border cards on the surface token, 44px segment chips, stat tiles. Colour
 * comes only from the tokens in globals.css, so the press-box (light) and night-game
 * (dark) themes apply everywhere.
 */
export function PageTitle({ children, lead, compact = false }: { children: React.ReactNode; lead?: React.ReactNode; compact?: boolean }) {
  return (
    <header className="flex flex-col gap-3 pt-4">
      <h1 className={`wdth-expanded font-black leading-[0.95] tracking-[-0.01em] ${compact ? "text-[32px] sm:text-[40px]" : "text-[40px] sm:text-[56px]"}`}>
        {children}
      </h1>
      {lead ? <div className="max-w-[760px] text-[17px] leading-relaxed text-ink-2 [text-wrap:pretty]">{lead}</div> : null}
    </header>
  );
}

/** A page section's heading (the game page's "Win probability" style). */
export function SectionTitle({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2 id={id} className="wdth-expanded text-[22px] font-bold">
      {children}
    </h2>
  );
}

export function Card({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <div className={`rounded-[6px] border border-rule bg-surface px-5 py-5 ${className}`}>{children}</div>;
}

/** A headline number with its caption (the home page's "This week in numbers"). */
export function StatTile({ value, label }: { value: React.ReactNode; label: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5 rounded-[6px] border border-rule bg-surface px-5 py-4">
      <span className="num wdth-expanded text-[40px] font-extrabold leading-none">{value}</span>
      <span className="text-sm text-muted">{label}</span>
    </div>
  );
}

/** A 44px segment chip (sort, day, window and candidate pickers); `on` is the current choice. */
export function chipClass(on: boolean): string {
  return `inline-flex h-11 items-center rounded-[3px] border px-3.5 text-[13px] no-underline ${on ? "border-ink bg-ink font-semibold text-surface" : "border-rule text-ink-2 hover:border-ink-2"}`;
}

/** The ink button of the header's Desk link. */
export const BUTTON_CLASS = "inline-flex h-11 items-center rounded-[3px] border border-ink bg-ink px-4 text-sm font-semibold text-surface no-underline";

/** A quiet bordered button (secondary actions). */
export const QUIET_BUTTON_CLASS = "inline-flex h-11 items-center rounded-[3px] border border-rule px-4 text-sm text-ink";

export const INPUT_CLASS = "mt-1 block h-11 w-full rounded-[3px] border border-rule bg-surface px-3 text-ink";
```

- [ ] **Step 4: The home page uses them** (no visual change; the empty state gets the page title). In `web/src/app/page.tsx` replace

```tsx
import { StatusBadge } from "@/components/StatusBadge";
import { candidateLines, evidence, publicSlate, runCandidates } from "@/lib/data/queries";
```

with

```tsx
import { StatusBadge } from "@/components/StatusBadge";
import { chipClass, PageTitle, StatTile } from "@/components/ui";
import { candidateLines, evidence, publicSlate, runCandidates } from "@/lib/data/queries";
```

  Replace

```tsx
        <h1 className="text-2xl font-semibold">This week</h1>
```

with

```tsx
        <PageTitle>This week</PageTitle>
```

  Replace

```tsx
  const chip = (on: boolean) =>
    `inline-flex h-11 items-center rounded-[3px] border px-3.5 text-[13px] no-underline ${on ? "border-ink bg-ink font-semibold text-surface" : "border-rule text-ink-2 hover:border-ink-2"}`;
```

with

```tsx
  const chip = chipClass;
```

  Replace

```tsx
        <div className="flex flex-col gap-1.5 rounded-[6px] border border-rule bg-surface px-5 py-4">
          <span className="num wdth-expanded text-[40px] font-extrabold leading-none">{games.length}</span>
          <span className="text-sm text-muted">games on the slate</span>
        </div>
        <div className="flex flex-col gap-1.5 rounded-[6px] border border-rule bg-surface px-5 py-4">
          <span className="num wdth-expanded text-[40px] font-extrabold leading-none">
            {statRows.length ? `${flipCount} of ${statRows.length}` : "–"}
          </span>
          <span className="text-sm text-muted">games where the model picks a different favourite</span>
        </div>
        <div className="flex flex-col gap-1.5 rounded-[6px] border border-rule bg-surface px-5 py-4">
          <span className="num wdth-expanded text-[40px] font-extrabold leading-none">{biggest ? `${(biggest.gap * 100).toFixed(1)} pts` : "–"}</span>
          <span className="text-sm text-muted">largest model–market gap{biggest ? `: ${biggest.g.awayTeamId} at ${biggest.g.homeTeamId}` : ""}</span>
        </div>
```

with

```tsx
        <StatTile value={games.length} label="games on the slate" />
        <StatTile value={statRows.length ? `${flipCount} of ${statRows.length}` : "–"} label="games where the model picks a different favourite" />
        <StatTile
          value={biggest ? `${(biggest.gap * 100).toFixed(1)} pts` : "–"}
          label={`largest model–market gap${biggest ? `: ${biggest.g.awayTeamId} at ${biggest.g.homeTeamId}` : ""}`}
        />
```

- [ ] **Step 5: Evidence.** Replace `web/src/app/evidence/page.tsx` with (same data and copy: headline and protocol lead, three stat tiles, window chips, skill and reliability charts in cards, gates table, CLV chips and histogram, controls and reproducibility side by side on wide screens, the ledger):

```tsx
import Link from "next/link";
import { ClvHistogram } from "@/components/charts/ClvHistogram";
import { ReliabilityGrid } from "@/components/charts/ReliabilityGrid";
import { SkillIntervals } from "@/components/charts/SkillIntervals";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, chipClass, PageTitle, SectionTitle, StatTile } from "@/components/ui";
import { evidence, ledger } from "@/lib/data/queries";
import { bps, shortSha, signedPct, utcStamp } from "@/lib/format";
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
      <>
        <PageTitle>Evidence</PageTitle>
        <div className="mt-6">
          <DataUnavailable title="No backtest ingested">A backtest bundle appears here after ingest.</DataUnavailable>
        </div>
      </>
    );
  }

  const pooled = ev.metrics.filter((m) => m.split === split && m.phase === "pooled");
  const market = pooled.find((m) => m.candidate === "C0");
  const confirm = ev.metrics.filter((m) => m.split === "confirm" && m.phase === "pooled" && m.candidate !== "C0");
  const best = [...confirm].sort((a, b) => b.skill - a.skill)[0];
  const passing = ev.gates.filter((g) => g.brierStatus.startsWith("passes"));
  const clvSummary = (ev.bt.clvSummary ?? {}) as Record<string, ClvAgg | { venue: string; tau: number }>;
  const clvCands = [...new Set(ev.clv.map((c) => c.candidate))];
  const clvCand = sp.clv && clvCands.includes(sp.clv) ? sp.clv : clvCands.includes("C2") ? "C2" : clvCands[0];
  const clvAgg = clvCand ? (clvSummary[clvCand] as ClvAgg | undefined) : undefined;
  const controls = ev.bt.controls as Record<string, { passed?: boolean } & Record<string, unknown>>;
  const folds = (ev.window?.folds ?? {}) as Record<string, { seasons: number[] | string; use: string; sealed?: boolean }>;
  const q = (s: Split, c?: string) => `/evidence?split=${s}${c ? `&clv=${encodeURIComponent(c)}` : ""}`;

  return (
    <>
      <PageTitle
        lead={
          <>
            <p className="text-ink">
              {passing.length
                ? `${passing.map((g) => candidateLabel(g.candidate)).join(", ")} passed the Confirm-stage gates; the sealed 2025 holdout is still pending.`
                : "No model or blend beat the no-vig closing market in the pre-registered test."}
            </p>
            <p className="mt-2">
              Protocol <code className="text-sm">{ev.window?.windowId}</code> was frozen and pushed before any Confirm-window
              scoring, and every candidate was refit walk-forward, week by week, on data available before kickoff.{" "}
              <Link href="/methodology">How it works</Link>
            </p>
          </>
        }
      >
        Evidence
      </PageTitle>

      <section aria-label="The test in numbers" className="mt-7 grid gap-4 sm:grid-cols-3">
        <StatTile value={confirm[0]?.n ?? "–"} label="Confirm games scored" />
        <StatTile
          value={ev.metrics.find((m) => m.split === "confirm" && m.phase === "pooled" && m.candidate === "C0")?.brier.toFixed(4) ?? "–"}
          label="Market Brier score (lower is better)"
        />
        <StatTile
          value={best ? signedPct(best.skill) : "–"}
          label={best ? `Closest candidate, skill vs market: ${candidateLabel(best.candidate)}; 95% interval ${signedPct(best.skillLo)} to ${signedPct(best.skillHi)}` : "Closest candidate, skill vs market"}
        />
      </section>

      <nav className="mt-7 flex flex-wrap items-center gap-1.5 border-y border-rule py-4" aria-label="Window">
        <span className="mr-1 text-[13px] text-muted">Window</span>
        {(["confirm", "tune"] as Split[]).map((s) => (
          <Link key={s} href={q(s, clvCand)} aria-current={s === split ? "true" : undefined} className={chipClass(s === split)}>
            {SPLIT_LABEL[s]}
          </Link>
        ))}
      </nav>

      <section className="mt-7" aria-labelledby="skill">
        <h2 id="skill" className="sr-only">Brier skill</h2>
        <Card>
          <SkillIntervals splitLabel={SPLIT_LABEL[split]} rows={pooled} />
          {market ? (
            <p className="mt-2 text-sm text-muted">
              Market Brier {market.brier.toFixed(4)} on {market.n} games. Skill = 1 − Brier(candidate) / Brier(market);
              intervals from a paired week-block bootstrap (10,000 resamples).
            </p>
          ) : null}
        </Card>
      </section>

      <section className="mt-8" aria-labelledby="rel">
        <h2 id="rel" className="sr-only">Reliability</h2>
        <Card>
          <ReliabilityGrid
            splitLabel={SPLIT_LABEL[split]}
            bins={ev.bins.filter((b) => b.split === split)}
            ece={Object.fromEntries(pooled.map((m) => [m.candidate, m.ece]))}
          />
        </Card>
      </section>

      <section className="mt-10" aria-labelledby="gates">
        <SectionTitle id="gates">Promotion gates, Confirm stage</SectionTitle>
        <p className="mt-2 max-w-3xl text-sm text-ink-2">
          G1: skill interval above zero. G2: Diebold–Mariano beats the market after Benjamini–Hochberg. G3: calibration
          slope interval contains 1 and ECE within 0.005 of the market. G4: every control passed. G1 and G2 must also hold
          on the sealed 2025 holdout.
        </p>
        <Card className="mt-3">
          <div tabIndex={0} role="region" aria-label="Scrollable table" className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-left text-sm">
              <thead className="text-ink-2">
                <tr>
                  <th className="py-1 pr-4 font-normal">Candidate</th>
                  {["G1", "G2", "G3", "G4"].map((g) => <th key={g} className="pr-4 font-normal">{g}</th>)}
                  <th className="pr-4 font-normal">Brier status</th>
                  <th className="font-normal">Betting value</th>
                </tr>
              </thead>
              <tbody>
                {ev.gates.map((g) => (
                  <tr key={g.candidate} className="border-t border-rule">
                    <td className="py-1.5 pr-4">{candidateLabel(g.candidate)}</td>
                    {[g.g1, g.g2, g.g3, g.g4].map((v, i) => (
                      <td key={i} className="pr-4"><StatusBadge status={v ? "passes" : "failed"} label={v ? "Pass" : "Fail"} /></td>
                    ))}
                    <td className="pr-4"><StatusBadge status={g.brierStatus} /></td>
                    <td className="text-ink-2">{g.bettingValueStatus}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </section>

      <section className="mt-10" aria-labelledby="clv">
        <SectionTitle id="clv">Closing-line value at the opener</SectionTitle>
        <nav className="mt-3 flex flex-wrap items-center gap-1.5" aria-label="CLV candidate">
          <span className="mr-1 text-[13px] text-muted">Candidate</span>
          {clvCands.map((c) => (
            <Link key={c} href={q(split, c)} aria-current={c === clvCand ? "true" : undefined} className={chipClass(c === clvCand)}>
              {candidateLabel(c)}
            </Link>
          ))}
        </nav>
        <Card className="mt-3">
          {clvCand ? (
            <ClvHistogram
              candidate={clvCand}
              values={ev.clv.filter((c) => c.candidate === clvCand).map((c) => c.clvBps)}
              meanCi={clvAgg ? { mean: clvAgg.mean_clv_bps, lo: clvAgg.clv_ci[0], hi: clvAgg.clv_ci[1] } : null}
              roi={clvAgg?.roi ?? null}
            />
          ) : null}
          <p className="mt-2 max-w-3xl text-sm text-muted">
            Pick rule: the side where the model beats the ESPN BET no-vig opener by 3 points or more. CLV = 10,000 × (close −
            open), both no-vig at the same venue. Four candidates were examined and the intervals are not corrected for that.
            {clvAgg ? ` ${candidateLabel(clvCand!)}: ${clvAgg.n} picks, mean ${bps(clvAgg.mean_clv_bps)}.` : ""}
          </p>
        </Card>
      </section>

      <div className="mt-10 grid gap-8 lg:grid-cols-2">
        <section aria-labelledby="controls">
          <SectionTitle id="controls">Controls</SectionTitle>
          <Card className="mt-3">
            <p className="text-sm text-ink-2">Any failed control voids the run. Run status: <StatusBadge status={ev.bt.status} /></p>
            <ul className="mt-3 divide-y divide-rule text-sm">
              {Object.entries(controls)
                .filter(([, v]) => v && typeof v === "object" && "passed" in v)
                .map(([k, v]) => (
                  <li key={k} className="flex items-center justify-between py-2">
                    <span>{k.replace(/_/g, " ")}</span>
                    <StatusBadge status={v.passed ? "passes" : "failed"} label={v.passed ? "Passed" : "Failed"} />
                  </li>
                ))}
            </ul>
          </Card>
        </section>

        <section aria-labelledby="repro">
          <SectionTitle id="repro">Protocol and reproducibility</SectionTitle>
          <Card className="mt-3">
            <dl className="num grid grid-cols-1 gap-x-8 gap-y-2 text-sm sm:grid-cols-[max-content_1fr]">
              <dt className="text-ink-2">Protocol sha256</dt><dd className="break-all">{ev.window?.protocolSha256}</dd>
              <dt className="text-ink-2">Frozen</dt><dd>{utcStamp(ev.window?.frozenAtUtc)}</dd>
              <dt className="text-ink-2">Result sha256</dt><dd className="break-all">{ev.bt.resultSha256}</dd>
              <dt className="text-ink-2">Code</dt><dd>{shortSha(ev.bt.codeGitSha)}</dd>
              <dt className="text-ink-2">Scored</dt><dd>{utcStamp(ev.bt.generatedUtc)}</dd>
            </dl>
            <ul className="mt-4 divide-y divide-rule border-t border-rule text-sm">
              {Object.entries(folds).map(([name, f]) => (
                <li key={name} className="flex flex-wrap items-center justify-between gap-2 py-2">
                  <span>
                    <span className="capitalize">{name.replace("_", "-")}</span>{" "}
                    <span className="num text-ink-2">{Array.isArray(f.seasons) ? `${f.seasons[0]}–${f.seasons[f.seasons.length - 1]}` : f.seasons}</span>
                  </span>
                  <span className="text-ink-2">{f.sealed ? <StatusBadge status="pending" label="Sealed" /> : f.use}</span>
                </li>
              ))}
            </ul>
          </Card>
        </section>
      </div>

      <section className="mt-10" aria-labelledby="ledger">
        <SectionTitle id="ledger">Evidence ledger</SectionTitle>
        <p className="mt-2 text-sm text-ink-2">Every quantitative claim about the model, including withdrawn ones and negative results.</p>
        <Card className="mt-3">
          <div tabIndex={0} role="region" aria-label="Scrollable table" className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-left text-sm">
              <thead className="text-ink-2">
                <tr><th className="py-1 pr-4 font-normal">Claim</th><th className="pr-4 font-normal">Status</th><th className="font-normal">Reason</th></tr>
              </thead>
              <tbody>
                {claims.map((c) => (
                  <tr key={c.claimId} className="border-t border-rule align-top">
                    <td className="py-2 pr-4">{c.claim}</td>
                    <td className="py-2 pr-4"><StatusBadge status={c.status} /></td>
                    <td className="py-2 text-ink-2">{c.reason}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </section>
    </>
  );
}
```

- [ ] **Step 6: Methodology.** Replace `web/src/app/methodology/page.tsx` with:

```tsx
import Link from "next/link";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, PageTitle, SectionTitle } from "@/components/ui";
import { evidence, ledger, pointerRun } from "@/lib/data/queries";
import { shortSha } from "@/lib/format";
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
    <article className="max-w-[880px]">
      <PageTitle lead="This page is generated from the published runs and the evidence ledger, so it cannot drift from what the numbers were computed with.">
        Methodology
      </PageTitle>

      <section className="mt-10" aria-labelledby="benchmark">
        <SectionTitle id="benchmark">The benchmark</SectionTitle>
        <Card className="mt-3">
          <p>
            The market probability is the closing moneyline with the bookmaker margin removed proportionally:
            p = q<sub>home</sub> / (q<sub>home</sub> + q<sub>away</sub>). {cfg.market_source ? `Source: ${cfg.market_source}.` : null}
          </p>
        </Card>
      </section>

      <section className="mt-10" aria-labelledby="candidates">
        <SectionTitle id="candidates">Registered candidates</SectionTitle>
        <Card className="mt-3">
          <ul className="space-y-3">
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
          <p className="mt-4 border-t border-rule pt-3 text-sm text-ink-2">
            The Monte Carlo score simulator ({candidateLabel("C3")}) joins as its own candidate in the next protocol version, once
            its features are point-in-time. Until then a simulator run is research output: its line is the simulator&apos;s two-way
            home win probability after its market blend.
          </p>
        </Card>
      </section>

      <section className="mt-10" aria-labelledby="judged">
        <SectionTitle id="judged">How candidates are judged</SectionTitle>
        <Card className="mt-3">
          <ul className="list-disc space-y-2 pl-5">
            <li>Walk-forward by NFL week: every fit uses only games that kicked off before that week, and a guard rejects any input that finished after kickoff.</li>
            <li>Tune on 2018–22, confirm on 2023–24, then score the sealed 2025 holdout once. The protocol file is hashed and committed before scoring.</li>
            <li>Brier skill against the market with paired week-block bootstrap intervals, Diebold–Mariano tests with Benjamini–Hochberg correction, calibration slope and ECE.</li>
            <li>Controls void a run: a leak canary, shuffled labels, a market copy that must score exactly zero, and a second process that must reproduce the result hash.</li>
            <li>Betting value is judged on closing-line value at decision-time prices, with at least 400 picks in a single look.</li>
          </ul>
          {ev?.window ? (
            <p className="mt-4 border-t border-rule pt-3 text-sm text-ink-2">
              Current protocol <code>{ev.window.windowId}</code>, sha256 {shortSha(ev.window.protocolSha256, 12)}; result{" "}
              {shortSha(ev.bt.resultSha256, 12)}. <Link href="/evidence">Results</Link>
            </p>
          ) : null}
        </Card>
      </section>

      <section className="mt-10" aria-labelledby="public">
        <SectionTitle id="public">What is shown publicly</SectionTitle>
        <Card className="mt-3">
          <p>
            A candidate that passed its gates is shown as validated. Until one does, the fields carry one research line,
            labelled unvalidated wherever it appears: the {candidateLabel("E1")} when the published run has it, otherwise the
            game simulator. There are no public picks. Stakes are never public; the private desk tracks paper leans only
            {cfg.paper_edge ? ` (edge of ${cfg.paper_edge * 100} points or more)` : ""}.
          </p>
        </Card>
      </section>

      <section className="mt-10" aria-labelledby="claims">
        <SectionTitle id="claims">Claims ledger</SectionTitle>
        <Card className="mt-3">
          <ul className="flex flex-wrap gap-x-6 gap-y-1">
            {Object.entries(counts).map(([status, n]) => (
              <li key={status}><StatusBadge status={status} label={`${n} ${status}`} /></li>
            ))}
          </ul>
        </Card>
      </section>
    </article>
  );
}
```

- [ ] **Step 7: Data health.** Replace `web/src/app/data-health/page.tsx` with:

```tsx
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, PageTitle, SectionTitle } from "@/components/ui";
import { dataHealth } from "@/lib/data/queries";
import { age, shortSha, utcStamp } from "@/lib/format";

export const dynamic = "force-dynamic";
export const metadata = { title: "Data health" };

export default async function DataHealthPage() {
  const { run, sources, ingests, runs } = await dataHealth();
  return (
    <>
      <PageTitle
        lead={
          run ? (
            <p>
              Published weekly run generated {utcStamp(run.generatedUtc)} from code {shortSha(run.codeGitSha)}
              {run.codeDirty ? " (uncommitted changes)" : ""}. QA:{" "}
              <StatusBadge status={run.qaOk ? "ok" : "qa_failed"} label={run.qaOk ? "Passed" : "Failed"} />
            </p>
          ) : null
        }
      >
        Data health
      </PageTitle>
      {run ? null : (
        <div className="mt-6">
          <DataUnavailable title="No published weekly run">Nothing ingested yet.</DataUnavailable>
        </div>
      )}

      <section className="mt-10" aria-labelledby="sources">
        <SectionTitle id="sources">Sources for this run</SectionTitle>
        <Card className="mt-3">
          <div tabIndex={0} role="region" aria-label="Scrollable table" className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-left text-sm">
              <thead className="text-ink-2">
                <tr>
                  <th className="py-1 pr-4 font-normal">Source</th>
                  <th className="pr-4 font-normal">Status</th>
                  <th className="pr-4 font-normal">Last success</th>
                  <th className="font-normal">Detail</th>
                </tr>
              </thead>
              <tbody>
                {sources.map((s) => (
                  <tr key={s.source} className="border-t border-rule align-top">
                    <td className="py-2 pr-4">{s.source.replace(/_/g, " ")}</td>
                    <td className="py-2 pr-4"><StatusBadge status={s.status} /></td>
                    <td className="num py-2 pr-4">{s.lastSuccessUtc ? `${utcStamp(s.lastSuccessUtc)} (${age(s.lastSuccessUtc)})` : "–"}</td>
                    <td className="py-2 text-ink-2">{s.detail}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </section>

      <div className="mt-10 grid gap-8 lg:grid-cols-2">
        <section aria-labelledby="runs">
          <SectionTitle id="runs">Recent runs</SectionTitle>
          <Card className="mt-3">
            <ul className="divide-y divide-rule text-sm">
              {runs.map((r) => {
                const failures = r.qaFailures as string[];
                return (
                  <li key={r.runId} className="py-2 first:pt-0 last:pb-0">
                    <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
                      <span className="font-medium">{r.modelLabel}</span>
                      <StatusBadge status={r.status} />
                    </div>
                    <p className="num mt-1 text-ink-2">
                      {r.kind} · data as of {utcStamp(r.dataAsofUtc)} · QA failures: {failures.length ? failures.join("; ") : "none"}
                    </p>
                  </li>
                );
              })}
            </ul>
          </Card>
        </section>

        <section aria-labelledby="ingests">
          <SectionTitle id="ingests">Ingest log</SectionTitle>
          <Card className="mt-3">
            <ul className="num divide-y divide-rule text-sm">
              {ingests.map((i) => (
                <li key={i.bundleSha256} className="flex flex-wrap items-center justify-between gap-2 py-2 first:pt-0 last:pb-0">
                  <span>{i.cycleId}</span>
                  <span className="text-ink-2">bundle {shortSha(i.bundleSha256, 12)}</span>
                  <StatusBadge status={i.status} />
                </li>
              ))}
            </ul>
          </Card>
        </section>
      </div>

      <section className="mt-10" aria-labelledby="unmatched">
        <SectionTitle id="unmatched">Unmatched entities</SectionTitle>
        <div className="mt-3">
          <DataUnavailable title="Not tracked yet">
            The unmatched-entity queue (players and teams a provider names that the ID tables cannot resolve) arrives with
            the odds layer in Phase 2. Until then joins use nflverse IDs only.
          </DataUnavailable>
        </div>
      </section>
    </>
  );
}
```

- [ ] **Step 8: Props.** Replace `web/src/app/props/page.tsx` with:

```tsx
import Link from "next/link";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, PageTitle } from "@/components/ui";

export const metadata = { title: "Props" };

const MARKETS = [
  { group: "Touchdowns", items: ["Anytime", "First", "Two or more"] },
  { group: "Yardage", items: ["Passing yards", "Rushing yards", "Receiving yards"] },
  { group: "Counts", items: ["Receptions", "Completions", "Pass attempts", "Passing TDs", "Interceptions"] }
];

export default function PropsPage() {
  return (
    <>
      <PageTitle
        lead={
          <span className="flex flex-wrap items-center gap-2">
            <StatusBadge status="unvalidated" label="Props model unvalidated" />
            <span>No prop is priced here until its market passes a pre-registered backtest.</span>
          </span>
        }
      >
        Player props
      </PageTitle>

      <div className="mt-8 grid gap-5 sm:grid-cols-3">
        {MARKETS.map((m) => (
          <Card key={m.group}>
            <section aria-labelledby={`m-${m.group}`}>
              <h2 id={`m-${m.group}`} className="font-bold">{m.group}</h2>
              <ul className="mt-3 text-sm">
                {m.items.map((i) => (
                  <li key={i} className="flex items-center justify-between gap-3 border-t border-rule py-2">
                    <span>{i}</span>
                    <StatusBadge status="unvalidated" label="Not priced" />
                  </li>
                ))}
              </ul>
            </section>
          </Card>
        ))}
      </div>

      <div className="mt-8">
        <DataUnavailable title="Why this page is empty">
          <p>
            The props engine has known defects that change every row (audit P1–P13): labels are column-wide, recommendation
            and stake disagree, and anytime-TD prices never reach the output. Phase 4 fixes them and rebuilds the model
            (usage shares, a touchdown engine), and Phase 5 backtests each market separately.
          </p>
          <p className="mt-2">
            A market is backtested only with at least 300 settled player-games that had a pre-kickoff price; below that it
            is tracked prospectively and labelled that way. What counts as a pre-kickoff price (checkpoint A5) is still an
            owner decision. See <Link href="/methodology">Methodology</Link>.
          </p>
        </DataUnavailable>
      </div>
    </>
  );
}
```

- [ ] **Step 9: Login.** Replace `web/src/app/login/page.tsx` with:

```tsx
import { BUTTON_CLASS, Card, INPUT_CLASS, PageTitle } from "@/components/ui";
import { login } from "./actions";

export const metadata = { title: "Sign in", robots: { index: false } };

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  return (
    <div className="mx-auto max-w-md">
      <PageTitle compact lead="The desk is private. Public pages never show stakes.">
        Sign in to the desk
      </PageTitle>
      <Card className="mt-6">
        {error ? (
          <p role="alert" className="mb-4 text-crit">That email and password did not match, or sign-in is paused after repeated attempts.</p>
        ) : null}
        <form action={login} className="space-y-4">
          <label className="block">
            <span className="text-sm text-ink-2">Email</span>
            <input name="email" type="email" autoComplete="username" required className={INPUT_CLASS} />
          </label>
          <label className="block">
            <span className="text-sm text-ink-2">Password</span>
            <input name="password" type="password" autoComplete="current-password" required className={INPUT_CLASS} />
          </label>
          <button type="submit" className={BUTTON_CLASS}>Sign in</button>
        </form>
      </Card>
    </div>
  );
}
```

- [ ] **Step 10: Desk.** Replace `web/src/app/desk/page.tsx` with (stakes stay in the private desk table, with `data-desk="recommendations"` and `data-stake` unchanged for `e2e/desk-auth.spec.ts`):

```tsx
import { redirect } from "next/navigation";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, PageTitle, QUIET_BUTTON_CLASS, SectionTitle } from "@/components/ui";
import { signOut } from "@/lib/auth";
import { requireUser } from "@/lib/auth/requireUser";
import { deskSlate } from "@/lib/data/queries";
import { pct, pts } from "@/lib/format";
import { candidateLabel } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = { title: "Desk", robots: { index: false } };

const DESK_MODEL = "C2";

export default async function DeskPage() {
  const user = await requireUser();
  if (!user) redirect("/login");
  const { run, games, lines, recs } = await deskSlate();
  // in kickoff order, like the board below
  const order = new Map(games.map((g, i) => [g.gameId, i]));
  const leans = recs
    .filter((r) => r.tier !== "pass")
    .sort((a, b) => (order.get(a.gameId) ?? 0) - (order.get(b.gameId) ?? 0));

  return (
    <>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <PageTitle
          lead={
            <span className="flex flex-wrap items-center gap-2">
              <StatusBadge status="unvalidated" label="Paper only" />
              Every candidate here failed to beat the closing market (nfl_games_v1). Leans are tracked on paper to test the
              prospective closing-line-value hypothesis; stakes are zero.
            </span>
          }
        >
          Desk
        </PageTitle>
        <form action={async () => { "use server"; await signOut({ redirectTo: "/" }); }} className="flex items-center gap-3">
          <span className="text-sm text-ink-2">{user.email}</span>
          <button type="submit" className={QUIET_BUTTON_CLASS}>Sign out</button>
        </form>
      </div>

      {run ? (
        <>
          <section className="mt-10" aria-labelledby="leans">
            <SectionTitle id="leans">Paper leans, {candidateLabel(DESK_MODEL)} vs market</SectionTitle>
            <Card className="mt-3">
              <div tabIndex={0} role="region" aria-label="Scrollable table" className="overflow-x-auto">
                <table className="num w-full min-w-[720px] text-left text-sm" data-desk="recommendations">
                  <thead className="text-ink-2">
                    <tr><th className="py-1 pr-4 font-normal">Game</th><th className="pr-4 font-normal">Side</th><th className="pr-4 font-normal">Model</th><th className="pr-4 font-normal">Market</th><th className="pr-4 font-normal">Edge</th><th className="pr-4 font-normal">Price</th><th className="pr-4 font-normal">Stake</th><th className="font-normal">Note</th></tr>
                  </thead>
                  <tbody>
                    {leans.map((r) => {
                      const g = games.find((x) => x.gameId === r.gameId);
                      const team = r.side === "home" ? g?.homeTeamId : g?.awayTeamId;
                      return (
                        <tr key={r.recId} className="border-t border-rule align-top">
                          <td className="whitespace-nowrap py-2 pr-4">{g ? `${g.awayTeamId} at ${g.homeTeamId}` : r.gameId}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{team}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{pct(r.pModel, 1)}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{pct(r.pMktNovig, 1)}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{r.pMktNovig !== null ? pts(r.pModel - r.pMktNovig) : "–"}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{r.priceAmerican !== null ? (r.priceAmerican > 0 ? `+${r.priceAmerican}` : r.priceAmerican) : "–"}</td>
                          <td className="whitespace-nowrap py-2 pr-4" data-stake>{pct(r.stakePct, 1)}</td>
                          <td className="py-2 text-ink-2">{r.passReason}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </Card>
          </section>

          <section className="mt-10" aria-labelledby="board">
            <SectionTitle id="board">Board</SectionTitle>
            <div className="mt-3"><FieldKey showModel modelLabel={candidateLabel(DESK_MODEL)} validated={false} /></div>
            <div className="mt-3 grid gap-5 lg:grid-cols-2">
              {games.map((g) => {
                const l = lines.find((x) => x.gameId === g.gameId && x.candidate === DESK_MODEL && x.p !== null);
                return (
                  <Field key={g.gameId} gameId={g.gameId} awayId={g.awayTeamId} homeId={g.homeTeamId} awayName={g.awayName}
                    homeName={g.homeName} kickoffUtc={g.kickoffUtc} neutral={g.neutral} pMarket={g.pMarket}
                    model={l ? { p: l.p as number, label: candidateLabel(DESK_MODEL), validated: false } : null} />
                );
              })}
            </div>
          </section>
        </>
      ) : null}
    </>
  );
}
```

- [ ] **Step 11: Not found.** Replace `web/src/app/not-found.tsx` with:

```tsx
import Link from "next/link";
import { PageTitle } from "@/components/ui";

export default function NotFound() {
  return (
    <div className="max-w-xl">
      <PageTitle compact lead={<>That page or game is not in the published data. <Link href="/">Back to this week</Link></>}>
        Not found
      </PageTitle>
    </div>
  );
}
```

- [ ] **Step 12: The review tool picks any game.** In `web/scripts/review-ui.mjs` replace

```js
const PAGES = ["/", "/evidence", "/methodology", "/data-health", "/props", "/games/2026_04_DEN_SF", "/login"];
```

with

```js
// GAME picks the game page (a simulator run's game ids differ from the fixture's)
const GAME = process.env.GAME ?? "2026_04_DEN_SF";
const PAGES = ["/", "/evidence", "/methodology", "/data-health", "/props", `/games/${GAME}`, "/login"];
```

  In `web/README.md` replace

```markdown
`scripts/review-ui.mjs` takes full-page screenshots at 390, 768 and 1440 px in both themes and prints overflow, console and axe results for a visual review.
```

with

```markdown
`scripts/review-ui.mjs` takes full-page screenshots at 390, 768 and 1440 px in both themes and prints overflow, console and axe results for a visual review (`GAME=<game_id>` picks the game page; default `2026_04_DEN_SF` from the fixture).
```

- [ ] **Step 13: Run the test and watch it pass.** `cd web && npx vitest run src/test/designLanguage.test.ts` → `Tests  3 passed (3)`.

- [ ] **Step 14: Full gates.** Web: `npm run typecheck && npm run lint && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run` → exit 0 (slop scan and docs truth pass). R: `Rscript scripts/run_tests.R`, `Rscript scripts/verify_repo_integrity.R` → exit 0 (62/62). Screenshots, axe and overflow at 390/768/1440 in both themes run in Task 10.

- [ ] **Step 15: Commit.**

```bash
git add web/src/components/ui.tsx web/src/test/designLanguage.test.ts web/src/app/page.tsx web/src/app/evidence/page.tsx web/src/app/methodology/page.tsx web/src/app/data-health/page.tsx web/src/app/props/page.tsx web/src/app/login/page.tsx web/src/app/desk/page.tsx web/src/app/not-found.tsx web/scripts/review-ui.mjs web/README.md
git commit -F- <<'EOF'
feat(web): carry the Broadcast Line design to evidence, methodology, data health, props, login, desk and not-found (A8)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 7: Retire the legacy HTML report

**Files:**
- Delete: `R/report_banner.R`, `tests/testthat/test-html-report-alignment.R`, `tests/testthat/test-moneyline-report-schema.R`, `tests/testthat/test-report-banner.R`
- Modify: `NFLmarket.R` (10 cuts, 2,215 lines out, 6 in), `NFLsimulation.R` (9 cuts, 1,058 lines out, 13 in), `run_week.R` (whole file), `scripts/verify_repo_integrity.R:454,463`, `scripts/audit_verify.sh:9-18`, `tests/testthat/test-report-audit-guards.R` (whole file), `tests/testthat/test-bet-governance.R` (append), `tests/testthat/test-run-week-outputs.R` (whole file)
- Create: `tests/testthat/test-report-retired.R`

**Interfaces:**
- Consumes: `nflmarket_env()` (`tests/testthat/helper-nflmarket.R`), `.test_project_root` (`tests/testthat/setup.R`), Task 3's `run_week.R` bundle step.
- Produces: no new functions. Removed for good: `export_moneyline_comparison_html`, `open_moneyline_report`, `moneyline_report`, `validate_moneyline_report_schema`, `moneyline_report_schema_contract`, `render_model_status_banner`, `html_escape_cell`, `evaluate_market_vs_blend()`'s `html_output_path`/`html_vig`/`html_title`, and in `NFLsimulation.R` the fallback exporter, `xfun_meets_min`, `has_namespace`, `gt_available`, `reactable_available`, `pal_fav`, `pal_total`, `primary_report_tbl`, the backtest report table and the reactable slate table. Kept: everything in the "Call-graph evidence" section above; `moneyline_report_inputs` (`$comparison`, `$join_keys`) still feeds `artifacts/baseline_games.csv`, now written with or without props.

Owner authority: the A8 decision ("Retire … but remove") authorizes these four file deletions and the two engine-file edits (CLAUDE.md STOP items 1 and 3). Nothing else is deleted.

- [ ] **Step 0: Record the base golden master** (before any change in this task; needs nflverse, about 5 minutes): `Rscript scripts/golden_master.R record 15 2024 <scratch>/gm-before-a8` → `recorded 16 games to <scratch>/gm-before-a8`.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-report-retired.R`:

```r
# =============================================================================
# The legacy HTML report is retired (checkpoint A8; spec §5 Phase 8). Results are
# viewed in the local web app; the computations other code uses are kept.
# =============================================================================

RETIRED_FUNCTIONS <- c("export_moneyline_comparison_html", "open_moneyline_report", "moneyline_report",
                       "validate_moneyline_report_schema", "moneyline_report_schema_contract",
                       "render_model_status_banner", "html_escape_cell")

test_that("no R file defines or calls the retired report functions", {
  files <- c(list.files(.test_project_root, pattern = "\\.R$", full.names = TRUE),
             list.files(file.path(.test_project_root, c("R", "scripts", "tests/testthat", "sports/nfl/props")),
                        pattern = "\\.R$", full.names = TRUE))
  files <- setdiff(normalizePath(files, winslash = "/"),
                   normalizePath(file.path(.test_project_root, "tests/testthat/test-report-retired.R"), winslash = "/"))
  hits <- character()
  for (f in files) {
    names_used <- tryCatch(all.names(parse(f, keep.source = FALSE)), error = function(e) character())
    found <- intersect(RETIRED_FUNCTIONS, names_used)
    if (length(found)) hits <- c(hits, sprintf("%s: %s", basename(f), paste(found, collapse = ", ")))
  }
  expect_equal(hits, character())
  expect_false(file.exists(file.path(.test_project_root, "R", "report_banner.R")))
})

test_that("NFLmarket.R keeps the comparison computations and drops the HTML hooks", {
  env <- nflmarket_env()
  for (fn in RETIRED_FUNCTIONS) expect_false(exists(fn, envir = env, inherits = FALSE), info = fn)
  expect_true(is.function(env$build_moneyline_comparison_table))
  expect_true(is.function(env$evaluate_market_vs_blend))
  expect_false(any(c("html_output_path", "html_vig", "html_title") %in% names(formals(env$evaluate_market_vs_blend))))
})

test_that("NFLsimulation.R still saves its run logs and exports draws for props, and renders no widget", {
  code <- readLines(file.path(.test_project_root, "NFLsimulation.R"), warn = FALSE, encoding = "UTF-8")
  for (line in c('saveRDS(final, file.path(log_dir, paste0("final_", run_id, ".rds")))',
                 'saveRDS(games_ready, file.path(log_dir, paste0("games_ready_", run_id, ".rds")))',
                 'assign("last_simulation_results", last_simulation_results, envir = .GlobalEnv)',
                 "moneyline_report_inputs <- list(")) {
    expect_true(any(grepl(line, code, fixed = TRUE)), info = line)
  }
  expect_false(any(grepl("reactable|gt_available|pal_fav|pal_total|primary_report_tbl|has_namespace", code)))
})

test_that("every static anchor in scripts/audit_verify.sh (CI) still matches its file", {
  sh <- readLines(file.path(.test_project_root, "scripts", "audit_verify.sh"), warn = FALSE)
  anchors <- regmatches(sh, regexec('^rg -n "(.+)" (\\S+) >/dev/null$', sh))
  anchors <- Filter(length, anchors)
  expect_gte(length(anchors), 3L)
  for (a in anchors) {
    src <- readLines(file.path(.test_project_root, a[[3]]), warn = FALSE, encoding = "UTF-8")
    expect_true(any(grepl(a[[2]], src, perl = TRUE)), info = sprintf("%s in %s", a[[2]], a[[3]]))
  }
})
```

  Replace `tests/testthat/test-run-week-outputs.R` with:

```r
# =============================================================================
# run_week.R outputs (checkpoint A8): a web bundle for the local app and the two
# audit CSVs; no HTML report and no browser. run_week.R runs the whole engine, so
# these checks read its source; the end-to-end run is the close-out demo.
# =============================================================================

run_week_code <- function() {
  src <- readLines(file.path(.test_project_root, "run_week.R"), warn = FALSE, encoding = "UTF-8")
  src[!grepl("^\\s*#", src)]
}

test_that("run_week.R writes the web bundle once, after the simulation, and reports it", {
  code <- run_week_code()
  expect_equal(sum(grepl("write_sim_bundle(", code, fixed = TRUE)), 1L)
  expect_equal(sum(grepl("report_sim_bundle(sim_bundle)", code, fixed = TRUE)), 1L)
  expect_lt(grep('source("NFLsimulation.R")', code, fixed = TRUE), grep("write_sim_bundle(", code, fixed = TRUE))
  # git state is read before the run rewrites the tracked artifacts/*.csv
  expect_lt(grep("run_git <- sb_git_state()", code, fixed = TRUE), grep('source("NFLsimulation.R")', code, fixed = TRUE))
})

test_that("run_week.R makes no HTML report and opens no browser", {
  code <- run_week_code()
  expect_false(any(grepl("export_moneyline_comparison_html|browseURL|NFLvsmarket|baseline_report\\.html|auto_open", code)))
})

test_that("run_week.R still writes both audit CSVs, and the games table no longer depends on props", {
  code <- run_week_code()
  expect_true(any(grepl('"baseline_games.csv"', code, fixed = TRUE)))
  expect_true(any(grepl('"baseline_props.csv"', code, fixed = TRUE)))
  build <- grep("last_comparison_tbl <- build_moneyline_comparison_table(", code, fixed = TRUE)
  expect_length(build, 1L)
  props_block <- grep("if (exists(\"RUN_PLAYER_PROPS\") && isTRUE(RUN_PLAYER_PROPS)) {", code, fixed = TRUE)
  props_end <- grep("^  }$", code)
  props_end <- props_end[props_end > props_block][1]
  expect_gt(build, props_end)
})
```

- [ ] **Step 2: Run them and watch them fail.**
  - Run: `Rscript -e "testthat::test_file('tests/testthat/test-report-retired.R')"` and `Rscript -e "testthat::test_file('tests/testthat/test-run-week-outputs.R')"`
  - Expected: `test-report-retired.R` fails its first three tests (the retired functions are defined and called in `NFLmarket.R`, `NFLsimulation.R`, `run_week.R`; `R/report_banner.R` exists; `evaluate_market_vs_blend` has `html_*` formals; `NFLsimulation.R` still has `reactable|gt_available|…`); its fourth test (audit anchors) passes for now. `test-run-week-outputs.R` fails "makes no HTML report and opens no browser" and "the games table no longer depends on props".

- [ ] **Step 3: Delete the four files** (list first, then remove only these paths):

```bash
ls -l R/report_banner.R tests/testthat/test-html-report-alignment.R tests/testthat/test-moneyline-report-schema.R tests/testthat/test-report-banner.R
git rm R/report_banner.R tests/testthat/test-html-report-alignment.R tests/testthat/test-moneyline-report-schema.R tests/testthat/test-report-banner.R
```

  The one test in them that checks something still alive moves: append to `tests/testthat/test-bet-governance.R`

```r

test_that("config declares paper staking by default", {
  # moved from test-report-banner.R when the HTML report was retired (A8)
  expect_identical(STAKING_MODE, "paper")
})
```

- [ ] **Step 4: Cut the engine files.** Save this tool as `<scratch>/a8_cut.R` (your scratchpad; never committed). Every anchor must match exactly one line and every cut must have its expected length, or it writes nothing:

```r
# A8 removal tool (scratch only; never committed).
#   Rscript --vanilla a8_cut.R <repo_root>
# Each cut deletes from the line equal to `from` (less `before` lines above it) through
# the first line equal to `to` that follows the line equal to `via` (or `from`), plus
# `after` lines; `insert` replaces the deleted lines. Every `from`/`via` must match
# exactly one line and every range must have exactly `n` lines, or nothing is written.
# Files are rewritten as UTF-8 with LF line endings.
`%||%` <- function(a, b) if (is.null(a)) b else a

a8_apply <- function(path, cuts) {
  x <- readLines(path, encoding = "UTF-8", warn = FALSE)
  one <- function(a) {
    i <- which(x == a)
    if (length(i) != 1) stop(sprintf("%s: anchor matches %d lines: %s", path, length(i), a), call. = FALSE)
    i
  }
  plan <- lapply(cuts, function(cut) {
    s <- one(cut$from)
    v <- if (is.null(cut$via)) s else one(cut$via)
    if (v < s) stop(sprintf("%s: via precedes from: %s", path, cut$via), call. = FALSE)
    e <- v
    if (!is.null(cut$to)) {
      rel <- which(x[(v + 1):length(x)] == cut$to)
      if (!length(rel)) stop(sprintf("%s: no '%s' after: %s", path, cut$to, cut$via %||% cut$from), call. = FALSE)
      e <- v + rel[1]
    }
    rng <- (s - (cut$before %||% 0)):(e + (cut$after %||% 0))
    if (length(rng) != cut$n) {
      stop(sprintf("%s: cut at '%s' spans %d lines (%d-%d), expected %d", path, cut$from, length(rng), min(rng), max(rng), cut$n), call. = FALSE)
    }
    list(rng = rng, insert = cut$insert %||% character())
  })
  plan <- plan[order(vapply(plan, function(p) min(p$rng), numeric(1)), decreasing = TRUE)]
  starts <- vapply(plan, function(p) min(p$rng), numeric(1))
  ends <- vapply(plan, function(p) max(p$rng), numeric(1))
  if (length(plan) > 1 && any(ends[-1] >= starts[-length(starts)])) stop(path, ": cuts overlap", call. = FALSE)
  for (p in plan) x <- append(x[-p$rng], p$insert, after = min(p$rng) - 1)
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(enc2utf8(x), con, sep = "\n", useBytes = TRUE)
  cat(sprintf("%s: %d cuts, %d lines removed, %d inserted\n", basename(path), length(plan),
              sum(vapply(plan, function(p) length(p$rng), numeric(1))),
              sum(vapply(plan, function(p) length(p$insert), numeric(1)))))
}

root <- commandArgs(trailingOnly = TRUE)[1]
stopifnot(!is.na(root), dir.exists(root))

a8_apply(file.path(root, "NFLmarket.R"), list(
  # header comment: the file no longer renders HTML
  list(from = "#          Handles market data integration, probability shrinkage, Kelly staking,",
       to = "#          and HTML report generation for moneyline comparison.", n = 2,
       insert = c("#          Handles market data integration, probability shrinkage and Kelly staking.",
                  "#          The HTML report was retired at checkpoint A8: run_week.R writes a web",
                  "#          bundle (R/sim_bundle.R) that the local app serves (cd web && npm run local).")),
  list(from = "#   - gt (>= 0.8.0): HTML table generation", n = 1),
  list(from = "#   - render_moneyline_comparison_html(): HTML report generation", n = 1),
  list(from = "#   - EV uses shrunk probabilities (lines 2863-2870)", n = 1,
       insert = "#   - EV uses shrunk probabilities (build_moneyline_comparison_table)"),
  # sourcing R/report_banner.R (deleted in this task): 44-46 at 4f9aad3
  list(from = "    banner_path <- if (file.exists(\"R/report_banner.R\")) \"R/report_banner.R\" else file.path(getwd(), \"R/report_banner.R\")",
       to = "    source(banner_path)", n = 3),
  # evaluate_market_vs_blend's three html_* parameters (1570-1572) and its HTML branch (1596-1616)
  list(from = "                                     html_output_path = NULL,",
       to = "                                     html_title = \"Blend vs Market Moneylines\",", n = 3),
  list(from = "  if (!is.null(html_output_path)) {", to = "  }", after = 1, n = 21),
  # build_moneyline_comparison_table's roxygen: it feeds artifacts/baseline_games.csv now
  list(from = "#' Edge quality classification (shown in HTML report):", n = 1,
       insert = "#' Edge quality classification (a column of artifacts/baseline_games.csv):"),
  list(from = "#' @seealso \\code{\\link{render_moneyline_comparison_html}}, \\code{\\link{compare_to_market}}", n = 1,
       insert = "#' @seealso \\code{\\link{compare_to_market}}"),
  # schema contract, validator, exporter, open_moneyline_report, moneyline_report: 2683-4863
  list(from = "moneyline_report_schema_contract <- function() {",
       via = "moneyline_report <- function(market_comparison_result,", to = "}", before = 2, after = 1, n = 2181)
))

a8_apply(file.path(root, "NFLsimulation.R"), list(
  # the dead fallback copy of the exporter (NFLmarket.R always defines it first): 1368-2131
  list(from = "if (!exists(\"export_moneyline_comparison_html\", inherits = FALSE)) {", to = "  open_", after = 3, n = 764),
  # gt/reactable availability and has_namespace(), used only by the widget: 2286-2314
  list(from = "xfun_meets_min <- tryCatch({", via = "if (!reactable_available) {", to = "}", after = 1, n = 29),
  # reactable cell palettes: 2363-2373
  list(from = "# --- Color palettes for cell backgrounds ---", via = "pal_total <- function(total) {", to = "}", after = 1, n = 11),
  # the report-preview comment and primary_report_tbl: 8155-8159
  list(from = "# Prepare snapshot for the current slate's moneyline report before kicking off",
       to = "primary_report_tbl <- NULL", n = 5,
       insert = c("# Current-slate comparison inputs for run_week.R's artifacts/baseline_games.csv,",
                  "# prepared before any backtesting so they use the probabilities the simulation",
                  "# just produced.",
                  "moneyline_report_inputs <- NULL")),
  # primary_report_tbl fed only the removed preview messages: 8190
  list(from = "    primary_report_tbl <- preview_tbl", n = 1),
  # the backtest report table, its schedule reload and the preview messages: 8252-8326
  list(from = "# Only initialize if not already set by upcoming snapshot (preserves current-week data)",
       via = "# HTML rendering authority is centralized in NFLmarket.R::moneyline_report().", to = "}", n = 75,
       insert = c("# Without a current-week snapshot, run_week.R's baseline_games.csv falls back to the",
                  "# blended backtest comparison (the retired report's fallback, now logged).",
                  "if (is.null(moneyline_report_inputs) && exists(\"cmp_blend\") && !is.null(cmp_blend)) {",
                  "  message(\"No current-week moneyline snapshot; baseline_games.csv will hold the blended backtest comparison.\")",
                  "  moneyline_report_inputs <- list(",
                  "    comparison = cmp_blend,",
                  "    join_keys = if (exists(\"PREDICTION_JOIN_KEYS\", inherits = TRUE)) PREDICTION_JOIN_KEYS else c(\"game_id\", \"season\", \"week\")",
                  "  )",
                  "}")),
  # the reactable slate table, part 1 (pretty_df, rt_df): 8328-8391
  list(from = "# ============================== INTERACTIVE SLATE TABLE (reactable) =============================",
       via = "rt_df <- pretty_df %>%", to = "  )", after = 1, n = 64),
  # the reactable slate table, part 2 (the widget): 8399-8453
  list(from = "if (reactable_available) {", via = "  message(\"Interactive slate table skipped because 'reactable' is not available.\")",
       to = "}", before = 2, n = 55),
  # the end-of-run moneyline_report() call: 8472-8525. Lines 8469-8471 stay, so Plan 1b-1's
  # added line after saveRDS(games_ready, ...) merges without a conflict
  list(from = "if (!is.null(moneyline_report_inputs) && exists(\"moneyline_report\", inherits = TRUE)) {",
       via = "  message(\"moneyline_report() is unavailable; HTML export skipped.\")", to = "}", after = 1, n = 54)
))
```

  - Run (worktree root): `Rscript --vanilla <scratch>/a8_cut.R C:/Users/jviol/Downloads/nfl-worktrees/a8`
  - Expected:
    ```
    NFLmarket.R: 10 cuts, 2215 lines removed, 6 inserted
    NFLsimulation.R: 9 cuts, 1058 lines removed, 13 inserted
    ```
  - If a cut stops (an anchor matching 0 or 2 lines, or a length mismatch, for example because Plan 1b-1 merged first and moved code), stop and report it; never adjust the expected numbers by hand.
  - Check: `Rscript -e "invisible(parse('NFLmarket.R')); invisible(parse('NFLsimulation.R')); cat('parsed\n')"` → `parsed`, and `wc -l NFLmarket.R NFLsimulation.R` → 2,659 and 7,533 lines (4,868 and 8,578 at `4f9aad3`).

- [ ] **Step 5: `run_week.R` without the report.** Replace `run_week.R` with (the props block no longer re-renders HTML; the comparison table for `artifacts/baseline_games.csv` is built once, after props, with or without them; no `browseURL`, no `artifacts/baseline_report.html`):

```r
#!/usr/bin/env Rscript
# =============================================================================
# NFL Week Analysis Runner
# =============================================================================
#
# Usage:
#   Rscript run_week.R [week] [season]
#
# Examples:
#   Rscript run_week.R          # Uses defaults from config.R
#   Rscript run_week.R 15       # Week 15, current season
#   Rscript run_week.R 15 2024  # Week 15, 2024 season
#
# Output:
#   Web bundle:   bundles/<season>-w<WW>-sim-<UTC stamp>/  (view offline: cd web && npm run local)
#   Audit tables: artifacts/baseline_games.csv, artifacts/baseline_props.csv
#   Run logs:     run_logs/
#
# Debug mode:
#   options(nfl.ev_debug = TRUE)  # Shows EV calculation trace
#
# =============================================================================

# Parse command line arguments and publish them before config.R is sourced (audit M1:
# NFLsimulation.R re-sources config.R, so overrides must live in options, not globals)
source("R/run_config.R")
set_run_options(parse_run_args(commandArgs(trailingOnly = TRUE)))
source("config.R")

# Print run info
cat("\n")
cat("=================================================================\n")
cat("  NFL WEEK ANALYSIS\n")
cat("=================================================================\n")
cat(sprintf("  Season: %d | Week: %d\n", SEASON, WEEK_TO_SIM))
cat(sprintf("  Trials: %s | Seed: %d\n", format(N_TRIALS, big.mark = ","), SEED))
cat("=================================================================\n\n")

# Check for required packages
required_pkgs <- c("tidyverse", "nflreadr")
missing_pkgs <- required_pkgs[!sapply(required_pkgs, requireNamespace, quietly = TRUE)]

if (length(missing_pkgs) > 0) {
  cat("Installing missing packages:", paste(missing_pkgs, collapse = ", "), "\n")

  # Check if renv is active
  if (file.exists("renv.lock") && requireNamespace("renv", quietly = TRUE)) {
    message("Using renv for package management...")
    renv::restore()
  } else {
    install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
  }
}

# Run the full simulation; its results go to a web bundle for the local app
message("Running NFLsimulation.R...")
message("This runs the Monte Carlo simulation and writes a web bundle (view it with: cd web && npm run local).\n")

tryCatch({
  # Bundle writer, and the code's git state before this run rewrites artifacts/
  source("R/bundle_writer.R")
  source("R/sim_bundle.R")
  run_git <- sb_git_state()

  source("NFLsimulation.R")

  # =============================================================================
  # CORRELATED PLAYER PROPS (if enabled in config.R)
  # =============================================================================
  if (exists("RUN_PLAYER_PROPS") && isTRUE(RUN_PLAYER_PROPS)) {
    cat("\n")
    cat("=================================================================\n")
    cat("  RUNNING CORRELATED PLAYER PROPS\n")
    cat("=================================================================\n")

    props_path <- file.path(getwd(), "R", "correlated_props.R")
    if (file.exists(props_path)) {
      source(props_path)

      # Run correlated props using exported simulation results
      if (exists("run_correlated_props", mode = "function") &&
          exists("last_simulation_results") &&
          length(last_simulation_results) > 0) {

        props_results <- tryCatch({
          run_correlated_props(
            game_sim_results = last_simulation_results,
            schedule_data = if (exists("schedule_for_props")) schedule_for_props else NULL,
            prop_types = if (exists("PROP_TYPES")) PROP_TYPES else c("passing", "rushing", "receiving", "td"),
            season = SEASON
          )
        }, error = function(e) {
          message(sprintf("Player props generation failed: %s", e$message))
          NULL
        })

        if (!is.null(props_results) && nrow(props_results) > 0) {
          # Export props results for artifacts/baseline_props.csv
          assign("props_results", props_results, envir = .GlobalEnv)

          # Show quick summary
          positive_ev <- props_results %>%
            dplyr::filter(recommendation != "PASS") %>%
            nrow()

          cat(sprintf("  Generated %d player props (%d with positive EV)\n",
                      nrow(props_results), positive_ev))
        } else {
          message("No player props were generated (possibly missing player data)")
        }
      } else {
        message("Simulation results not available for props correlation")
      }
    } else {
      message("correlated_props.R not found; skipping player props")
    }
  }

  # The game comparison table for artifacts/baseline_games.csv (built with or without props)
  if (exists("moneyline_report_inputs") && !is.null(moneyline_report_inputs) &&
      !is.null(moneyline_report_inputs$comparison)) {
    last_comparison_tbl <- build_moneyline_comparison_table(
      market_comparison_result = moneyline_report_inputs$comparison,
      enriched_schedule = if (exists("sched")) sched else NULL,
      join_keys = if (!is.null(moneyline_report_inputs$join_keys))
                    moneyline_report_inputs$join_keys else c("game_id", "season", "week"),
      vig = 0.10,
      verbose = FALSE
    )
  } else {
    message("No moneyline comparison inputs from NFLsimulation.R; artifacts/baseline_games.csv not written.")
  }

  # Export audit artifacts (baseline tables + run context)
  tryCatch({
    artifact_dir <- file.path(getwd(), "artifacts")
    if (!dir.exists(artifact_dir)) dir.create(artifact_dir, recursive = TRUE)
    if (exists("last_comparison_tbl") && is.data.frame(last_comparison_tbl)) {
      games_export <- last_comparison_tbl
      list_cols <- vapply(games_export, is.list, logical(1))
      if (any(list_cols)) {
        games_export[list_cols] <- lapply(games_export[list_cols], function(col) {
          vapply(col, function(v) {
            if (is.null(v) || length(v) == 0) return(NA_character_)
            if (is.atomic(v)) return(paste(v, collapse = ";"))
            paste(unlist(v), collapse = ";")
          }, character(1))
        })
      }
      utils::write.csv(games_export, file.path(artifact_dir, "baseline_games.csv"), row.names = FALSE)
    }
    if (exists("props_results") && is.data.frame(props_results)) {
      props_export <- props_results
      list_cols <- vapply(props_export, is.list, logical(1))
      if (any(list_cols)) {
        props_export[list_cols] <- lapply(props_export[list_cols], function(col) {
          vapply(col, function(v) {
            if (is.null(v) || length(v) == 0) return(NA_character_)
            if (is.atomic(v)) return(paste(v, collapse = ";"))
            paste(unlist(v), collapse = ";")
          }, character(1))
        })
      }
      utils::write.csv(props_export, file.path(artifact_dir, "baseline_props.csv"), row.names = FALSE)
    }

    log_dir <- file.path(getwd(), "run_logs")
    if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    commit_hash <- tryCatch(system("git rev-parse HEAD", intern = TRUE), error = function(e) NA_character_)
    trials <- if (exists("N_TRIALS")) format(N_TRIALS, big.mark = ",") else "NA"
    log_lines <- c(
      sprintf("timestamp=%s", timestamp),
      sprintf("season=%s", SEASON),
      sprintf("week=%s", WEEK_TO_SIM),
      sprintf("trials=%s", trials),
      sprintf("commit=%s", ifelse(length(commit_hash) > 0, commit_hash[1], NA_character_))
    )
    writeLines(log_lines, file.path(log_dir, sprintf("audit_context_%s.txt", timestamp)))
  }, error = function(e) {
    message(sprintf("Audit artifact export failed: %s", e$message))
  })

  # Web bundle: the results the local app shows (replaces the retired HTML report, A8)
  cat("\n")
  # draws missing (NFLsimulation.R's export failed) -> every game is a QA failure, not a crash
  sim_bundle <- write_sim_bundle(
    final = final, sims = get0("last_simulation_results", ifnotfound = NULL), schedule = sched, quality = get_data_quality(),
    season = SEASON, week = WEEK_TO_SIM, seed = SEED, n_sims = N_TRIALS, git = run_git
  )
  report_sim_bundle(sim_bundle)

  cat("\n")
  cat("=================================================================\n")
  cat("  ANALYSIS COMPLETE\n")
  cat("=================================================================\n")
  cat("  Check the run_logs/ folder for output files.\n")
  cat("  View the results offline: cd web && npm run local\n")
  if (exists("props_results") && !is.null(props_results)) {
    cat("  Player props included in analysis.\n")
  }
  cat("=================================================================\n")

}, error = function(e) {
  cat("\n")
  cat("=================================================================\n")
  cat("  ERROR DURING ANALYSIS\n")
  cat("=================================================================\n")
  cat(sprintf("  %s\n", conditionMessage(e)))
  cat("=================================================================\n")
  quit(status = 1)
})

cat("\nDone.\n")
```

- [ ] **Step 6: Integrity, the CI audit script and the label guard.** In `scripts/verify_repo_integrity.R` replace

```r
# So we check for actual file artifacts, not Windows reserved names
# Note: NFLvsmarket_report.html is a valid output file, not a stale artifact
stale_files <- c(".RData")
```

with

```r
# So we check for actual file artifacts, not Windows reserved names
stale_files <- c(".RData")
```

  and replace

```r
    fail("invariant", sprintf("Stale artifact found: %s", f))
  }
}

```

with

```r
    fail("invariant", sprintf("Stale artifact found: %s", f))
  }
}

# =============================================================================
# INVARIANT: Legacy HTML report retired (checkpoint A8)
# =============================================================================

cat("\n--- Invariant: Legacy HTML report retired (A8) ---\n")

# Results are served by the local web app (cd web && npm run local); no R code may
# bring back the gt report, its exporter or its output file.
retired_report <- paste(c("export_moneyline_comparison_html", "open_moneyline_report", "moneyline_report\\(",
                          "validate_moneyline_report_schema", "moneyline_report_schema_contract",
                          "render_model_status_banner", "NFLvsmarket_report"), collapse = "|")
report_scan <- setdiff(c(list.files(".", pattern = "\\.R$"), list.files("R", pattern = "\\.R$", full.names = TRUE),
                         list.files("scripts", pattern = "\\.R$", full.names = TRUE)),
                       c("scripts/verify_repo_integrity.R", "./scripts/verify_repo_integrity.R"))
report_hits <- character()
for (f in report_scan) {
  src <- readLines(f, warn = FALSE, encoding = "UTF-8")
  hit <- grep(retired_report, src[!grepl("^\\s*#", src)])
  if (length(hit)) report_hits <- c(report_hits, f)
}
if (!length(report_hits) && !file.exists("R/report_banner.R")) {
  pass("invariant", sprintf("No legacy HTML report code in %d R files", length(report_scan)))
} else {
  fail("invariant", "Legacy HTML report code found", paste(c(report_hits, if (file.exists("R/report_banner.R")) "R/report_banner.R"), collapse = ", "))
}

```

  In `scripts/audit_verify.sh` replace (CI job `audit-verify` would fail on six labels that lived only in the deleted exporter)

```bash
# Static invariants that should always hold in source
rg -n "Market Home Win % \(Fair, Devig=proportional\)" NFLmarket.R >/dev/null
rg -n "ML Implied Home % \(Raw\)" NFLmarket.R >/dev/null
rg -n "EV Edge \(Raw\)" NFLmarket.R >/dev/null
rg -n "EV Edge \(Displayed, Capped\)" NFLmarket.R >/dev/null
rg -n "Min Stake \(%\)" NFLmarket.R >/dev/null
rg -n "Negative EV" R/utils.R >/dev/null
rg -n "Stake below minimum" R/utils.R >/dev/null
rg -n "Market odds missing/placeholder" R/utils.R >/dev/null
rg -n "MODEL ERROR / REVIEW" NFLmarket.R >/dev/null
```

with

```bash
# Static invariants that should always hold in source. The HTML report's display labels
# went with the report (checkpoint A8); the governance pass reasons below still feed
# artifacts/baseline_games.csv. tests/testthat/test-report-retired.R checks each line.
rg -n "Negative EV" R/utils.R >/dev/null
rg -n "Stake below minimum" R/utils.R >/dev/null
rg -n "Market odds missing/placeholder" R/utils.R >/dev/null
```

  Replace `tests/testthat/test-report-audit-guards.R` with:

```r
# =============================================================================
# Report Audit Guardrails (governance labels)
# =============================================================================
# The display-label guards went with the HTML report (checkpoint A8); the governance
# pass reasons live in R/utils.R and still feed artifacts/baseline_games.csv.

context("Report Audit Guardrails")

test_that("pass reasons include required deterministic governance reasons", {
  market_file <- file.path(.test_project_root, "NFLmarket.R")
  utils_file <- file.path(.test_project_root, "R", "utils.R")

  txt <- paste(readLines(market_file, warn = FALSE), collapse = "\n")
  utils_txt <- paste(readLines(utils_file, warn = FALSE), collapse = "\n")
  combined <- paste(txt, utils_txt, collapse = "\n")

  expect_match(combined, "Market odds missing/placeholder")
  expect_match(combined, "Negative EV")
  expect_match(combined, "Stake below minimum")
})
```

- [ ] **Step 7: Run the tests and watch them pass; record the call graph.**
  - `Rscript -e "testthat::test_file('tests/testthat/test-report-retired.R')"` → `[ FAIL 0 | ... | PASS 21 ]`; `test-run-week-outputs.R` → `[ FAIL 0 | ... | PASS 9 ]`.
  - Red check for the audit-anchor test: `git stash push scripts/audit_verify.sh && Rscript -e "testthat::test_file('tests/testthat/test-report-retired.R')"; git stash pop` → with the old script it fails 6 expectations naming `Market Home Win % \(Fair, Devig=proportional\) in NFLmarket.R` … `MODEL ERROR / REVIEW in NFLmarket.R` (dry run: `[ FAIL 6 | WARN 3 | SKIP 0 | PASS 21 ]`).
  - Save this tool as `<scratch>/a8_callgraph2.R` and run `Rscript <scratch>/a8_callgraph2.R C:/Users/jviol/Downloads/nfl-worktrees/a8`:

```r
# A8 call-graph evidence (scratch tool; never committed).
#   Rscript a8_callgraph2.R <worktree>
# Compares the worktree with its base commit 4f9aad3:
#   1. every top-level definition (function or value) that A8 removes, and how many
#      references to it remain in any .R file of the worktree (must be 0);
#   2. every repo-defined name that the deleted lines used and that A8 keeps, with its
#      remaining references (the reason it stays).
args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(args[1], winslash = "/")
base <- "4f9aad3"
git <- function(...) system2("git", c("-C", shQuote(root), ...), stdout = TRUE)

r_files_now <- list.files(root, pattern = "\\.[Rr]$", recursive = TRUE)
r_files_now <- r_files_now[!grepl("^(renv|web|node_modules)/", r_files_now)]
r_files_base <- git("ls-tree", "-r", "--name-only", base)
r_files_base <- r_files_base[grepl("\\.[Rr]$", r_files_base) & !grepl("^(renv|web)/", r_files_base)]

parse_text <- function(lines, label) {
  tryCatch(getParseData(parse(text = lines, keep.source = TRUE, srcfile = srcfilecopy(label, lines))),
           error = function(e) { message("parse failed: ", label); NULL })
}
base_src <- function(f) git("show", sprintf("%s:%s", base, f))
now_src <- function(f) readLines(file.path(root, f), warn = FALSE, encoding = "UTF-8")

# top-level assignments (also inside top-level if (...) { } blocks): name and line
defs_of <- function(pd) {
  if (is.null(pd)) return(data.frame(name = character(), line = integer()))
  a <- pd[pd$token %in% c("LEFT_ASSIGN", "EQ_ASSIGN"), ]
  out <- list()
  for (k in seq_len(nrow(a))) {
    par <- pd[pd$id == a$parent[k], ]
    # walk up: the assignment's expr must sit at top level or in a top-level if-body brace
    up <- par$parent; depth_ok <- FALSE
    if (up == 0) depth_ok <- TRUE else {
      brace <- pd[pd$id == up, ]
      if (nrow(brace) && any(pd$parent == up & pd$token == "'{'")) {
        ifexpr <- pd[pd$id == brace$parent, ]
        depth_ok <- nrow(ifexpr) && ifexpr$parent == 0 && any(pd$parent == ifexpr$id & pd$token == "IF")
      }
    }
    if (!depth_ok) next
    lhs <- pd[pd$parent == a$parent[k] & pd$token == "expr" & pd$line1 <= a$line1[k], ]
    lhs <- lhs[order(lhs$line1, lhs$col1), ][1, ]
    sym <- pd[pd$parent == lhs$id & pd$token == "SYMBOL", ]
    if (nrow(sym) == 1) out[[length(out) + 1]] <- data.frame(name = sym$text, line = sym$line1)
  }
  if (length(out)) unique(do.call(rbind, out)) else data.frame(name = character(), line = integer())
}
refs_of <- function(pd) {
  if (is.null(pd)) return(data.frame(text = character(), line = integer()))
  t <- pd[pd$token %in% c("SYMBOL", "SYMBOL_FUNCTION_CALL", "STR_CONST"), c("text", "line1", "token")]
  t$text <- ifelse(t$token == "STR_CONST", gsub("^[\"']|[\"']$", "", t$text), t$text)
  data.frame(text = t$text, line = t$line1)
}

# deleted base lines per file, from the diff
deleted <- list()
for (f in r_files_base) {
  if (!file.exists(file.path(root, f))) { deleted[[f]] <- seq_along(base_src(f)); next }
  d <- git("diff", "-U0", base, "--", f)
  hunks <- regmatches(d, regexpr("^@@ -[0-9]+(,[0-9]+)? ", d))
  lines <- integer()
  for (h in hunks) {
    m <- as.integer(strsplit(sub("^@@ -", "", trimws(h)), ",")[[1]])
    n <- if (length(m) == 2) m[2] else 1L
    if (n > 0) lines <- c(lines, seq.int(m[1], length.out = n))
  }
  deleted[[f]] <- lines
}

base_pd <- setNames(lapply(r_files_base, function(f) parse_text(base_src(f), f)), r_files_base)
now_pd <- setNames(lapply(r_files_now, function(f) parse_text(now_src(f), f)), r_files_now)

base_defs <- do.call(rbind, lapply(names(base_pd), function(f) { d <- defs_of(base_pd[[f]]); if (nrow(d)) cbind(file = f, d) }))
now_defs <- do.call(rbind, lapply(names(now_pd), function(f) { d <- defs_of(now_pd[[f]]); if (nrow(d)) cbind(file = f, d) }))
now_refs <- do.call(rbind, lapply(names(now_pd), function(f) { r <- refs_of(now_pd[[f]]); if (nrow(r)) cbind(file = f, r) }))

# 1. removed definitions: defined in base on a deleted line, and no longer defined anywhere
removed <- base_defs[mapply(function(f, l) l %in% deleted[[f]], base_defs$file, base_defs$line), ]
removed <- removed[!removed$name %in% now_defs$name, ]
removed <- removed[!duplicated(removed$name), ]
# the two guards that list the retired names as strings so they cannot come back
GUARDS <- c("scripts/verify_repo_integrity.R", "tests/testthat/test-report-retired.R")
live_refs <- now_refs[!now_refs$file %in% GUARDS, ]
removed$refs_left <- vapply(removed$name, function(n) sum(live_refs$text == n), integer(1))
removed$where <- vapply(removed$name, function(n) {
  h <- live_refs[live_refs$text == n, ]
  paste(head(unique(sprintf("%s:%d", h$file, h$line)), 3), collapse = " ")
}, "")

# 2. kept: repo-defined names used on deleted lines that are still defined
used <- do.call(rbind, lapply(names(base_pd), function(f) {
  r <- refs_of(base_pd[[f]]); r <- r[r$line %in% deleted[[f]], ]
  if (nrow(r)) cbind(file = f, r)
}))
CORE <- now_defs$file %in% c("NFLmarket.R", "NFLsimulation.R", "NFLbrier_logloss.R") | grepl("^R/", now_defs$file)
kept_names <- intersect(unique(used$text), unique(now_defs$name[CORE]))
kept_names <- kept_names[vapply(kept_names, function(n) any(base_defs$name == n & !mapply(function(f, l) l %in% deleted[[f]], base_defs$file, base_defs$line)), logical(1))]
kept <- data.frame(name = kept_names, stringsAsFactors = FALSE)
kept$defined_in <- vapply(kept$name, function(n) paste(unique(now_defs$file[now_defs$name == n]), collapse = " "), "")
kept$refs_now <- vapply(kept$name, function(n) sum(now_refs$text == n), integer(1))
kept$where <- vapply(kept$name, function(n) {
  h <- now_refs[now_refs$text == n, ]
  paste(head(unique(sprintf("%s:%d", h$file, h$line)), 3), collapse = " ")
}, "")
is_fun <- vapply(kept$name, function(n) any(vapply(names(now_pd), function(f) {
  pd <- now_pd[[f]]; !is.null(pd) && any(pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == n)
}, logical(1))), logical(1))

options(width = 200)
cat(sprintf("Deleted lines vs %s: %s\n", base, paste(sprintf("%s %d", names(deleted), lengths(deleted))[lengths(deleted) > 0], collapse = "; ")))
cat("\n== Removed top-level definitions and the references left to them ==\n")
print(removed[order(removed$file, removed$line), c("file", "line", "name", "refs_left", "where")], row.names = FALSE, right = FALSE)
cat("\n== Kept: repo functions the deleted lines called, still defined and used ==\n")
print(kept[is_fun, ][order(-kept$refs_now[is_fun]), ], row.names = FALSE, right = FALSE)
cat(sprintf("\nRemoved definitions with references left: %d\n", sum(removed$refs_left > 0)))
```

  - Expected: the table in "Call-graph evidence" above and the last line `Removed definitions with references left: 0`. Paste the output into the PR.

- [ ] **Step 8: Prove the Plan 1b-1 merge stays clean.**

```bash
mkdir -p <scratch>/mergeprobe
git show 4f9aad3:NFLsimulation.R > <scratch>/mergeprobe/base.R
git show fix/phase1b-1-explicit-model:NFLsimulation.R > <scratch>/mergeprobe/b1.R
cp NFLsimulation.R <scratch>/mergeprobe/a8.R
git merge-file -p <scratch>/mergeprobe/a8.R <scratch>/mergeprobe/base.R <scratch>/mergeprobe/b1.R > <scratch>/mergeprobe/merged.R; echo "conflicts=$?"
grep -n 'saveRDS(mu_terms' <scratch>/mergeprobe/merged.R
```

  Expected: `conflicts=0` and one `saveRDS(mu_terms, file.path(log_dir, paste0("mu_terms_", run_id, ".rds")))` line right after `saveRDS(games_ready, ...)` (dry run against the 1b-1 worktree on 2026-10-03: `conflicts=0`, the line at `merged.R:7475`). Repeat against the 1b-1 branch head at merge time; a conflict means rebase A8 onto 1b-1 and re-run Step 4.

- [ ] **Step 9: Golden master, attributed to this commit.** After Step 6: `Rscript scripts/golden_master.R compare 15 2024 <scratch>/gm-before-a8` → `golden master: no differences` (Step 0 recorded the base the same day, so live nflverse revisions cannot leak in). Offline: skip both runs and rely on CI's golden-master workflow, which records every commit of the PR and attributes each change; predict "no differences" for every A8 commit.

- [ ] **Step 10: Full gates.** `Rscript scripts/run_tests.R` → exit 0, `failed=0 errors=0 unapproved_skips=0`; `Rscript scripts/verify_repo_integrity.R` → exit 0, `Total: 63 passed, 0 failed` with `[PASS] No legacy HTML report code in 30 R files`. Web unchanged (no web gates needed); `git status` shows no `artifacts/` change.

- [ ] **Step 11: Commit.**

```bash
git add NFLmarket.R NFLsimulation.R run_week.R scripts/verify_repo_integrity.R scripts/audit_verify.sh tests/testthat/test-report-retired.R tests/testthat/test-run-week-outputs.R tests/testthat/test-report-audit-guards.R tests/testthat/test-bet-governance.R
git commit -F- <<'EOF'
refactor(model): retire the legacy HTML report, its fallback copy and its tests; keep every computation other code uses (A8)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

  (The four `git rm` deletions from Step 3 are already staged and go into this commit.)

---

### Task 8: Docs follow the code

**Files:**
- Modify: `CLAUDE.md` (entrypoints, Expected Outputs, What "Correct" Looks Like, Validation Agent, the §5 playbook, §6 inventory, §7 commands), `README.md`, `GETTING_STARTED.md`, `DOCUMENTATION.md`, `docs/API.md`, `docs/ARCHITECTURE.md`, `docs/modeling.md`

**Interfaces:** none (text). Facts the text must match: the bundle path `bundles/<season>-w<WW>-sim-<UTC stamp>/`, `npm run local` on 127.0.0.1:3000, `npm run local:stop`, `PG_BIN`, `Rscript scripts/write_backtest_bundle.R` for /evidence, `run_matrix` 11 artifacts (Task 3 added `sim-bundle`), `R/sim_bundle.R`, `scripts/write_sim_fixture.R`. History entries in `README.md`'s version notes and `CHANGELOG.md` stay as they are (they describe what was true then).

- [ ] **Step 1: The checks that guard these docs.** `Rscript -e "testthat::test_file('tests/testthat/test-docs-truth.R')"` passes before and after (withdrawn claims must not appear in README, CLAUDE.md, GETTING_STARTED). After the edits, this must print nothing:

```bash
grep -n "NFLvsmarket\|HTML Report  \|moneyline_report()\|render_moneyline_comparison_html\|10/10" CLAUDE.md README.md GETTING_STARTED.md docs/API.md docs/ARCHITECTURE.md docs/modeling.md
```

  Before the edits it lists 15 lines (dry run).

- [ ] **Step 2: CLAUDE.md.** Replace

```markdown
| `scripts/run_matrix.R` | Run all artifacts | `Rscript scripts/run_matrix.R` |

### Player Props Module (v2.9.0)
```

with

```markdown
| `scripts/run_matrix.R` | Run all artifacts | `Rscript scripts/run_matrix.R` |
| `web/scripts/local.ts` | Offline results viewer (the local app) | `cd web && npm run local` |

### Player Props Module (v2.9.0)
```

  Replace

```markdown
When `run_week.R` completes successfully:
1. **HTML Report**: `NFLvsmarket_report.html` with game predictions AND player props (tabbed)
2. **Run Logs**: `run_logs/config_*.rds`, `run_logs/final_*.rds`
3. **Console**: Data quality badge, simulation progress, calibration status
```

with

```markdown
When `run_week.R` completes successfully:
1. **Web bundle**: `bundles/<season>-w<WW>-sim-<UTC stamp>/` with the market (C0) and simulator (C3) win probabilities, margin and total distributions, and source status (`R/sim_bundle.R`). View it offline with `cd web && npm run local` (http://127.0.0.1:3000). The HTML report was retired at checkpoint A8.
2. **Audit tables**: `artifacts/baseline_games.csv` and, when `RUN_PLAYER_PROPS`, `artifacts/baseline_props.csv`
3. **Run Logs**: `run_logs/config_*.rds`, `run_logs/final_*.rds`
4. **Console**: Data quality badge, simulation progress, calibration status, the bundle path and its QA result
```

  Replace

```markdown
- `scripts/run_matrix.R`: 10/10 artifacts pass (the golden-master artifact may SKIP as LIVE when nflverse is unreachable)
```

with

```markdown
- `scripts/run_matrix.R`: 11/11 artifacts pass (the golden-master artifact may SKIP as LIVE when nflverse is unreachable)
```

  Replace

```markdown
3. Rscript scripts/run_matrix.R (must show 10/10 pass, or 9 pass + golden-master LIVE skip offline)
4. Verify HTML report generates if run_week.R was changed
```

with

```markdown
3. Rscript scripts/run_matrix.R (must show 11/11 pass, or 10 pass + golden-master LIVE skip offline)
4. If run_week.R or R/sim_bundle.R changed: run_week.R prints "Web bundle: <dir>" and "QA: passed", and `cd web && npm run local` serves that run
```

  Replace

```markdown
### HTML Report Not Generated

**Symptom**: run_week.R completes but no HTML file

**Diagnosis**: Check for earlier errors; report generation is near end of pipeline.

**Common Causes**:
1. gt package not installed
2. Previous step produced empty results
3. File write permission issue
```

with

```markdown
### Web Bundle Not Written or Not Shown

**Symptom**: run_week.R completes but writes no `bundles/<cycle_id>/`, or `npm run local` shows an older run

**Diagnosis**: The end of run_week.R prints `Web bundle: <dir>` and `QA: passed` or `QA: FAILED (n)` with each failure.

**Common Causes**:
1. An earlier error stopped the run; the bundle step runs after the simulation and props
2. QA failed: the ingest stores the run as `qa_failed` and the app keeps the last good run (the failures are listed in the console and on /data-health)
3. PostgreSQL not found by `npm run local`: set `PG_BIN` to its bin directory (Windows default `C:/Program Files/PostgreSQL/17/bin`)
4. /evidence is empty: no backtest bundle; run `Rscript scripts/write_backtest_bundle.R` once
```

  Replace

```markdown
- `R/bundle_writer.R` - R side of the R -> web data contract (validates against `contracts/schema/`)
```

with

```markdown
- `R/bundle_writer.R` - R side of the R -> web data contract (validates against `contracts/schema/`)
- `R/sim_bundle.R` - the simulator's weekly bundle, written by `run_week.R` (replaced the HTML report at A8)
```

  Replace

```markdown
- `scripts/run_matrix.R` - Execute all artifacts
```

with

```markdown
- `scripts/run_matrix.R` - Execute all artifacts
- `scripts/write_sim_fixture.R` - writes the web test fixture `contracts/fixtures/bundles/weekly-sim-2024-w15` (synthetic draws, not model output)
```

  Replace (inside the §7 bash block)

```markdown
# 3. Full artifact matrix (must show 10/10 pass; golden-master needs network)
Rscript scripts/run_matrix.R

# 4. Run weekly simulation (use valid week!)
# Edit config.R first: WEEK_TO_SIM <- 16; SEASON <- 2024
Rscript -e "source('run_week.R')"
```

with

```markdown
# 3. Full artifact matrix (must show 11/11 pass; golden-master needs network)
Rscript scripts/run_matrix.R

# 4. Run weekly simulation (use valid week!)
# Edit config.R first: WEEK_TO_SIM <- 16; SEASON <- 2024
Rscript -e "source('run_week.R')"

# 5. View the run offline (after `npm ci` in web/ once)
cd web && npm run local
```

- [ ] **Step 3: README.md.** Replace

```
│  run_week.R (Entry) │ config.R (Params) │ HTML Report          │
```

with

```
│  run_week.R (Entry) │ config.R (Params) │ Web bundle (bundles/)│
```

  Replace

```markdown
This fail-fast wrapper validates report schema/governance guards and, when `Rscript` is available, runs full testthat + audit verification.
```

with

```markdown
This fail-fast wrapper checks the governance pass reasons in `R/utils.R` and, when `Rscript` is available, runs full testthat + audit verification.
```

  Replace

```markdown
The script generates a unified HTML report with:
- **Report Authority**: `NFLmarket.R::moneyline_report()` is the sole HTML rendering/export path; `NFLsimulation.R` only prepares inputs.
- **Game Predictions**: Game-by-game predictions with EV analysis
- **Player Props** (v2.9.0): Correlated with game simulation
- **Market Comparison**: Blend vs Vegas odds
- **Vigged Model Lines**: Realistic ~10% juice moneylines
- **Paper Stakes**: 1/8 Kelly stake sizes in tracking units (`STAKING_MODE = "paper"`), not betting advice
- **Tabbed Interface**: Switch between Games and Props sections
```

with

````markdown
The run writes:
- **Web bundle**: `bundles/<season>-w<WW>-sim-<UTC stamp>/` (`R/sim_bundle.R`): per game the no-vig market (C0) and the simulator (C3, unvalidated) win probabilities, the simulated margin and total distributions, and the run's source status. The console prints the bundle path and its QA result.
- **Audit tables**: `artifacts/baseline_games.csv` (the model vs market comparison, with paper stakes: 1/8 Kelly in tracking units, `STAKING_MODE = "paper"`, not betting advice) and `artifacts/baseline_props.csv` (player props, when `RUN_PLAYER_PROPS`).

View the results offline in the local web app (the HTML report was retired at checkpoint A8):

```bash
cd web
npm ci            # once, with a network
npm run local     # http://127.0.0.1:3000, no network needed
```

See [web/README.md](web/README.md) for what `npm run local` does and its settings.
````

  Replace

```markdown
Rscript scripts/run_matrix.R  # Should show 10/10 passed (golden-master needs network)
```

with

```markdown
Rscript scripts/run_matrix.R  # Should show 11/11 passed (golden-master needs network)
```

  Replace

```markdown
| `NFLsimulation.R` | Monte Carlo simulation engine (~7,800 lines); computes probabilities and report inputs only |
| `NFLmarket.R` | Market comparison + **sole HTML/report authority** (`moneyline_report`, `export_moneyline_comparison_html`) |
```

with

```markdown
| `NFLsimulation.R` | Monte Carlo simulation engine; computes probabilities, the comparison inputs and the draws behind the score distributions |
| `NFLmarket.R` | Market comparison and paper Kelly staking (`build_moneyline_comparison_table`) |
```

  Replace

```markdown
| `R/date_resolver.R` | Timezone-safe datetime parsing |
```

with

```markdown
| `R/date_resolver.R` | Timezone-safe datetime parsing |
| `R/bundle_writer.R` | Writes and validates R -> web bundles (`contracts/schema/`) |
| `R/sim_bundle.R` | The simulator's weekly bundle, written by `run_week.R` |
```

  Replace

```markdown
- HTML report shows banner indicating fallback mode used
```

with

```markdown
- The run's source status records the fallback (the local app's /data-health page shows it)
```

- [ ] **Step 4: GETTING_STARTED.md.** Replace

```markdown
The script generates an HTML report with:
- Game-by-game predictions with win probabilities
- EV analysis and model picks (paper stakes, not betting advice)
- Market comparison (model vs Vegas)
- Paper stake sizes (1/8 Kelly, tracking units; `STAKING_MODE = "paper"`)

Output file: `NFLvsmarket_week15_2024.html` (or similar)
```

with

````markdown
The run writes a web bundle to `bundles/<season>-w<WW>-sim-<UTC stamp>/` and prints its path. View it in the local web app, which runs with no internet connection (the HTML report was retired at checkpoint A8):

```bash
cd web
npm ci            # once, with a network (Node 20.9+)
npm run local     # then open http://127.0.0.1:3000
npm run local:stop
```

You need PostgreSQL installed (on Windows the default is `C:/Program Files/PostgreSQL/17/bin`; set `PG_BIN` if yours is elsewhere). The app shows, per game, the no-vig market and the simulator's win probability (unvalidated), and the simulated margin and total distributions. For the evidence page, run `Rscript scripts/write_backtest_bundle.R` once.

The run also writes `artifacts/baseline_games.csv` (model vs market, with paper stakes: 1/8 Kelly in tracking units, `STAKING_MODE = "paper"`, not betting advice) and, with player props on, `artifacts/baseline_props.csv`.
````

- [ ] **Step 5: DOCUMENTATION.md.** Replace

```markdown
5. **Reporting**
   - `build_moneyline_comparison_table()`: Model vs market table
   - `export_moneyline_comparison_html()`: HTML report generation
   - Interactive visualizations
```

with

```markdown
5. **Reporting**
   - `build_moneyline_comparison_table()`: Model vs market table (written to `artifacts/baseline_games.csv` by `run_week.R`)
   - The HTML report (`export_moneyline_comparison_html()`) was retired at checkpoint A8; `R/sim_bundle.R` writes the run to a web bundle that the local app shows (`cd web && npm run local`)
```

  Replace

```markdown
### Moneyline Report Columns (HTML)

Key columns and definitions for the game table:
```

with

```markdown
### Moneyline Report Columns (retired HTML labels)

These were the display labels of the HTML report retired at checkpoint A8. `artifacts/baseline_games.csv` carries the underlying snake_case columns of `build_moneyline_comparison_table()`. Key columns and definitions for the game table:
```

  Replace

```markdown
### Player Props Report Columns (HTML)

Key columns and definitions for the player props table:
```

with

```markdown
### Player Props Report Columns (retired HTML labels)

These were the display labels of the HTML report retired at checkpoint A8. `artifacts/baseline_props.csv` carries the props table's underlying columns. Key columns and definitions for the player props table:
```

- [ ] **Step 6: docs/API.md, docs/ARCHITECTURE.md, docs/modeling.md.** In `docs/API.md` replace

````markdown
### `render_moneyline_comparison_html()`

**File**: [NFLmarket.R](../NFLmarket.R#L2800)

Generate HTML report from comparison table.

```r
render_moneyline_comparison_html(
  moneyline_tbl,    # Output from build_moneyline_comparison_table()
  output_file = "NFLvsmarket_report.html"
)
```
````

with

````markdown
### `write_sim_bundle()`

**File**: [R/sim_bundle.R](../R/sim_bundle.R)

Write the simulator's weekly bundle (it replaced the HTML report at checkpoint A8). `run_week.R` calls it after the simulation; the local app (`cd web && npm run local`) ingests and shows it.

```r
write_sim_bundle(
  final, sims = last_simulation_results, schedule = sched, quality = get_data_quality(),
  season = SEASON, week = WEEK_TO_SIM, seed = SEED, n_sims = N_TRIALS
)  # writes bundles/<season>-w<WW>-sim-<UTC stamp>/ and returns its manifest (qa$ok, qa$failures)
```
````

  In `docs/ARCHITECTURE.md` replace

```
│  run_week.R (Entry Point)  │  config.R (Parameters)  │  HTML Report        │
```

with

```
│  run_week.R (Entry Point)  │  config.R (Parameters)  │  Web bundle         │
```

  Replace

```
│  ├── conservative_kelly_stake()           1/8 Kelly with edge caps          │
│  └── render_moneyline_comparison_html()   Report generation                 │
```

with

```
│  └── conservative_kelly_stake()           1/8 Kelly with edge caps          │
```

  Replace

```
│  • NFLvsmarket_report.html                          │
```

with

```
│  • bundles/<cycle_id>/ (web bundle; npm run local)  │
```

  In `docs/modeling.md` replace

```markdown
## Report Rendering Authority

HTML/report rendering is intentionally centralized in `NFLmarket.R` (`moneyline_report()` and `export_moneyline_comparison_html()`). `NFLsimulation.R` is limited to simulation/backtest generation and preparing report inputs; it does not own a separate HTML export path.
```

with

```markdown
## Where Results Go

The HTML report was retired at checkpoint A8. `run_week.R` writes the run to a weekly web bundle (`R/sim_bundle.R`: the no-vig market as candidate C0, the simulator as C3, margin and total distributions, source status) and the comparison table to `artifacts/baseline_games.csv`. The local web app shows the bundle offline (`cd web && npm run local`).
```

- [ ] **Step 7: Gates.** The Step 1 grep prints nothing. `Rscript scripts/run_tests.R` → exit 0; `Rscript scripts/verify_repo_integrity.R` → exit 0 (63/63). `cd web && npx vitest run src/test/docsTruth.test.ts` → passed.

- [ ] **Step 8: Commit.**

```bash
git add CLAUDE.md README.md GETTING_STARTED.md DOCUMENTATION.md docs/API.md docs/ARCHITECTURE.md docs/modeling.md
git commit -F- <<'EOF'
docs: results are viewed in the local web app; the HTML report is retired (A8)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 9: Online: the deployed app reads the same bundle (`weekly-sim.yml`)

Owner, 2026-10-03 and again 2026-10-04 (verbatim): "Make sure UI/UX is switched for both offline and online to the Next.js script. Make sure all accuracy, testing is maxed." Controller ruling: the Next.js app is the only UI everywhere; offline is `npm run local`; online is the deployed app fed by the same simulator bundle through a GitHub Actions workflow that runs the weekly simulation, writes and validates the bundle, uploads it as an artifact and ingests it into `DATABASE_URL` only when that secret exists; `contents: read`; the existing workflows' patterns (setup-r 4.5.1, setup-renv, Node from the web app's `engines`). Deployment itself (Vercel, Neon) stays pending: the owner has not authorized those connectors.

**Files:**
- Create: `.github/workflows/weekly-sim.yml`, `tests/testthat/test-workflows.R`, `web/scripts/check-bundle.ts`, `web/scripts/check-bundle/report.ts`, `web/scripts/check-bundle/report.test.ts`
- Modify: `web/package.json` (`check-bundle` script), `web/README.md` (one paragraph)

**Interfaces:**
- Consumes: `run_week.R` → `write_sim_bundle()` (Task 3; the same R path as the offline app), `loadBundle()` and `BundleRejected` (`web/src/lib/ingest/ingest.ts`; the ingest's own validation), `npm run db:migrate`, `npm run ingest`.
- Produces: `bundleReport(bundle: LoadedBundle): string[]` (one `ok …` summary line, then one `::warning title=Bundle QA::…` per QA failure); `npm run check-bundle -- <dir>` (exit 0 when the ingest would accept the bundle, 1 when it would reject it, 2 on usage); the workflow's job graph `simulate` → (`gate`) → `ingest`, with `ingest` running only when `gate` finds the `DATABASE_URL` secret.

Decisions inside the workflow: manual `workflow_dispatch` with required `week` and `season` (no cron: `config.R` defaults to 2025 week 22, and 2025 stays sealed, so a schedule comes with deployment); a step refuses `season = 2025`; the secret is tested inside a `gate` job (a job-level `if:` cannot read `secrets`), and only `gate` and the ingest step see it; the bundle is checked with the web loader before upload, so a bundle the ingest would reject fails the run early, and a QA-failed bundle uploads with warnings (the ingest stores it as `qa_failed` and keeps the last good run published).

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-workflows.R` (actionlint is not installed, so every workflow is parsed with `yaml::read_yaml` — `yaml` 2.3.12 is already in `renv.lock` — and the job graph is pinned):

```r
# =============================================================================
# GitHub Actions workflows (A8). actionlint is not installed here, so every workflow must
# at least parse as YAML with read-only contents permission, and weekly-sim.yml (the
# online path: the same simulator bundle the offline app reads) must keep its job graph,
# its season guard and its secret gate: nothing is ingested unless DATABASE_URL exists.
# =============================================================================

wf_dir <- file.path(.test_project_root, ".github", "workflows")
wf_read <- function(name) yaml::read_yaml(file.path(wf_dir, name))
wf_on <- function(w) if (!is.null(w[["on"]])) w[["on"]] else w[["TRUE"]]   # YAML 1.1 reads the key `on` as TRUE
wf_runs <- function(job) paste(vapply(job$steps, function(s) if (is.null(s$run)) "" else s$run, ""), collapse = "\n")
wf_uses <- function(job) vapply(job$steps, function(s) if (is.null(s$uses)) "" else s$uses, "")

test_that("every workflow parses as YAML and grants read-only contents permission", {
  files <- list.files(wf_dir, pattern = "\\.ya?ml$")
  expect_true("weekly-sim.yml" %in% files)
  for (f in files) {
    w <- wf_read(f)
    expect_true(is.list(w$jobs) && length(w$jobs) > 0, info = f)
    expect_identical(w$permissions, list(contents = "read"), info = f)
  }
})

test_that("weekly-sim runs on demand with an explicit week and season, and refuses the sealed 2025", {
  w <- wf_read("weekly-sim.yml")
  on <- wf_on(w)
  expect_identical(names(on), "workflow_dispatch")
  expect_true(isTRUE(on$workflow_dispatch$inputs$week$required) && isTRUE(on$workflow_dispatch$inputs$season$required))
  sim <- w$jobs$simulate
  expect_match(wf_runs(sim), 'if [ "$SEASON" = "2025" ]; then', fixed = TRUE)
  expect_match(wf_runs(sim), 'Rscript run_week.R "$WEEK" "$SEASON"', fixed = TRUE)
})

test_that("weekly-sim builds the bundle with the same R path as the local app, checks it and keeps it", {
  sim <- wf_read("weekly-sim.yml")$jobs$simulate
  uses <- wf_uses(sim)
  expect_true(all(c("actions/checkout@v4", "r-lib/actions/setup-r@v2", "r-lib/actions/setup-renv@v2",
                    "actions/setup-node@v4", "actions/upload-artifact@v4") %in% uses))
  setup_r <- sim$steps[[which(uses == "r-lib/actions/setup-r@v2")]]
  expect_identical(setup_r$with$`r-version`, "4.5.1")
  setup_node <- sim$steps[[which(uses == "actions/setup-node@v4")]]
  expect_identical(setup_node$with$`node-version-file`, "web/package.json")
  runs <- wf_runs(sim)
  expect_match(runs, "npm run check-bundle --", fixed = TRUE)
  # run_week.R is the only bundle writer: it calls R/sim_bundle.R's write_sim_bundle(), as for npm run local
  run_week <- readLines(file.path(.test_project_root, "run_week.R"), warn = FALSE)
  expect_true(any(grepl("write_sim_bundle(", run_week, fixed = TRUE)))
  upload <- sim$steps[[which(uses == "actions/upload-artifact@v4")]]
  expect_identical(upload$with$name, "sim-bundle")
  expect_identical(upload$with$`if-no-files-found`, "error")
})

test_that("weekly-sim ingests only after the bundle is built and only when the DATABASE_URL secret exists", {
  jobs <- wf_read("weekly-sim.yml")$jobs
  expect_setequal(names(jobs), c("simulate", "gate", "ingest"))
  expect_setequal(unlist(jobs$ingest$needs), c("simulate", "gate"))
  expect_identical(jobs$ingest$`if`, "needs.gate.outputs.has_db == 'true'")
  gate_step <- jobs$gate$steps[[1]]
  expect_identical(gate_step$env$DATABASE_URL, "${{ secrets.DATABASE_URL }}")
  expect_match(gate_step$run, 'if [ -n "$DATABASE_URL" ]', fixed = TRUE)
  expect_identical(jobs$gate$outputs$has_db, "${{ steps.check.outputs.has_db }}")
  ingest_runs <- wf_runs(jobs$ingest)
  expect_match(ingest_runs, "npm run db:migrate", fixed = TRUE)
  expect_match(ingest_runs, "npm run ingest -- ../sim-bundle", fixed = TRUE)
  # the secret reaches only the gate and the ingest step, never the simulation
  expect_false(grepl("secrets.", paste(unlist(jobs$simulate), collapse = " "), fixed = TRUE))
})
```

  Create `web/scripts/check-bundle/report.test.ts`:

```ts
import { cpSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { BundleRejected, loadBundle } from "../../src/lib/ingest/ingest";
import { bundleReport } from "./report";

const SIM = join(import.meta.dirname, "..", "..", "..", "contracts", "fixtures", "bundles", "weekly-sim-2024-w15");

describe("check-bundle (the weekly-sim workflow's check before upload and ingest)", () => {
  it("summarises a bundle the ingest accepts", () => {
    const b = loadBundle(SIM);
    expect(bundleReport(b)).toEqual([
      `ok weekly weekly-sim-2024-w15 (bundle ${b.sha256.slice(0, 12)}): 51 rows in teams, games, game_predictions, score_distributions, source_status; QA passed`
    ]);
  });

  it("turns each QA failure into a GitHub warning, because a QA-failed bundle is still stored (as qa_failed)", () => {
    const b = loadBundle(SIM);
    const failed = { ...b, manifest: { ...b.manifest, qa: { ok: false, failures: ["games: not in the schedule: X", "two\nlines"] } } };
    expect(bundleReport(failed)).toEqual([
      `ok weekly weekly-sim-2024-w15 (bundle ${b.sha256.slice(0, 12)}): 51 rows in teams, games, game_predictions, score_distributions, source_status; QA FAILED (2)`,
      "::warning title=Bundle QA::games: not in the schedule: X",
      "::warning title=Bundle QA::two lines"
    ]);
  });

  it("a tampered bundle is rejected before anything is reported", () => {
    const dir = mkdtempSync(join(tmpdir(), "check-bundle-"));
    cpSync(SIM, dir, { recursive: true });
    const games = join(dir, "games.json");
    writeFileSync(games, readFileSync(games, "utf8").replace('"home_score":6', '"home_score":7'));
    expect(() => loadBundle(dir)).toThrow(BundleRejected);
    expect(() => loadBundle(dir)).toThrow("games.json: sha256 does not match the manifest");
  });
});
```

- [ ] **Step 2: Run them and watch them fail.**
  - `Rscript -e "testthat::test_file('tests/testthat/test-workflows.R')"` → fails: `weekly-sim.yml` does not exist (the "every workflow" test passes for the four existing files and fails on `expect_true("weekly-sim.yml" %in% files)`; the other three error opening the file).
  - `cd web && npx vitest run scripts/check-bundle/report.test.ts` → fails to resolve `./report`.

- [ ] **Step 3: The check.** Create `web/scripts/check-bundle/report.ts`:

```ts
/**
 * What `npm run check-bundle` prints for a bundle the ingest accepts (A8): one summary line,
 * then each QA failure as a GitHub warning annotation. A QA-failed bundle is still
 * ingestible (it is stored as qa_failed and the publish pointer stays on the last good run),
 * so QA failures warn; only a bundle the ingest would reject fails the check.
 */
import type { LoadedBundle } from "../../src/lib/ingest/ingest";

export function bundleReport(bundle: LoadedBundle): string[] {
  const m = bundle.manifest;
  const rows = m.files.reduce((n, f) => n + f.rows, 0);
  const tables = m.files.map((f) => f.name.replace(/\.json$/, "")).join(", ");
  const qa = m.qa.ok ? "QA passed" : `QA FAILED (${m.qa.failures.length})`;
  return [
    `ok ${m.bundle_kind} ${m.cycle_id} (bundle ${bundle.sha256.slice(0, 12)}): ${rows} rows in ${tables}; ${qa}`,
    ...m.qa.failures.map((f) => `::warning title=Bundle QA::${f.replace(/\r?\n/g, " ")}`)
  ];
}
```

  Create `web/scripts/check-bundle.ts`:

```ts
/**
 * Check a bundle directory the way the ingest does, without a database (A8: the
 * weekly-sim workflow checks the simulator bundle before it uploads and ingests it).
 *   npm run check-bundle -- ../bundles/<cycle_id>
 * Exit 0 when the ingest would accept it (hashes, schema major, every row valid); QA
 * failures print as GitHub warnings (scripts/check-bundle/report.ts). Exit 1 when the
 * ingest would reject it, 2 on bad usage.
 */
import { BundleRejected, loadBundle } from "../src/lib/ingest/ingest";
import { bundleReport } from "./check-bundle/report";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: npm run check-bundle -- <bundle_dir>");
  process.exit(2);
}
try {
  for (const line of bundleReport(loadBundle(dir))) console.log(line);
} catch (e) {
  if (!(e instanceof BundleRejected)) throw e;
  console.error(`::error title=Bundle rejected::${e.message}`);
  process.exit(1);
}
```

  In `web/package.json` replace

```json
    "local:stop": "tsx scripts/local.ts stop"
```

with

```json
    "local:stop": "tsx scripts/local.ts stop",
    "check-bundle": "tsx scripts/check-bundle.ts"
```

- [ ] **Step 4: The workflow.** Create `.github/workflows/weekly-sim.yml`:

```yaml
name: Weekly simulation

# The online half of A8: the deployed app reads the same simulator bundle that the offline
# app (cd web && npm run local) reads. run_week.R writes it with R/sim_bundle.R, the web's
# own loader checks it (hashes, schema, every row), it is kept as an artifact, and it is
# ingested into the deployed database only when the DATABASE_URL secret exists. Deployment
# (Vercel, Neon) waits for the owner; until then the ingest job is skipped and says why.
# Manual only: config.R's default is 2025 week 22, and 2025 data stays sealed, so a schedule
# comes with deployment, once a week can be chosen without that default.
# tests/testthat/test-workflows.R pins the job graph, the permissions and the secret gate.

on:
  workflow_dispatch:
    inputs:
      week:
        description: "NFL week (1-22; 19-22 are the playoffs)"
        required: true
        type: string
      season:
        description: "Season (2011-2030, except the sealed 2025)"
        required: true
        type: string

permissions:
  contents: read

concurrency:
  group: weekly-sim
  cancel-in-progress: false

jobs:
  simulate:
    runs-on: ubuntu-latest
    timeout-minutes: 150
    outputs:
      bundle: ${{ steps.bundle.outputs.name }}
    steps:
      - uses: actions/checkout@v4

      - name: Refuse the sealed 2025 season
        env:
          SEASON: ${{ inputs.season }}
        run: |
          if [ "$SEASON" = "2025" ]; then echo "::error::2025 data stays sealed (owner rule; the 2025 holdout is scored once, A2)"; exit 1; fi

      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: "4.5.1"
          use-public-rspm: true

      - name: Install system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libcurl4-openssl-dev libssl-dev libxml2-dev gfortran

      - uses: r-lib/actions/setup-renv@v2

      - name: Run the weekly simulation (writes bundles/<season>-w<WW>-sim-<UTC stamp>/)
        env:
          WEEK: ${{ inputs.week }}
          SEASON: ${{ inputs.season }}
        run: Rscript run_week.R "$WEEK" "$SEASON"

      - uses: actions/setup-node@v4
        with:
          node-version-file: web/package.json
          cache: npm
          cache-dependency-path: web/package-lock.json

      - name: Install the web app
        working-directory: web
        run: npm ci

      - name: Check the bundle the way the ingest will
        id: bundle
        run: |
          dir="$(ls -d bundles/*-sim-* 2>/dev/null | sort | tail -n 1)"
          if [ -z "$dir" ]; then echo "::error::run_week.R wrote no simulator bundle"; exit 1; fi
          echo "name=$(basename "$dir")" >> "$GITHUB_OUTPUT"
          cd web && npm run check-bundle -- "../$dir"

      - uses: actions/upload-artifact@v4
        with:
          name: sim-bundle
          path: bundles/${{ steps.bundle.outputs.name }}/
          if-no-files-found: error
          retention-days: 90

  gate:
    runs-on: ubuntu-latest
    outputs:
      has_db: ${{ steps.check.outputs.has_db }}
    steps:
      - name: Is there a database to ingest into?
        id: check
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: |
          if [ -n "$DATABASE_URL" ]; then
            echo "has_db=true" >> "$GITHUB_OUTPUT"
          else
            echo "has_db=false" >> "$GITHUB_OUTPUT"
            echo "::notice::No DATABASE_URL secret: the bundle is kept as an artifact and not ingested (deployment is pending owner approval)."
          fi

  ingest:
    needs: [simulate, gate]
    if: needs.gate.outputs.has_db == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version-file: web/package.json
          cache: npm
          cache-dependency-path: web/package-lock.json

      - name: Install the web app
        working-directory: web
        run: npm ci

      - uses: actions/download-artifact@v4
        with:
          name: sim-bundle
          path: sim-bundle

      - name: Migrate, then ingest (idempotent on the bundle sha; a QA-failed run keeps the last good one published)
        working-directory: web
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: |
          npm run db:migrate
          npm run ingest -- ../sim-bundle
```

  In `web/README.md` replace

```markdown
## Run it locally (development)
```

with

```markdown
Online, the deployed app reads the same bundle: `.github/workflows/weekly-sim.yml` (started by hand with a week and season) runs `run_week.R`, checks the bundle with `npm run check-bundle` (the ingest's own loader, no database), keeps it as an artifact for 90 days, and runs `npm run ingest` against the deployed database only when the `DATABASE_URL` secret exists. Deployment is pending the owner's approval of the hosting connectors.

## Run it locally (development)
```

- [ ] **Step 5: Run the tests and watch them pass.**
  - `Rscript -e "testthat::test_file('tests/testthat/test-workflows.R')"` → `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 31 ]`.
  - `cd web && npx vitest run scripts/check-bundle/report.test.ts` → `Tests  3 passed (3)`.
  - The CLI on the fixture: `npm run check-bundle -- ../contracts/fixtures/bundles/weekly-sim-2024-w15` → `ok weekly weekly-sim-2024-w15 (bundle <12 hex>): 51 rows in teams, games, game_predictions, score_distributions, source_status; QA passed`, exit 0; with no argument → `usage: npm run check-bundle -- <bundle_dir>`, exit 2.

- [ ] **Step 6: Full gates.** Web: `npm run typecheck && npm run lint && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run` → exit 0. R: `Rscript scripts/run_tests.R` → exit 0; `Rscript scripts/verify_repo_integrity.R` → exit 0 (63/63). The workflow's first real run needs the owner (Task 10 Step 12).

- [ ] **Step 7: Commit.**

```bash
git add .github/workflows/weekly-sim.yml tests/testthat/test-workflows.R web/scripts/check-bundle.ts web/scripts/check-bundle/report.ts web/scripts/check-bundle/report.test.ts web/package.json web/README.md
git commit -F- <<'EOF'
ci: weekly-sim workflow builds, checks and keeps the simulator bundle, and ingests it only when DATABASE_URL exists (A8 online path)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 10: Close-out — every gate, the end-to-end demo, CHANGELOG, HANDOFF, draft PR

"Testing maxed" (controller ruling on the owner's 2026-10-03/04 note): R run_tests, integrity and run_matrix; web typecheck, lint and vitest with `REQUIRE_DB_TESTS=1`; the full Playwright suite with the offline spec and the probability-match test; axe on every page at 390/768/1440 in both themes; Lighthouse on home, game and evidence, desktop and mobile; the end-to-end demo with screenshots of every page. Quote every result in the PR and in HANDOFF.md; a failure is reported, not hidden.

**Files:**
- Modify: `CHANGELOG.md` (new top section under `## [Unreleased]`), `HANDOFF.md` (new current-state section)
- Scratch only (never committed): `<scratch>/lighthouse.mjs`, screenshots, Lighthouse JSON, logs. Restore `artifacts/baseline_games.csv` and `artifacts/baseline_props.csv` after the demo (audit H2: every run rewrites them).

- [ ] **Step 1: Free ports, clean state.** `netstat -ano | grep -E ":3000 |:3100 " | grep LISTEN` must print nothing; if a `node.exe … next start` from an earlier run holds a port, stop that process (`Get-CimInstance Win32_Process -Filter "ProcessId=<pid>"` first to see its command line). In the dry run two stale servers on :3000/:3100 made the first e2e run hit an old build and fail 45 tests with `Refused to apply style … MIME type ('text/plain')`; after stopping them every test passed. `git status` is clean apart from gitignored files.

- [ ] **Step 2: R gates.**
  - `Rscript scripts/run_tests.R` → exit 0, `failed=0 errors=0 unapproved_skips=0` (dry run: `tests=407 passed=1589 failed=0 errors=0 skipped=1 unapproved_skips=0`; the one skip is the allowlisted `KNOWN-DEFECT P13`).
  - `Rscript scripts/verify_repo_integrity.R` → exit 0, `Total: 63 passed, 0 failed`.
  - `Rscript scripts/run_matrix.R` → 11 artifacts. Expected: 10 pass; `golden-master` (compare against the committed `reports/2026-09-29/golden-master/2024-w15`) is reported as it is: in the dry run it FAILED identically on `main` and on A8 (live nflverse inputs drifted since 2026-09-29, the M20 input-drift problem that Plan 1b-1's golden-master commits address), while A8's own attribution (Task 7 Steps 0 and 9) showed no differences. A8 does not change the golden master's inputs, so it does not re-record it; re-recording is Plan 1b-1's (or the owner's) call. Record the matrix table verbatim.

- [ ] **Step 3: Web unit and integration gates** (scratch PostgreSQL from Setup S3):

```bash
cd web
npm run typecheck && npm run lint
npm run contracts:export && git diff --exit-code -- ../contracts/schema
TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run
```

  Expected: exit 0 each; `contracts/schema` unchanged; vitest `Test Files  15 passed (15)`, `Tests  106 passed (106)` (dry run).

- [ ] **Step 4: Playwright on the fixtures, as CI runs it** (server on :3100; secrets generated in the shell, never printed):

```bash
cd web
PGBIN="C:/Program Files/PostgreSQL/17/bin"
"$PGBIN/dropdb.exe" -h 127.0.0.1 -p 5436 -U ci --if-exists nfl_ci
"$PGBIN/createdb.exe" -h 127.0.0.1 -p 5436 -U ci nfl_ci
export DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_ci NEXT_TELEMETRY_DISABLED=1 E2E_BASE_URL=http://127.0.0.1:3100
export DESK_EMAIL=desk@example.test
export DESK_PASSWORD="$(node -e "process.stdout.write(require('crypto').randomBytes(24).toString('base64'))")"
export AUTH_SECRET="$(node -e "process.stdout.write(require('crypto').randomBytes(32).toString('base64'))")"
npm run db:migrate
npm run ingest -- ../contracts/fixtures/bundles/weekly-2026-w04
npm run ingest -- ../contracts/fixtures/bundles/backtest-nfl-games-v1
npm run seed:user
npm run build
node node_modules/next/dist/bin/next start -H 127.0.0.1 -p 3100 > <scratch>/next3100.log 2>&1 &
for i in $(seq 1 60); do curl -fsS -o /dev/null http://127.0.0.1:3100/login && break; sleep 1; done
npx playwright test --grep-invert @sim
npm run ingest -- ../contracts/fixtures/bundles/weekly-sim-2024-w15
npx playwright test --grep @sim
npx playwright test e2e/offline.spec.ts
mkdir -p <scratch>/shots-fixture
BASE=http://127.0.0.1:3100 OUT=<scratch>/shots-fixture GAME=2024_15_LA_SF node scripts/review-ui.mjs
```

  Expected (dry run, 2026-10-03): `70 passed` (axe/overflow/console on 7 public pages and `/desk` at 390/768/1440 × light/dark, desk auth, stakes never public, ID leaks, reduced motion, security headers, offline); then `11 passed` for `@sim` (home field summaries; market `pct(p, 1)` and simulator `pct(p, 1)` on all three game pages equal the bundle's `p_home_mkt_novig` and C3 `p_home_final`; both distribution figures with full table views; 390/768/1440 × light/dark with no overflow and no serious axe issue); `1 passed` offline on the simulator run; `review-ui.mjs` prints 48 rows, every one with overflow 0, errors 0, no serious axe rule and no leak. Stop the :3100 server afterwards (`kill %1`).

- [ ] **Step 5: The end-to-end demo, R side.**
  - `Rscript run_week.R 15 2024` (network; ~15 minutes with props). Expected at the end: `Web bundle: bundles/2024-w15-sim-<UTC stamp>`, `QA: passed`, `View it offline: cd web && npm run local   (then open http://127.0.0.1:3000)`, `ANALYSIS COMPLETE`, exit 0; no browser opens and no `NFLvsmarket_report.html` or `artifacts/baseline_report.html` appears (`ls *.html artifacts/*.html` → no such file).
  - `npm run check-bundle -- ../bundles/2024-w15-sim-<UTC stamp>` (in `web/`) → `ok weekly … 116 rows …; QA passed` (dry run: 16 games × 2 candidates, 32 distributions, 32 teams, 4 sources).
  - `Rscript scripts/write_backtest_bundle.R` → `bundle 07b2495f… -> bundles/backtest-nfl-games-v1-7244a0bc (qa ok: TRUE)`.
  - `git checkout -- artifacts/baseline_games.csv artifacts/baseline_props.csv` (run outputs, audit H2), then `git status` clean.

- [ ] **Step 6: The end-to-end demo, offline app.** `cd web && npm run local` in its own terminal (or in the background with output to `<scratch>/local.log`). Expected on a first start: `created a local PostgreSQL cluster in …\.local\pgdata`, `web/.env.local: added DATABASE_URL and AUTH_SECRET` (or a note that it keeps its own `DATABASE_URL`), `PostgreSQL started on 127.0.0.1:5434`, `created database nfl_local`, `migrations applied`, `published  2024-w15-sim-…`, `published  backtest-nfl-games-v1-7244a0bc`, no "no … published yet" hint, `the build is current` (or one `next build`), `Broadcast Line, offline: http://127.0.0.1:3000`. A second `npm run local` after Ctrl+C prints `PostgreSQL already running`, `duplicate` for both bundles and serves the same run.

- [ ] **Step 7: The owner's probability test on the real run, and offline rendering** (with `npm run local` serving):

```bash
cd web
BUNDLE="C:/Users/jviol/Downloads/nfl-worktrees/a8/bundles/$(ls ../bundles | grep -- '-sim-' | sort | tail -1)"
E2E_BASE_URL=http://127.0.0.1:3000 E2E_SIM_BUNDLE="$BUNDLE" npx playwright test --grep @sim
E2E_BASE_URL=http://127.0.0.1:3000 npx playwright test e2e/offline.spec.ts
```

  Expected (dry run on the 2024 week-15 bundle): `24 passed` (home summaries for 16 games; 16 game pages whose market and simulator numbers equal the bundle's at one decimal; the distributions; 6 layout/axe runs) and `1 passed` offline.

- [ ] **Step 8: Screenshots of every page, axe at 390/768/1440 in both themes, on the real run.** Seed a desk user into the local database (password generated, never printed) and run the review tool:

```bash
cd web
export DATABASE_URL="$(node -e "const c=require('../.local/pgdata/nfl_local_credentials.json');process.stdout.write('postgres://'+c.user+':'+encodeURIComponent(c.password)+'@127.0.0.1:5434/nfl_local')")"
export DESK_EMAIL=desk@example.test
export DESK_PASSWORD="$(node -e "process.stdout.write(require('crypto').randomBytes(24).toString('base64'))")"
npm run seed:user
mkdir -p <scratch>/shots-local
BASE=http://127.0.0.1:3000 OUT=<scratch>/shots-local GAME=2024_15_KC_CLE node scripts/review-ui.mjs
```

  Expected: 48 rows (home, evidence, methodology, data-health, props, the KC at CLE game, login, desk × 390/768/1440 × light/dark), every one with overflow 0, errors 0, no serious axe rule, no leak (dry run: all clean). Then look at the screenshots yourself (spec §6 makes that part of the gate): every page has the wide Archivo title, cards on the surface token, 44px chips, the scrimmage-blue market and first-down-gold simulator lines, the distributions with labelled median and result, and the night-game and press-box themes; compare the game page with `Game.dc.html` (one series here: no spread or total price is stored, so no market marker).

- [ ] **Step 9: Lighthouse on home, game and evidence, desktop and mobile** (against :3000; Lighthouse 13.5.0 as on 2026-09-30, with Playwright's Chromium):

```bash
OUT=<scratch>/lighthouse; mkdir -p "$OUT"
CHROME="$(ls -d "$HOME"/AppData/Local/ms-playwright/chromium-*/chrome-win*/chrome.exe | sort | tail -1)"
for page in "/" "/games/2024_15_KC_CLE" "/evidence"; do
  slug=$(echo "$page" | sed 's#^/$#home#; s#^/##; s#/#_#g')
  for form in mobile desktop; do
    preset=""; [ "$form" = desktop ] && preset="--preset=desktop"
    CHROME_PATH="$CHROME" npx -y lighthouse@13.5.0 "http://127.0.0.1:3000$page" $preset --quiet \
      --only-categories=performance,accessibility,best-practices --chrome-flags="--headless=new --no-sandbox" \
      --output=json --output-path="$OUT/${slug}.${form}.json"
  done
done
node <scratch>/lighthouse.mjs "$OUT"
```

  `<scratch>/lighthouse.mjs` (summary and the spec §6 gates: accessibility ≥ 0.95, performance ≥ 0.8, CLS < 0.1, LCP < 2.5 s):

```js
// Lighthouse summary for the A8 close-out: node lighthouse.mjs <dir with *.json reports>
// Gates (spec §6, P7): accessibility >= 0.95, performance >= 0.8, CLS < 0.1, LCP < 2.5 s.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2];
let failed = 0;
console.log(`${"report".padEnd(34)} ${"lh".padEnd(7)} ${"a11y".padStart(5)} ${"perf".padStart(5)} ${"CLS".padStart(7)} ${"LCP s".padStart(6)}  gates`);
for (const f of readdirSync(dir).filter((n) => n.endsWith(".json")).sort()) {
  const r = JSON.parse(readFileSync(join(dir, f), "utf8"));
  const a11y = r.categories.accessibility.score;
  const perf = r.categories.performance.score;
  const cls = r.audits["cumulative-layout-shift"].numericValue;
  const lcp = r.audits["largest-contentful-paint"].numericValue / 1000;
  const ok = a11y >= 0.95 && perf >= 0.8 && cls < 0.1 && lcp < 2.5;
  if (!ok) failed += 1;
  console.log(`${f.padEnd(34)} ${r.lighthouseVersion.padEnd(7)} ${a11y.toFixed(2).padStart(5)} ${perf.toFixed(2).padStart(5)} ${cls.toFixed(3).padStart(7)} ${lcp.toFixed(2).padStart(6)}  ${ok ? "PASS" : "FAIL"}`);
}
process.exit(failed ? 1 : 0);
```

  Expected from the dry run (record yours, pass or fail, in the PR and HANDOFF): desktop passes on all three (a11y 1.00, perf 0.99–1.00, CLS 0.000, LCP 0.72–0.90 s); accessibility 1.00 and CLS 0.000 everywhere; mobile performance fails the gate on this machine (perf 0.74–0.80, LCP 2.82–3.26 s, TBT 630–800 ms of chart and React hydration; Lighthouse warns the CPU is slower than it expects). The same mobile LCP shortfall was recorded before A8 (2026-09-30: evidence 2.94 s, game 2.62 s) and is spec §6 P7 work, not an A8 regression; report it as an open item for the owner, with CI or a reference machine to confirm.

- [ ] **Step 10: Stop the offline app.** Ctrl+C the web server, then `cd web && npm run local:stop` → `PostgreSQL stopped`. Stop the scratch test cluster if Setup S3 created it (`pg_ctl stop -D <scratch>/pg-test -m fast`).

- [ ] **Step 11: CHANGELOG and HANDOFF.** Insert under `## [Unreleased]` in `CHANGELOG.md`, above the M19 section:

```markdown
### A8: the HTML report is retired; the Next.js app is the only UI, offline and online (owner decisions 2026-10-01, 2026-10-03, 2026-10-04)

- **Offline:** `run_week.R` writes a weekly bundle (`R/sim_bundle.R`: C0 market and C3 simulator win probabilities, margin and total distributions over the central 99.9% of draws, source status; every problem is a QA failure, a game without a market keeps NA market fields). `cd web && npm run local` creates a private loopback PostgreSQL, ingests every bundle and serves the app on 127.0.0.1:3000 with no network; Archivo is committed (`next/font/local`), so a build needs no network either.
- **Online:** `.github/workflows/weekly-sim.yml` runs the same `run_week.R`, checks the bundle with the ingest's loader (`npm run check-bundle`), keeps it as an artifact and ingests it only when the `DATABASE_URL` secret exists. Deployment waits for the owner.
- **Pages:** the field shows the simulator (labelled unvalidated) when the published run carries it; the game page draws the margin and total distributions with summaries and table views; evidence, methodology, data health, props, login, desk and not-found carry the Broadcast Line design.
- **Removed:** `export_moneyline_comparison_html`, `open_moneyline_report`, `moneyline_report`, the report schema validator, `R/report_banner.R`, the `NFLsimulation.R` fallback exporter and reactable slate table, three test files, and six display-label greps in `scripts/audit_verify.sh`. A call-graph check found no remaining reference; `build_moneyline_comparison_table` and the CSV exports stay. Golden master: A8 against a same-day base recording, "no differences"; the committed 2026-09-29 recording no longer matches `main` either (live nflverse drift).
- **Gates** (the dry run's numbers; write the ones you measured in Steps 2–9 if they differ): `run_tests.R` 407 tests, 1589 passed, 0 failed, 1 allowlisted skip; integrity 63/63; `run_matrix` 10/11 (golden-master against the drifted committed recording, failing on `main` too); vitest 15 files, 106 tests with the pg suites; Playwright 70 (fixtures) + 11 (`@sim` fixture) + 24 (`@sim` on the 2024 week-15 run) + offline on both; axe/overflow clean on 48 + 48 page views (390/768/1440, both themes); Lighthouse desktop pass on home, game and evidence, mobile performance below the gate (LCP 2.8–3.3 s, open P7 item).
- **For the owner:** removal candidates `gt` and `scales` (`DESCRIPTION` Imports; nothing calls them now), `htmltools` stays as a dependency of other packages; the weekly-sim workflow needs a first manual run, and a `DATABASE_URL` secret once Vercel/Neon are approved.
```

  In `HANDOFF.md`, add above `## Current state — 2026-09-30, session 3` a section `## Current state — A8 (feat/a8-local-app)`, dated the day you finish, with: the branch and PR, the task list with commit shas, the gate results from Steps 2–9 verbatim, the open items (mobile Lighthouse; the committed golden master's input drift; owner actions below), and the context-reset packet fields (objective · done · not done · confirmed facts · open risks · next target).

- [ ] **Step 12: Owner actions (list them in the PR body).**
  - Merge approval (and the order relative to Plan 1b-1; Task 7 Step 8 shows a clean merge).
  - Removing `gt`/`scales` from `DESCRIPTION` and `renv.lock` (dependency change; not done here).
  - Deployment: authorize Vercel/Neon, then add the `DATABASE_URL` secret; until then `weekly-sim.yml` keeps the bundle as an artifact and its `ingest` job is skipped with a notice.
  - The workflow's first run: after the PR merges, `gh workflow run weekly-sim.yml -f week=15 -f season=2024` exercises everything up to the ingest (a run on a feature branch needs the workflow on the default branch first).
  - Mobile Lighthouse performance (P7) and re-recording the committed golden master (input drift) are open.

- [ ] **Step 13: Commit, push, draft PR.**

```bash
git add CHANGELOG.md HANDOFF.md
git commit -F- <<'EOF'
docs: A8 close-out (CHANGELOG, HANDOFF) with the gate results

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git push -u origin feat/a8-local-app
gh pr create --draft --base main --head feat/a8-local-app --title "A8: retire the HTML report; the Next.js app is the only UI, offline and online" --body-file <scratch>/a8-pr-body.md
```

  `<scratch>/a8-pr-body.md`: the goal (one paragraph), the task list with commit shas, the call-graph table, the golden-master attribution, every gate result from Steps 2–9 verbatim, the screenshots' location, the owner actions from Step 12, ending with the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Do not merge.

---

## Dry run (2026-10-03/04, throwaway worktree `C:/Users/jviol/Downloads/nfl-worktrees/a8dry`, base `4f9aad3`, uncommitted)

**The worktree matches this plan exactly.** The plan is generated from its parts by a scratch script that also applies every replace/append/whole-file step above, in task order, to the files at `4f9aad3` and compares each result with a8dry byte for byte: `every planned file equals a8dry` (58 files, 108 file operations) and `every a8dry change is in the plan`. The Task 7 cut tool, run on fresh copies of `NFLmarket.R` and `NFLsimulation.R` from `4f9aad3`, reproduces a8dry's two engine files byte for byte (`NFLmarket.R: 10 cuts, 2215 lines removed, 6 inserted`; `NFLsimulation.R: 9 cuts, 1058 lines removed, 13 inserted`). The fixture tables' sha256 equal Task 3 Step 5's list.

**What the previous planner's draft got wrong or left out, now fixed in the plan and in a8dry:**
- `scripts/audit_verify.sh` (CI job `audit-verify`) grepped six labels that lived only in the deleted exporter; CI would have failed. Fixed, with a test that every remaining anchor matches (red with the old script: `[ FAIL 6 | ... ]`).
- The fixture e2e did not cover 768px, and the offline spec visited only home and a game page; both now cover the owner's widths and every public page.
- CI never ran the `@sim` spec, and the main e2e run would have run it against the wrong run; `ci-web.yml` now runs `--grep-invert @sim`, then ingests the simulator fixture and runs `--grep @sim`.
- `npm run local`'s "nothing published" hints now come from the database's publish pointers (the cluster keeps earlier sessions' runs), not from the folder.
- A game without a kickoff time was filled with 1:00 PM ET silently; `source_status` now names it. A run whose draws were not exported now writes a QA-failed bundle instead of erroring (`get0(...)` in `run_week.R`).
- The not-found page and the home page's empty state kept the old look; `designLanguage.test.ts` now guards every page.
- No docs were updated; Task 8 does it. Two stale roxygen lines in `NFLmarket.R` pointed at the deleted renderer.
- The draft left `artifacts/baseline_*.csv` rewritten by its run; they are restored (audit H2) and the close-out says so.
- Added for the owner's 2026-10-03/04 note: `weekly-sim.yml`, `npm run check-bundle`, the workflow tests, Lighthouse and `run_matrix` in the close-out.

**Gates the controller asked for (final a8dry state):**

| Gate | Result |
|---|---|
| `Rscript scripts/run_tests.R` | exit 0, `tests=407 passed=1589 failed=0 errors=0 skipped=1 unapproved_skips=0` (the skip is the allowlisted `KNOWN-DEFECT P13`) |
| `Rscript scripts/verify_repo_integrity.R` | exit 0, `Schema Checks: 19 passed, 0 failed`, `Invariant Checks: 44 passed, 0 failed`, `Total: 63 passed, 0 failed` |
| `npm run typecheck` | exit 0 |
| `npm run lint` | exit 0 |
| `npx vitest run` (`REQUIRE_DB_TESTS=1`, `TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test`) | exit 0, `Test Files  15 passed (15)`, `Tests  106 passed (106)` |
| `npm run contracts:export` then `git diff -- contracts/schema` | no drift |

Baseline at `4f9aad3` (same machine, same day): `tests=394 passed=1502 failed=0 errors=0 skipped=1`, integrity `60 passed`.

**Close-out gates, also run in the dry run (Task 10 plans them precisely):**

| Gate | Result |
|---|---|
| `Rscript scripts/run_matrix.R` | 11 artifacts: 10 PASS (`sim-bundle` PASS: `fixture … (qa ok: TRUE)`), `golden-master` FAIL against the committed recording. The same comparison on untouched `main` (`4f9aad3`) fails identically (10 games, `home_p_2w_blend` max 0.009364088, `margin_blend` max 0.293353978): live nflverse drift, not A8. |
| Golden master, A8 attribution | a8dry vs a base recording from the same day: `golden master: no differences` |
| Playwright on the fixtures (:3100) | `70 passed` with `--grep-invert @sim`; `11 passed` with `--grep @sim` after ingesting the simulator fixture; offline spec `1 passed` on the simulator run |
| Playwright on the real `run_week.R` bundle via `npm run local` (:3000) | `24 passed` (`E2E_SIM_BUNDLE=bundles/2024-w15-sim-20261003T174900Z`: market and simulator probabilities equal the bundle at the displayed precision on all 16 game pages and in every field summary); offline `1 passed` |
| `npm run local` | first start created the cluster, migrated, `published  2024-w15-sim-20261003T174900Z`, `published  backtest-nfl-games-v1-7244a0bc`, served on 127.0.0.1:3000 |
| Screenshots + axe, 390/768/1440 × light/dark (`review-ui.mjs`) | fixture run: 48 rows, all overflow 0, console errors 0, no serious/critical axe rule, no leaks; real run (`GAME=2024_15_KC_CLE`): 48 rows, all clean. Reviewed by eye: game page (both themes), evidence, login at 390. |
| Lighthouse 13.5.0 (:3000) | desktop PASS on home (perf 1.00, LCP 0.81 s), game (0.99, 0.90 s), evidence (1.00, 0.72 s); accessibility 1.00 and CLS 0.000 on all six; **mobile FAIL** on performance: home 0.74 / LCP 3.16 s, game 0.74 / 3.26 s, evidence 0.80 / 2.82 s (TBT 630–800 ms; Lighthouse warns of a slow CPU). Pre-existing (2026-09-30: evidence 2.94 s, game 2.62 s); open P7 item for the owner. |
| `npx next build` behind a dead proxy | exit 0 with the committed font; exit 1 (`Failed to fetch Archivo from Google Fonts.`) with the old layout |
| `npm run check-bundle` | fixture: `51 rows … QA passed`; real run: `116 rows … QA passed`; no argument: exit 2 |
| `test-workflows.R` | `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 31 ]` |
| Plan 1b-1 merge probe | `git merge-file` of a8dry's `NFLsimulation.R` with the 1b-1 worktree's: `conflicts=0`, `saveRDS(mu_terms, ...)` kept after `saveRDS(games_ready, ...)` |

**Pending, recorded honestly:** the `weekly-sim.yml` workflow has not run on GitHub (it needs the branch pushed and, for its first manual run, the workflow on the default branch); its YAML parses, its job graph, permissions and secret gate are pinned by `test-workflows.R`, and its bundle step is the same `run_week.R` → `write_sim_bundle()` path the offline run exercised. The ingest job is untested against a deployed database because none exists yet.

## Self-review

- **Spec coverage:** §3 bundle/ingest/publish pointer → Tasks 3, 2, 9; §4 design system, charts, pages → Tasks 4, 5, 6; §5 Phase 8 A8 deletion → Task 7, docs → Task 8; §6 gates → every task's gates and Task 10; owner 2026-10-03 probabilities → Task 4 (`simRun.test.ts`, `sim-bundle.spec.ts`) and Task 10 Step 7; owner 2026-10-03 UI/UX ruling → Task 6 and Task 10 Step 8; owner 2026-10-03/04 offline+online and testing → Tasks 2, 9, 10.
- **Placeholders:** none; every code step carries the code the dry run tested.
- **Names across tasks:** `publicFieldLine(gates, available)`, `runCandidates`, `gameDistributions`, `parseBins`, `ScoreDistributionChart`, `write_sim_bundle`, `report_sim_bundle`, `sb_git_state`, `missingPointers`, `bundleReport`, `chipClass`/`PageTitle`/`StatTile` are defined where first used and used with the same signatures later.
- **Review Focus:** each of the five items has its test in the owning task (Tasks 3, 3, 2, 5, 1).

## Execution

Subagent-driven, as the controller decided: one implementer and one reviewer per task, in order (Tasks 1–10; Tasks 1, 2 and 3 are independent, Task 4 needs Task 3's fixture, Task 5 needs Task 4, Tasks 6–9 need Task 5's game page only for the full gates). Stop and ask the owner before merging, before any dependency removal, and if any golden-master comparison in Task 7 is not "no differences".

