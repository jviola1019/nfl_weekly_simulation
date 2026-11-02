# Other ways to gain value: the hypotheses, fixed before testing

2026-10-29. The owner asked for more information on different hypotheses of gaining value or profit. This file fixes each hypothesis, its data, its test and its decision rule **before** any of them is run. It is committed first, so the commit time stamps it.

## How results will be read

- **Families.** Each family is corrected with BH at q < 0.05. A family's tests share data or a mechanism.
- **Direction.** A test is one-sided only where a published study or the stated mechanism fixes the direction. Every other test is two-sided.
- **Statistically promising** means significant after BH.
- **Economically promising** means the betting return, after the spread and fees, has a 95% interval above 0. Intervals resample games, or season-weeks for game lines.
- **Data already seen.** The 2026 weeks 1–7 Kalshi data were already explored for calibration (`reports/2026-10-28/feasibility`). A test on them that overlaps that look is marked *seen*, and it cannot be confirmatory.
- **Nothing here confirms an edge.** A promising result becomes a hypothesis of `nfl_props_v1` or `nfl_market_v1`. It is confirmed only on games played after this file's commit: 2026 week 8 onward.
- **No 2025 data.** Every loader asserts it, and every Kalshi request is windowed to 2026 closes.

## Family E: published NFL line anomalies, tested after their authors' samples

The data are nflverse closing spreads, totals and odds from 1999–2024, plus 2026 weeks 1–7.
- **Each test** runs only on seasons after the study's last sample season. If that season is unknown, it runs on seasons after publication.
- **The statistic** is the rate of the predicted side, with pushes excluded. The 95% interval resamples season-weeks.
- **The return** uses the recorded odds where nflverse has them, and −110 otherwise.

| ID | Study | Bet | Test seasons | Direction |
|---|---|---|---|---|
| E1 | Levitt (2004), 1980–2001 | Home underdogs against the spread | 2002–2024 | cover > 50% |
| E2 | Borghesi (2007), late-season bias | Home underdogs, weeks 13+ | 2007–2024 | cover > 50% |
| E3 | Borghesi (2008), weather, 1984–2004 | Under, outdoors, wind ≥ 15 mph | 2005–2024 | under > 50% |
| E4 | Borghesi (2007), home weather advantage | Home team, outdoors, ≤ 32°F, visitor from a dome or warm city | 2008–2024 | cover > 50% |
| E5 | Shank (2019), 2003–2016 | Away team in division games | 2017–2024 | home cover < 50% |
| E6 | Shank (2019), 2003–2016 | Under in division games | 2017–2024 | under > 50% |
| E7 | Shank (2018) | Home underdogs of 7 or more | 2018–2024 | cover > 50% |
| E8 | Shank (2018) | Over, closing total in its season's bottom or top 10% | 2018–2024 | over > 50% |
| E9 | Shank (2018) | Home team that failed to cover its previous game | 2018–2024 | cover > 50% |
| E10 | Costa (2025), 2020–2024 | Away moneyline when the home no-vig price is 0.3–0.7 | 2026 weeks 1–7 | return > 0 |

For context, each anomaly is also shown over its study's own years. Those results are a replication, not a test.

## Family A: Kalshi's structure and relative value, at the close, 2026 weeks 1–7

| ID | Hypothesis | Test |
|---|---|---|
| A1 | Kalshi's spread ladder misprices the NFL margin's key numbers (3, 7, 10, 14) | A model of P(margin > x \| spread), from 2015–2024 games, centred on nflverse's closing spread (Gaussian kernel on the spread, bandwidth 1.5). Its paired Brier is compared with Kalshi's close on `KXNFLSPREAD`, by game, with H1 that the model is better; plus the model's taker return. A secondary model is trained on 1999–2024. |
| A2 | The same for totals and team totals | The same with P(total > x \| total line) on `KXNFLTOTAL`, and P(points > x \| implied team total) on `KXNFLTEAMTOTAL` |
| A3 | Protected and unprotected twins are priced inconsistently | For each pair (same player, stat, threshold and game), count the pairs where the protected Yes bid exceeds the unprotected Yes ask, or the reverse, after fees. Test whether the price gap predicts the payout gap (two-sided). |
| A4 | The touchdown family breaks its order: first TD ≤ team first TD ≤ anytime TD | Count bid/ask violations at the close beyond fees, and the return from trading them |
| A5 | Scalar ladders and binary ladders imply different expected yards | Compare the binary ladder's implied mean (survival summed between rungs) with the scalar price; regress realized yards on both (two-sided) |
| A6 | A ladder's rungs break monotonicity: a higher rung's bid above a lower rung's ask | Count, and the return after fees |

## Family B: information and behaviour in Kalshi props, 2026 weeks 1–7

| ID | Hypothesis | Test | Direction |
|---|---|---|---|
| B1 | The market under-adjusts teammates when a player is out | Calibration-in-the-large of contracts on teammates of a player who was Out on the final report or never took a snap, against all other contracts | teammates > others |
| B2 | Questionable players who play are underpriced (a no-snap refunds at the fair price, so no discount is due) | Calibration-in-the-large of contracts on players listed Questionable who played | > 0 |
| B3 | The last day's move overreacts (Moskowitz 2021) | y ~ offset(logit close) + (logit close − logit 24 h before), clustered by game | coefficient < 0 |
| B4 | The price 24 hours out is miscalibrated in a way a refit can use | A recalibration of the 24 h price fit on weeks 1–5 and scored on weeks 6–7; Brier and taker return | two-sided |
| B5 | Thin markets are less efficient | Calibration slope and calibration-in-the-large in the bottom against the top tercile of 48 h volume | two-sided |
| B6 | Takers over-buy YES on cheap contracts (Bartlett 2026; Bürgi, Deng and Whelan) | Calibration-in-the-large of contracts priced under 20¢ (*seen*) | < 0 |

## Family C: makers and takers, from Kalshi trades

The sample is every `KXNFLGAME` market and a random sample of 2,000 other contracts from weeks 1–7. The window is each trade before kickoff, up to 72 hours.
- **The maker's P&L** per contract is p − y when the taker bought YES, and y − p when the taker bought NO, with p the YES price.
- **The taker's P&L** is the negative of that, less the taker fee.
- **The maker fee** of 0.0175 × P × (1 − P) is applied in a second version.

| ID | Hypothesis | Test |
|---|---|---|
| C1 | Makers earn a positive return before kickoff, net of the maker fee | The mean P&L per contract, with games resampled (one-sided > 0) |
| C2 | Taker order flow in the last 24 hours is informed | y ~ offset(logit close) + the net YES share of taker volume, clustered by game (two-sided) |

## Family D: in-game prices against a public win-probability model, 2026 weeks 1–7

The data are Kalshi `KXNFLGAME` one-minute candles from kickoff to the end of each game, and nflfastR's `vegas_home_wp` from 2026 play-by-play.
- **The model's price** at each minute is the pre-snap win probability of the first play after that minute.
- **Kalshi's price** is the home team's mid.

| ID | Hypothesis | Test |
|---|---|---|
| D1 | The public model is more accurate in-game | Paired Brier by game, one value per game (two-sided) |
| D2 | The model adds information to the live price | y ~ offset(logit Kalshi) + (logit model − logit Kalshi), clustered by game (one-sided > 0) |
| D3 | The live price lags scoring plays | The median minutes until Kalshi's price moves half of a scoring play's model jump (descriptive) |

## Family F: Kalshi against DraftKings, 2026 weeks 6–7

The data are the moneyline at the last capture before kickoff, from ESPN's odds in the capture archive, against Kalshi's price at the same hour.

| ID | Hypothesis | Test |
|---|---|---|
| F1 | Buying the cheaper side on each venue sometimes locks a profit | The count of games where the two best prices sum below 1 after Kalshi's fee and DraftKings' price |
| F2 | One venue is more accurate | Paired Brier by game (two-sided) |

## Family G: a simple public projection, against Kalshi props, 2026 weeks 2–7

The projection uses only 2026 games before the week being priced:
- each player's exponentially weighted mean (half-life 3 games), shrunk to his position's mean (weight n / (n + 3));
- a negative binomial for counts, and a gamma with a zero mass for yards, with dispersion fit by position on the earlier weeks.

| ID | Hypothesis | Test |
|---|---|---|
| G1 | The projection adds information to Kalshi's close | y ~ offset(logit close) + (logit model − logit close), clustered by game (one-sided > 0) |
| G2 | Betting the disagreements pays after costs | The taker return where the model beats the ask plus the fee; 95% interval by game |

## Family H: opening lines, ESPN BET 2023–2024 (D1's archive)

| ID | Hypothesis | Test |
|---|---|---|
| H1 | The move from open to close overreacts (Moskowitz 2021) | y ~ offset(logit close) + (logit close − logit open), clustered by season-week | coefficient < 0 |
| H2 | The move is predictable from the opener | Regress the move on the open price, home and favourite, fit on 2023 and scored on 2024. The test is the correlation of the predicted and actual moves (one-sided > 0), and the CLV of betting the predicted side at the open. |

## Deliverables

- One script per family in this folder, each writing its results to a CSV.
- `HYPOTHESES.md`: the verdicts, the literature, and what goes into the protocols.
- `nfl_props_v1` and `nfl_market_v1` protocol drafts, unsigned, for the owner, covering the promising hypotheses on 2026 week 8 onward.
