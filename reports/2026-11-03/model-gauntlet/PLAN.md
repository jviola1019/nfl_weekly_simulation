# The NFL model gauntlet: can any model family beat the no-vig close, or add to it?

**Written 2026-11-03, before any gauntlet prediction was scored.** The plan is committed first, and the run records this file's sha256. It is exploratory: no bet and no app number depends on it. A family that passes earns a pre-registered confirmation, not a place in the model.

## Why

- **What has been tested:** games v1 (`reports/2026-09-29/backtest-games-v1/`) tested Elo (C1), an EPA ridge (C2), their ensemble (E1) and market stacks. None beat the no-vig close on Confirm 2023–24.
  - That is a result about a few families. Reporting "nothing works" from it overstates what was searched.
- **The ask:** on 2026-11-03 the owner asked for "various different models (RoboBot sim should be looked into), concepts and … testing … gauntlet looping".
- **The model:** this follows the owner's own `fantasy_football_dashboard/scripts/model-gauntlet.ts`. The search widens and the evidential standard stays the same: nothing is relaxed to produce a winner, and positive controls must pass or the run is void.
- **"RoboBot sim":** no project or product of that name was found (this repo, the owner's other projects, the web). It is read here as a game simulated drive by drive (family F9). That is a different concept from the production simulator, which draws scores from fitted means. The reading is open to the owner's correction.

## Data and windows

- **Inputs:** `backtest/data/` is committed and point-in-time:
  - games 1999–2024;
  - per-team and per-QB EPA, 2006–2024.
- **One new derived table,** `backtest/data/drive_games.csv`: per team-game drive counts and outcomes for 2006–2022, from nflverse play-by-play (keyless), with each raw file's sha256 in its sources record.
- **2025 is never read.** 2023–2024 are not used either: they stay unseen for any survivor's confirmation.
- **Selection window, 2012–2017:** every family predicts walk-forward, week by week. Each family's hyperparameters are chosen by mean log loss here; a tie goes to the simpler setting.
- **Gauntlet window, 2018–2022:** every family predicts walk-forward with its selected hyperparameters, and is scored once.
- **Training for a week** uses only games that kicked off before that week's first kickoff (`bt_assert_asof` on every feature).
- **Scored games:** regular season and postseason, with a no-vig close (`p_c0`) and a result. Ties are excluded from win scoring.

## Families

Each family gives P(home win) per game. Families with a margin model also give a median margin.

| ID | Family | Concept | Selection grid |
|---|---|---|---|
| F1 | Elo (C1's form, FiveThirtyEight) | Margin-of-victory Elo, seasonal regression | `BT_ELO_GRID` |
| F2 | QB-adjusted Elo | F1 plus the starting QB's value against the team's recent QB, from rolling QB EPA per dropback | QB weight {0.5, 1, 1.5} × QB half-life {4, 8, 16} games |
| F3 | EPA ridge (C2) | Exponentially weighted EPA features, ridge logistic | `BT_EPA_GRID` (half-life {4, 8, 16} × lambda {1, 10, 100, 300, 1000}) |
| F4 | Margin ratings (Massey) | Weighted least squares on margins with exponential decay and league home field; P = Φ(margin / σ), σ from training residuals | decay half-life {4, 8, 16, 32} weeks |
| F5 | Ratings with team home field, strength-free | F4 plus a team home term shrunk toward the league value (team strength estimated jointly) | F4 × shrinkage {1, 4, 16} |
| F6 | Ratings with the engine's team home field | F4 with each team's home field = mean home margin shrunk n/(n+60), as `team_hfa_table()` does; this measures the confound found in the final test | F4 |
| F7 | Poisson scores (Maher) | log means = attack + defence + home, exponentially weighted Poisson GLM; P from the two Poissons (ties split) | half-life {8, 16, 32} weeks |
| F8 | Dynamic ratings (Kalman) | Team strength a random walk; margin = strength difference + home field + noise | process SD {0.5, 1, 2} points/week × season carry-over {0.5, 0.75, 1} |
| F9 | Drive simulator | Each drive ends in a touchdown, field goal, score for the defence or nothing. The rates come from the offence's and defence's weighted histories; drives per team come from both teams' pace; 20,000 simulated games; an overtime tie is split | half-life {8, 16, 32} weeks |
| F10 | Gradient boosting (xgboost) | Trees on F1's rating difference, F3's EPA features, rest difference, division and neutral flags | depth {2, 3} × rounds {100, 300}, eta 0.05 |

**Stacks.** For every family F there is a stack S[F]: logit P = a + b·logit(C0) + c·logit(P_F), fitted by maximum likelihood.
- **Training data:** the selection window's predictions plus every gauntlet week before the one predicted.
- **What it asks:** whether F adds information the market lacks. A model can lose to the market alone and still add to it.

**Reference:** C0, the no-vig close.

## Statistics, and what passing means

- **Reported for each candidate** on the gauntlet window:
  - Brier score and log loss, and the difference from C0;
  - a week-block bootstrap 95% interval (B = 10,000, seed 20261103);
  - a one-sided Diebold–Mariano test (HLN-corrected) on the Brier difference;
  - calibration slope, ECE, and median-margin MAE against the closing spread.
- **The correction:** Holm, across all 20 candidates (10 families, 10 stacks).
- **PASS** requires both:
  - a Holm-adjusted p below 0.05;
  - a bootstrap interval of the Brier difference wholly below 0.

## Controls (a failure voids the run)

| ID | Control | Must |
|---|---|---|
| K1 | **Leak canary:** a feature equal to the final margin plus N(0, 7²) noise. (a) The as-of assertion must reject it, since its source ends after kickoff. (b) With the assertion bypassed, a stack given it must PASS. | (a) reject, (b) pass |
| K2 | **Market copy:** logit(C0) plus N(0, 0.1²) noise | not pass |
| K3 | **Shuffled scores:** F1 and F4 rerun on globally permuted result tuples (`bt_shuffle_scores`) | not pass |
| K4 | **Implausible skill:** a non-control family with Brier skill above 5% against C0 | none |
| K5 | **Reproducibility:** the whole run twice gives the same result sha256 | identical |

## Outcomes

- **Nothing passes:** the run states a null for these 20 candidates on 2018–2022, with each one's interval. That is a wider null than v1's, not a proof that no edge exists.
- **A family or stack passes:** it is a candidate. Its confirmation is a separate protocol on unseen data:
  - 2026 weeks forward, prospectively;
  - or the sealed 2025 season, once, if the owner opens it (checkpoint 8).
  - Confirm 2023–24 cannot serve: games v1 already scored candidates there.
- **Either way,** F5 against F6 shows whether the engine's home-field estimator costs accuracy. That is an input to the term-admission backtest (M22).
