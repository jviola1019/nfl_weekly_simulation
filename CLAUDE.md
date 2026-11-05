# NFL Prediction Model - Claude Code Agent Guide

**This file is the SINGLE SOURCE OF TRUTH for how Claude Code should operate in this repository.**

---

## 1. REPO CONTEXT

### What This Project Does

An NFL game prediction model using Monte Carlo simulation with:
- Negative Binomial score distributions with Gaussian copula correlation
- Spline calibration (calibrator currently invalid, audit M4; disabled in Phase 1)
- 70% market shrinkage for probability estimates (increased from 60% when spline calibration unavailable)
- 1/8 Kelly staking with edge skepticism
- Strength-of-schedule and injury adjustments (computed and logged, but not part of the simulated means until admitted in Plan 1b-3 via `MU_TERMS_ADMITTED`)
- **Player props correlated with game simulation outcomes (v2.9.0)**
- **Vigged model moneylines matching market juice (~10%)**
- **v2.9.1 Audit Fixes**: Roster exclusivity, CV-scaled SD, scoring TD separation, hybrid win probability, EV tier system

### Primary Entrypoints

| File | Purpose | Run Command |
|------|---------|-------------|
| `run_week.R` | Weekly predictions | `Rscript run_week.R` (the upcoming week) or `Rscript run_week.R <week> <season>` |
| `config.R` | Configuration | `SEASON` and `WEEK_TO_SIM` auto-resolve from the calendar; pass a week and season to `run_week.R` instead of editing them |
| `scripts/run_tests.R` | Test suite + skip policy | `Rscript scripts/run_tests.R` |
| `scripts/verify_repo_integrity.R` | Integrity check | `Rscript scripts/verify_repo_integrity.R` |
| `scripts/run_matrix.R` | Run all artifacts | `Rscript scripts/run_matrix.R` |
| `web/scripts/local.ts` | Offline results viewer (the local app) | `cd web && npm run local` |

### Player Props Module (v2.9.0)

| File | Purpose |
|------|---------|
| `R/correlated_props.R` | Gaussian copula correlation engine |
| `sports/nfl/props/props_config.R` | Prop-specific hyperparameters |
| `sports/nfl/props/data_sources.R` | Player data loading with fallback chain |
| `sports/nfl/props/*.R` | Position-specific simulations |

**Correlation Model** (current config values, unvalidated, see docs/EVIDENCE_LEDGER.md):
- Player props are correlated with game simulation outcomes
- Uses Gaussian copula to link player stats to game totals
- Same random seed ensures consistency across simulation

**Hyperparameters** (current config values, unvalidated, see docs/EVIDENCE_LEDGER.md):

| Parameter | Value | Empirical Source |
|-----------|-------|------------------|
| QB passing ↔ game total | r = 0.40 | config.R (unvalidated) |
| RB rushing ↔ game total | r = 0.09 | config.R (unvalidated) |
| WR receiving ↔ team passing | r = 0.30 | config.R (unvalidated) |
| TD probability ↔ game total | r = 0.17 | config.R (unvalidated) |
| Same-team cannibalization | r = -0.15 | Player target share data |
| Model vig percentage | 10% | Industry standard |

**Key Functions**:
```r
# Generate correlated variates using Gaussian copula
generate_correlated_variates(n, rho, z_reference)

# Apply vig to model probabilities
apply_model_vig(prob, vig_pct = 0.10)  # 50% → -110

# Devig market odds
devig_american_odds(home_ml, away_ml)  # Returns true probabilities

# Load players with fallback for future seasons
get_player_projections_with_fallback(season, week, home_team, away_team)

# Run all props for a single game (passing/rushing/receiving/td)
run_game_props(game_sim, home_team, away_team, season)

# Run props across all games in simulation
run_correlated_props(game_sim_results, schedule_data, prop_types, season)

# Apply opponent defense adjustments to player projections
apply_defense_adjustments(players, home_team, away_team, season)

# Apply game context (dome, home field) to player projections
apply_game_context(players, game)
```

**Model Accuracy Benchmarks**: Withdrawn 2026-09-28; see docs/EVIDENCE_LEDGER.md.

### Expected Outputs

When `run_week.R` completes successfully:
1. **Web bundle**: `bundles/<season>-w<WW>-sim-<UTC stamp>/` with the market (C0) and simulator (C3) win probabilities, margin and total distributions, and source status (`R/sim_bundle.R`). View it offline with `cd web && npm run local` (http://127.0.0.1:3000). The HTML report was retired at checkpoint A8.
2. **Audit tables**: `artifacts/baseline_games.csv` and, when `RUN_PLAYER_PROPS`, `artifacts/baseline_props.csv`
3. **Run Logs**: `run_logs/config_*.rds`, `run_logs/final_*.rds`
4. **Console**: Data quality badge, simulation progress, calibration status, the bundle path and its QA result

### What "Correct" Looks Like

- `scripts/verify_repo_integrity.R` exits 0
- `scripts/run_matrix.R`: 11/11 artifacts pass (the golden-master artifact may SKIP as LIVE when nflverse is unreachable)
- `scripts/run_tests.R` exits 0 (skip policy enforced)
- `run_week.R`: Completes without exit code 1

---

## 2. AGENT OPERATING RULES

### ALWAYS Do This

1. **Start in READ-ONLY audit mode** - Never modify code before understanding the failure
2. **Reproduce errors before fixing** - Run the failing command first
3. **Prefer minimal diffs** - Small, reversible changes only
4. **Run verification after changes** - `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R` (both exit 0)
5. **No silent fallbacks** - Every data issue must be logged and flagged
6. **No unverifiable claims** - Don't claim metrics without running scripts
7. **Use canonical API** - Check R/data_validation.R for correct function signatures

### NEVER Do This

1. **Guess at fixes** without understanding root cause
2. **Add features** while fixing bugs
3. **Refactor** unrelated code
4. **Delete files** without verifying they're unused via run_matrix
5. **Commit untested changes**
6. **Use hardcoded values** - Put in config.R instead
7. **Use a keyed, login or challenge-protected data source** - Odds and props data are keyless only:
   - no API keys we register for, no logins and no challenge cookies;
   - a 403, captcha or geo-fence drops the venue, and is never evaded;
   - at most 1 request per second per domain, with a truthful user agent;
   - raw sportsbook payloads are never published (the repo is public).

   Endpoints are in `docs/odds-sources.md`.

### Data Quality API Reference

```r
# CORRECT status values (memorize these!)
update_injury_quality("full" | "partial" | "unavailable", missing_seasons = c(...))
update_weather_quality("full" | "partial_fallback" | "all_fallback", fallback_games = c(...))
update_market_quality("full" | "partial" | "unavailable", missing_games = c(...))
update_calibration_quality(method = "...", leakage_free = TRUE/FALSE)

# Access quality (nested structure!)
quality <- get_data_quality()
quality$injury$status      # NOT quality$injury_status
quality$weather$status     # NOT quality$weather_status
quality$market$status      # NOT quality$market_status
quality$calibration$method # NOT quality$calibration_method

# Overall quality returns uppercase
compute_overall_quality()  # Returns "HIGH", "MEDIUM", "LOW", "CRITICAL"
```

---

## 3. STANDARD AGENT PROMPTS

### Audit Agent (Use First)

```
Read only: edit nothing. Run every R gate with a fresh HOME (HOME=$(mktemp -d)): the calibration and
score caches live in ~/.cache and every checkout shares them.
1. Reproduce: Rscript run_week.R <week> <season> with
   options(error = function() { traceback(2); quit(status = 1) }), and keep the log.
2. Data first: read the data-quality badge, the bundle's source_status.json and any golden-master
   INPUT DRIFT line before blaming code. An empty nflreadr download can look like a code change.
3. Schemas: every update_*_quality() call matches R/data_validation.R (section 2).
4. Joins: game keys go through standardize_join_keys(); team joins use franchise codes (franchise_code()).
5. Silent fallbacks: a default that replaces missing data without a flag, a tryCatch that drops an
   error, suppressWarnings() around a download.
6. Look-ahead: any input that a past week's run computes from games at or after its kickoff.
Output a diagnosis, with file:line evidence for each finding, before any fix.
```

### Fix Agent (After Audit)

```
Fix the diagnosed root cause with the smallest change, test first.
1. Write the failing test (on real recorded data where possible), run it, and see it fail for the
   expected reason.
2. Change only the lines the fix needs: no refactors, no features. Stop first for anything in section 4.
3. Calibration-history code changed: bump the version in calib_cache_key() and score_cache_key().
4. Engine output changes: expect a golden-master difference, and name the commit that causes it.
5. Never edit an R script while an Rscript run is reading it; run long jobs from a frozen worktree.
6. Rscript scripts/run_tests.R and Rscript scripts/verify_repo_integrity.R, fresh HOME: both exit 0.
7. CHANGELOG.md: a dated entry with what changed, why, the test and the evidence.
```

### Validation Agent (After Fixes)

```
Re-run every gate on the commit under review, with a fresh HOME and the PC on AC power. A sleep turns
wall-clock timeouts into false failures: check Kernel-Power events 506/507 before calling a timeout
a defect.
1. Rscript scripts/run_tests.R: exit 0, no failures or errors, only skips on tests/skip_allowlist.txt.
2. Rscript scripts/verify_repo_integrity.R: exit 0.
3. Rscript scripts/run_matrix.R: 11/11 (the golden master may SKIP as LIVE offline). A golden-master
   difference needs its INPUT DRIFT lines read and a commit that explains it.
4. run_week.R or R/sim_bundle.R changed: the run prints "Web bundle: <dir>" and "QA: passed", and
   `cd web && npm run local` serves that run.
5. web/ changed: npm run typecheck, npm run lint, npm test and npm run e2e, the last also with
   E2E_SIM_BUNDLE=<a real bundle>.
6. After the push: CI green on the head (R, web, and the golden master's commit-by-commit attribution).
Report PASS or FAIL for each gate, quoting its summary line.
```

### Docs Agent (When Requested)

```
1. README.md and section 6 of this file: the file inventory matches the repo.
2. CHANGELOG.md: a dated entry for each change.
3. HANDOFF.md: the state, what is running, the open risks and the next targets, so a new session can
   resume from it.
4. CLAUDE.md: the rules and prompts match current practice.
5. Run every documented command and check every path; fix or remove what fails.
```

---

## 4. STOP / CONTINUE CHECKPOINT RULES

### STOP and Ask for Confirmation When:

1. **Deleting any file** (even if appears unused)
2. **Changing config.R defaults** (affects all users)
3. **Modifying NFLsimulation.R or NFLmarket.R** (core engine, high risk)
4. **Adding new dependencies** (affects renv.lock)
5. **Changing API signatures** in R/data_validation.R
6. **Exit code 1 persists** after first fix attempt
7. **Editing `backtest/eval_windows/*.json` or a frozen `PROTOCOL.md`** (register a new version instead)
8. **Anything that reads, builds or scores the sealed 2025 holdout.** 2025 may be model history, but it is never scored, and 2025 prices are never computed.
9. **Merging a PR**: the owner approves each merge

### Continue Automatically When:

1. Fixing obvious typos or syntax errors
2. Updating test expectations to match correct behavior
3. Adding log/debug statements
4. Updating documentation only
5. Running verification scripts
6. Creating new test files

---

## 5. COMMON FAILURE PLAYBOOK

### Exit Code 1 After Injury Loading

**Symptom**: Script crashes after "Loaded X injury records for season YYYY"

**Diagnosis**:
```r
options(error=function(){traceback(2); quit(status=1)})
source("run_week.R")
```

**Common Causes**:
1. Wrong API call: `update_injury_quality("complete")` should be `"full"`
2. Wrong parameter: `seasons_missing` should be `missing_seasons`
3. A release download that fails. nflreadr returns an empty table with only a warning, and remembers the failure for the session. `safe_load_injuries()` retries the seasons that have completed games and flags one that stays empty as "partial", with nflreadr's warning as the cause.

**Fix**: Check the `update_injury_quality()` calls in `safe_load_injuries()` (NFLsimulation.R). Then check the run's `source_status.json`.

### Invalid Week Error

**Symptom**: "No games found for Week X", or an offseason stop

**Diagnosis**: `run_week.R` with no arguments resolves the upcoming week from the nflverse schedule (`R/date_resolver.R`, `R/run_config.R`), and stops in the offseason. Pass the week and season instead: `Rscript run_week.R <week> <season>`.

**Valid Weeks**:
- Regular season: 1-18
- Wild Card: 19
- Divisional: 20
- Conference: 21
- Super Bowl: 22

### Empty Join Results

**Symptom**: `build_moneyline_comparison_table()` returns 0 rows

**Diagnosis**:
```r
# Check key types before join
str(schedule[c("game_id", "season", "week")])
str(predictions[c("game_id", "season", "week")])
```

**Fix**: Apply `standardize_join_keys()` to both tables before joining.

### lintr normalizePath("") Error

**Symptom**: VS Code R extension crashes or shows normalizePath errors

**Fix**: Ensure `.lintr` file exists and excludes problematic directories:
```
exclusions: list("renv" = Inf, "run_logs" = Inf)
```

### Web Bundle Not Written or Not Shown

**Symptom**: run_week.R completes but writes no `bundles/<cycle_id>/`, or `npm run local` shows an older run

**Diagnosis**: The end of run_week.R prints `Web bundle: <dir>` and `QA: passed` or `QA: FAILED (n)` with each failure.

**Common Causes**:
1. An earlier error stopped the run; the bundle step runs after the simulation and props
2. QA failed: the ingest stores the run as `qa_failed` and the app keeps the last good run (the failures are listed in the console and on /data-health)
3. PostgreSQL not found by `npm run local`: set `PG_BIN` to its bin directory (Windows default `C:/Program Files/PostgreSQL/17/bin`)
4. /evidence is empty: no backtest bundle; run `Rscript scripts/write_backtest_bundle.R` once

### Script Hangs After "Snap-weighted injury impacts enabled"

**Symptom**: Script stops after injury loading, shows "✓ Snap-weighted injury impacts enabled"

**Diagnosis**: Network timeout when loading snap participation data

**Root Cause**:
- `nflreadr::load_participation()` hangs when data unavailable for current season
- The function has no timeout protection

**Fix**:
```r
# Verify in config.R:
USE_SNAP_WEIGHTED_INJURIES <- FALSE  # Must be FALSE
```

**Important**: Disabling snap weighting does NOT affect model accuracy:
- Position-level injury weights remain active (unvalidated, see ledger C-POSW)
- Snap weighting had no empirical evidence of improving Brier/log-loss
- The feature was disabled in v2.6.7 as the default

### Golden-Master Difference

**Symptom**: `run_matrix.R`'s golden-master artifact, or CI's attribution, shows output columns that changed

**Diagnosis**:
1. Read the INPUT DRIFT lines first. A data change can mimic a code change: one run with injuries UNAVAILABLE looked like a defect in #223.
2. Rerun with a fresh HOME. A stale shared calibration cache once looked like a platform difference.

**Fix**: For an intended change, name the commit that causes it in the PR. Then re-record the reference from CI's artifact, with a section in `reports/2026-09-29/golden-master/2024-w15/ATTRIBUTION.md`.

### A Long Gate Fails After the PC Slept

**Symptom**: `run_matrix.R` reports a timeout for testthat or the golden master. Tool timestamps jump by hours.

**Diagnosis**: The PC uses Modern Standby: on battery it sleeps after about 3 minutes idle. The gates' limits are wall-clock time, so a sleep looks like a failure. Check Kernel-Power events 506/507 (`Get-WinEvent`) for the run's window.

**Fix**: Rerun on AC power with the lid open. Downloads cut off by a sleep leave truncated files, so write to `.part` and rename only once the file reads.

### knitr/xfun GitHub Actions Crash

**Symptom**: GitHub Actions fail with knitr or xfun namespace errors

**Fix**:
1. Run `renv::snapshot()` to capture xfun dependency
2. Verify knitr is in DESCRIPTION Imports (not just Suggests)
3. Push updated renv.lock

---

## 6. FILE INVENTORY (Quick Reference)

### Core Pipeline (DO NOT DELETE)
- `run_week.R` - Entry point
- `config.R` - Configuration
- `NFLsimulation.R` - Simulation engine (7,400+ lines)
- `NFLmarket.R` - Market analysis (2,600+ lines)
- `NFLbrier_logloss.R` - Metrics

### R/ Library (Canonical Source)
- `R/utils.R` - Core utilities (SINGLE SOURCE OF TRUTH)
- `R/data_validation.R` - Data quality tracking
- `R/logging.R` - Structured logging
- `R/playoffs.R` - Playoff logic
- `R/date_resolver.R` - Date resolution
- `R/sleeper_api.R` - Sleeper fantasy API integration
- `R/red_zone_data.R` - Red zone efficiency metrics
- `R/correlated_props.R` - Gaussian copula player props (v2.9.0)
- `R/bundle_writer.R` - R side of the R -> web data contract (validates against `contracts/schema/`)
- `R/sim_bundle.R` - the simulator's weekly bundle, written by `run_week.R` (replaced the HTML report at A8)
- `R/mu_terms.R` - explicit mean composition: the term table and `compose_mu()` (M22)
- `R/schedule_context.R` - neutral sites, home-field points and rest days (M24, M23)
- `R/run_config.R` - `run_week.R`'s arguments and the auto-resolved week (with `R/date_resolver.R`)
- `R/odds/` - the keyless odds layer (D1): `http.R` is the only HTTP code for ESPN and Kalshi (nflverse loads through nflreadr; 1 request/second per domain, no workaround for a 403/429 or a challenge page); providers for nflverse, ESPN core and Kalshi; the `odds_snapshots` shape; the closing rule; the archive builder. Tests inject a fetch function and read `tests/testthat/fixtures/odds/`; live checks are in `tests/live/` only. Endpoints and the terms matrix: `docs/odds-sources.md`

### Props Data Sources
- `sports/nfl/props/data_sources.R` - Player projections with fallback chain
- `sports/nfl/props/props_config.R` - Prop hyperparameters and baselines

### Scripts
- `scripts/run_tests.R` - testthat suite; exits 0 only with 0 failures, 0 errors and every skip on `tests/skip_allowlist.txt`
- `scripts/verify_repo_integrity.R` - repository integrity checks; exits 0 when all pass
- `scripts/verify_requirements.R` - 20-issue audit verification
- `scripts/run_matrix.R` - Execute all artifacts
- `scripts/golden_master.R` - records the game model's numeric output for 2024 week 15, compares it with the committed reference, and attributes CI's per-commit records (`.github/workflows/golden-master.yml`)
- `scripts/write_sim_fixture.R` - writes the web test fixture `contracts/fixtures/bundles/weekly-sim-2024-w15` (synthetic draws, not model output)

### Game Backtest
- `backtest/walk_forward.R` - pre-registered walk-forward shootout; `--stage score` refuses to run unless `reports/<date>/backtest-games-v1/PROTOCOL.md` matches the hash in `backtest/eval_windows/nfl_games_v1.json` and is committed. Never edit a frozen PROTOCOL.md; register a new version instead.
- `backtest/build_inputs.R` - derives the committed point-in-time inputs in `backtest/data/`
- `backtest/build_odds_archive.R` - derives `backtest/data/odds_archive/` (ESPN game openers and closes, 2023-2024). It refuses 2025: the G3 Holdout build appends 2025 after the freeze
- `backtest/vvf/` - the validation framework on PR #205's ported inputs: S0 provenance and the registry, S1 screen, S2 structure (A3a); S3 incremental skill, S4 controls, S5 diagnostics (A3b). `backtest/vvf/reproduce_v2.R` is its known-answer test.
- `backtest/vvf/run_a3b_close.R` - the close-anchored run of S3, S4 and S5 on Tune 2018-2022 (`reports/2026-10-28/vvf-a3b-close/`)
- `backtest/vvf/input_schema.R` - the input ERD: every table's key and references, checked against the data, drawn in the ledger
- `reports/2026-10-28/a3-research/` - the research behind S4's null, the joint test's p, the cluster unit and late schedule changes
- `reports/2026-10-28/verification/` - `verify.R` recomputes A3b's p-values, Brier and log loss, the research and the blends independently (56 checks; run long R scripts from a frozen copy)
- `docs/VARIABLE_LEDGER.md` - every variable, its known-at class, defects, results, admission, the input ERD and disclosures; generated, never edited by hand
- `scripts/write_variable_ledger.R` - writes `docs/VARIABLE_LEDGER.md` from the registry and the committed results
- `scripts/diagnose_mu_na.R` - F11: which calibration mean term is NA, found from the call frames
- `backtest/eval_windows/` - the signed protocols' windows and hashes (`nfl_games_v1`, `nfl_props_v1`, `nfl_preclose_v1`); never edited, see section 4
- `backtest/preclose/` - `nfl_preclose_v1` (signed 2026-11-02, v1.1 before week 9): the history build and the weekly predictions (`reports/2026-11-02/preclose-v1/`)

### Database and Web Checks
- `web/scripts/db-check.ts` - the SQL data checks (`src/lib/dbcheck/checks.ts`). `npm run db-check` exits 1 when an error-level check is violated, and prints warnings. Run it after every ingest.
- `docs/ERD.md` - the database diagram, generated from the Drizzle schema. `npm run erd` rewrites it, and `npm run erd -- --check` exits 1 when it is stale.

### Tests
- `tests/testthat/setup.R` - Test infrastructure
- `tests/testthat/test-*.R` - Unit tests

### Documentation
- `README.md` - Project overview
- `GETTING_STARTED.md` - Setup guide
- `DOCUMENTATION.md` - Technical reference
- `CLAUDE.md` - This file (agent guide)
- `HANDOFF.md` - the resume point: current state, what is running, open risks and next targets
- `reports/history/AUDIT.md` - superseded audit (current: `reports/2026-09-28/AUDIT.md`)
- `CHANGELOG.md` - Change log

---

## 7. VERIFICATION COMMANDS (Run These)

```bash
# R gates use a fresh HOME: the calibration and score caches live in ~/.cache and every checkout shares them
export HOME=$(mktemp -d)

# 1. Unit tests + skip policy (must exit 0; only KNOWN-DEFECT and LIVE skips are allowed)
Rscript scripts/run_tests.R

# 2. Integrity checks (must exit 0)
Rscript scripts/verify_repo_integrity.R

# 3. Full artifact matrix (must show 11/11 pass; golden-master needs network)
Rscript scripts/run_matrix.R

# 4. Run weekly simulation: the upcoming week from the nflverse schedule, or name one
Rscript run_week.R            # prints "Auto-resolved <season> week <w> (...)"
Rscript run_week.R 16 2024    # a named week and season

# 5. View the run offline (after `npm ci` in web/ once)
cd web && npm run local

# 6. Web gates, when web/ changed
cd web && npm run typecheck && npm run lint && npm test
cd web && npm run e2e                                   # the committed fixtures
cd web && E2E_SIM_BUNDLE=<bundle dir> npm run e2e       # a real run_week.R bundle
```

---

## 8. WHEN IN DOUBT

1. Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R` first
2. Read error messages carefully - they usually tell you exactly what's wrong
3. Check this file's API reference section
4. Search for similar patterns in test files
5. Ask for clarification rather than guessing

---

*Last updated: 2026-11-04*
*Version: 2.9.4, plus the unreleased changes in CHANGELOG.md*
