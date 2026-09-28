# Full repository audit (2026-09-28)

Read-only audit of `main` at `7723e3b`. Nothing was changed while auditing. The approved overhaul plan built on these findings is `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md`.

## Method

- Three independent read-only code audits: game model, backtest and docs; props, scrapers, report UI and data model; the two reference repos (`fantasy_football_dashboard`, `nba`).
- A live render of `NFLvsmarket_report.html` in Playwright at 1440×900 and 390×844, with DOM checks (overflow, scripts, SRI, CSP, aria, fonts).
- Direct source reads to confirm the decisive findings (marked **verified**).
- Gate runs: `Rscript scripts/verify_repo_integrity.R` → 56 passed / 1 failed.
- Live keyless probes of ESPN core API, Kalshi public API and nflverse, to establish which odds sources work without API keys.
- Palette checks with the dataviz `validate_palette.js`.

Severity: **Critical** changes shown numbers or invalidates claims; **High** is wrong behavior or a false claim; **Med** is a risk or drift; **Low** is hygiene.

## 1. Game model

| ID | Sev | Finding | Evidence |
|---|---|---|---|
| M1 | Critical | Command-line week/season are discarded: `NFLsimulation.R` re-sources `config.R`, which resets `SEASON <- 2025`, `WEEK_TO_SIM <- 22`. `Rscript run_week.R 15 2024` runs 2025 week 22. | `NFLsimulation.R:2422-2423` (verified); `config.R:33,40` |
| M2 | Critical | Dynamic shrinkage pushes away from the market. `extra_market_weight <- dynamic_shrinkage - .default_shrinkage` is 0.55 − 0.70 = −0.15 for a regular-season game, then `p <- (1-extra)·p + extra·mkt` = 1.15·p − 0.15·mkt. | `NFLsimulation.R:8100-8127` (verified) |
| M3 | High | Shrinkage is applied twice (a second 0.70 shrink in the market layer), so the effective weight is ≈0.345·blend + 0.655·market. No single documented number describes it. | `NFLmarket.R:2217-2224` |
| M4 | Critical | The production calibrator was trained on `raw_prob = pnorm((home_score - away_score + noise)/13)`, i.e. the final score. Saved test Brier 0.105; it makes probabilities more extreme (0.70 → 0.805). | `ensemble_calibration_implementation.R:82-83`; `ensemble_calibration_production.rds` |
| M5 | Critical | Look-ahead leakage: HFA, RHO, league PPG and the points cap use all seasons; each team's max-week strength row is joined to every game that season; "nested CV" is leave-one-week-out yet `leakage_free = TRUE`; `cal3` is fit in-sample. | `NFLsimulation.R:3565-3683, 7448-7452, 7540, 5675, 5793-5795, 5907, 5946` |
| M6 | Critical | The backtest engine `week_inputs_and_sim_2w` is a reduced model (no GLMM, injuries, weather, QB, turnovers, pressure), so its scores don't describe production. | `NFLsimulation.R:5344-5528` |
| M7 | Critical | Headline metrics can't be reproduced by any script with saved output: Brier 0.211/0.214, "2,282 games" (2022–24 is ≈855), 67.1% (hardcoded, cites a nonexistent RESULTS.md), 538/FPI/"Rank #2" (mock data), rolling validation built from actual scores, correlation CIs. | `simplified_baseline_comparison.R:252-258`; `professional_model_benchmarking.R:50-52,243-258`; `rolling_validation_system.R:108-117` |
| M8 | High | Train/serve skew: the blend is trained on spline-mapped `p_model` and served on raw `home_p_2w_raw`. | `NFLsimulation.R:7294` vs `:8001` |
| M9 | High | The NB-GLMM prior pools 10 seasons with no season term and gets 35–70% weight. | `NFLsimulation.R:4408-4428, 4530-4535` |
| M10 | High | Spread sign inverted: `map_spread_prob(sp) = plogis(-sp/3.5)` assumes "negative favors home" but is fed nflreadr `spread_line` (positive = home favored). Used when moneylines are missing. Three different spread maps exist. | `NFLsimulation.R:6568-6571, 6609-6643` (verified); `:7226`; `NFLbrier_logloss.R:637`; `NFLmarket.R:1373` |
| M11 | High | A missing market probability is silently filled with the model probability; the market-load error returns an empty tibble; `update_market_quality` is never called. | `NFLsimulation.R:6667-6680` |
| M12 | Med | `randtoolbox::sobol(scrambling = 0, seed = seed)`: the seed is ignored without scrambling, so every game uses the same uniform stream (cross-game correlation is wrong; single-game probabilities unaffected). | `NFLsimulation.R:5316` (verified) |
| M13 | Med | Hardcoded values outside config: vig 0.10, Kelly 0.125/0.10/0.02, `BACKTEST_TRIALS 8000L`, default shrinkage 0.60, GLMM weights, `w_off = 0.65`, betting thresholds. Many config parameters are never read. | `run_week.R:143,191`; `NFLmarket.R:2555-2557`; `NFLsimulation.R:8065,8266,4499,4530,5918` |

## 2. Player props

| ID | Sev | Finding | Evidence |
|---|---|---|---|
| P1 | High | `classify_prop_edge_quality` is scalar but called on whole columns inside `case_when`, so it takes the max over all rows and labels every row "Review". The unit test uses `mapply`, so it misses this. | `R/correlated_props.R:1467`; `sports/nfl/props/props_config.R:273-280`; `test-props-edge-policy.R:44-55` |
| P2 | High | Rows show OVER/UNDER with Final Stake 0 ("Stake below minimum") and are highlighted green; stake is not shown in the props table. | `NFLmarket.R:4235-4240`; `artifacts/baseline_props.csv` |
| P3 | Med | For REVIEW/PASS rows the stake inputs default to the over side (an under at +16.8% EV gets "Negative EV"). | `R/correlated_props.R:1421-1438` |
| P4 | Critical | The Odds API fallback requests player markets from `/odds` (props need `/events/{id}/odds`), then iterates a `fromJSON` data frame as a list; receptions never requested. | `R/prop_odds_api.R:42-43, 66-84, 111, 120` |
| P5 | High | 0 anytime-TD rows in the latest output; the ScoresAndOdds "touchdowns" over price is treated as Yes (unverified); The Odds API No price is never attached. | `artifacts/baseline_props.csv`; `R/prop_odds_api.R:141-161, 322` |
| P6 | High | Projections ignore the target week (future games leak into backtests), injuries and depth charts; plain 3-season mean; synthetic "KC QB1" fallback. 17 of 25 rows REVIEW; EV up to +119.6%. | `sports/nfl/props/data_sources.R:51-192, 172-187, 292-369` |
| P7 | High | Correlation uses only the z-scored game total; team score vectors are exported but unused; intra-team correlation never called; prop variates drawn without a seed. | `R/correlated_props.R:15, 81, 404, 447-459`; `NFLsimulation.R:8609-8612` |
| P8 | Med | Yards are a Normal clipped at 0; receptions Poisson with overdispersion discarded. | `R/correlated_props.R:406-409, 1040-1049` |
| P9 | High | Odds join to players by fuzzy name only ("A.St. Brown" matches "A.J. Brown"; suffixes break). Team normalizer `tolower(gsub("[^a-z]", "", x))` turns "KC" into ""; LA/LAR mismatch breaks the time-zone join (`2025_21_LA_SEA` has `away_tz = NA`). | `R/prop_odds_api.R:549, 573-607, 703`; `NFLsimulation.R:3028` |
| P10 | Med | A second, unused, drifted props engine (QB anytime TD there counts passing TDs). | `sports/nfl/props/props_pipeline.R:63, 586` |
| P11 | Med | Missing markets: first TD (only p/12 in the unused copy), 2+ TD computed but not priced, completions advertised without a module, pass TDs, INTs, attempts, longest, alt lines, SGP. | `touchdowns.R:144, 220-241`; `props_config.R:18,190-195` |
| P12 | Med | EV uses the raw quoted price (no devig); edge bins on EV; line shopping picks the lowest-vig book regardless of the side the model likes. | `R/correlated_props.R:693-712, 1215-1224`; `R/prop_odds_api.R:628-639` |

## 3. Odds sources and scrapers

| ID | Sev | Finding | Evidence |
|---|---|---|---|
| S1 | High | ToS/legal risk: ScoresAndOdds private AWS endpoint with a spoofed Chrome UA; OddsTrader/Covers return nothing (Covers 403s bots) but still make two requests; a minified OddsTrader JS bundle is committed; ESPN robots check hard-coded `TRUE`. | `R/prop_odds_api.R:239, 263, 404-505`; `artifacts/oddstrader_playerprops.js`; `injury_scalp.R:386-390` |
| S2 | High | First source to return anything wins for all markets; no scrape timestamps; odds never snapshotted, so props can't be backtested and stale lines can't be detected. | `R/prop_odds_api.R:859-910, 316-330` |
| S3 | Med | Weather: `httr2` with no timeout or retry, failure returns NULL silently, forecast cache never expires, neutral sites fall back to Kansas. | `NFLsimulation.R:4120-4131, 4187-4198` |
| S4 | Med | Game lines are nflreadr schedule closes with no timestamp or book. | `NFLsimulation.R:854` |

## 4. HTML report (live render)

| ID | Sev | Finding |
|---|---|---|
| U1 | High | The sticky search header overlaps and hides the tab bar. |
| U2 | High | Moneyline table: gt title and blank spanner rows render above the column labels, which appear below the only data row; spanners literally "????" (emoji lost to encoding, `NFLmarket.R:3572-3592`). |
| U3 | High | Horizontal overflow at 1440px and at 390px (document 593px wide in a 390px viewport); fixed column widths sum to ≈1,775px (`NFLmarket.R:4201-4218`). |
| U4 | Med | Five static base-R PNG charts (900×520): truncated axis labels, stacked bar without legend, mixed-scale scatter, game charts drawn from n=1. |
| U5 | Med | three.js r128 from cdnjs with no SRI/crossorigin; the WebGL loop keeps running under reduced motion (`NFLmarket.R:3841-3923`). |
| U6 | Low | Invalid HTML: `<html>` nested inside `<html>`; htmltools' white body background injected. |
| U7 | High | Props tab: no search/filter/sort (wired to the moneyline table only), no matchup/kickoff/stake/pass-reason/odds-timestamp columns. |
| U8 | Med | 1 `aria-` attribute and 0 `role=` in the document; tabs lack tab roles; color-only meaning. |
| U9 | Med | Explanatory boilerplate fills most of the first screen. |
| U10 | Med | Dark coral-on-near-black theme with Inter declared but never loaded; no light mode, no print CSS, no "generated at" time. Copy hard-codes "60% Shrinkage" and correlations that drift from config. |

## 5. Tests, CI, hygiene, docs

| ID | Sev | Finding | Evidence |
|---|---|---|---|
| T1 | High | `verify_repo_integrity.R` fails: requires passing correlation in [0.70, 0.80]; config has 0.40. | `scripts/verify_repo_integrity.R:294`; `config.R:815` |
| T2 | High | No test executes `simulate_game_nb`, `score_weeks`, the blend, shrinkage, `market_probs_from_sched` or `compare_to_market`; `test-correlated-props.R` catches all errors; about 200 skip sites; `setup.R` only warns when a module is missing. | `tests/testthat/*` |
| T3 | Med | `run_matrix.R` only sources library files and runs testthat with `stop_on_failure = FALSE`. | `scripts/run_matrix.R:80,167` |
| T4 | High | CI uses R 4.4.0 vs renv 4.5.1; testthat has no top-level renv entry; `audit_verify.sh` needs `rg`, not installed; `actions/cache@v3`. | `.github/workflows/ci.yml:20` |
| H1 | Med | 165 `run_logs/` files tracked despite `.gitignore`; invalid rds artifacts tracked; ~2,100 lines of `if (!exists())` fallback copies in `NFLsimulation.R:147-2268`; `standardize_join_keys` defined 3 times; `core/`, `sports/nfl/config.R`, `validation/calibration_harness.R` never sourced; 0-byte `nul`; version strings 2.7.0 / 2.9.0 / 2.9.3 / 2.9.4. | |
| H2 | Med | `.gitignore` ignored all of `reports/`, so dated evidence could never be committed. | `.gitignore:32` |
| D1 | High | Docs contradict config and each other: shrinkage 60% (README, docs/API.md, ARCHITECTURE.md) vs 70% (CLAUDE.md, config); correlations 0.75/0.60/0.50/0.40 "validated" vs config 0.40/0.09/0.30/0.17 (changed in `74b831a` without a CHANGELOG entry); GETTING_STARTED CLI broken (M1); CHANGELOG missing 2 commits; `DESCRIPTION` says MIT + LICENSE but no LICENSE. | |

## 6. Security

| ID | Sev | Finding |
|---|---|---|
| SEC1 | High | Untracked `.claude/settings.json` allows blanket `Bash`, `Edit`, `Write`; `.claude/settings.local.json` is tracked. |
| SEC2 | Low | `.gitignore` lacks `.Renviron`, `.env*`, `.claude/settings*.json`, `.playwright-mcp/`. |
| SEC3 | Med | CDN script without SRI; no CSP; the Odds API key would travel in the query string (provider requirement; must never be logged). |
| SEC4 | Low | No-gt fallback HTML concatenates unescaped values (`NFLmarket.R:4778-4803`); export force-deletes its output path (`:2946-2948`); `run_matrix.R:59` runs `system()` on a built string; `readRDS` of `~/.cache` files. |
| OK | – | No secrets in the tree or history; no `eval(parse())`. |

## 7. Keyless data sources (probed 2026-09-28)

| Source | Result |
|---|---|
| nflverse schedules | Closing spread/total/moneyline, 1999 onward. No timestamp or book. |
| ESPN core `…/competitions/{id}/odds` | DraftKings/ESPN BET open + close for 2023+ games (2018/2020/2022 list providers without open/close). |
| ESPN core `…/odds/58/propBets` (ESPN BET) | 2024 season through ~week 13 of 2025. 596 rows for a 2024 game, 940 for a 2025 week 1 game, including anytime/first/last TD, yards, receptions, completions, attempts, INTs, longest. Only a subset keeps prices (2025 wk1 anytime TD 38/109; 2024 sample 0/43). `lastUpdated` falls after kickoff, so `current` is not a pre-kickoff close. |
| ESPN core `…/odds/100/propBets` (DraftKings) | Live only (404 after the game). Lines (open → current) but no prices; TD rows empty. |
| Kalshi `/historical/markets`, `/historical/markets/{t}/candlesticks` | Settled NFL player markets with hourly bid/ask/last and volume; anytime TD `KXNFLANYTD` from ~Dec 2025 (e.g. 19 markets for LA@SEA 2026-01-25; top market ≈747k contracts, 1–2¢ spread). |
| Kalshi `/markets?status=open` | 2026 season: 38 per-game series open for PHI@CHI (2026-09-28), with touchdown markets under `KXNFLTD` (1+/2+ strikes). |
| The Odds API | Historical props require a paid plan. |
| OddsPapi | Free tier includes historical odds but needs a signup key; excluded by the no-key decision. |

## 8. Cross-repo note

CLV is computed as `model_prob − closing_prob` here (`NFLmarket.R:680`) and the NBA repo picks the model probability as the "recommendation side prob" (`nba/R/clv_tracking.R:158`). Measured this way, CLV on +EV picks is structurally negative, which likely explains NBA's constant ≈−800 bps summary. Correct: `clv_bps = 10000 × (p_close_novig(side) − p_taken_novig(side))`.

## 9. Reference apps (what is ported, what is not)

- From `fantasy_football_dashboard`: stack, CSP/security headers, auth throttling, evidence ledger with Validated/Reproducible/Withdrawn tiers, protocol/result pairs, docs-truth and slop-scan tests, Playwright/axe/Lighthouse gates, HANDOFF format. Not its visual look.
- From `nba`: walk-forward backtest, hash-locked eval windows, promotion policy with an honest default, schema validators, publish policy with last-known-good. Not its CLV definition or its decorative visuals.
