# NFL Prediction Model: Technical Reference

**Verified against the code on 2026-11-05** (main after #235–#237). This replaces the January 2026 reference (v2.6.4), which described scripts removed in September 2026 and validation figures since withdrawn.

**What this file contains:**
- settings, with their current values;
- function signatures;
- naming conventions;
- formulas;
- R 4.5.1 notes.

It makes no claims about model accuracy. Those live only in `docs/EVIDENCE_LEDGER.md` and the dated `reports/`.

| For | Read |
|---|---|
| How the parts fit together | `docs/ARCHITECTURE.md` |
| The model's statistics in detail | `docs/modeling.md` |
| Function reference (R/ modules) | `docs/API.md` |
| Database tables and keys | `docs/ERD.md` |
| Data sources and their rules | `docs/odds-sources.md` |
| Evidence for every model claim | `docs/EVIDENCE_LEDGER.md`, `docs/VARIABLE_LEDGER.md` |
| How to run things, and the agent rules | `README.md`, `GETTING_STARTED.md`, `CLAUDE.md` |

## Key settings (`config.R`)

| Setting | Value | Meaning |
|---|---|---|
| `SEASON`, `WEEK_TO_SIM` | auto-resolved | From the calendar; `Rscript run_week.R <week> <season>` names one |
| `N_TRIALS` | 100000 | Simulated games per matchup |
| `SEED` | 471 | Random seed |
| `MU_TERMS_ADMITTED` | `c("base", "hfa")` | The terms in the simulated means (audit M22); every other term is logged only |
| `HFA_TEAM_ESTIMATOR` | see `config.R` | `"league"`, `"strength_free"` or `"team_margin"`; overridable with `options(nfl_sim.hfa_estimator = ...)` |
| `SHRINKAGE` | 0.70 | Weight on the no-vig market in the published (C3) probability |
| `KELLY_FRACTION` | 0.125 | 1/8 Kelly |
| `CALIBRATION_METHOD` | `"spline"` | Fitted each run and printed as a diagnostic only (audit M4) |
| `RUN_PLAYER_PROPS` | TRUE | Run the props module |
| `PROP_REQUIRE_MARKET_ODDS` | TRUE | Keep only market-priced props in the output when any exist |
| `PROP_QUOTE_MAX_AGE_MIN` | 120 | A prop quote older than this is stale |
| `KALSHI_TAKER_FEE_COEF` | 0.07 | Unverified against Kalshi's schedule (see its note in `config.R`) |
| `USE_SNAP_WEIGHTED_INJURIES` | FALSE | Snap weighting off (it could hang on a missing season) |
| `INJURY_LOAD_RETRIES`, `SCHEDULE_LOAD_RETRIES` | 2 each | Downloads retried before a season is flagged or the run stops |

## Key functions

| Function | Where | Signature |
|---|---|---|
| `simulate_game_nb` | `NFLsimulation.R` | `(mu_home, sd_home, mu_away, sd_away, n_trials = N_TRIALS, rho = RHO_SCORE, cap = PTS_CAP_HI, seed = SEED)` |
| `nb_size_from_musd` | `NFLsimulation.R` | `(mu, sd)`: the negative binomial size for a mean and SD |
| `score_variance_from_mu` | `NFLsimulation.R` | `(games)`: each game's SDs and NB sizes from its means |
| `compose_mu` | `R/mu_terms.R` | `(components, admitted)`: the sum of the admitted terms; stops on a non-finite term or a non-positive mean |
| `mu_components` | `R/mu_terms.R` | `(games, pressure_pts)`: every term, home and away, per game |
| `calibration_mu_components` | `R/mu_terms.R` | `(g, admitted)`: the calibration backtest's terms; stops on a term it cannot simulate |
| `week_inputs_and_sim_2w` | `NFLsimulation.R` | `(cut_season, cut_week, n_trials = CALIB_TRIALS)`: one week of the calibration backtest |
| `hfa_table_asof` | `R/schedule_context.R` | `(games, season, week, teams, den_bonus, estimator, n_seasons = 10L)` |
| `hfa_games_asof` | `R/schedule_context.R` | `(games, season, week, n_seasons = 10L)` |
| `team_hfa_table` | `R/schedule_context.R` | `(home_margins, teams, league_hfa, den_bonus = 0, shrink_n = 60, estimator)` |
| `home_field_points` | `R/schedule_context.R` | `(home_hfa, league_hfa, playoff_mult, neutral_site)`: capped at ±6, 0 at a neutral site |
| `load_schedules_checked` | `R/schedule_context.R` | `(seasons, retries = 2L, wait = 3, loader, clear)` |
| `safe_load_injuries` | `NFLsimulation.R` | `(seasons, prefer_fast = TRUE, allow_live_fallback = FALSE, ..., retries, retry_wait, retry_seasons)` |
| `calc_injury_impacts` | `NFLsimulation.R` | `(df, group_vars = c("team"), season = NULL)` |
| `rho_from_game` | `NFLsimulation.R` | `(total_mu, spread_abs, rho_global = RHO_SCORE)` |
| `make_calibrator` | `NFLsimulation.R` | `(method, p, y, weights = NULL)` |
| `shrink_probability_toward_market` | `R/utils.R` | `(model_prob, market_prob, shrinkage = 0.6)`; callers pass `SHRINKAGE` (0.70) |
| `sb_predictions` | `R/sim_bundle.R` | `(final, shrinkage = SHRINKAGE)`: the C0 and C3 rows of the bundle |
| `write_sim_bundle` | `R/sim_bundle.R` | `(final, sims, schedule, quality, season, week, seed, n_sims, out_root = "bundles", ...)` |
| `build_moneyline_comparison_table` | `NFLmarket.R` | `(market_comparison_result, enriched_schedule, join_keys = PREDICTION_JOIN_KEYS, vig = 0.10, ...)` |
| `resolve_target_week` | `R/run_config.R` | `(schedule, now = Sys.time())`: the earliest week with a game not yet kicked off |

## Naming conventions

**Prefixes:**

| Prefix | Meaning |
|---|---|
| `mu_` | expected value |
| `sd_` | standard deviation |
| `p_` | probability |
| `rho_` | correlation |
| `n_` | count |
| `w_` | weight |
| `adj_` | adjusted |
| `raw_` | unadjusted |
| `home_`, `away_` | side |
| `off_`, `def_` | offense, defense |

**Suffixes:**

| Suffix | Meaning |
|---|---|
| `_home`, `_away` | side |
| `_avg` | average |
| `_med` | median |
| `_sd` | standard deviation |
| `_wt` | weight |
| `_adj` | adjusted |
| `_raw` | raw |
| `_pen` | penalty |
| `_bonus` | bonus |

**Abbreviations:**

| Abbreviation | Meaning |
|---|---|
| `ppg` | points per game |
| `epa` | expected points added |
| `sos` | strength of schedule |
| `hfa` | home field |
| `glmm` | mixed model |
| `pbp` | play-by-play |
| `rz` | red zone |
| `to` | turnover |

**Moneylines, fair against vigged:**
- `blend_home_prob_shrunk` is the shrunk home win probability used for betting math.
- `blend_home_ml` is the fair moneyline computed only from it.
- `blend_home_ml_vig` (and `blend_away_ml_vig`) is the vigged moneyline computed only from the fair one.
- Probability coherence checks use fair quantities only, never vigged moneylines.

## Formulas

**Probability to American moneyline (fair):** `-round(100·p/(1−p))` if p ≥ 0.5, otherwise `round(100·(1−p)/p)` (`probability_to_american()`).

**American moneyline to implied probability:** `−ML/(−ML+100)` if ML < 0, otherwise `100/(ML+100)` (`american_to_probability()`). The round trip should return p.

**Vigged moneyline from a fair one:** `−round(|ML|·(1+v))` if ML < 0, otherwise `round(ML/(1+v))` (`apply_moneyline_vig()`). It is used for display and comparison only.

**Brier score:** `(1/N)·Σ(p_i − y_i)²`.
- It ranges from 0 (perfect) to 1. Always predicting 50% scores 0.25.
- **A measured reference:** the no-vig closing line scores 0.2111 on the 1,365 games of 2018–2022 (`reports/2026-11-03/model-gauntlet/RESULT.md`). No model in this repository beats it there.

**Log loss:** `−(1/N)·Σ[y_i·log(p_i) + (1−y_i)·log(1−p_i)]`. Probabilities are clamped to `[ε, 1−ε]` with ε = `PROB_EPSILON` = 10⁻⁹ (`R/utils.R`).

**Negative binomial scores:** `E[Y] = μ`, `Var[Y] = μ + μ²/φ`.
- **Size:** each game's size φ comes from its mean and SD (`nb_size_from_musd()`).
- **SD:** a blend of the fitted SD and a target curve for the total (`score_variance_from_mu()`).

**Gaussian copula:**
1. Draw (Z₁, Z₂) from a bivariate normal with correlation ρ.
2. Set U = Φ(Z).
3. Each score is the negative binomial quantile of its U.

ρ (`RHO_SCORE`) is estimated from data when not set, then clamped to `[RHO_LO, RHO_HI]`.

**Isotonic regression:** the non-decreasing f minimizing `Σ w_i·(f(p_i) − y_i)²`, fitted by pool-adjacent-violators.

## R 4.5.1 notes

1. **`dplyr::lag()`** needs a scalar default: the code uses `default = NA_real_` or `0`, then `coalesce()`.
2. **`tidyr::pivot_longer()`** fails on duplicate names: drop clashing columns first (for example `select(-any_of("location"))`).
3. **`RNGversion()` before `set.seed()`:** `config.R` fixes the generator, so runs repeat. The CI golden master records the same commit twice, and its determinism line must show no differences.

## Validation status

This file states no accuracy figures. The current record:

| Study | Result | Where |
|---|---|---|
| Model gauntlet: 10 families and their market stacks, 2018–2022 | None beats or adds to the no-vig close | `reports/2026-11-03/model-gauntlet/RESULT.md` |
| Pre-registered game backtest v1 | Tune and Confirm scored; Holdout sealed | `reports/` (backtest-games-v1) |
| `nfl_preclose_v1` (signed) | No candidate beats the opener on Tune/Confirm; v1.1 runs prospectively in 2026 | `reports/2026-11-02/preclose-v1/RESULT.md` |
| `nfl_props_v1` (signed) | Runs on 2026 weeks 9–18 | `backtest/eval_windows/nfl_props_v1.json` |
| Engine home-field comparison v2 | Void by its validity gate | `reports/2026-11-04/hfa-engine-v2/RESULT.md` |
| The earlier Brier, accuracy, spline-calibration and prop-correlation figures (claims C-BRIER, C-ACC, C-SPLINE, C-CORR) | Withdrawn 2026-09-28 | `docs/EVIDENCE_LEDGER.md` |

## Removed in 2026

- **The validation scripts this reference used to describe** were removed on 2026-09-29 (audit M7): `model_validation.R`, `injury_model_validation.R`, `professional_model_benchmarking.R`, `calibration_refinement.R`, `rolling_validation_system.R`, `run_validation_example.R` and `final_verification_checklist.R`. Their figures are withdrawn.
- **Still present:** `ensemble_calibration_implementation.R` is in the repository, but its calibrator is invalid (audit M4).
- **The HTML report** and its column labels were retired at checkpoint A8. The web bundle and the app replace them.
