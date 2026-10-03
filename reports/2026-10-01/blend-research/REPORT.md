# Blend research v3: can a mesh of XGBoost and logistic regression, or another model family, beat the close?

<!-- rendered by backtest/v3/report.R from the CSVs in this directory; do not edit by hand -->

**Owner's request (2026-10-01):** "Spend more time improving model accuracy and blending. Look into XGBoost blends and meshes with logistic regression, other models."

**Added 2026-10-03:** "Continue with all full access and testing, probabilities." So every family, new and v2, now has complete probability-quality evidence: Brier and log-loss skill with CIs, the logistic recalibration slope and intercept, ECE, and a 10-bin reliability table.

## Short answer

- **No.** On the 1,365 non-tie Tune games (2018–2022), no mesh and no other family beats the no-vig close.
  - The best new point estimate is S1 at +0.068% [-0.10%, +0.23%] Brier skill.
  - Every interval includes zero or lies below it, and after Benjamini–Hochberg across all 39 moneyline candidates (v2 and v3) every q-value is 1.000. The smallest one-sided Diebold–Mariano p among the new candidates is 0.262 (S1).
- **The meshes collapse onto the market.**
  - S1's ridge meta-learner gives all seven level-0 models a weight of zero (largest |weight| 4e-38) in every Tune week. So S1 is the close plus a walk-forward intercept, and that intercept is its whole edge.
  - R1's cross-validated boosting rounds fall from a median of 69 in 2018 to 1 in 2022: as the training window grows, the booster finds less to learn beyond the glmnet.
  - O1 ends with its weight on the close (0.24) and the four anchored blends (0.76 together); Elo, EPA and E1 end near zero (0.0001 together).
- **The other families find nothing either.**
  - G2's smooths are shrunk to at most 0.18 effective degrees of freedom after 2018 (season medians; a straight line is 1). Adding the four Tune-screened features makes it worse than the gap-only GAM: G2 -0.090% against G2_GAPS +0.003%.
  - T1's fits are singular (a team variance estimated at zero) in 106 of 107 weeks, and both team variances are zero in 84. The largest team SD in any week is 0.23 on the logit scale. No team is detectably mispriced.
  - N1's cross-validation picks the largest decay in every season, which pins it to the close (mean |logit gap| 0.005, skill -0.020% [-0.06%, +0.02%]).
  - Among the new candidates the only significant result is negative: N1_NARROW, the first version of N1, at -1.005% [-1.82%, -0.19%].
- **Probabilities.** The anchored families are as well calibrated as the close. The close has recalibration slope 1.05 [0.89, 1.20] and intercept -0.080 [-0.201, 0.040], and ECE 0.0310.
  - Among the uncalibrated families, only c2 has a slope CI that excludes 1 or an intercept CI that excludes 0.
- **Controls pass.** With the outcomes shuffled, no family, new or v2, shows positive skill over climatology (13 of 13 pass; largest point estimate -0.04%).
- **Nothing here is validated.** This is exploration on the window v2 already used for every choice.

All tables: `TABLES.md`, rendered by `backtest/v3/report.R` from the CSVs in this directory.

**Reproduce:**
```
Rscript backtest/v3/sprint.R --out reports/2026-10-01/blend-research --workers 8
Rscript backtest/v3/report.R reports/2026-10-01/blend-research
```
`--workers` only sets how many local R processes share the weekly fits. Each fit sets its own seed, so the outputs do not depend on it (the chunk-invariance test). The reproduction checks are `backtest/v3/check_v2_repro.R` (v2 unchanged) and `backtest/v3/check_rerun.R` (a second v3 run).

## What this is, and what it is not

- **Exploration on a window v2 already used.**
  - Tune 2018–2022 was the window for every v2 choice.
  - A good result here would be a *hypothesis* for the v2 protocol, not validation. Nothing below is "validated" or "calibrated" in the protocol's sense.
- **Data:**
  - Only Tune 2018–2022 is scored, with 2010–2017 as training history.
  - Confirm 2023–2024 and the sealed 2025 holdout were not built or scored. The sha-locked input files hold rows up to 2024. Each table is cut at 2022 right after its sha256 check, before any feature or model sees it, and every v3 fit stops on a row after 2022 (`bt3_guard`).
  - v3 checks its base models against v2's Tune-only tracking file. It never opens v1's `predictions.csv`, which also holds Confirm rows.
  - No 2025 row exists in any input. v2's sealed-season guard at 2024 is unchanged.
- **v2 is unchanged.** No file under `backtest/v2/`, `backtest/*.R` or `backtest/eval_windows/` was edited, and `PROTOCOL-DRAFT.md` is untouched.
  - A fresh re-run of the v2 stages reproduced 11 of 11 v2 output files byte for byte: 10 CSVs and TABLES.md (`v2_reproduction.csv`).
  - Level 0, regenerated inside v3 with v2's code, equals v2's committed Tune predictions exactly at their 8-decimal rounding: largest difference 1.1e-16 (`level0/check_vs_v2.csv`).
- **No new packages.** glmnet, xgboost, mgcv, lme4 and nnet all come from `renv.lock`. SVM was excluded because it does not give probabilities.

## Method

### Candidates

Every candidate is fit walk-forward by week, on games that kicked off before the week's first kickoff. Every one is built on the no-vig close: as an offset, as a base margin, or (O1) as one of the experts.

| Label | What it is | Inputs | How it is fit |
|---|---|---|---|
| **S1** | Stacked mesh | Logits of the 7 level-0 predictions: LR_E1, GLMNET, XGB, GBM, C1 (Elo), C2 (EPA GLM), E1 (v1 ensemble) | Ridge logistic (glmnet, alpha 0) with offset logit(close) and an unpenalised intercept; lambda.1se from season-grouped CV on the training games |
| **S1_MIN** | S1 with `lambda.min` | As S1 | Declared sensitivity variant of the lambda rule |
| **R1** | Residual mesh: XGBoost on top of the logistic blend | v2 features: Elo and EPA gaps plus 27 situational features | xgboost with `base_margin` = the anchored glmnet's out-of-fold logit; v2 XGB hyperparameters; rounds by early stopping in season-grouped CV on the training games, then refit |
| **O1** | Online convex blend | The 7 level-0 predictions plus the close | Exponentially weighted average on cumulative Brier loss; eta = 0.5, chosen on 2014–2017 |
| **G2** | GAM | Shrinkage smooths of the Elo and EPA gaps and of the v2 moneyline screen's 4 best features (raw p < 0.10: time zones crossed, closed roof, west-coast early kickoff, linebacker injuries) | `mgcv::gam`, REML, `bs = "ts"` (binary features as ridge-penalised `bs = "re"` terms), offset logit(close); every earlier game from 2010 |
| **G2_GAPS** | GAM without screen features | Elo and EPA gap smooths | As G2. The selection-free check on G2 |
| **T1** | Team mixed model | Home and away franchise | `lme4::glmer` with offset logit(close) and random intercepts for the home and the away team; rolling window = current season to date plus 2 prior seasons |
| **N1** | Neural net | logit(close) plus the v2 features | `nnet`, 1 hidden layer (size 1–3) with skip connections; the skip weight on logit(close) is fixed at 1 (an offset); size and decay (1 to 10,000) by season-grouped CV at each season's first week |
| **N1_NARROW** | N1 as first run | As N1 | Decay grid 1 to 100 only (see Disclosures) |

### How the nesting prevents leakage

1. **Level 0 is v2's own code, unchanged** (`bt2_walk_models`).
   - For each week from 2014 week 1, each v2 family is fit on every labelled game from 2010 that kicked off before that week, then predicts the week.
   - So every level-0 prediction is out of fold and point in time.
   - C1, C2 and E1 are v1's walk-forward base models.
2. **Level 1 for a Tune week uses only games that kicked off before that week:**
   - S1 and S1_MIN train on those games' level-0 predictions, each made before its own week, and on their outcomes. Lambda is chosen by CV inside that training set. They then predict the week from its own level-0 predictions.
   - R1's base margin is the glmnet's out-of-fold prediction on every training row and on the target week, so the booster fits the residual it will actually face. Its rounds are chosen by CV inside the training set.
   - O1's weights for a week depend only on the Brier losses of earlier games. eta was fixed once, on 2014–2017.
   - G2, T1 and N1 train on earlier games (T1 on its rolling window). N1's size and decay are chosen at each season's first week, on games before it.
3. **Burn-in.** Level 0 starts in 2014, and the meta-learners (S1, S1_MIN, R1) need at least 500 level-0 games over 3 seasons.
   - Before the first Tune week they already have 2014–2017 (1,064 labelled games; `meshes/s1_by_week.csv`).
   - O1 starts in 2014 with equal weights.
   - Burn-in weeks are not scored, and no Tune week is excluded.
4. **Tests** (`tests/testthat/test-backtest-v3-meshes.R`):
   - **Leak canary.** Every later outcome is flipped, including the target week's own, and every later feature, price, level-0 prediction and team label is rewritten. The target week's predictions stay bit-identical for all 9 new candidates.
   - **End-to-end nesting.** Level 0 refit with v2's code on the rewritten data feeds S1 and R1, with the same result.
   - Determinism run to run.
   - **Chunk invariance:** walking weeks together equals walking them one at a time, which is why the parallel run equals a serial one.
   - Shuffled-label sanity, and O1 weights use past losses only.
   - N1 keeps its market weight at 1. An unanchored net at the same decay collapses toward 0.5.
   - N1 tuning uses only games before the season, and every v3 fit refuses a 2023 row.
- **Statistics (as v2):**
  - Brier and log-loss skill vs the close, with week-block bootstrap 95% CIs (B = 10,000, v2's seed, so v2 rows keep their v2 intervals).
  - One-sided Diebold–Mariano tests with the HLN correction.
  - BH q-values across all moneyline candidates.
  - Logistic recalibration y ~ a + b·logit(p) with Wald CIs, calibration-in-the-large, and ECE with reliability in 10 equal-count bins.
  - v2 rows are re-scored from v2's committed per-game file, so v2 and v3 share one multiplicity family.

## Results: every family

All 39 candidates are scored on the same 1,365 Tune games. The table shows each family uncalibrated. v2's Platt, isotonic and spline variants are in `TABLES.md` (section 2) and are part of the BH family.

- Slope and intercept come from the recalibration fit y ~ a + b·logit(p).
- `fit (s)` sums the weekly fit times over the walk. v2 families' times are from their level-0 walk over 2014–2022 in this run; C1, C2 and E1 are not timed separately.

| family | source | Brier | Brier skill vs close [95% CI] | log-loss skill [95% CI] | DM p | BH q | slope [95% CI] | intercept [95% CI] | ECE | fit (s) |
|---|---|---|---|---|---|---|---|---|---|---|
| S1 | v3 (new) | 0.2110 | +0.07% [-0.10%, +0.23%] | +0.02% [-0.10%, +0.15%] | 0.262 | 1.000 | 1.04 [0.89, 1.20] | -0.045 [-0.164, 0.074] | 0.0305 | 28 |
| R1 | v3 (new) | 0.2110 | +0.07% [-0.25%, +0.38%] | +0.05% [-0.22%, +0.31%] | 0.368 | 1.000 | 1.00 [0.85, 1.14] | -0.045 [-0.164, 0.074] | 0.0285 | 136 |
| O1 | v3 (new) | 0.2110 | +0.04% [-0.14%, +0.22%] | +0.02% [-0.12%, +0.18%] | 0.358 | 1.000 | 1.03 [0.88, 1.18] | -0.061 [-0.181, 0.059] | 0.0316 | 1 |
| GLMNET | v2 (committed) | 0.2110 | +0.03% [-0.20%, +0.28%] | +0.01% [-0.20%, +0.23%] | 0.405 | 1.000 | 0.99 [0.84, 1.13] | -0.040 [-0.159, 0.079] | 0.0291 | 252 |
| S1_MIN | v3 (new) | 0.2111 | +0.02% [-0.21%, +0.23%] | -0.03% [-0.22%, +0.15%] | 0.457 | 1.000 | 1.03 [0.88, 1.18] | -0.043 [-0.162, 0.076] | 0.0287 | 33 |
| G2_GAPS | v3 (new) | 0.2111 | +0.00% [-0.13%, +0.13%] | -0.01% [-0.12%, +0.09%] | 0.488 | 1.000 | 1.04 [0.89, 1.20] | -0.054 [-0.173, 0.066] | 0.0325 | 184 |
| C0 | market | 0.2111 | +0.00% [+0.00%, +0.00%] | – [–, –] | – | – | 1.05 [0.89, 1.20] | -0.080 [-0.201, 0.040] | 0.0310 | – |
| T1 | v3 (new) | 0.2111 | -0.00% [-0.42%, +0.42%] | -0.10% [-0.42%, +0.23%] | 0.503 | 1.000 | 1.03 [0.87, 1.18] | -0.008 [-0.126, 0.110] | 0.0336 | 47 |
| LR_E1 | v2 (committed) | 0.2111 | -0.01% [-0.28%, +0.27%] | -0.04% [-0.28%, +0.22%] | 0.526 | 1.000 | 0.98 [0.84, 1.13] | -0.045 [-0.164, 0.074] | 0.0285 | 3 |
| N1 | v3 (new) | 0.2112 | -0.02% [-0.06%, +0.02%] | -0.02% [-0.04%, +0.01%] | 0.870 | 1.000 | 1.04 [0.89, 1.20] | -0.078 [-0.199, 0.042] | 0.0285 | 573 |
| GBM | v2 (committed) | 0.2113 | -0.08% [-0.61%, +0.43%] | -0.09% [-0.54%, +0.35%] | 0.597 | 1.000 | 1.02 [0.87, 1.17] | -0.053 [-0.173, 0.066] | 0.0435 | 1315 |
| XGB | v2 (committed) | 0.2113 | -0.08% [-0.40%, +0.24%] | -0.05% [-0.30%, +0.21%] | 0.691 | 1.000 | 1.03 [0.88, 1.19] | -0.074 [-0.194, 0.047] | 0.0375 | 62 |
| G2 | v3 (new) | 0.2113 | -0.09% [-0.26%, +0.08%] | -0.09% [-0.21%, +0.04%] | 0.805 | 1.000 | 1.04 [0.89, 1.19] | -0.053 [-0.172, 0.067] | 0.0325 | 273 |
| LR_C1C2 | v2 (committed) | 0.2117 | -0.26% [-0.57%, +0.03%] | -0.23% [-0.48%, +0.01%] | 0.921 | 1.000 | 0.99 [0.85, 1.14] | -0.050 [-0.169, 0.069] | 0.0419 | 1 |
| XGB_FREE | v2 (committed) | 0.2129 | -0.86% [-2.14%, +0.36%] | -0.72% [-1.85%, +0.36%] | 0.924 | 1.000 | 1.09 [0.93, 1.26] | -0.054 [-0.172, 0.065] | 0.0354 | 165 |
| N1_NARROW | v3 (new) | 0.2132 | -1.01% [-1.82%, -0.19%] | -0.79% [-1.44%, -0.14%] | 0.994 | 1.000 | 0.98 [0.83, 1.12] | -0.048 [-0.167, 0.071] | 0.0436 | 432 |
| E1 | v2 (committed) | 0.2195 | -3.99% [-5.89%, -2.07%] | -3.18% [-4.65%, -1.71%] | 1.000 | 1.000 | 1.10 [0.92, 1.28] | -0.093 [-0.213, 0.027] | 0.0430 | – |
| C2 | v2 (committed) | 0.2196 | -4.04% [-6.05%, -1.97%] | -3.15% [-4.64%, -1.60%] | 1.000 | 1.000 | 1.06 [0.89, 1.24] | -0.151 [-0.275, -0.027] | 0.0449 | – |
| C1 | v2 (committed) | 0.2224 | -5.33% [-7.56%, -3.13%] | -4.28% [-6.02%, -2.57%] | 1.000 | 1.000 | 1.02 [0.84, 1.20] | -0.009 [-0.124, 0.107] | 0.0248 | – |

- **Significant differences:** nothing is significantly better than the close. Significantly worse (CI entirely below 0):
  - new: N1_NARROW;
  - v2: the unanchored base models c1, c2, e1 (6 columns, including calibration variants).
- **Interval width tracks how far a family moves from the market:** S1 spans 0.33 points, O1 0.35, R1 0.64, T1 0.84, against 1.74 for v2's XGB with isotonic calibration.
- **By season** (TABLES.md section 5): no family is ahead of the close in every season.
  - S1's positive total comes from 2020 (+0.16%) and 2021 (+0.41%).
  - It is behind in 2018 (-0.11%), 2019 (-0.02%) and 2022 (-0.12%).

## Probability quality

For each family, uncalibrated:
- **Logistic recalibration:** y ~ a + b·logit(p). Perfect calibration is a = 0, b = 1; b < 1 means too extreme, b > 1 too timid.
- **Calibration-in-the-large:** the intercept with the slope fixed at 1.
- **ECE:** 10 equal-count bins.
- **Reliability:** each bin's mean prediction against the observed home-win rate.
  - `bins outside` counts bins whose observed rate's Wilson 95% CI excludes the mean prediction. About 0.5 such bins in 10 are expected by chance.
  - The full 10-bin tables, with n per bin and the CIs, are in `TABLES.md` section 4 and `scores/reliability_tune.csv`, which also covers every v2 calibration variant.

| candidate | ECE | slope b [95% CI] | intercept a [95% CI] | calibration-in-the-large [95% CI] | bins outside Wilson CI (of 10) | largest bin gap |
|---|---|---|---|---|---|---|
| S1 | 0.0305 | 1.04 [0.89, 1.20] | -0.045 [-0.164, 0.074] | -0.037 [-0.152, 0.078] | 1 | 0.076 |
| R1 | 0.0285 | 1.00 [0.85, 1.14] | -0.045 [-0.164, 0.074] | -0.045 [-0.161, 0.071] | 0 | 0.081 |
| O1 | 0.0316 | 1.03 [0.88, 1.18] | -0.061 [-0.181, 0.059] | -0.056 [-0.171, 0.060] | 0 | 0.075 |
| GLMNET | 0.0291 | 0.99 [0.84, 1.13] | -0.040 [-0.159, 0.079] | -0.043 [-0.159, 0.073] | 0 | 0.082 |
| S1_MIN | 0.0287 | 1.03 [0.88, 1.18] | -0.043 [-0.162, 0.076] | -0.038 [-0.153, 0.077] | 1 | 0.084 |
| G2_GAPS | 0.0325 | 1.04 [0.89, 1.20] | -0.054 [-0.173, 0.066] | -0.045 [-0.160, 0.070] | 0 | 0.072 |
| C0 | 0.0310 | 1.05 [0.89, 1.20] | -0.080 [-0.201, 0.040] | -0.070 [-0.185, 0.045] | 1 | 0.100 |
| T1 | 0.0336 | 1.03 [0.87, 1.18] | -0.008 [-0.126, 0.110] | -0.004 [-0.119, 0.111] | 1 | 0.090 |
| LR_E1 | 0.0285 | 0.98 [0.84, 1.13] | -0.045 [-0.164, 0.074] | -0.049 [-0.164, 0.067] | 0 | 0.079 |
| N1 | 0.0285 | 1.04 [0.89, 1.20] | -0.078 [-0.199, 0.042] | -0.069 [-0.184, 0.046] | 1 | 0.100 |
| GBM | 0.0435 | 1.02 [0.87, 1.17] | -0.053 [-0.173, 0.066] | -0.050 [-0.165, 0.066] | 0 | 0.064 |
| XGB | 0.0375 | 1.03 [0.88, 1.19] | -0.074 [-0.194, 0.047] | -0.066 [-0.181, 0.049] | 1 | 0.100 |
| G2 | 0.0325 | 1.04 [0.89, 1.19] | -0.053 [-0.172, 0.067] | -0.045 [-0.160, 0.070] | 0 | 0.080 |
| LR_C1C2 | 0.0419 | 0.99 [0.85, 1.14] | -0.050 [-0.169, 0.069] | -0.051 [-0.167, 0.064] | 1 | 0.108 |
| XGB_FREE | 0.0354 | 1.09 [0.93, 1.26] | -0.054 [-0.172, 0.065] | -0.037 [-0.151, 0.077] | 1 | 0.106 |
| N1_NARROW | 0.0436 | 0.98 [0.83, 1.12] | -0.048 [-0.167, 0.071] | -0.053 [-0.168, 0.062] | 1 | 0.082 |
| e1 | 0.0430 | 1.10 [0.92, 1.28] | -0.093 [-0.213, 0.027] | -0.070 [-0.183, 0.042] | 1 | 0.109 |
| c2 | 0.0449 | 1.06 [0.89, 1.24] | -0.151 [-0.275, -0.027] | -0.133 [-0.246, -0.020] | 0 | 0.071 |
| c1 | 0.0248 | 1.02 [0.84, 1.20] | -0.009 [-0.124, 0.107] | -0.006 [-0.118, 0.106] | 0 | 0.046 |

- **The close itself is calibrated on Tune:** slope 1.05 [0.89, 1.20], intercept -0.080 [-0.201, 0.040].
  - Its intercept leans negative: home teams won slightly less often than the close implied. The CI includes zero.
  - That lean is what the walk-forward intercepts of S1 and T1 pick up.
- **Miscalibrated uncalibrated families:** c2 (slope 1.06, intercept -0.151). Its intercept or slope CI misses the ideal value. It is an unanchored base model, not a candidate.
- **v2's isotonic maps** still produce slopes of about 0.87 (too extreme), as v2 found.

## Controls

- **Shuffled labels:**
  - Outcomes are permuted globally with v2's seed: the same permutation as v2's control.
  - Every learner is refit walk-forward on the permuted labels. That includes the four level-0 families feeding the meshes (GBM's first shuffled-label control), followed by every new family.
  - Each is scored on Tune against an expanding home-win-rate climatology.
  - **Pass rule (v2's):** the lower bound of the skill CI is not above 0. The table also shows whether the point estimate is ≤ 0.

| model | refit as | skill vs climatology [95% CI] | passed | point <= 0 |
|---|---|---|---|---|
| LR_E1 | v2 level-0 (refit) | -0.13% [-0.25%, -0.01%] | TRUE | TRUE |
| GLMNET | v2 level-0 (refit) | -0.04% [-0.12%, +0.03%] | TRUE | TRUE |
| XGB | v2 level-0 (refit) | -8.44% [-11.84%, -5.02%] | TRUE | TRUE |
| GBM | v2 level-0 (refit) | -8.92% [-12.40%, -5.44%] | TRUE | TRUE |
| S1 | v3 new | -2.06% [-4.20%, +0.06%] | TRUE | TRUE |
| S1_MIN | v3 new | -2.17% [-4.24%, -0.17%] | TRUE | TRUE |
| R1 | v3 new | -0.10% [-0.41%, +0.20%] | TRUE | TRUE |
| O1 | v3 new | -0.07% [-0.15%, +0.01%] | TRUE | TRUE |
| G2 | v3 new | -8.53% [-11.97%, -5.03%] | TRUE | TRUE |
| G2_GAPS | v3 new | -8.54% [-11.99%, -5.01%] | TRUE | TRUE |
| T1 | v3 new | -10.48% [-14.44%, -6.62%] | TRUE | TRUE |
| N1 | v3 new | -3.28% [-5.02%, -1.55%] | TRUE | TRUE |
| N1_NARROW | v3 new | -3.28% [-5.02%, -1.55%] | TRUE | TRUE |

- **Result:** 13 of 13 pass. Every point estimate is at or below 0.
- **Reproduction of v2's control:** LR_E1, GLMNET and XGB reproduce v2's committed control values, because they are the same refits on the same permutation.
- **What the anchored families show:** they are far below climatology under permutation, because the close they are anchored to carries no information about permuted outcomes. That is the expected behaviour of an anchored model, not a defect.
- **N1 and N1_NARROW are identical under permutation** (-3.28% each). Identical predictions mean both CVs picked the same size and a decay of at most 100 (N1_NARROW's grid) on the permuted labels.
- **Leakage, determinism and point in time** are covered by the tests above.
- **Reproducibility:** a second full run of `sprint.R` reproduced 20 of 20 CSVs byte for byte (`determinism.csv`; `backtest/v3/check_rerun.R`).
- **v2 is unchanged:** the re-run reproduced all of v2's files byte for byte, and level 0 matches v2's committed Tune predictions.

## Which mesh is most useful, and why

**S1, the stacked mesh**, though not because it beats the close. Three reasons:
- **Accuracy and stability.** It has the best point estimate of any candidate, +0.068% [-0.10%, +0.23%], with one of the narrowest intervals (0.33 points wide, against 0.64 for R1). That interval comes from moving only slightly from the market: mean |logit gap| 0.035.
- **Cost.** About 28 s of fitting on top of level 0, against 136 s for R1.
- **It is interpretable, and its fit is the main finding of this sprint.**
  - The meta-learner shrinks every level-0 weight to zero in every Tune week. None of the seven models (logistic, glmnet, XGBoost, gbm, Elo, EPA, ensemble) carries information the close lacks.
  - What S1 adds is a walk-forward intercept: on average 0.003 in 2018, -0.035 in 2020 and -0.057 in 2021 (logit scale), tracking the close's own negative intercept on Tune.
  - That component needs no level-0 model at all. It is a one-parameter correction of home-field advantage in the close.
  - One possible explanation is the shift in home-field advantage around the 2020 season played without crowds. This run does not test it.

**The other meshes:**
- **O1 (online blend)** is the most stable runner-up: +0.039% [-0.14%, +0.22%], with no tuning on Tune. It needs the full level-0 stack, though, and its weights end on the close and the anchored blends.
- **R1 (XGBoost on the logistic residual)** gets a similar point estimate (+0.065% [-0.25%, +0.38%]) with an interval 1.9 times as wide: boosting adds variance, not information, which repeats v2's finding.
- **S1_MIN** (the less-shrunk lambda) scores +0.016% [-0.21%, +0.23%]. Letting the level-0 weights move away from zero lowers the point estimate; the difference from S1 is within noise.

## Verdict

- **Nothing beats the closing moneyline on the Tune window,** whether a mesh of XGBoost and logistic regression or any of the other families tried (GAM, team mixed model, neural net, online blend).
- **The more flexible the family, the closer its cross-validation pushes it to the market:**
  - the stack zeroes its model weights;
  - the booster's cross-validated rounds fall to 1 by 2022;
  - the GAM shrinks its smooths away;
  - the mixed model finds almost no team variance;
  - the net is decayed onto the close.
- **Probabilities:** the anchored families are calibrated about as well as the close itself. None has a slope or intercept CI that excludes the ideal value.
- **Overall:** this repeats v2's conclusion with more model capacity. At about 270 games a season, public pre-kickoff information adds nothing detectable beyond the closing price.
- **Status:** it is exploration on a window already used, so it is evidence of absence at this sample size, not proof that no edge exists.

## What to pre-register in the v2 protocol (proposals only; `PROTOCOL-DRAFT.md` is unchanged)

1. **No v3 family has earned a place as a likely winner.** On this evidence the draft's L1, G1 and X1 (and C3 when it is point in time) remain the right candidates.
2. **Optional, if the owner wants one mesh in:** S1 in its reduced form, "close plus a walk-forward intercept".
   - Why: one parameter, no Tune-selected inputs, and an interval 0.33 points wide, against 0.65 for X1 (v2's XGB).
   - It should *replace* X1 rather than be added, so the multiplicity stays at four.
   - The hypothesis it tests is narrow: does the close misprice home-field advantage on average?
3. **Keep the v2 choices that v3 supports:**
   - anchor every candidate on the market;
   - use no calibration map for anchored blends (their recalibration slopes cover 1, and isotonic still over-steepens);
   - run the shuffled-label control on every learner, now including gbm.
4. **Do not pre-register G2** (its features were selected on Tune), **T1** (almost no team variance) or **N1** (its CV pins it to the close).

## Disclosures (choices made after seeing a Tune result)

- **N1's decay grid.**
  - The first development run used decay 1–100. Its CV chose the grid edge (100) in every season, and that run's Tune score had been seen.
  - The grid was widened to 1–10,000 so the CV optimum could be interior. The CV then chose the new edge, 10,000, in every season, which is the limit where the net becomes the close.
  - The first version is kept as **N1_NARROW** (-1.005% [-1.82%, -0.19%]) in every table and in the BH family, so the choice is visible.
- **O1's eta grid.**
  - The first grid started at 0.5, and the selection on 2014–2017 chose that edge. It was widened to 2^-4…2^6, and 0.5 is the interior optimum, so O1's predictions did not change (`meshes/o1_eta_grid.csv`).
  - eta = 0.5 is also the largest rate at which squared loss on [0, 1] is exp-concave, the condition for EWA's ln(N)/eta regret bound.
- **G2's features** were chosen from v2's Tune screen (raw p < 0.10). Its Tune score is therefore optimistic, and G2_GAPS is the selection-free comparison.
- **S1_MIN** was declared as a sensitivity variant in the code before any Tune result was seen.
- **Development runs** used the same Tune window. Every number in this report comes from the committed run in this directory.

## Compute

- **Whole run:** 1379 s wall-clock with 8 worker processes. That covers level 0 for 2014–2022, the 9 new candidates, and the full shuffled-label control including its level 0.
- **Level 0 stage:** 231 s.
- **New families' fits:** 1707 s of fitting in total. The most expensive are N1 (573 s, mostly its CV) and G2 (273 s).
- Per-family numbers: `compute/seconds.csv` and `TABLES.md` section 9.

