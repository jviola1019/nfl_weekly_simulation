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
- Strength-of-schedule, injury, and coaching change adjustments
- **Player props correlated with game simulation outcomes (v2.9.0)**
- **Vigged model moneylines matching market juice (~10%)**
- **v2.9.1 Audit Fixes**: Roster exclusivity, CV-scaled SD, scoring TD separation, hybrid win probability, EV tier system

### Primary Entrypoints

| File | Purpose | Run Command |
|------|---------|-------------|
| `run_week.R` | Weekly predictions | `source("run_week.R")` |
| `config.R` | Configuration | Edit `SEASON`, `WEEK_TO_SIM` |
| `scripts/run_tests.R` | Test suite + skip policy | `Rscript scripts/run_tests.R` |
| `scripts/verify_repo_integrity.R` | Integrity check | `Rscript scripts/verify_repo_integrity.R` |
| `scripts/run_matrix.R` | Run all artifacts | `Rscript scripts/run_matrix.R` |

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

### Hyperparameter Empirical Sources

**Correlation Coefficients** (current config values, unvalidated, see docs/EVIDENCE_LEDGER.md):

| Parameter | Value | Validation Method |
|-----------|-------|-------------------|
| QB passing ↔ game total | 0.40 | config.R (unvalidated) |
| RB rushing ↔ game total | 0.09 | config.R (unvalidated) |
| WR receiving ↔ team passing | 0.30 | config.R (unvalidated) |
| TD probability ↔ game total | 0.17 | config.R (unvalidated) |
| Same-team cannibalization | -0.15 | Within-team target share analysis |
| Model vig percentage | 0.10 | Industry standard sportsbook juice |

**Model Accuracy Benchmarks**: Withdrawn 2026-09-28; see docs/EVIDENCE_LEDGER.md.

### Expected Outputs

When `run_week.R` completes successfully:
1. **HTML Report**: `NFLvsmarket_report.html` with game predictions AND player props (tabbed)
2. **Run Logs**: `run_logs/config_*.rds`, `run_logs/final_*.rds`
3. **Console**: Data quality badge, simulation progress, calibration status

### What "Correct" Looks Like

- `scripts/verify_repo_integrity.R` exits 0
- `scripts/run_matrix.R`: 9/9 artifacts pass
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
Read the entire repo. Do not edit any files.
Identify:
1. Runtime failures (run run_week.R with traceback)
2. Schema mismatches (check data_validation.R API calls)
3. Join risks (search for *_join without standardize_join_keys)
4. Data quality issues (silent fallbacks, missing error handling)

Output a diagnosis report before any fixes.
```

### Fix Agent (After Audit)

```
Implement the minimal fix for the identified root cause.
Rules:
1. Change only the lines needed to fix the issue
2. Add regression test if applicable
3. No refactors, no feature additions
4. Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R` after fix (both exit 0)
5. Document the change in CHANGELOG.md
```

### Validation Agent (After Fixes)

```
Re-run all verification:
1. Rscript scripts/run_tests.R (must exit 0: no failures, no errors, only allowlisted skips)
2. Rscript scripts/verify_repo_integrity.R (must exit 0)
3. Rscript scripts/run_matrix.R (must show 9/9 pass)
4. Verify HTML report generates if run_week.R was changed

Report: PASS/FAIL with evidence.
```

### Docs Agent (When Requested)

```
Update documentation:
1. README.md - Verify file inventory is complete
2. CHANGELOG.md - Add dated entry for changes made
3. CLAUDE.md - Update if agent rules need clarification
4. Verify all run commands work as documented
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
3. 2025 injury data 404 (expected, should be handled gracefully)

**Fix**: Check NFLsimulation.R lines 3144-3150 for correct API calls.

### Invalid Week Error

**Symptom**: "No games found for Week X"

**Diagnosis**: Check config.R `WEEK_TO_SIM` value against valid weeks.

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

### HTML Report Not Generated

**Symptom**: run_week.R completes but no HTML file

**Diagnosis**: Check for earlier errors; report generation is near end of pipeline.

**Common Causes**:
1. gt package not installed
2. Previous step produced empty results
3. File write permission issue

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
- `NFLsimulation.R` - Simulation engine (8300+ lines)
- `NFLmarket.R` - Market analysis (3900+ lines)
- `NFLbrier_logloss.R` - Metrics

### R/ Library (Canonical Source)
- `R/utils.R` - Core utilities (SINGLE SOURCE OF TRUTH)
- `R/data_validation.R` - Data quality tracking
- `R/logging.R` - Structured logging
- `R/playoffs.R` - Playoff logic
- `R/date_resolver.R` - Date resolution
- `R/sleeper_api.R` - Sleeper fantasy API integration
- `R/red_zone_data.R` - Red zone efficiency metrics
- `R/coaching_adjustments.R` - Coaching change adjustments
- `R/simulation_helpers.R` - Simulation utility functions
- `R/model_diagnostics.R` - Calibration diagnostics
- `R/correlated_props.R` - Gaussian copula player props (v2.9.0)

### Props Data Sources
- `sports/nfl/props/data_sources.R` - Player projections with fallback chain
- `sports/nfl/props/props_config.R` - Prop hyperparameters and baselines

### Scripts
- `scripts/run_tests.R` - testthat suite; exits 0 only with 0 failures, 0 errors and every skip on `tests/skip_allowlist.txt`
- `scripts/verify_repo_integrity.R` - repository integrity checks; exits 0 when all pass
- `scripts/verify_requirements.R` - 20-issue audit verification
- `scripts/run_matrix.R` - Execute all artifacts

### Game Backtest
- `backtest/walk_forward.R` - pre-registered walk-forward shootout; `--stage score` refuses to run unless `reports/<date>/backtest-games-v1/PROTOCOL.md` matches the hash in `backtest/eval_windows/nfl_games_v1.json` and is committed. Never edit a frozen PROTOCOL.md; register a new version instead.
- `backtest/build_inputs.R` - derives the committed point-in-time inputs in `backtest/data/`

### Tests
- `tests/testthat/setup.R` - Test infrastructure
- `tests/testthat/test-*.R` - Unit tests

### Documentation
- `README.md` - Project overview
- `GETTING_STARTED.md` - Setup guide
- `DOCUMENTATION.md` - Technical reference
- `CLAUDE.md` - This file (agent guide)
- `reports/history/AUDIT.md` - superseded audit (current: `reports/2026-09-28/AUDIT.md`)
- `CHANGELOG.md` - Change log

---

## 7. VERIFICATION COMMANDS (Run These)

```bash
# 1. Unit tests + skip policy (must exit 0; only KNOWN-DEFECT and LIVE skips are allowed)
Rscript scripts/run_tests.R

# 2. Integrity checks (must exit 0)
Rscript scripts/verify_repo_integrity.R

# 3. Full artifact matrix (must show 9/9 pass)
Rscript scripts/run_matrix.R

# 4. Run weekly simulation (use valid week!)
# Edit config.R first: WEEK_TO_SIM <- 16; SEASON <- 2024
Rscript -e "source('run_week.R')"
```

---

## 8. WHEN IN DOUBT

1. Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R` first
2. Read error messages carefully - they usually tell you exactly what's wrong
3. Check this file's API reference section
4. Search for similar patterns in test files
5. Ask for clarification rather than guessing

---

*Last updated: 2026-02-05*
*Version: 2.9.0*
