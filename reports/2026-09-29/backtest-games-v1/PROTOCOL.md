# Game backtest protocol `nfl_games_v1`

**Status: frozen before any Confirm scoring.** This file's sha256 is recorded in `backtest/eval_windows/nfl_games_v1.json`, and `backtest/walk_forward.R --stage score` refuses to run unless the hash matches and this file is committed unchanged. Changing anything here means registering a new version (`nfl_games_v2`).

- **Design:** `docs/superpowers/specs/2026-09-29-model-shootout-design.md`, including the A2 decisions of 2026-09-29.
- **Owner authorization:** the owner approved scoring Tune and Confirm once this file's hash is committed. The 2025 Holdout stays sealed until the simulator (C3) joins as `nfl_games_v2` (A2 decision 3).

## 1. Question

Does any independent model, ensemble or market blend give NFL home-win probabilities that are better than the no-vig closing moneyline? The test is judged by paired, out-of-sample Brier score, and by closing-line value where decision-time prices exist. **A null result is reported as a null result.**

## 2. Data

The walk-forward reads only the committed derived files in `backtest/data/`. `backtest/build_inputs.R` builds them from nflverse release files and records every raw sha256 in `backtest/data/SOURCES.json`. nflverse re-publishes release files, so these derived files, not the URLs, are the reproducible snapshot.

| File | Rows | sha256 | Content |
|---|---|---|---|
| `games.csv` | 6,991 | `fae0e4cabda2357a19d7a12bf370a74b0a090008e7cbfc97b8098ada4c536063` | Schedules, 1999–2024: kickoff (UTC), scores, closing moneylines, rest days, location, starting QB ids |
| `team_games.csv` | 10,292 | `bad973261fa472daa0c98d65beb632b284bd29029b3b3b3619764e2bce602305` | Per (game, offense), 2006–2024: plays, EPA, success, pass/rush splits |
| `qb_games.csv` | 12,536 | `65b2f7f0938b44966b1cf5bfaf95831ca00808061a50b2deeadd7816fed57bee` | Per (game, team, QB): dropbacks, summed `qb_epa` |
| `espn_open_close.csv` | 284 | `98dfb3198f91492982432abbb8474043cfa95cc1e97890aee1ef04bfd37cc746` | ESPN BET moneyline open and close, 2024 (keyless ESPN core API) |

**Definitions:**
- **Offensive play:** `play_type` is pass or run, `pass == 1` or `rush == 1`, EPA not missing, and not a two-point attempt.
- **Relocated franchises** share one history: OAK→LV, SD→LAC, STL→LA.
- **Nothing after 2024 is in the inputs.** The Holdout is sealed physically, not only by filtering.

## 3. Windows

| Window | Seasons | Use |
|---|---|---|
| Burn-in | 2010–2017 | Training history for blends and calibrators. Candidate predictions start in 2010; never scored. |
| Tune | 2018–2022 | Select every hyperparameter, using walk-forward (out-of-fold) predictions |
| Confirm | 2023–2024 | First honest comparison. Nothing is tuned here. |
| Holdout | 2025 | **Sealed.** Scored once, together with C3, in `nfl_games_v2` |
| Prospective | 2026 onward | Scored live from forward-captured odds |

**Scope and ties:**
- Regular season and playoffs are both included. Results are reported pooled and by phase (REG, POST).
- Ties are excluded from scoring, and their count is reported.
- Tune metrics are in-sample with respect to hyperparameter selection and are labeled that way. Only Confirm (and later Holdout) is an honest estimate.

## 4. Walk-forward mechanics

**Refit schedule:**
- Predictions are made one NFL week at a time: `(season, week)`, in kickoff order.
- For each week, the cutoff is that week's first kickoff.
- Every fitted component is refit on games that kicked off **before the cutoff** and predicts that week's games.

**As-of guard:**
- Each feature row records when its latest source game ended: the source game's kickoff plus 4 hours.
- `bt_assert_asof()` stops the run if any source did not end before the row's kickoff.

**Randomness:**
- Seeds are fixed: bootstrap 20260929, canary 20260929, shuffle 20260930.
- Every draw uses Mersenne-Twister with Inversion and Rejection sampling.
- The caller's random-number stream is restored afterwards.

## 5. Candidates

The benchmark **C0** is the no-vig closing moneyline from nflverse, devigged proportionally: `p = q_home / (q_home + q_away)`. There are eight scored candidates, which matches the multiplicity used in the A2 power analysis.

| Label | Definition | Selected on Tune from |
|---|---|---|
| **C1** Elo | FiveThirtyEight NFL Elo, public `nfl_elo.py` form. Ratings start in 1999 at a mean of 1505. `p = 1/(1+10^(-(R_h − R_a + HFA·!neutral)/400))`. Update `K · ln(max(|margin|,1)+1) · 2.2/(winner_diff·0.001+2.2) · (result − p)`; the multiplier's denominator is 1 for ties. Each new season, `R ← (1−regress)·R + regress·1505`. **No starting-QB adjustment in v1.** | K ∈ {15, 20, 25, 30} × HFA ∈ {20, 30, 40, 55, 70} × regress ∈ {0.20, 1/3, 0.45, 0.60} |
| **C2** EPA GLM | Ridge logistic model (see "C2 details" below). | halflife ∈ {4, 8, 16} team-games × λ ∈ {1, 10, 100, 300, 1000} |
| **E1** | Equal-weight logit average of C1 and C2 | – |
| **B1[C1]**, **B1[C2]**, **B1[E1]** | Ridge logistic `y ~ 1 + logit(C0) + logit(Ci)`, intercept unpenalized. Refit weekly on every earlier game from 2010 on with both inputs; at least 200 training rows are required. The market weight is learned. | λ ∈ {0.1, 1, 10}, chosen separately for each base |
| **B2[E1]** | `(1−w)·E1 + w·C0` | w ∈ {0.50, 0.55, …, 0.95} |
| **K[E1]** | E1 calibrated by nested walk-forward. The calibrator for week t is fit only on out-of-fold E1 predictions from 2010 on that kicked off before week t; at least 500 rows are required. Platt: `y ~ 1 + logit(p)`. Isotonic: pool-adjacent-violators, linearly interpolated, clamped to [0.01, 0.99]. | method ∈ {platt, isotonic} |

**C2 details:**
- **Features:** home-minus-away differences in offensive EPA/play, offensive success rate, offensive pass EPA/play and offensive rush EPA/play. The same four for defense, measured on the plays opponents ran. The starting QB's EPA/dropback. Rest days, clipped to ±7. Plus a home indicator that is 0 at neutral sites.
- **Estimator:** for team T before game g, sum over T's earlier games j with weight `decay^age_j · 0.5^(season boundaries between j and g)`, where `decay = 0.5^(1/halflife)`. Then `rate = (Σ w·stat + 3·μ·n̄) / (Σ w·plays + 3·n̄)`.
- **Prior:** μ and n̄ are the **previous** season's league per-play mean and plays per team-game. The first pbp season, 2006, uses itself; 2006–2007 are warm-up only.
- **QB feature:** the same estimator over the starter's own dropbacks, on whatever team they played. The starter is nflverse `home_qb_id`/`away_qb_id`.
- **Model:** no intercept. The home indicator is unpenalized. Features are scaled by their training SD but not centered, so swapping home and away flips the signs.
- **Training:** seasons 2008 onward, no ties.

**Selection rule:** minimum mean log loss (p clipped to [1e−6, 1−1e−6]) over the Tune window's non-tie games. Ties go to the first entry in grid order. Components are selected in this order: C1 and C2, then E1 (fixed), then each B1 λ, then B2's w, then K's method.

Register a new version for any candidate not listed here (weather, injuries, pace, the simulator).

## 6. Metrics (per candidate, same non-tie games, per window and phase)

**Scores:**
- **Brier score** and **log loss**.
- **Accuracy** (secondary).
- **ECE:** 10 equal-mass bins.
- **Calibration slope:** logistic `y ~ 1 + logit(p)`.
- **Calibration intercept-in-the-large:** `y ~ 1` with offset `logit(p)`.
- Both calibration terms get Wald 95% CIs.

**Comparisons with C0:**
- Brier skill vs C0: `1 − Brier_c / Brier_C0`.
- The Brier difference and the log-loss difference.

**Statistics:**
- **Paired week-block bootstrap:** B = 10,000 resamples of NFL weeks with replacement, seed 20260929, with the same resample matrix for every candidate in a window. 95% percentile CIs for skill, the Brier difference and the log-loss difference.
- **Diebold–Mariano test** on the per-game Brier differential (candidate − C0) in kickoff order, with h = 1 and the Harvey–Leybourne–Newbold correction, referred to t(n−1). It is one-sided, with H1: candidate loss < C0 loss. **Benjamini–Hochberg** adjusts across the eight candidates.

## 7. Promotion gates

A candidate may be described as **"better than the market (Brier)"** only if every gate passes:

| Gate | Requirement |
|---|---|
| G1 | Skill > 0 and 95% block-bootstrap lower bound > 0, on Confirm **and** on Holdout |
| G2 | DM beats C0 at a BH-adjusted p < 0.05, on Confirm ∪ Holdout |
| G3 | The calibration-slope 95% CI contains 1, and ECE ≤ ECE(C0) + 0.005 |
| G4 | Every control passes (§8) |

In v1, G1 and G2 are evaluated on Confirm alone. So the strongest possible status is **"passes Confirm; Holdout pending"**. Any failure gives **"not better than market"**.

A candidate may be described as having **"betting value"** only under §9.

## 8. Controls (any failure voids the run: `run_status = "void"`)

1. **Leak canary.** Add a feature equal to the final margin plus N(0, 1) noise, whose source ends 3.5 h after kickoff.
   - (a) `bt_assert_asof()` must reject it.
   - (b) Refit C2 with the canary, bypassing the assertion, on the evaluation weeks. It must show skill > 0.05, which demonstrates that the implausible-skill guard catches a leak that gets through.
2. **Implausible-skill guard.** Every candidate's Confirm skill vs C0 must be ≤ 0.05. Beating the no-vig close by more than 5% of Brier is not credible, and it voids the run pending investigation.
3. **Shuffled labels.** Permute the result tuples (home score, away score) **globally** across every played game (seed 20260930). Re-run the whole pipeline with the selected hyperparameters. Every candidate's skill against expanding-window climatology (the home-win rate of all earlier games) must have a 95% CI lower bound ≤ 0 on the evaluation window.
4. **Market copy.**
   - (a) Scoring C0 as a candidate must give skill = 0 and a Brier difference of exactly 0.
   - (b) B1 fit on (C0, C0) with λ = 1 must recover a total market slope (`b_mkt + b_model`, averaged over the evaluation weeks) inside [0.85, 1.15].
5. **Reproducibility.** A second, fresh process with the same window and code must produce an identical `result_sha256`.

## 9. Betting value (closing-line value at decision-time prices)

**Decision-time candidates:** C1, C2, E1 and K[E1]. Their inputs are known before the opener.
- **Caveat:** C2's starting-QB feature uses the game's actual starter. This is announced at the latest with inactives, 90 minutes before kickoff, but may be unknown at the opener.
- B1 and B2 use the closing line, so they are **not evaluable at the opener in v1**.

**Pick rule:** take the home side when `p_model − p_open ≥ 0.03`, and the away side when `p_model − p_open ≤ −0.03`. `p_open` is the ESPN BET no-vig opener.

**Metrics:**
- CLV in bps: `10000 · (p_close − p_open)` for the side taken, both no-vig at ESPN BET.
- Flat 1-unit ROI at the opening price; pushes return 0.
- Week-block bootstrap CIs, B = 10,000.

**Gate** (A2 decision 1, single look): at least **400** decision-time picks, mean CLV ≥ +100 bps with 95% lower bound > 0, and the flat-ROI 95% lower bound > −2%.
- In Confirm, openers exist for 2024 only (284 games), so fewer than 400 picks are possible.
- The v1 CLV numbers are **descriptive, not a gate look**, and every status reads "not evaluable: n < 400".

## 10. Outputs

`reports/2026-09-29/backtest-games-v1/`:
- `predictions.csv`: one row per game × candidate, for Tune and Confirm; probabilities are rounded to 10 decimal places.
- `metrics.json`: selections, grids with Tune losses, scores, CLV and gates.
- `controls.json`
- `run_meta.json`: `result_sha256`, code SHA, R and package versions, protocol commit.
- `RESULT.md`

`result_sha256` = sha256 of the concatenated sha256 hex digests of `predictions.csv` and `metrics.json`. A test (`tests/testthat/test-backtest-games.R`) re-derives it from the committed files. Every claim goes into `docs/EVIDENCE_LEDGER.md`, including negative results.

## 11. Disclosed departures from the design document, and development history

- **Shuffled labels:** the permutation is global, not within-week.
  - Measured during development on Tune only: a within-week permutation keeps each week's home-win count. That count correlates with the market's weekly mean home probability, so the market-anchored B1 candidates kept real week-level information (skill-CI lower bounds of +0.0001 to +0.0003 vs climatology).
  - The control exists to detect pipeline leakage, which requires destroying all association.
  - The criterion is "lower bound ≤ 0" rather than "CI includes 0". A forecast that is sharp on noise labels is penalized, and that would wrongly fail a clean candidate.
- **Candidate set:** the design allowed B2 and K for every model. v1 registers them for E1 only, and chooses K's method on Tune. This keeps eight candidates, as in the A2 power analysis.
- **Grids widened during development:** the first Tune-only runs chose boundary values (Elo HFA 40, regress 0.45; GLM λ 100). HFA {20, 30}, regress 0.60 and λ {300, 1000} were added before freezing. B2's grid is as designed; a selection at its 0.95 boundary means the model adds nothing over the market.
- **Implausible-skill guard:** added as part of control 1(b).
- **Development runs:** Tune-only runs (`--stage dev`, which stops predicting after 2022) were made while building the harness. **The Confirm seasons were never predicted or scored before this file was committed.**

## 12. Known limitations

- The nflverse closing moneyline has no timestamp or book; it is a "consensus close".
- The C2 starter caveat in §9.
- ESPN BET openers cover 2024 only in these inputs; 2023 openers exist upstream but were not captured.
- **Environment:** the run is made with R 4.3.3 (Ubuntu apt), plus data.table, jsonlite and digest, with the exact versions recorded in `run_meta.json`. The repository's renv pins R 4.5.1. `result_sha256` is guaranteed identical only within one environment. Probabilities are rounded to 10 decimal places to minimize differences between environments.
