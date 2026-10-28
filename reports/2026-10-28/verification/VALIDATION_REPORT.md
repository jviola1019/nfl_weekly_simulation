# Validation report: A3b's p-values, Brier and log loss, research and blends, recomputed independently

2026-10-28. The owner asked to verify the model p-values, Brier and log loss, the research validations and the blend validations.

`verify.R` recomputes every one of them along code paths independent of `backtest/vvf`'s statistics:
- base R: `glm`, `lm`, `anova`, `t.test`, `oneway.test`, `p.adjust`, `ks.test`;
- cluster-robust sandwiches written by hand;
- `lmtest`, `car` and `nlme`, all locked in `renv.lock`.

It writes `checks.csv`, one row per check with its largest difference and tolerance, and exits 1 if any check fails. Detail files sit beside it:
- `pvalue_calibration.csv`, the null simulations;
- `research_replication.csv`;
- `blends.csv`, every blend recomputed.

**Result: 56 of 56 checks pass** (`checks.csv`). Every number below is in those files, and `logs.txt` is the run's console output (1,449 s).

```
Rscript reports/2026-10-28/verification/verify.R reports/2026-10-28/verification origin/feat/validation-sprint-v2 origin/feat/blend-research
```

Run it from the repository root, with the blend branches fetched; it takes about 25 minutes. Long R runs go from a frozen copy of the script: Rscript reads a file as it runs, so editing it mid-run corrupts the run.

**What is shared, and what is not.** Three things are shared with the code under test:
- the data, through the VVF loaders, which the input checks (0 violations) and the v2 reproduction verify;
- the Rademacher weights of the wild bootstrap and the week-resampling counts of S3's bootstrap, so that the same draws can be compared exactly;
- S4's new-seed replication, which runs `vvf_control_null` itself.

Every statistic is recomputed independently: the fits, the tests, the sandwiches, the bootstrap arithmetic, the skill and loss formulas, BH and the blends' scores.

**Tolerance.** The committed CSVs hold 6 significant digits, so a recomputation passes within 1e-9 + 1e-5 × |reference|, unless a row says otherwise.

## A. S1, the per-feature screen (108 rows of the v2 reproduction)

| Check | Largest difference |
|---|---|
| `p_test`, LR or F, by `anova` | 4.96e-07 |
| The coefficient | 1.07e-05 (spread points; within 6 digits) |
| Robust SE, spread and total: a hand-written sandwich, (X'X)⁻¹ Σ_g U_g U_g' (X'X)⁻¹ × G/(G − 1) | 2.91e-05 (points; within 6 digits) |
| Robust SE, moneyline: the same for the logit | 2.71e-06 |
| `p_robust`, by z on the hand-written sandwich, and by `lmtest::coeftest` on `sandwich::vcovCL` | 4.84e-07 to 5.78e-06 |
| BH q within each family | 6.46e-07 |

**One finding, not a defect.** For the logit, the hand-written sandwich, evaluated at glm's converged probabilities, differs from `sandwich::vcovCL` by up to 1.6e-5 relative. vcovCL builds its bread from glm's stored IRLS working weights, which date from the last iteration (glm stops after 3 or 4 iterations here). With those weights the gap falls to 4.1e-6, the CSVs' rounding (`sandwich_convergence.R` and its output `sandwich_convergence.txt`). The moneyline rows therefore use a relative tolerance of 5e-5 for the SE and an absolute 1e-5 for p.

## B. The joint tests (6 rows)

| Check | Result |
|---|---|
| Estimable feature sets, by QR, independent of glm | 6 of 6 identical |
| `p_test` by `anova` | 4.24e-07 |
| The Wald statistic by `car::linearHypothesis` on a hand-written sandwich (v2's known answer, kept) | 0.000205 on statistics of 29–88 |
| `p_joint_wild` by a plain loop over the bootstrap draws (same weights) | identical (0) |
| `p_joint = max(p_test, p_joint_wild)` | 3.86e-07 |

## C. S3, incremental skill (36 features)

| Check | Result |
|---|---|
| Walk-forward predictions: an independent weekly refit loop against `vvf_s3_refit` | 2.22e-16 |
| Scored games | 1,365 for every feature |
| Brier skill, 1 − Brier / Brier(anchor) | 3.9e-09 |
| Brier and log-loss differences | 4.8e-10 and 1.75e-09 |
| Skill CI, the week-block bootstrap's arithmetic | 4.97e-09 |
| DM-HLN p against the paired one-sided `t.test` | 4.76e-07 |
| BH over the 36 | 4.39e-07 |
| Claims | none: 0 intervals wholly above 0; smallest BH p 0.964 |

**An identity.** At horizon 1, the DM-HLN statistic, d̄ / √(γ̂₀/n) × √((n − 1)/n), is exactly the paired t statistic, d̄ / (s/√n). So every S3 DM p (and every blend's, section G) is checkable with R's own `t.test`, and matches it.

## D. S5, the models' scores and diagnostics

| Check | Result |
|---|---|
| Brier of C0, C1, C2, E1 (plain formula) | 4.39e-07 |
| Murphy: reliability, resolution, uncertainty (own 10-bin rank binning) | 1.82e-07 |
| Calibration slope, with Wald CI | 4.97e-06 |
| Calibration-in-the-large, with Wald CI | 4.6e-07 |
| The anchor's Tune log loss, overall and by season | 2.42e-07 and 3.33e-07 |
| Loss ANOVA F and p (`oneway.test`), and BH over the four | 3.33e-06 and 2.41e-07 |
| Team effects, LR and F under treatment contrasts (the statistic is invariant to the contrasts) | 2.27e-05 on statistics of 1–63; p 1.22e-07 |
| E1 = the logit mean of C1 and C2, on every game | identical (0) on 3,508 games |
| The closing lines' error bias and variance | 0.000232 on variances of 163–178 |

## E. Are the p-values calibrated under the null?

Each test was run on data where the null is true. A calibrated test rejects about 5% at α = 0.05, inside the binomial 99% band, and has a uniform p, by the KS test. (`pvalue_calibration.csv`)

| Test | Draws | Rejects at 0.05 (99% band) | At 0.01 | KS p |
|---|---|---|---|---|
| S3's DM p, the real loss differences with signs flipped at random | 2,000 | 0.049 (0.038–0.063) | 0.005 | 0.111 |
| S1's LR p, 500 N(0, 1) placebos on the Tune design | 500 | 0.042 (0.026–0.076) | 0.010 | 0.364 |
| S1's robust p alone (sandwich z, 107 clusters) | 500 | 0.048 (0.026–0.076) | 0.006 | 0.215 |
| S1's p = max(LR, robust) | 500 | 0.040 (0.026–0.076) | 0.006 | 0.060 |
| The joint wild p, y drawn from the anchor, the real 29 situational features | 300 | 0.043 (0.020–0.083) | 0.007 | 0.559 |
| The joint LR p, the same draws | 300 | 0.043 (0.020–0.083) | 0.007 | 0.668 |

Every test holds its size. S1's robust p alone holds 0.048, the evidence RESEARCH.md cites for keeping it.

## F. The research, replicated (`research_replication.csv`)

| Claim | Replication |
|---|---|
| The cluster-robust Wald's null size is 0.399 (situational, 107 clusters) | 0.397 over 300 new draws, with `car::linearHypothesis` on a hand-written sandwich (3 SE: 0.085) |
| The season-week ICC is about 0 | REML random intercept (`nlme`): 0.00000 for the moneyline, ATS and total residuals |
| The late-change rows match their games | 77 of 77: each row's game exists, its week matches, and both franchises appear in its Wikipedia bullet |
| The anchor and permuted-x nulls claim nothing | On two new seeds (the null seed + 101 and + 102, B = 1,000), each null: 0 claims and 0 intervals wholly above 0 |
| The spec's shuffle fails by construction | On a new seed, 9 of 36 intervals wholly above 0 |

## G. The blends (#205: 30 candidates; #209: 9)

Recomputed from their committed per-game files, read with `git show` at #205 `759dd1c` and #209 `0347df3` (`blends.csv`):

| Check | Result |
|---|---|
| Per-game Brier and log loss in the tracking files, from `p_model` and the outcome | 1.2e-07 over 159,705 values |
| Their market probability against VVF's no-vig close | 4.99e-09 on 1,365 games: the same close in both codebases |
| #205: Brier, log loss and skill of its 30 candidates, against its `scores_tune.csv` | 4.6e-07 |
| #205: DM p, by the paired t-test | 4.98e-07 |
| #209: Brier, log loss and skill of its 9 new candidates | 5.0e-07 |
| #209: DM p, by the paired t-test | 1.04e-06 |
| #209: BH q over its 39 moneyline candidates | identical (0) |
| #209's C0, C1, C2 and E1 against VVF's own base predictions (Brier and log loss) | 4.6e-07: the same models in both codebases |
| The close's slope and calibration-in-the-large, VVF against #209 | 2.42e-06 |

**The blend conclusion holds.** The best candidate is S1 at +0.00068 Brier skill (one-sided DM p 0.262), then R1 at +0.00065 (0.368) and O1 at +0.00039 (0.358). Every BH q is 1.000, so no blend beats the close.

**Why the two intercepts differ.** #209's REPORT quotes the close's intercept as −0.080, and VVF's calibration file gives −0.0699. Both are right: −0.080 is the intercept of the recalibration model y ~ a + b·logit(p), and −0.0699 is calibration-in-the-large with logit(p) as an offset. #209's table carries both (`recal_intercept` −0.0804 and `citl` −0.0699), and its slope and calibration-in-the-large match VVF's.

## What this does not verify

- **Model choices:** that the protocol's choices are right, as opposed to computed right.
- **The feature builder's known-at timing.** The registry and the canary cover it.
- **The ESPN and nflverse source data.** The input checks cover keys and references only.
- **Anything after 2022, or the 2025 holdout.** Neither is read.
