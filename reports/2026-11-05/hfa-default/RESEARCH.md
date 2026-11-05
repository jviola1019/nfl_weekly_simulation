# Home-field default: league (2026-11-05)

The owner asked on 2026-11-05 to "choose whatever is recommended with extensive research". The choices were the three options in `reports/2026-11-04/hfa-engine-v2/RESULT.md`:
- keep `team_margin`;
- switch to `league`;
- run a v3 with a corrected gate.

**The recommendation is `league`.** `config.R`'s `HFA_TEAM_ESTIMATOR` now defaults to it.

## What the literature and established models do

| Source | Home-field model | Finding on team-specific home field |
|---|---|---|
| FiveThirtyEight NFL Elo ([methodology](https://fivethirtyeight.com/methodology/how-our-nfl-predictions-work)) | One league-wide adjustment (about 48 Elo points) from a rolling 10-year average, plus travel distance | Not modelled per team |
| nfelo ([HFA tracker](https://www.nfeloapp.com/tools/nfl-home-field-advantage-hfa-tracker/), [further exploration](https://www.nfeloapp.com/analysis/a-further-exploration-of-home-field-advantage-in-the-nfl/)) | A backward-looking rolling league average, plus situational adjustments (divisional games, surface, byes, time zones) | "few, if any, teams possess predictably better HFA than others"; its variance "would suggest it is more ephemeral or perhaps even random" |
| Open Source Football, 2021 ([analysis](https://opensourcefootball.com/posts/2021-01-11-hfa-analysis/)) | League home field as a fixed effect (about 2.85 points, 2006–2020); team home field as a random slope | "iHFA appears to be very unpredictable and almost random on a year over year basis" |
| Tierney ([hierarchical model](https://g-tierney.github.io/post/home_field/)) | Each team's home field drawn from a league distribution, fitted each season (Stan) | Team values have converged: "Starting around 2015, that variability drops off and teams all start to look very similar to each other". There is no formal test. |

**Recent level:** nfelo reports 2.05 points over the last 5 seasons and 2.34 since 1999, and says recent seasons are "closer to 1.5 points than to 2.5 points".

## Our evidence

- **The model gauntlet** (2018–2022, 1,365 games, a ratings model): the engine's team estimator cost +0.0048 Brier against a league home field (interval +0.0025 to +0.0072). Strength-free team terms cost +0.0012 (+0.0003 to +0.0020). League was best.
- **The engine's v2 comparison** (void by its gate, so exploratory): league was best (−0.0018 against `team_margin`, interval −0.0046 to +0.0010).

## The decision and its scope

- **Default:** `league`. Every team gets the league value as of the slate (`hfa_table_asof()`), which `DEN_ALTITUDE_BONUS` (0) leaves unchanged.
- **Kept:** `team_margin` and `strength_free` remain options (`options(nfl_sim.hfa_estimator = ...)`).
- **Not changed here:**
  - **The window:** ten seasons, the same as FiveThirtyEight's. It overstates today's home field by about 0.6 points (+1.94 simulated against +1.29 in the results, 2019–2023). nfelo's shorter window and its situational adjustments are candidates for the term-admission backtest (M22), each pre-registered. Changing the window here would be a second change without its own evidence.
- **Golden master:** it moves. Every home team's value becomes the league value as of the slate, so `mu_home` changes in every game. CI attributes the change.
