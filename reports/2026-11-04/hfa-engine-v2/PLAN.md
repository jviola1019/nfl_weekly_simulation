# The engine's home-field comparison, v2: pre-registration (2026-11-04)

Written and committed before any v2 run. The owner asked on 2026-11-04 to "Complete and fix the home field issues".

## Why a v2

v1 (`reports/2026-11-04/hfa-engine/README.md`) was void.
- **No home field:** the calibration simulations averaged a −0.02-point home margin against +1.29 in the results.
- **Look-ahead (M5):** their home-field table included later seasons.

`5a0df15` fixes both:
- **The calibration's means are production's:** `compose_mu()` sums `MU_TERMS_ADMITTED`. The home team gets its full home-field points, there is no rest unless rest is admitted, and the run stops if a term is admitted that the calibration cannot simulate.
- **Home field as of each slate:** production builds its table at `SEASON`/`WEEK_TO_SIM`, and the calibration at every cut. Each table uses regular-season results, without neutral sites, from the ten seasons ending at the cut and played before its week.

## The question

Which home-field estimator should production use by default: `league`, `strength_free` or `team_margin`?

## The runs

- **What runs:** three `run_week.R 15 2024` runs at `5a0df15`, one per estimator (`options(nfl_sim.hfa_estimator)`).
- **Isolation:** each has a fresh HOME (calibration cache v7).
- **Scripts:** `run.R`, `run_all.sh`, `score.R` and `bias.R` from `reports/2026-11-04/hfa-engine/`, unchanged.
- **Scored:** each run's calibration simulations, the 1,322 regular-season games of 2019–2023. The measures are the Brier score and log loss of `p_home_2w_sim` against the results.
- **Intervals:** a week-block bootstrap, B = 10,000, seed 20261104 (the seed in `score.R`).

## Validity gates (all must hold, or nothing is decided)

| Gate | Requirement | Why |
|---|---|---|
| V1 | Every run's mean simulated home margin is between +0.29 and +2.29 points, within 1.0 of the results' +1.29 | The simulations carry a home field again. A ten-season window lags a home field that has been falling, so an exact match is not required. |
| V2 | Every run's intercept, from regressing the result margin on the simulated margin, is between −1.0 and +1.0 | v1's intercept was +1.31 in every run: the missing home field |
| V3 | Each run passes bundle QA and writes a calibration cache of 1,322 games | The run is complete |

## Decision rule

- **The default is `league`** unless `team_margin` or `strength_free` beats it.
- **"Beats":** the estimator's Brier minus league's has a 95% interval wholly below zero.
- **If both beat it,** the one with the lower Brier is the default.
- **Why league is the default to beat:**
  - the model gauntlet found it best;
  - it has one parameter;
  - `team_margin` mostly measures team strength.

  A team-specific value must clearly earn its place.

**Reported, not decisive:**
- log loss;
- the in-pipeline blend Brier, the number behind C3;
- the calibration slope;
- the difference between the two team estimators;
- the mean simulated home margin against the results and the closing spread.

## What it changes

- **If the rule picks an estimator other than `team_margin`:** `config.R` `HFA_TEAM_ESTIMATOR`'s default changes to it, and the golden master's move is attributed in CI.
- **If it keeps `team_margin`:** nothing changes.

## Disclosures

- **Same games as v1:** v1's numbers were seen, but they came from the broken calibration path.
- **2025** is not read.
- **The window is fixed:** this does not test the ten-season window or any recency weighting. If V1 shows a large lag, that is reported as a separate finding.
