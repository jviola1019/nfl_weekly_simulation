# Model and blend shootout (design, Phase 3 addendum)

Status: **draft for owner review** (checkpoint A2). This document fixes *what* gets compared and *how it's judged* before any scoring runs. Once the owner approves it, the protocol file is hashed and locked, and changing it means registering a new version.

## Why

The owner asked for professional-grade NFL game probabilities that do better than the market's Brier score, comparing different models and blends. The audit found that the model's current accuracy claims can't be reproduced (`reports/2026-09-28/AUDIT.md`, M4–M7).

Before anything is labeled "better than the market", we need a comparison that is point-in-time, out-of-sample and pre-registered. It should include simple, independent models, because they are the honest baseline any complex simulator must beat.

**What to expect.** NFL closing lines are among the most efficient betting markets. Published model comparisons rarely beat the no-vig closing line on Brier. Realistic wins are:
1. a blend that uses the market as an input and improves on it slightly;
2. positive closing-line value (CLV) when acting on earlier lines (openers or midweek).

The protocol is built so that a null result is reported as a null result.

## Baseline to beat (measured 2026-09-29)

No-vig closing market from nflverse moneylines, proportional devig, ties excluded. Script and output: `reports/2026-09-29/market-baseline/`. nflreadr 1.5.0, R 4.5.1.

| Season | Games | With moneyline | Market Brier | Market log-loss | Favorite accuracy |
|---|---|---|---|---|---|
| 2018 | 267 | 267 | 0.2124 | 0.6135 | 66.4% |
| 2019 | 267 | 267 | 0.2141 | 0.6163 | 64.3% |
| 2020 | 269 | 269 | 0.2019 | 0.5900 | 67.5% |
| 2021 | 285 | 285 | 0.2177 | 0.6232 | 62.3% |
| 2022 | 284 | 284 | 0.2093 | 0.6050 | 66.0% |
| 2023 | 285 | 285 | 0.2186 | 0.6270 | 67.7% |
| 2024 | 285 | 285 | 0.2010 | 0.5892 | 70.5% |
| 2025 | 285 | 285 | 0.2109 | 0.6070 | 66.2% |
| **2018–2025 pooled** | **2,219 (non-tie)** | | **0.2108** | **0.6089** | |

- **Paired comparison only.** The market's own Brier moves by ±0.009 between seasons. So "better than the market" can only be judged with **paired**, same-game differences, never by comparing season-level Brier to a fixed number such as "0.211".
- **Tie-out on withdrawn claims.** For reference, 2022–2024 has 854 games, which is consistent with the audit's M7 finding that "2,282 games" was impossible.

## Candidates

All candidates are point-in-time: each game's inputs come only from data timestamped before that game's kickoff. Every candidate is refit walk-forward, by week, on an expanding window.

| ID | Candidate | Inputs | Notes |
|---|---|---|---|
| C0 | **Market** | No-vig closing moneyline (nflverse), proportional devig | The benchmark. Scored identically to every other candidate. |
| C0o | Market at open | No-vig opener (ESPN core 2023+, Kalshi 2025+) | Decision-time reference for CLV. |
| C1 | **Elo** | Final scores | Margin-of-victory multiplier, home-field term, a between-season regression to the mean, and an optional starting-QB adjustment. K, HFA and the regression weight are tuned on the tuning window only. |
| C2 | **EPA GLM** | nflverse play-by-play | Ridge logistic model on home-minus-away differences of exponentially weighted offensive and defensive EPA/play, success rate, pass/rush splits, QB EPA, rest days and a home indicator. Features are computed as of the day before kickoff. |
| C3 | **NB-copula simulator** | Current pipeline after Phase 1a/1b | Pre-shrink probability `p_raw` from `predict_week()`. It joins as soon as Phase 1b makes it point-in-time, as its own registered version (v2). |
| E1 | Equal-weight logit average of the model-only candidates (C1, C2, and C3 once available) | – | A simple, hard-to-overfit ensemble. |
| B1 | **Market-anchored stack** | logit(C0) + logit(Ci), and optionally a week-of-season term | Ridge logistic model fit walk-forward. The market weight is learned from data, not fixed at 70%. Fit separately for each Ci and for E1. |
| B2 | **Fixed-weight shrink** | (1−w)·p_model + w·p_market | w is chosen on the tuning window from {0.50, 0.55, …, 0.95} and then frozen. This mirrors today's 70% approach, so it can be compared directly. |
| K | **Calibrators** | Out-of-fold predictions only | Platt and isotonic, fit with nested walk-forward. A calibrated variant is scored only if its calibrator never saw the evaluation fold. |

Anything else a later phase wants to add (weather, injuries, pace) is registered as a new version. It is never retrofitted into this one.

## Data windows (hash-locked in `backtest/eval_windows/nfl_games_v1.json`)

| Window | Seasons | Use |
|---|---|---|
| Tune | 2018–2022 | Choose hyperparameters and blend weights, using only out-of-fold predictions |
| Confirm | 2023–2024 | First honest comparison; no tuning allowed |
| Holdout | 2025 | Sealed; scored **once**, after the owner signs the protocol |
| Prospective | 2026 onward | Scored live, week by week, from forward-captured odds |

- Regular season and playoffs are included, and results are reported both pooled and by phase.
- Ties are excluded from Brier and log-loss, and the count is reported.
- The source-data sha256 (schedules and play-by-play release files) is written into the window file.

## Metrics

For each candidate, on the same games:
- Brier score, log loss, and Brier skill vs C0: `1 − Brier_c / Brier_C0`.
- ECE (10 equal-mass bins), calibration slope and intercept.
- Accuracy, reported as secondary only.
- Where decision-time odds exist: CLV in basis points, `10000 · (p_close_novig(side) − p_taken_novig(side))`, plus flat-stake and paper-Kelly ROI by edge decile.

Statistics:
- Paired block bootstrap by NFL week (B = 10,000) for every difference against C0.
- Diebold–Mariano with the HLN correction.
- Benjamini–Hochberg correction across all candidates.

## Promotion gates (the honest default: nothing is claimed unless every gate passes)

A candidate may be described as "better than the market (Brier)" only if all of these hold:
1. Brier skill vs C0 > 0, with the 95% block-bootstrap lower bound > 0, on Confirm **and** on Holdout.
2. The DM test beats C0 at BH-adjusted p < 0.05 on Confirm ∪ Holdout.
3. The calibration slope's 95% CI contains 1, and ECE ≤ ECE(C0) + 0.005.
4. Every control passes (below).

A candidate may be described as having "betting value" only if both hold:
- Mean CLV ≥ +100 bps, with the 95% CI lower bound > 0, on ≥ 300 recommendations taken at decision-time prices (ESPN openers from 2023, Kalshi from 2025, and forward capture).
- Flat-stake ROI has a 95% CI lower bound > −2%. That is a sanity bound, not a profitability claim.

Candidates that fail stay in the report, labeled "not better than market". The public site shows market-equivalent probabilities for them, and no picks.

## Controls (a failure voids the run)

1. **Leak canary.** Add a feature equal to the final margin plus noise. The as-of assertion (`source_max_ts < kickoff` on every row) must reject it. If it somehow gets through, the resulting implausible skill must flag the run.
2. **Shuffled labels.** Shuffle outcomes within each week. Every candidate's skill CI must include 0.
3. **Market copy.** Feed C0 as a "model". Skill must be exactly 0, and B1 on C0 must recover a market weight ≈ 1.
4. **Reproducibility.** Rerunning with the same window file and code SHA gives an identical `result_sha256`.

## Deliverables

- `model/backtest/`:
  - `candidates/{market.R, elo.R, epa_glm.R, sim_nb.R}`
  - `blends.R`, `calibrators.R`, `walk_forward.R`, `metrics.R`, `controls.R`
  - `eval_windows/nfl_games_v1.json`
- `reports/<date>/backtest-games-v1/`: `PROTOCOL.md` (hashed before scoring), `predictions.csv` (one row per game × candidate), `metrics.json` and `RESULT.md`.
- Evidence-ledger rows for every claim, **including negative results**.
- The web app's `/evidence` page reads `metrics.json`: reliability diagram per candidate, Brier skill with CIs, CLV distribution, ROI by edge decile.

## Order of work

1. Phase 1a (wiring fixes) is independent of this shootout.
2. Build C0, C1, C2, E1, B1, B2 and K with the walk-forward harness, the controls and the metrics. This doesn't depend on the simulator, so it can run in parallel with Phase 1b.
3. Owner signs `PROTOCOL.md` (A2). Score Confirm. Score Holdout once.
4. Phase 1b makes the simulator point-in-time. Register v2 with C3 added. Score it the same way.

## Open questions for the owner (A2)

1. **Minimum sample for the betting-value gate:** 300 recommendations (proposed), or the NBA policy's 500. At NFL volume, 500 may take more than a season of forward capture.
2. **Include playoffs** in the headline metrics, or report them separately only?
3. **Holdout timing:** score the 2025 holdout as soon as the confirm window is done, or wait for C3 so every candidate is judged on it at once? Proposed: wait.
