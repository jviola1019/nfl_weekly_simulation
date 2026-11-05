# Verification sweep, 2026-11-05

**Status: every gate passes.** The findings below are recorded, not changed.

**The ask** (owner, 2026-11-05): "full app verifications (Playwright,etc.) and do not skip anything. Architectures, ERDs, documentation should be verified."

**The commit verified:** `4ece613`, the head of #240.
- It is main (`85fd35a`, after #239) with #240's documentation merged in. Merging #240 unchanged gives main this exact tree.
- `run_week.R` ran on `85fd35a`. Outside markdown, #240 changes only `tests/testthat/test-docs-truth.R` and `web/src/lib/erd.ts`, and `run_week.R` reads neither.

## Gates

| Gate | Where | Result |
|---|---|---|
| Integrity: `Rscript scripts/verify_repo_integrity.R` | local, fresh HOME | 63 passed, 0 failed |
| R tests: `Rscript scripts/run_tests.R` | local, fresh HOME | 920 tests; 4,149 passed, 0 failed, 0 errors, 0 skipped |
| Artifact matrix: `Rscript scripts/run_matrix.R` | local | 11 of 11 pass |
| Golden master, 2024 week 15 (inside the matrix) | local | "golden master: no differences" against the `league` reference #239 recorded from CI; data quality HIGH, every source FULL |
| Weekly run: `Rscript run_week.R`, no arguments | local, fresh HOME | "Auto-resolved 2026 week 9 (15 games, first kickoff Thu 2026-11-05 20:15 ET)"; "QA: passed" |
| Web: typecheck, lint, contract drift, unit and Postgres tests, build | CI `web` | every step passes; 35 of 35 test files |
| Playwright on the fixtures | CI `web` | 112 passed: axe, overflow, headers, desk auth, stakes never public, ID leaks, reduced motion, offline |
| Playwright `@sim` on the fixture run | CI `web` | 11 passed |
| Pixel parity, offline against online | CI `parity` | 60 passed offline and 60 online: zero differing pixels |
| Playwright on the real week 9 run, against `npm run local` | local | 135 passed, 0 failed, 0 skipped (2.2 minutes); `@sim` checked all 15 games against the bundle |
| Every page, read and drawn (`app_shots.mjs`) | local | 21 pages, plus 3 at phone width or in the dark theme: all HTTP 200, 0 console errors, 32 of 32 charts drawn |
| SQL data checks: `npm run db-check` | local, after the ingest | 18 checks, 0 errors, 0 warnings |
| ERD: `npm run erd -- --check` | local | "docs/ERD.md matches the schema" |
| Docs truth: `test-docs-truth.R` | in the R tests | passes; since #240 it covers every current document |

**Lighthouse 13.5.0 mobile** (its default emulation and simulated throttling; local app; median of 3 runs a page):

| Page | Performance | Accessibility | Best practices | LCP (s) | CLS | TBT (ms) |
|---|---|---|---|---|---|---|
| Home | 91 | 100 | 100 | 2.74 | 0 | 262 |
| Game (NYJ at KC) | 93 | 100 | 100 | 2.77 | 0 | 174 |
| Props | 98 | 100 | 100 | 1.98 | 0 | 123 |
| Evidence | 87 | 100 | 100 | 2.80 | 0 | 379 |
| Methodology | 94 | 100 | 100 | 2.58 | 0 | 194 |
| Data health | 93 | 100 | 100 | 2.64 | 0 | 238 |

## Output audit: 2026 week 9

The run is `2026-w09-sim-20261105T205729Z`: code `85fd35a`, data as of 2026-11-05 20:57 UTC, 20.5 minutes.

- **Inputs:**
  - data quality HIGH;
  - injuries, weather and market data FULL;
  - calibration "spline (DIAGNOSTIC ONLY)", as documented (audit M4).
- **Home field:** "league estimator (league 1.67 points, results before 2026 week 9)".
- **Quarterbacks:** one adjustment, for BAL's starter: OUT, backup quality 0.35, −6.2 points.
- **Probabilities:**
  - There are 30 rows: the market (C0) and the simulator (C3) for 15 games. All are inside (0, 1).
  - The simulator's published value is within 0.023 of the no-vig market everywhere. The largest gap is TB at CHI: 0.695 against 0.718.
  - No game has a different favourite.
- **Before the market weight,** the simulator differs most on:
  - NYJ at KC: 0.579 against 0.817;
  - TB at CHI: 0.553 against 0.718;
  - DET at MIA: 0.373 against 0.252.
- **Margins and totals:** no gap is above 10 points between the raw simulation's medians and the market's lines.
  - The largest margin gap is NYJ at KC: KC by 2 against KC by 10.
  - The largest total gaps are where the market's total is low:
    - JAX at BAL: 49 against 39.5;
    - NYG at PHI: 46 against 38.5;
    - ARI at SEA: 46 against 39.5.
- **Props:**
  - 606 rows, every one priced from the model's own lines: "PROP_REQUIRE_MARKET_ODDS=TRUE but no market odds found; retaining model rows". None has a positive EV.
  - /props shows every market "Not priced".
- **Warnings:**
  - package build-version notes;
  - the known `collapse_by_keys_relaxed` note: the backtest per-game table has no `game_type` column.

## Findings (recorded, not changed)

| # | Finding | Evidence | Where it belongs |
|---|---|---|---|
| F1 | **A game page shows two simulator numbers that disagree.** Its margin chart is the raw simulation, while its "Simulator" moneyline is the value after the 70% market weight. Only the moneyline explains the weight. | NYJ at KC: median KC by 2 (about 58%) beside "Simulator 81.4%" | B5 (a design for each tab), or a copy fix |
| F2 | **The published value can sit outside both the raw simulation and the market.** The shrink is a weighted average with the market, so the value before it was already above both: the blend steps before the shrink produce it. | LV at SF: 0.822 published, against 0.728 raw and 0.804 market | Audit M8 (train/serve skew); G2 |
| F3 | **Simulated totals sit high where the market's total is low.** | The three lowest market totals (39.5, 39.5, 38.5): the simulation is 6.5 to 9.5 points higher. This is one week. | A3 S5 (the bias of the total errors) |
| F4 | **The weekly run prices no prop from a market.** The dispatcher captures Kalshi, Pinnacle and Smarkets props each snapshot, but `run_week.R` does not read them. | 606 rows from model lines; 0 with positive EV | The props design, #238 |
| F5 | **LCP is above 2.5 s on five of six pages** (median of 3 local runs). B2 shipped with the owner's acceptance of two pages over the gate. | 2.58 to 2.80 s; props 1.98 s | B3/B5 performance |
| F6 | **`scripts/verify_requirements.R` skips two checks for functions that no longer exist:** `get_default_weather_conditions` and `check_injury_availability`. | 28 passed, 0 failed, 2 skipped | Track X (cleanup) |

## Architecture, ERD and documentation

- **#240:**
  - rewrote `docs/ARCHITECTURE.md` and `DOCUMENTATION.md` from the code;
  - fixed `docs/modeling.md` and `docs/ERD.md`;
  - widened the docs-truth guard to every current document. The guard failed on its findings before the fixes.
- **The checks on this commit:**
  - the ERD check passes;
  - the docs-truth tests pass;
  - #240's CI (`web`, `parity`, `audit-verify`, `lint-and-check`) passes.

## Reproduce

```bash
# R, from a worktree at 4ece613 with a fresh HOME
Rscript scripts/verify_repo_integrity.R
Rscript scripts/run_tests.R
Rscript scripts/run_matrix.R
Rscript run_week.R                      # no arguments: the week comes from the schedule

# web
cd web && npm run local                 # ingests every bundle, runs db-check, serves http://127.0.0.1:3000
npm run db-check && npm run erd -- --check
E2E_BASE_URL=http://127.0.0.1:3000 E2E_SIM_BUNDLE=<bundle dir> npx playwright test --grep-invert @parity
npx -y lighthouse@13.5.0 http://127.0.0.1:3000/ --only-categories=performance,accessibility,best-practices
```

Playwright on the real run needs a desk user in the local database (`npm run seed:user` with `DESK_EMAIL` and `DESK_PASSWORD`).
