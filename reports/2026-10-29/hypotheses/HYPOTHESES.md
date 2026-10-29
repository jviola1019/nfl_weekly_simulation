# Other ways to gain value: what the tests show

2026-10-29. The owner asked for more information on different hypotheses of gaining value or profit.

How to read this report:
- **Every hypothesis was fixed before testing** in `PLAN.md`, committed as `d9367fd` at 19:26Z on 2026-10-29, before 2026 week 8 kicked off.
- **Every number** comes from `out/<family>/` or `out/verdicts.csv`, written by the script named beside it.
- **Deviations from the plan** are listed as rulings in §10.

## The short answer

| Family | What was tested | Result |
|---|---|---|
| **E. Published NFL line anomalies** | Ten published edges, on seasons after each study's sample | None survives BH (q ≥ 0.27). Home underdogs: 49.7% ATS over 2002–2024. |
| **A. Kalshi's structure** | Key numbers, protected twins, the touchdown family, scalar against binary ladders, rung order | **Two survive BH:** protected contracts are underpriced (A3), and the binary ladder beats the scalar's mean (A5). Neither pays a taker after costs. |
| **B. Information and behaviour** | Absent teammates, Questionable tags, overreaction, the 24 h price, thin markets, cheap YES | None survives BH (q ≥ 0.38). |
| **C. Makers and takers** | Who earns before kickoff | Neither, detectably: makers net +0.75¢ a contract (95% CI −2.86 to +4.36, q 0.68), and taker flow predicts nothing (p 0.94). Only an edge of 4.6¢ a contract was detectable. |
| **D. In-game** | Kalshi's live price against nflfastR's win probability | None once the model is denied look-ahead (60 s buffer: p 0.053, q 0.11). |
| **F. Kalshi against DraftKings** | Cross-venue locks and accuracy | No locks (the cheapest pair cost $1.020); equally accurate. |
| **G. A public projection** | Recency-weighted player means against the props | A trace of information (coefficient 0.09, p 0.054). Betting it loses 3.8%. |
| **H. Opening lines** | Overreaction and predictable moves, 2023–24 | Neither (p 0.89 and 0.47). |

So:
- **No hypothesis gives a taker an edge** after multiple testing and costs.
- **The two real mispricings are inside Kalshi**, between related contracts. They pay only as a better choice of contract, or from the maker side if resting orders fill at the mid, which these data cannot show (§4):
  - **Protected contracts.** A protected YES pays at least the unprotected YES, yet is priced 0.35¢ lower on average. Its protection paid +0.63¢. Choosing it over the unprotected contract is worth +0.97¢ per contract to a YES buyer (A3).
  - **Scalar ladders.** Kalshi's scalar ladders price a player's mean about 2.5–3 yards above what the binary ladder on the same stat implies, and the binary ladder is the one that matches the results (A5).

## 1. Published NFL line anomalies (Family E; `classic_anomalies.R`, `out/classic/`)

The data are nflverse closing lines and the recorded odds, regular season, 1999–2024 plus 2026 weeks 1–7. 2025 is never loaded.
- **Each anomaly** is tested only on the seasons after its study's sample.
- **The interval** resamples season-weeks.
- **The return** is at the recorded odds, or −110 where there are none.

| ID | Bet (study) | Test seasons | Bets | Rate (95% CI) | Return (95% CI) | BH q |
|---|---|---|---|---|---|---|
| E1 | Home underdogs ATS (Levitt 2004) | 2002–2024 | 2,046 | 49.7% (47.6–51.7) | −3.7% (−7.8 to +0.3) | 0.76 |
| E2 | Home underdogs, weeks 13+ (Borghesi 2007) | 2007–2024 | 545 | 49.7% (45.8–53.3) | −3.3% | 0.76 |
| E3 | Under, outdoors, wind ≥ 15 mph (Borghesi 2008) | 2005–2024 | 336 | 54.5% (49.1–60.0) | +6.1% (−4.3 to +16.8) | 0.27 |
| E4 | Home, ≤ 32°F, warm visitor (Borghesi 2007) | 2008–2024 | 63 | 61.9% (48.3–73.3) | +21.2% (−5.1 to +43.7) | 0.27 |
| E5 | Away ATS in division games (Shank 2019) | 2017–2024 | 750 | 51.7% (48.3–55.3) | +0.4% | 0.36 |
| E6 | Under in division games (Shank 2019) | 2017–2024 | 760 | 51.7% (48.0–55.5) | +0.4% | 0.36 |
| E7 | Home underdogs of 7+ (Shank 2018) | 2018–2024 | 161 | 54.7% (47.1–62.1) | +4.0% | 0.36 |
| E8 | Over at extreme totals (Shank 2018) | 2018–2024 | 413 | 47.5% (43.0–52.3) | −8.2% | 0.86 |
| E9 | Home after failing to cover (Shank 2018) | 2018–2024 | 826 | 49.2% (45.7–52.6) | −4.9% | 0.76 |
| E10 | Away moneyline, home 0.3–0.7 (Costa 2025) | 2026 weeks 1–7 | 76 | 53.9% | +3.2% (−8.6 to +15.1) | 0.52 |

**The home-underdog effect is gone.** It won 53.2% in our 1999–2001 slice of Levitt's sample, and 49.7% since.

**Weather is the one theme that still leans the published way** (E3, E4), but it fails BH:
- wind ≥ 15 mph comes about 17 times a season;
- the cold-weather bet, 63 games in 17 seasons.

Confirming either would take years of games.

## 2. Kalshi's structure (Family A; `key_numbers.R`, `kalshi_consistency.R`)

All of these use 2026 weeks 1–7, at the close (the hourly candle at kickoff), with quotes within the 10¢ spread limit.

**A1–A2, key numbers.** A model of P(margin > x | spread) was built from 2015–2024 games, centred on nflverse's closing spread, and paired by game against Kalshi.

| Ladder | Contracts | Model's Brier skill | p | Taker return (95% CI) |
|---|---|---|---|---|
| Spreads | 2,730 | +0.64% | 0.22 | +1.7% (−13.3 to +16.6) |
| Team totals | 2,885 | +0.38% | 0.26 | +3.6% (−7.6 to +14.7) |
| Totals | 2,033 | −1.1% | 0.89 | −15.3% |

- **Kalshi already prices the 3-point mass.** For the favourite's ladder, P(> 2.5) − P(> 3.5) averages 8.8%, against the model's 9.1% and 8.4% realized (`key_numbers_mass3.csv`).
- **An exploratory variant** places the historical shape on Kalshi's own median. It reaches +1.2% on spreads (p 0.12), which is not significant.

**A3, protected twins.**
- **The rule.** A protected YES settles at the pre-game fair price when the player leaves at the half without the stat, instead of 0, so it is worth at least the unprotected YES.
- **The prices are the wrong way round.** Over 12,205 pairs in 43 games:
  - the protected mid averages 0.35¢ *below* the unprotected one, and is lower in 7,007 pairs;
  - the protection paid +0.63¢ per pair;
  - so the premium is mispriced by +0.97¢ (p 9×10⁻⁸, BH q 4×10⁻⁷).
- **At taker prices** the pair trade (long protected YES, short unprotected YES) loses 4.3¢ per pair.
- **As a maker at the mids**, after Kalshi's NFL maker fee, it makes +0.50¢ per pair (95% CI +0.22 to +0.81). That assumes both legs fill at the mid, which these data cannot show.
- **By stat:** receiving yards, receptions, rushing yards and touchdowns carry the protection value. QB markets have none, because QBs rarely leave at the half (`consistency_a3_by_series.csv`).

**A5, scalar against binary ladders.** Each pays a fraction of $1 per unit: $0.05 a catch, $0.0025 a yard. The binary ladder's mean is its survival summed over the rungs.

| Ladder | Pairs | Scalar's mean | Binary ladder's mean | Realized |
|---|---|---|---|---|
| Receiving yards | 357 | 47.9 | 45.3 | 45.3 |
| Rushing yards | 180 | 52.2 | 49.1 | 50.0 |
| Receptions | 305 | 4.14 | 4.09 | 4.05 |

- **The binary ladder carries the information.** The realized stat moves 0.81 of the gap between the two means (p 1×10⁻⁴, q 2.5×10⁻⁴).
- **Traded at taker prices** with no fitted parameter (the scalar priced at the ladder's mean), it returns +1.7% on 120 bets (95% CI −0.6 to +3.5). The gap, about 0.6¢ a contract on yards, is smaller than the half-spread plus the fee.

**A4 and A6, sure profits.**
- The touchdown family obeys its order at the bid and ask: none of 2,244 player-games has a sure profit after fees.
- Of 204,900 rung pairs in 9,652 ladders, 3 had a sure profit. The largest was 1.3¢.

## 3. Information and behaviour in props (Family B; `kalshi_behaviour.R`, `out/behaviour/`)

| ID | Hypothesis | Estimate (95% CI) | p | BH q |
|---|---|---|---|---|
| B1s | Position-group teammates of a player who played last game and took no snap now are underpriced (192 absences) | +0.12 logit (−0.04 to +0.28) | 0.067 | 0.38 |
| B2 | Questionable players who played are underpriced | −0.25 (−0.61 to +0.10) | 0.92 | 0.94 |
| B3 | The last day's move overreacts | +0.02 (−0.31 to +0.34) | 0.54 | 0.86 |
| B4 | A refit of the 24 h price beats it out of sample | −0.09% Brier skill | 0.36 | 0.79 |
| B5 | Thin markets are miscalibrated | slope difference +0.02 (−0.03 to +0.08) | 0.40 | 0.79 |
| B6 | YES under 20¢ is overpriced | +0.03 (−0.07 to +0.13) | 0.75 | 0.94 |

Notes:
- **A third of contracts traded nothing** in the last 48 hours, and they are as well calibrated as the busiest third: slope 0.99 against 0.96.
- **A taker trading the 24 h refit** loses 34.5% on player props.
- **Absences (B1s)** point the hypothesised way, but the effect is not significant. It is a candidate for fresh data. B1 and B1r are §10's rulings.

## 4. Makers and takers (Family C; `kalshi_trades.R`, `kalshi_trades_agg.R`, `maker_taker.R`, `out/maker/`)

**The data.** Every KXNFLGAME contract plus a seeded sample of 2,000 other single-game contracts, weeks 1–7, and each one's trades in the 72 hours before kickoff.
- 2,212 contracts have an outcome, and 1,584 of them traded: 2,584,811 trades and 298 million contracts, in 107 games.
- The fetch read at most 20 pages per contract, keeping the newest trades. 61 contracts hit that cap, so their earliest trades in the window are missing.
- The committed input sums the trades by contract, taker side, price and window (`out/kalshi_trades_agg.csv.gz`).

| ID | Test | Estimate (95% CI) | p | BH q | Detectable with 80% power |
|---|---|---|---|---|---|
| C1 | Makers' net return per contract before kickoff, after the maker fee (one-sided > 0) | +0.75¢ (−2.86 to +4.36) | 0.34 | 0.68 | 4.6¢ |
| C2 | The last day's net YES taker share predicts the result beyond the close | −0.01 logit (−0.25 to +0.23) | 0.94 | 0.94 | 0.35 logit |

- **Game lines dominate:** they carry 287 of the 298 million contracts. Their maker return is +0.65¢ (−3.07 to +4.37).
- **Without the 61 capped contracts**, the maker return is −0.94¢ (−5.48 to +3.60).
- **No segment stands out.** The largest, +11.4¢ for makers on trades at 50–70¢, has a one-sided p of 0.048 before any correction across the six price buckets (`maker_taker_segments.csv`).
- **The test is underpowered.** 107 game results drive the variance, so only an edge of about 4.6¢ a contract could be detected. A null here does not rule out an edge of a cent or two.
- **For A3, this means** its maker-side profit still rests on the untested assumption that both legs fill at the mid.

## 5. In-game prices (Family D; `kalshi_live_candles.R`, `live_wp.R`, `out/live/`)

The data are Kalshi's one-minute moneyline candles against nflfastR's pre-snap `vegas_home_wp`, across 106 games and 19,956 minutes.

| Buffer before the minute ends | Model's Brier against Kalshi's (0.1654) | Model adds information (D2) | Model's change now → Kalshi's next minute |
|---|---|---|---|
| 0 s (the plan's definition) | 0.1629 (p 0.30) | 0.88, p 0.039 | 0.32 (SE 0.03) |
| 30 s | 0.1636 | 0.70, p 0.057 | 0.09 (SE 0.02) |
| **60 s (of record)** | **0.1641 (p 0.58)** | **0.59, p 0.053** | **0.04 (SE 0.01)** |
| 120 s | 0.1652 | 0.44, p 0.058 | 0.00 |

- **The lead was look-ahead.** The plan's definition let the model see the result of a play still in progress when the minute ended. Without that, Kalshi's live price takes in the public game state within one to two minutes.
- **A real in-game edge would need sub-minute data and execution:** a live feed such as ESPN's public play-by-play, timestamped as it arrives. Minute candles cannot test that.

## 6. Kalshi against DraftKings (Family F; `cross_venue.R`, `out/cross_venue/`)

The sample is 28 games in weeks 6–7. DraftKings' moneyline is from ESPN's feed at the last capture, a median 18.8 h before kickoff; Kalshi's is the candle at that hour.
- **No game could be locked** by buying one side on each venue. The cheapest pair cost $1.020, and the median $1.036.
- **The two venues are equally accurate:** Brier 0.2449 against 0.2472 (p 0.28), and the mean gap is 0.7 points.

## 7. A public projection (Family G; `props_projection.R`, `out/projection/`)

Each player-week gets a recency-weighted mean of the player's own 2026 games, shrunk toward listed players at his position. A negative binomial covers counts, and a gamma with a zero mass covers yards.

| Measure | Result |
|---|---|
| Brier, model alone | 0.1597, against Kalshi's 0.1476 |
| Information added (G1) | coefficient 0.09 (−0.02 to +0.20), p 0.054 |
| Taker betting (G2) | −3.8% (−6.8 to −0.8) on 19,926 bets |

- **The information is in receiving and rushing** (coefficients 0.13–0.21). On QB stats the coefficient is negative (`projection_by_stat.csv`).
- **The market already has nearly everything** a box-score average knows.

## 8. Opening lines (Family H; `opening_lines.R`, `out/opening/`)

The data are ESPN BET's moneylines, 2023–2024: 463 games with an open and a close.
- **No overreaction** (Moskowitz 2021): the coefficient is +0.54 (−0.35 to +1.42), p 0.89.
- **The move is not predictable** from the opener (fit on 2023, scored on 2024): correlation 0.005 (p 0.47), and CLV +40 bps (95% CI −26 to +104).
- **The open-to-close move** has an SD of 495 bps.

## 9. Value that needs live trading to test

These are real sources of value in the literature or Kalshi's rules. This data cannot measure them, because each depends on placing orders.
- **Making markets instead of taking them.**
  - Bartlett (2026, 41.6 million Kalshi trades) finds market makers earn twice as much per contract, helped by traders over-buying YES.
  - Bürgi, Deng and Whelan find makers out-earn takers on Kalshi.
  - Here, A3's pair trade is positive only as a maker (+0.50¢, CI above 0, if both legs fill at the mid). §4's realized maker return across all trades, +0.75¢ (CI −2.86 to +4.36), can neither confirm nor rule that out.
- **Kalshi's Liquidity Incentive Program.**
  - It pays $1–$1,000 per market per day for resting orders near the best price, scored every second, even when they don't fill.
  - It runs until 2027-01-01, for most US members.
  - Each market page shows whether that market pays.
- **Speed in-game.** A sub-minute feed plus a win-probability model; §5 shows a minute-level public model has no edge.
- **Line shopping across books.** DraftKings and Kalshi never crossed (§6). More books would need track K's venue survey, and a 2025-free history would need track H.

## 10. Rulings: where the run departs from PLAN.md

1. **B1.** The plan's definition, any player Out on the report, flagged 80% of contracts. Most teams list some prop player Out most weeks, so the test had no contrast.
   - **B1r:** absent after playing the previous game. It still flagged 70%, because Kalshi does not list every player every week.
   - **B1s:** absent by snap counts, with the flag limited to teammates in the absent player's position group.
   - All three are reported and all three are in the BH family.
2. **D.** The plan's model price, "the first play after the minute", looks ahead. The model now only uses plays that started a buffer before the minute ended. 60 s is of record, and 0, 30 and 120 s are shown.
3. **A3 and A5.** The first run had no spread limit. Contracts quoted 0 / 0.99, with a mid of 0.495, inflated the scalar means, so both use the 10¢ limit like every other test. A3's sure-profit count still uses every executable quote, because a wide quote cannot create a false arbitrage.
4. **A5.** The receptions mean uses the discrete sum over k of P(Y ≥ k). The trapezoid first used overstated it by about 0.5 catch.
5. **A1.** The shape-only variant, centred on Kalshi's own median, was not in the plan. It is labelled exploratory.
6. **E.**
   - Regular season only.
   - A warm visitor is a team whose home games that season were mostly indoors, or averaged 60°F or warmer.
   - Where nflverse has no odds, the return uses −110. The share recorded is in `classic_anomalies.csv`.

## 11. What goes into the protocols

The protocol drafts are `PROTOCOL_props_v1_DRAFT.md` and `PROTOCOL_market_v1_DRAFT.md`. Both are unsigned, for the owner, and test only games from 2026 week 8 on.
- **Props:**
  - A3, the protection mispricing, as a price relation;
  - A5, the scalar against the binary ladder;
  - B1s, absences;
  - the interception ladder's compression, from `reports/2026-10-28/feasibility`;
  - CLV for the props module.
- **Market:**
  - the weather unders (E3);
  - the cold home team (E4);
  - the key-number shape on spreads (A1, shape-only).

  Each has the power it would reach by the end of the 2026 season.

## Sources

**Studies tested:**
- Levitt, "Why are gambling markets organised so differently from financial markets?", *Economic Journal* 2004 (home underdogs). Summarized in the [Freakonomics posts](https://freakonomics.com/2006/12/28/home-underdogs-in-the-nfl/).
- Borghesi, "The late-season bias: explaining the NFL's home-underdog effect", *Applied Economics* 2007 ([IDEAS](https://ideas.repec.org/a/taf/applec/v39y2007i15p1889-1903.html)).
- Borghesi, "Weather biases in the NFL totals market", *Applied Financial Economics* 2008 ([EconBiz](https://econbiz.de/Record/weather-biases-in-the-nfl-totals-market-borghesi-richard/10005485078)).
- Borghesi, "The home team weather advantage and biases in the NFL betting market", *Journal of Economics and Business* 2007 ([RePEc](https://econpapers.repec.org/RePEc:eee:jebusi:v:59:y:2007:i:4:p:340-354)).
- Shank, "NFL betting market efficiency, divisional rivals, and profitable strategies", *Studies in Economics and Finance* 2019 ([DOI](https://www.doi.org/10.1108/SEF-11-2018-0354)).
- Shank, "Is the NFL betting market still inefficient?", *Journal of Economics and Finance* 2018 ([Springer](https://link.springer.com/article/10.1007/s12197-018-9431-4)).
- Costa, "NFL Moneyline Market Efficiency", Claremont McKenna thesis 2025 ([Scholarship@Claremont](https://scholarship.claremont.edu/cmc_theses/3975)).
- Moskowitz, "Asset Pricing and Sports Betting" ([NBER working paper](https://conference.nber.org/conf_papers/f92072/f92072.pdf)).

**Prediction-market microstructure:**
- Bartlett, "Adverse Selection in Prediction Markets: Evidence from Kalshi", Stanford 2026 ([Stanford Law](https://law.stanford.edu/publications/adverse-selection-in-prediction-markets-evidence-from-kalshi/)).
- Bürgi, Deng and Whelan, "Makers and Takers: The Economics of the Kalshi Prediction Market" ([IDEAS, CEPR DP 20631](https://ideas.repec.org/p/cpr/ceprdp/20631.html)).
- [Kalshi's Liquidity Incentive Program](https://help.kalshi.com/incentive-programs/liquidity-incentive-program).
- Kalshi's rule filings at the [CFTC](https://www.cftc.gov/filings/orgrules/rules10142633445.pdf).

**Context:**
- On key numbers: [Action Network](https://www.actionnetwork.com/nfl/nfl-key-betting-numbers-spread-margins-of-victory-line-value), and the [margin-of-victory data, 1999–2025](https://www.deucescracked.com/blog/nfl-margin-of-victory-data-1999-2025).
- On in-play markets: "Beating the House" ([arXiv 1910.08858](https://arxiv.org/pdf/1910.08858)).
- On fill probability and returns: "The Market Maker's Dilemma" ([arXiv 2502.18625](https://arxiv.org/pdf/2502.18625)).
