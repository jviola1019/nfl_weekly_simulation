# The engine's home-field comparison (2026-11-04): void

**Status: void.** The engine's calibration path cannot compare home-field estimators: its simulations have no home field, and its home-field table looks ahead. `HFA_TEAM_ESTIMATOR` stays `team_margin`.

## The question

The model gauntlet (`reports/2026-11-03/model-gauntlet/RESULT.md`, PR #233) found that in a ratings model the engine's estimator (`team_hfa_table()`, each team's mean home margin, shrunk) costs +0.0048 Brier against a single league value. Does the engine agree?

## The runs

- **What ran:** three runs of the golden-master week (`run_week.R 15 2024`) at `746f0d6`, the same engine code as `a340a32`. There was one run per estimator (`league`, `strength_free`, `team_margin`).
- **Isolation:** each had a fresh HOME, so each built its own calibration cache: the engine's simulated probabilities for the 1,322 regular-season games of 2019–2023.
- **Outcome:** all three passed bundle QA (`out/runs.txt`).
- **Scoring:** against the results, with a week-block bootstrap (B = 10,000; `score.R`, `out/score.txt`).

**As scored:**

| Estimator | Brier | Log loss |
|---|---|---|
| league | 0.24162 | 0.67604 |
| strength_free | 0.24125 | 0.67533 |
| team_margin | 0.23773 | 0.66802 |
| no-vig close | 0.21236 | 0.61249 |

| Comparison | Brier difference | 95% interval |
|---|---|---|
| league − team_margin | +0.00389 | +0.00224 to +0.00560 |
| strength_free − team_margin | +0.00352 | +0.00171 to +0.00540 |
| league − strength_free | +0.00037 | −0.00027 to +0.00103 |

Taken at face value this reverses the gauntlet. It cannot be taken at face value.

## Why it is void

Both defects are in the calibration path, `week_inputs_and_sim_2w()`. Both were measured on the same games (`bias.R`, `out/bias.csv`).

**1. The calibration simulations have no home field.**
- **Production** gives the home team its full home field. The admitted term `hfa` is `HFA_pts = home_field_points(home_hfa, …)` (`NFLsimulation.R:3745`, composed at `:5399`; `MU_TERMS_ADMITTED`, `config.R:292`).
- **The calibration path** gives the margin `(home_hfa − away_hfa)/2` (`NFLsimulation.R:4601`). That averages zero, because every team is at home as often as it is away. Under `league` it is zero in every game: every team has the same value, and `DEN_ALTITUDE_BONUS` is 0.
- **Rest:** the calibration path also adds rest points (`:4603`), which production has not admitted.

| Same 1,322 games | league | strength_free | team_margin | Results | Closing spread |
|---|---|---|---|---|---|
| Mean home margin (points) | −0.02 | −0.01 | −0.02 | +1.29 | +1.57 |
| Mean home win probability | 0.499 | 0.499 | 0.499 | 0.530 (rate) | |
| Intercept of result margin on simulated margin | +1.31 | +1.31 | +1.31 | | |
| Correlation of simulated margin with the result | 0.247 | 0.247 | 0.291 | | 0.443 |

**2. The home-field table looks ahead (audit M5).**
- **One table for every week:** `seasons_hfa <- (SEASON - 9):SEASON` (`:1874`) builds a single table from 2015–2024 (`:2762-2784`). It is joined into every calibration week (`:4366`).
- **So:** each 2019–2023 game's team values include that game and later seasons.
- **Under `team_margin`** the difference `(home_hfa − away_hfa)/2` is mostly a difference in team strength, since a team's mean home margin measures how good the team is. It carries later seasons' team quality into the simulation. The correlation with the result rises from 0.247 to 0.291.
- **Conclusion:** `team_margin` scores best because of that leak. Home field plays no part.

## What reaches published numbers

C3 `p_home_final` is built in four steps:
1. it starts from the raw production simulator, which has the full home field (`NFLsimulation.R:7143`);
2. a ridge blend (`:7100-7113`) and an isotonic map (`:7127`) are applied;
3. the blend's model input is the spline-mapped calibration simulation (`map_iso(p_home_2w_sim)`, `:6418`/`:6436`);
4. the result is shrunk toward the market (`R/sim_bundle.R:88-99`).

That training-against-serving difference is audit M8. This finding adds that the two simulators also differ in home field and rest.

**The blend barely moves.** Its in-pipeline Brier on the same games is 0.216 under `league`, 0.215 under `strength_free` and 0.216 under `team_margin`, against the market's 0.212 (`out/runs.txt`).

## Decision, and where the fix lives

- **The default** stays `team_margin`. There is no valid engine-level comparison, and the gauntlet's evidence comes from a different model.
- **Neither defect is patched here.**
  - G1 (Plan 1b-2 in `docs/superpowers/plans/2026-10-12-modeling-roadmap.md`, branch `docs/modeling-roadmap`, PR #211) retires `week_inputs_and_sim_2w()` (M6/M8). It replaces it with one point-in-time `predict_week()` that production and the backtest share, with as-of features (M5) and a production = backtest bit-parity gate. That removes both defects.
  - Patching the function first would move the golden master twice.
- **After G1:** rerun this comparison on the shared `predict_week()` with these scripts. G2's term-admission backtest (M22) decides the default.

## Reproduce

From the repository root of the commit under test:

```bash
bash reports/2026-11-04/hfa-engine/run_all.sh <log dir> <scratch dir>     # three runs, about 20 minutes each
Rscript reports/2026-11-04/hfa-engine/score.R . <scratch>/home-hfa-league <scratch>/home-hfa-strength_free <scratch>/home-hfa-team_margin
Rscript reports/2026-11-04/hfa-engine/bias.R  . <scratch>/home-hfa-league <scratch>/home-hfa-strength_free <scratch>/home-hfa-team_margin out.csv
```

| File | What it holds |
|---|---|
| `run.R`, `run_all.sh` | the three engine runs |
| `score.R` | Brier, log loss and the paired bootstrap differences |
| `bias.R` | the home-edge measurements |
| `out/score.txt`, `out/bias.csv`, `out/runs.txt` | their outputs, and each run's estimator line, calibration size, in-pipeline Brier and QA line |
