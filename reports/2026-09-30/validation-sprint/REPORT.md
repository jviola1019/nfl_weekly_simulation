# Validation sprint v2: can any model beat the closing market?

**Owner's question (2026-09-30):** fully validate the model, backtest and fix it, and get a Brier score below the market's. Test every variable for significance, compare XGBoost with logistic-regression blends, verify every calibration, and track the backtest and handicapping results.

**Short answer:** no model beats the closing line on the Tune window, and none is validated. The market-anchored logistic blends are the most useful family: they match the close at a fraction of the cost and variance of boosting. No situational variable adds significant signal beyond the close after multiple-testing correction. One spread effect (time-zone travel) is the only candidate worth a pre-registered out-of-sample test.

All tables: `TABLES.md` (rendered by `backtest/v2/report.R` from the CSVs in this directory).

**Reproduce:**
```
Rscript backtest/v2/sprint.R --out reports/2026-09-30/validation-sprint --stages screen,models,handicap,controls
Rscript backtest/v2/report.R reports/2026-09-30/validation-sprint
```

## Guardrails

- **Data:**
  - Only the Tune window, 2018–2022, is used, with 2010–2017 as training history.
  - Every table is cut at 2022 before any feature or model sees it, and a sealed-season guard stops on any row after 2024.
  - The 2025 holdout was not read, built or scored.
  - The Confirm window, 2023–2024, was not used. It was already viewed for moneyline in v1, so it can only be secondary evidence for moneyline.
- **Point in time:**
  - Every feature is known before kickoff (see `backtest/v2/features.R`).
  - Injury reports count only when timestamped more than 6 hours before kickoff. Referee tendencies use prior seasons only.
  - Base model probabilities are walk-forward.
  - Observed game-day weather is screened only as a labelled post-hoc diagnostic.
- **Reproduction of v1:**
  - The regenerated walk-forward Elo, EPA GLM and ensemble predictions equal the committed v1 Tune predictions to within 5e-11 (v1 rounds to 1e-10).
  - The v2 logistic stack `LR_E1` is v1's `B1[E1]`, and it reproduces v1's Tune result: Brier 0.2111, skill −0.01%.
- **Leak canary and determinism** (`tests/testthat/test-backtest-v2-models.R`):
  - Rewriting every later result and feature leaves a week's predictions unchanged for all six model families and all three calibration maps.
  - Runs are reproducible, and a second full run of every stage reproduced every CSV byte for byte (see `run_meta.json`).
- **Shuffled-label control** (`models/control_shuffled_labels.csv`): with outcomes permuted globally, no blend beats a climatology base rate. This passes for all three flexible families:

  | Family | Skill vs climatology [95% CI] |
  |---|---|
  | Logistic stack | −0.13% [−0.25, −0.01] |
  | glmnet | −0.04% [−0.12, +0.03] |
  | XGBoost | −8.44% [−11.84, −5.02] |

  The harness does not manufacture skill.

**Context from the engine audit.** The production simulator's "situational adjustments" have never reached a prediction (audit M22: a NaN turnover term forces a rescue to drives × points per drive). This screen is the first honest test of whether those factors carry signal beyond the market.

## 1. Which variables matter beyond the close? (the "ANOVA" question)

**Method.** 36 point-in-time features, each tested three ways on about 1,370 Tune games:
- **Moneyline:** logistic regression with the no-vig close as an offset, likelihood-ratio test.
- **Spread:** OLS on home margin minus `spread_line`, F test.
- **Totals:** OLS on total points minus `total_line`, F test.

Each coefficient also gets a week-clustered robust test. q-values are Benjamini–Hochberg within each market, taken on the larger of the model-based and robust p-values.

**Features by group:**
- **Model vs market:** Elo, EPA GLM and ensemble minus the close.
- **Market shape:** the close itself, home underdog, big favourite.
- **Schedule:** rest difference, short weeks, byes, Thursday, division, neutral site, late season, playoffs.
- **Travel and venue:** away travel distance, travel difference, time-zone shift, west-coast team in an early kickoff, prime time, altitude, closed roof, turf.
- **Injuries and QB:** status-weighted report counts by position group, starting QB listed out, QB change.
- **Officials:** referee tendencies from prior seasons.

**Results:**
- **Moneyline: nothing.** The smallest q is 0.49 (away time-zone shift, raw p = 0.0095).
- **The close is well calibrated:** its slope coefficient is +0.047 [−0.114, +0.208] around 1. There is no favourite–longshot bias to exploit.
- **Joint LR test of all 29 situational features:** χ² = 26.9, p = 0.63.
- **Spread: one weak signal.** Away teams cover 0.88 points less for each time zone crossed [−1.46, −0.30], p = 0.004, q = 0.15. Nothing else reaches q < 0.20. Joint F test: p = 0.38.
- **Totals: nothing survives correction.** Closed roofs +2.09 points (q = 0.31) and turf +1.72 (q = 0.33) are nominal only. Joint F test: p = 0.42.
- **Power:** the `MDE per SD` column in `TABLES.md` gives the smallest effect each test could detect with 80% power. "No evidence" means no effect larger than that; it does not mean exactly zero.
- The week-clustered joint Wald tests do reject. With 29–34 coefficients and about 90 week clusters that estimator is unstable and over-rejects, so the model-based joint tests are the evidence (see TABLES.md).

## 2. XGBoost or logistic regression blends? Which calibration?

**Method.** Six blend families were fit week by week on identical inputs (market, model-vs-market gaps and 28 situational features), trained on every earlier game from 2010. Each got four calibration maps (none, Platt, isotonic, spline), each fit only on earlier weeks' out-of-fold predictions. Everything was scored on the 1,365 non-tie Tune games against the close, which scores Brier 0.2111.

| Family | Best version | Brier skill vs close [95% CI] | Compute (fits, whole walk) |
|---|---|---|---|
| Penalised logistic (glmnet, market unpenalised) | no calibration | +0.03% [−0.20, +0.28] | 205 s |
| Logistic stack (market + ensemble) | no calibration | −0.01% [−0.28, +0.27] | 1 s |
| XGBoost anchored on the market | isotonic | +0.02% [−0.85, +0.88] | 47 s |
| XGBoost anchored, no calibration | – | −0.08% [−0.40, +0.24] | – |
| gbm anchored on the market | no calibration | −0.08% [−0.61, +0.43] | 1,244 s |
| Logistic on Elo + EPA separately | no calibration | −0.26% [−0.57, +0.03] | 1 s |
| XGBoost **without** the market anchor | no calibration | −0.86% [−2.14, +0.36] | 141 s |
| v1 ensemble alone (no market) | no calibration | −3.99% [−5.89, −2.07] | – |

**Most useful: the market-anchored logistic family** (glmnet or the simple stack). The reasons:
- It is as accurate as anything else.
- Its interval is half as wide as boosting's, so it is more stable week to week.
- It costs 1–200 s instead of 1,244 s.
- It is interpretable.

At NFL sample sizes (about 270 games a season) boosting adds variance, not accuracy. Early stopping kept the anchored XGBoost at a median of 9 trees, which is the model telling us there is little to learn beyond the market. Without the market anchor XGBoost is clearly worse, so **anchoring to the market is the single most important design choice.**

**Is any of them validated? No.** Every interval includes zero, and the Diebold–Mariano p-values (BH) are 1.000. "Validated" means passing the pre-registered gates on data not used for any choice. That needs the signed v2 protocol and the sealed 2025 holdout.

**Calibration:**
- The anchored blends are already calibrated: slopes 0.98–1.03.
- Platt and the 4-knot spline are neutral to slightly negative. Every spline fit was monotone.
- **Isotonic hurts** in every family except XGBoost: −0.2% to −0.6%, with slopes of about 0.87. It overfits step functions on about 1,300 games.
- **The engine's own spline calibrator is invalid** (audit M4, fit on leaked outcomes). It must not be used, and its replacement should be "none" or Platt, fit walk-forward.
- The production calibration chain (70% market weight plus isotonic) can only be validated once the simulator is point-in-time (Phase 1b, candidate C3).

## 3. Handicapping: spread and totals

The market baseline is the nflverse consensus closing spread/total price, devigged. The prices are low-vig (−105/−105 is the most common pair), and pushes are dropped.

**Brier:**
- **Spread:** the market scores 0.2494, and every model is slightly worse (−0.04% to −0.26%, all intervals include 0).
- **Totals:** the market scores 0.2499. The residual model is significantly worse (−0.40% [−0.71, −0.08]); the others are within noise.

**Flat 1-unit bets at the closing price when the model is ≥ 3 points off the market:**
- **Spread:**
  - The best is the time-zone rule: 268 picks, 51.9% [45.9, 57.8] against a 49.3% break-even at the prices taken, ROI +4.9%, p = 0.22.
  - It was selected on this same window, so the figure is optimistic.
  - XGBoost: 52.9% on 189 picks against a 51.2% break-even, ROI +2.8%, p = 0.35.
- **Totals:** every rule loses (ROI −3.4% to −14.0%).

**Conclusion.** No handicapping edge against the close is detectable. The time-zone travel effect on spreads is the one hypothesis worth a pre-registered, out-of-sample test. 2023–2025 spreads have not been analysed for it by anyone.

## 4. Tracking

- **`tracking/moneyline_tune.csv`:** every Tune game × candidate × calibration. Fields: model and market probability, outcome, Brier, log loss, and the market's Brier.
- **`tracking/handicap_tune.csv`:** the same for spread and totals.
- **`backtest/v2/track_append.R`:** grades each prospective 2026 weekly bundle into `moneyline_prospective.csv`. It refuses any season before 2026, refuses bundles generated after kickoff, and never double-counts (`tests/testthat/test-backtest-v2-track.R`).

## 5. What would actually give an edge

The close is the market's most informed price, and on this evidence it cannot be beaten with public, pre-kickoff information at NFL sample sizes. The realistic routes:

1. **Beat the opener, not the close.** Betting value is closing-line value: taking a price early that the close later moves toward. v1's EPA model showed +93 bps CLV at the ESPN BET opener [+40, +149], on 214 picks. That is descriptive only, below the 400-pick gate. Measuring it properly needs openers across 2023–2025 (Part B item 16) and forward capture, which is already running.
2. **Pre-register the time-zone spread hypothesis** and test it once on 2023–2025.
3. **Fix the simulator's architecture** (M22, M23, M18–M21) and let C3 compete under the same rules. Its lost adjustments must each earn their place in this screen first.

## 6. Owner decisions

- **Sign the v2 protocol** (`reports/2026-09-30/backtest-games-v2/PROTOCOL-DRAFT.md`). It freezes the candidates, endpoints, multiplicity rule and the single holdout score.
- **Choose how M22 is fixed** (see the audit addendum).
