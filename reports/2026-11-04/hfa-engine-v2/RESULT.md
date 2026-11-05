# The engine's home-field comparison, v2: result (2026-11-05)

**Status: void by a validity gate.** Gate V2 failed for `league`: its intercept is −1.024, outside the band of −1.0 to +1.0. Under the pre-registration (`PLAN.md`, committed as `cbce705` before any run), nothing is decided. **`HFA_TEAM_ESTIMATOR` stays `team_margin`.**

## The fix worked

The v1 defect is gone. The calibration simulations carry a home field again: +1.90 to +1.94 points in every run, against −0.02 in v1. Gate V1 passed.

## Why V2 failed, and why that is the gate's flaw

The intercept from regressing the result margin on the simulated margin is the mean result minus the slope times the mean simulated margin. It depends on the slope as well as on the level of home field.
- **The level is the same:** the three runs carry the same home field, +1.90 to +1.94.
- **The spread differs:** `league`'s simulated margins are less spread out (slope 1.20) than the team estimators' (0.76–0.77). That alone pushes its intercept to −1.02.
- **So:** the gate was meant to catch a missing home field, but it cannot tell a level problem from a spread problem.
- **It stands:** it was fixed before any run and is not changed after it.

## The runs (`out/runs.txt`, `out/bias.csv`)

- **What ran:** three `run_week.R 15 2024` runs of `5a0df15`, from a frozen worktree at `cbce705`, each with a fresh HOME.
- **The rerun:** the `team_margin` run first died on a dropped connection at 22:35Z: the schedule download returned an empty table, which led to `fix/schedule-load-error`. It was rerun at 04:08Z on 2026-11-05 from the same commit.

| Same 1,322 games (2019–2023) | league | strength_free | team_margin | Results | Closing spread |
|---|---|---|---|---|---|
| Mean home margin | +1.94 | +1.94 | +1.90 | +1.29 | +1.57 |
| V1: within 1.0 of +1.29 | pass | pass | pass | | |
| Intercept, result on simulated margin | **−1.024** | −0.207 | −0.150 | | |
| V2: between −1.0 and +1.0 | **fail** | pass | pass | | |
| Slope | 1.20 | 0.77 | 0.76 | | |
| Correlation with the result | 0.248 | 0.217 | 0.234 | | 0.443 |
| Mean home win probability | 0.553 | 0.552 | 0.549 | 0.530 (rate) | |
| V3: QA passed, 1,322 calibration games | pass | pass | pass | | |

## Exploratory: not a decision (`out/score.txt`)

| Estimator | Brier | Log loss | Blend behind C3 (in-pipeline Brier) |
|---|---|---|---|
| league | 0.24101 | 0.67476 | 0.215 |
| strength_free | 0.24373 | 0.68033 | 0.215 |
| team_margin | 0.24280 | 0.67878 | 0.216 |
| no-vig close | 0.21236 | 0.61249 | 0.212 |

| Comparison | Brier difference | 95% interval (week-block bootstrap) |
|---|---|---|
| league − team_margin | −0.00179 | −0.00462 to +0.00103 |
| strength_free − team_margin | +0.00093 | −0.00335 to +0.00513 |
| league − strength_free | −0.00272 | −0.00589 to +0.00046 |

- **The ordering reversed from v1.** With the look-ahead gone and the home field restored, `league` scores best and `team_margin` and `strength_free` follow. That is the model gauntlet's order. v1's `team_margin` lead came from the leak.
- **Nothing is significant:** no difference clears 95%.
- **Had the gates held,** the rule would have chosen `league`, because no team estimator beats it.
- **The blend behind the published C3 probability** barely moves: 0.215–0.216 against the market's 0.212.

## A separate finding: the window lags a falling home field

The ten-season window overstates today's home field by about 0.6 points: +1.94 against +1.29 in the results and +1.57 in the closing spread. Home field has fallen over those seasons. A shorter or recency-weighted window is a candidate for the term-admission backtest (M22). It is not tested here.

## What follows (the owner's choice)

1. **Keep `team_margin`.** This is the current default and the protocol's outcome.
2. **Switch to `league` as a judgment call.** For it:
   - the gauntlet found it best;
   - v2's point estimates agree;
   - it has one parameter and no strength confound.

   It is a `config.R` default change, which is an owner STOP.
3. **Run a v3 with a corrected gate** (V1 only, or the level gap instead of the intercept). It would be scored on games not used here, such as 2026 weeks 10–18 prospectively, so these games are not reused after being seen.
