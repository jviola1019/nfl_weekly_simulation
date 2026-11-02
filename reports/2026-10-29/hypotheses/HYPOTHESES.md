# Other ways to gain value: what the tests show

2026-10-29. The owner asked for more information on different hypotheses of gaining value or profit.

How to read this report:
- **Every hypothesis in families A–H was fixed before testing** in `PLAN.md`, committed as `d9367fd` at 19:26Z on 2026-10-29, before 2026 week 8 kicked off.
- **K and M came later, at the owner's requests** of 2026-10-29 (every venue, arbitrage and price gaps) and 2026-11-02 (does our model beat any book). They are measurements, not pre-registered tests.
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
| **K. Every venue at once** (§12) | Arbitrage, middles and price gaps across 11 venues, week 8 | Game lines: no arbitrage, and 20 of 2,172 sides beat Pinnacle's no-vig price. Props: 5 small arbitrages, all through Smarkets (best +1.39¢ per $1). |
| **M. Our model against the books** (§13) | The week-7 run against four books' prices | The model is worse than every closing price, and its bets lose. Its props projections show a weak, insignificant signal (p 0.066). |
| **T. Timing** (§15) | Does a forecast predict the market's later move? | **Yes, in two places.** The EPA model's picks at ESPN BET's opener gained +85 bps of CLV in 2023 (p 0.008), replicating 2024's +93. It does not cover one book's margin, and part of it may be look-ahead if openers were posted before the previous week's games. Prop projections predict Kalshi's last-day drift (p 2×10⁻¹⁴), but the drift is a quarter of a cent. |

So:
- **No hypothesis gives a taker an edge** after multiple testing and costs.
- **The two real mispricings are inside Kalshi**, between related contracts. They pay only as a better choice of contract, or from the maker side if resting orders fill at the mid, which these data cannot show (§4):
  - **Protected contracts.** A protected YES pays at least the unprotected YES, yet is priced 0.35¢ lower on average. Its protection paid +0.63¢. Choosing it over the unprotected contract is worth +0.97¢ per contract to a YES buyer (A3).
  - **Scalar ladders.** Kalshi's scalar ladders price a player's mean about 2.5–3 yards above what the binary ladder on the same stat implies, and the binary ladder is the one that matches the results (A5).
- **Our game model does not beat the market or any single book** (§13).
- **What does exist is timing information** (§15):
  - a separate EPA model sees where opening lines will move, replicated in a second season;
  - prop projections see Kalshi's last-day drift.
  - Neither is yet large enough to pay after a single venue's margin.
- **Prices differ little between venues** (§12). The line moves 2.9 points between Tuesday and the close, four times more than books differ from each other. Timing matters more than the choice of book.
- **What is worth pursuing, and how to test it**, is §14.

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
  - On 2026-10-29 it paid on 19 NFL markets out of 5,863 programs, all of them season or novelty markets. No NFL game line or player prop paid (`kalshi_incentives.R`, `out/incentives/`).
- **Speed in-game.** A sub-minute feed plus a win-probability model; §5 shows a minute-level public model has no edge.
- **Line shopping across books.** DraftKings and Kalshi never crossed (§6). Track K's survey now covers 11 venues (§12). A 2025-free price history would need track H.

## 10. Rulings: where the run departs from PLAN.md

1. **B1.** The plan's definition, any player Out on the report, flagged 80% of contracts. Most teams list some prop player Out most weeks, so the test had no contrast.
   - **B1r:** absent after playing the previous game. It still flagged 70%, because Kalshi does not list every player every week.
   - **B1s:** absent by snap counts, with the flag limited to teammates in the absent player's position group.
   - All three are reported and all three are in the BH family.
2. **D.** The plan's model price, "the first play after the minute", looks ahead. The model now only uses plays that started a buffer before the minute ended. 60 s is of record, and 0, 30 and 120 s are shown.
3. **A3 and A5.** The first run had no spread limit. Contracts quoted 0 / 0.99, with a mid of 0.495, inflated the scalar means, so both use the 10¢ limit like every other test. A3's sure-profit count still uses every executable quote, because a wide quote cannot create a false arbitrage.
4. **A5.** The receptions mean uses the discrete sum over k of P(Y ≥ k). The trapezoid first used overstated it by about 0.5 catch.
5. **A1.** The shape-only variant, centred on Kalshi's own median, was not in the plan. It is labelled exploratory.
6. **K1's snapshot schedule.** Snapshots were planned up to Thursday night's kickoff. Only three ran, all before 21:30Z: the loop was stopped to switch script versions and not restarted before the session ended.
7. **K1's prices.**
   - **Kalshi's moneyline.** Kalshi settled 2026's only tie at $0.50 on both teams' contracts, so NO on one team is the same bet as YES on the other. The snapshot prices each side by the cheaper of the two. Regenerating both snapshots changed no summary number.
   - **Smarkets' commission** is an assumed 2%, from third-party guides.
   - **Polymarket's fee** is from its documentation.
8. **M's props test** uses Family G's dispersion model around the module's projected means. The module outputs a probability only at its own line, so its own distribution cannot be recovered.
9. **T1 was fixed in `opener_clv.R` before it ran**, as the one test, for C2 on 2023. The hypothesis itself was named in v1's RESULT.md on 2026-10-01. The script was not committed before the run.
   - 2023 is `nfl_preclose_v1`'s Tune season, so T1 is Tune-stage evidence, not confirmation.
   - The edge bands and the starter split are descriptive.
10. **The props timing tests** (GT, MT) were added on 2026-11-02, after §7 and §13. Their 24-hour window is the longest Kalshi's candles in these files hold.
11. **E.**
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

## 12. Every venue at once (track K1; `venue_snapshot.R`, `props_snapshot.R`, `VENUE_SURVEY.md`)

The owner asked to test every betting site and sportsbook for arbitrage and price disparities. `VENUE_SURVEY.md` lists the venues that can be read without a key. The keyless set is Action Network's six books, Pinnacle, Bovada, Polymarket, Smarkets and Kalshi; DraftKings, Caesars, BetMGM and Fanatics refuse direct requests.

Three snapshots were taken before week 8's Thursday game:
- **Game lines** (20:48Z and 21:07Z, up to 11 venues, 6,948 quotes):
  - **No arbitrage.** The cheapest two-sided pair cost exactly $1.00.
  - **No middle with a positive EV.**
  - **Line shopping** beats the median venue by a mean of 0.7–1.4¢ per $1.
  - **Few prices beat Pinnacle.** 20 of 2,172 sides beat its no-vig price under both devigs, and 2 by more than 2%. Of the 13 at 20:48Z, 12 were still positive 18 minutes later.
- **Player props** (21:22Z: Kalshi, Smarkets and Pinnacle, 677 props at two venues or more):
  - **Five arbitrages**, the best +1.39¢ per $1.
  - **All through Smarkets**, a UK exchange that does not take US customers, under an assumed 2% commission.

## 13. Our model against the books (Family M; `model_vs_books.R`, `out/model_vs_books/`)

The owner asked whether our model beats any book.
- **The cleanest test** is the 2026 week-7 run: code `4c1c377`, written 2026-10-20 19:45Z, before any week-7 game. Its outputs are copied to `out/model_vs_books/inputs/`.
- **No other 2026 week has a forecast made in advance**, and a retroactive run is not point-in-time (below).
- **Fourteen games is a measurement, not a test with power.**

**Moneyline** (Brier score on the 14 results; lower is better):

| Forecast | Brier | Mean distance from the consensus close |
|---|---|---|
| Kalshi's close (hourly candle at kickoff) | 0.2268 | 0.67 points |
| Consensus close (nflverse) | 0.2310 | – |
| DraftKings (ESPN's feed, last capture before kickoff) | 0.2312 | 0.68 points |
| Simulator, raw | 0.2437 | 8.4 points |
| GLMM blend | 0.2469 | 4.4 points |
| C3 final, the number the app shows | 0.2488 | 3.2 points |
| Consensus on Tuesday, the run's market input | 0.2498 | 2.9 points |

- **Every version of the model is worse than every closing price.** The shown number trails Kalshi's close by 0.022 in Brier (95% CI 0.0004 to 0.051).
- **Its bets lose at every book.**
  - The raw simulator claimed an average edge of 35–37% and won 2 of its 8 bets at each book.
  - The shown number won 3 of 10 at the consensus close, −1.93 units (`games_bets.csv`).

**Spreads and totals**, priced from the simulated margin and total distributions:
- **Against the consensus close at −110**, its 10 spread picks lost 6.18 units and its 10 total picks lost 2.36. Its spread Brier is 0.294, worse than a coin's 0.25.
- **On Kalshi's ladders at the close**, it scores worse than Kalshi and adds no information:

| Ladder | Contracts | Brier: model vs Kalshi | Coefficient (95% CI) |
|---|---|---|---|
| Spreads | 353 | 0.188 vs 0.173 | −0.30 (−2.71 to +2.12) |
| Totals | 266 | 0.184 vs 0.174 | −0.11 (−1.94 to +1.73) |

**The model's disagreements are its own error.**
- The raw simulator sits a mean 8.0 points from the Tuesday consensus it was given.
- The books sit 0.7 points from each other.
- The line moved 2.9 points between Tuesday and the close.
- The 70% shrinkage toward the market keeps the shown number a mean 0.6 points from the market.

**Props: one weak signal.**
- **The props module has never seen a market price.**
  - None of its 570 week-7 props has a market line or odds (`line_source = model`, `odds_source = missing`).
  - Its yardage and reception lines are its own projections, and every recommendation is PASS.
- **Its projected means were tested against Kalshi's close** on 2,485 matched contracts (140 players, 14 games), with Family G's dispersion model:

| Measure | Props module | Family G's projection (same contracts) |
|---|---|---|
| Information beyond Kalshi's close | 0.26 (−0.09 to +0.61), one-sided p 0.066 | 0.03 (−0.62 to +0.68), p 0.46 |
| Brier (Kalshi: 0.1439) | 0.1495 | 0.1525 |

- **Betting its disagreements at Kalshi's taker prices** returns −0.7% (−9.3% to +9.5%) on 2,034 bets.
- **By stat**, the module is worse than Kalshi on passing yards, rushing yards, receptions and touchdowns, and slightly better on receiving yards (`props_by_stat.csv`).
- **Two defects in its projection** (`sports/nfl/props/data_sources.R:62-158`):
  - It averages every game of three seasons equally, though its comment says "recency weighting".
  - It has no week filter, so a retroactive run sees later games. Week 7 is its only clean test.

**Together with the earlier evidence:**
- **Against the close nothing beats the market.** The best of 39 blends reaches +0.068% Brier skill, and the smallest detectable skill on all 4,997 games with a closing moneyline is 0.39% (`reports/2026-10-28/feasibility/FEASIBILITY.md`).
- **Kalshi's props are calibrated at kickoff:** slope 0.958 over 88,439 contracts.

## 14. Is the model worth pursuing? What to pursue instead

**The game model, for moneylines, spreads, totals and team totals: not as a source of edge.**
- **It is worse than the close** wherever it has been measured. The books it would bet against sit a mean 0.7 points from the close.
- **Its edges are mostly its own error.** Because the books barely differ, it makes nearly the same bets at each one: 8, 8 and 8 for the raw simulator, and 10, 9 and 9 for the shown number (`games_bets.csv`).
- **Keep it** as the product's explanation layer (distributions, scenarios) and as a prior.
- **Stop trying to make it beat the close.** The best of 39 blends would need 20,836 games to confirm, about four times every NFL game with a closing moneyline (FEASIBILITY.md).

**Props: worth one bounded, pre-registered test, and no more until it passes.**
- **Two different projections point the same way:** Family G over weeks 2–7 (0.09, p 0.054) and the module in week 7 (0.26, p 0.066). Neither is significant, and they share week 7.
- **The steps:**
  1. Give the projection a week filter and real recency weighting.
  2. Give the module market prices: Kalshi's ladders, Smarkets and Pinnacle, all keyless, through `props_snapshot.R`'s parsers.
  3. Register the information test for weeks 9–18 in `PROTOCOL_props_v1_DRAFT.md`, with a stopping rule: if the coefficient's interval includes 0 at season's end, stop.
  4. Track closing-line value against Kalshi's close as the leading indicator. +100 bps needs about 412 player-game picks (FEASIBILITY.md).
- **Its power** (`out/protocol_power.csv`):
  - Weeks 9–18, 140 games, would detect the week-7 coefficient of 0.26 almost surely. A one-week estimate is probably inflated, though.
  - At Family G's smaller 0.09, 154 games give 76% power, and 80% needs 175 games.
- **Team totals and totals deserve a place in it.**
  - Team totals are the game market with the largest line-shopping gain, and their spread of prices across venues is second only to the moneyline's (§12).
  - In the first snapshot, 7 of the 13 sides that beat Pinnacle were team-total unders, at Kalshi, BetRivers, BetMGM and Polymarket. In the second, team-total unders and game-total overs made up 13 of the 20.

**Concepts that do not need a better forecast**, ranked by the evidence:
1. **Timing: beat the move, not the result.**
   - The line moves 2.9 points from Tuesday to the close, about four times the gap between books.
   - A model of where the line will go, from injury news, weather and early sharp money, is worth more than another model of who wins.
   - **§15 now has evidence for it.** The EPA model's picks at the opener gained +85 bps of CLV in 2023 (p 0.008), replicating 2024's +93. That is short of the ~200 bps one book charges per side, so it needs better prices, a larger edge threshold, or both.
   - The confirmatory test is `nfl_preclose_v1`'s PC-C2 (designed, awaiting signature and the 2025-history decision). For props it is closing-line value.
2. **Price-relative betting.**
   - Bet a book or exchange only when it beats a sharp reference: Pinnacle's no-vig price, or the consensus.
   - [Kaunitz, Zhong and Kreiner (2017)](https://pdf.arxiv.org/pdf/1710.02824) made this pay against 32 soccer bookmakers, until the books limited their accounts.
   - Exchanges such as Kalshi match traders against each other, so a winner costs the venue nothing.
   - Our snapshot found 20 such sides, 2 of them by more than 2%. It needs a prospective series scored by CLV and by results.
3. **Line shopping, always.** It is small but certain: 0.7–1.4¢ per $1 against the median venue.
4. **Exchange structure, A3 and A5.** These pay only from the maker side and need a small live test of fill rates (owner decision, real money).
5. **A model trained to differ from the market.** [Hubáček and Šír (2023)](https://econpapers.repec.org/RePEc:eee:intfor:v:39:y:2023:i:2:p:691-719) beat markets with deliberately "bad" forecasters whose errors are uncorrelated with the market's. This needs a long price history (track H's openers).
6. **Not recommended:**
   - published line anomalies (§1);
   - in-game betting on public data (§5);
   - recalibrating Kalshi's prop prices, which loses 15.7% traded (FEASIBILITY.md).

**The testing program, week 9 onward** (built and running; §15):
- **At each decision point (Tuesday and Friday):**
  - run `run_week.R`;
  - take `venue_snapshot.R` and `props_snapshot.R` snapshots at the same times, and an hour before each kickoff;
  - keep Kalshi's candle at kickoff as the close.
- **Score:**
  - closing-line value for every claimed edge;
  - Brier and log loss of the model against each venue at decision time;
  - the props information test;
  - the persistence of sides that beat Pinnacle (`venue_persistence.R`).
- **Sign the two protocols:** `nfl_preclose_v1` (games against the opener) and `nfl_props_v1` (props).
- **Track H's historical openers** would power the opener test from thousands of games instead of hundreds.
- **Where the snapshots run is owner checkpoint 3.** They hold sportsbook prices, so they cannot go into the public repository's workflow artifacts.

## 15. Timing: does a model see where the price will go? (Family T; `opener_clv.R`, `out/timing/`, and the timing parts of `props_projection.R` and `model_vs_books.R`)

The owner asked to complete the tests §14 proposed. Timing ranked first there. These tests ask whether a forecast predicts the market's later move, which is closing-line value (CLV), rather than the result.

**Games: the EPA model at the opener.**
- **The lead.** `nfl_games_v1` found that C2's picks at ESPN BET's opener gained +93 bps of CLV in 2024. C2 is the EPA ridge model; the production simulator is not involved. That was descriptive only (`reports/2026-09-29/backtest-games-v1/RESULT.md`), and the report named a single follow-up: C2 at the opener, plus 2023 openers.
- **The replication, T1.** D1's archive now has 2023 openers (205 games). T1 replicates the lead on 2023, a season the lead was not found in.
  - It uses v1's own walk-forward predictions, pick rule (C2 at least 3 points from the no-vig open), CLV definition and week-block bootstrap.
  - Recomputing 2024 reproduces RESULT.md exactly, and D1's 2024 prices match v1's inputs in every game.

| C2 at ESPN BET's opener | Picks | Mean CLV (bps) | 95% CI | Flat ROI at the opener (95% CI) |
|---|---|---|---|---|
| **2023, the replication (T1)** | 141 | **+85** | one-sided lower bound +25; **p 0.008** | +4.1% (−19.6% to +29.0%) |
| 2024, where the lead was found | 214 | +93 | +40 to +149 | −7.0% (−22.8% to +9.3%) |
| Both seasons | 355 | +90 | +47 to +135 | −2.6% (−16.1% to +11.2%) |
| Both, no starter changed from the previous game | 280 | +103 | +58 to +150 | +1.6% |
| Both, a starter changed | 75 | +38 | −69 to +172 | −18.1% |

- **The lead replicates.** In both seasons, ESPN BET's line moved toward C2's side between the open and the close.
- **It is not v1's starter caveat.** C2 uses the game's actual starting QB, which the opener may not know (PROTOCOL.md §9). Yet the CLV is larger where no starter changed.
- **It is specific to the EPA model.** Elo (C1) has none: −19 bps in 2024 and −13 bps in 2023.
- **It does not pay at one book.**
  - ESPN BET's median opening overround is 397 bps across both sides (`opener_clv_data_checks.csv`), so about 200 bps per side. +90 bps of CLV does not cover it, which is why the flat ROI interval includes 0.
  - The CLV is largest where C2 disagrees most: +162 bps (SE 38) on the 163 picks 8 or more points from the open, against +45 and +16 bps in the smaller bands (`opener_clv_by_edge.csv`). This is descriptive and chosen after looking.
- **Open caveat: when were the openers posted?**
  - v1's C2 knows week w−1's results. If ESPN BET posted week w's opener before those games, part of this CLV is look-ahead. That is why the pre-close design keeps such information sets out of its confirmatory set (IS-B, "may not be executable").
  - **It could not be settled here.** ESPN keeps no line history for 2023–2024: its movement endpoint returns nothing.
  - The 2026 capture archive first sees week w only after week w−1 is over (`opener_timing.R`: `archive_could_see_an_earlier_opener` is FALSE for both weeks). That is because main's capture reads only ESPN's current-week scoreboard; #217 adds the next week by number.
  - **One fact argues against pure look-ahead.** Elo (C1) also uses week w−1's results, yet gets no CLV.
- **What it means.**
  - The EPA model probably holds information the opening line lacks and the market prices in by the close. It is the only game-level signal found in this research.
  - It is worth money only with a better price than one book's opener, a larger edge threshold, or both.
  - It needs confirming with an information set that is surely executable: PC-C2 on IS-A, or C2 at Tuesday's price, when week w−1 is over.
- **The confirmatory path is already designed:** `nfl_preclose_v1`'s PC-C2 (the same model on IS-A features, which use the previous game's starter). It is scored on the sealed 2025 Holdout and prospectively in 2026. Both need the owner, because 2025 seasons enter as model history.

**Props: do projections predict Kalshi's last day?** The question is whether a projection known before the week predicts Kalshi's move from 24 hours before kickoff to the close. The regression is (logit close − logit 24-hour mid) on (logit projection − logit 24-hour mid), clustered by game.

| Projection | Contracts (games) | Coefficient (95% CI), one-sided p | CLV of picks 5+ points from the 24-hour mid |
|---|---|---|---|
| Family G, weeks 2–7 | 21,463 (75) | **0.032 (0.025 to 0.039), p 2×10⁻¹⁴** | +22.5 bps (+14.2 to +31.8), 11,688 picks |
| The props module, week 7 | 2,255 (14) | **0.043 (0.022 to 0.064), p 0.0004** | +29.2 bps (+15.1 to +44.5), 1,300 picks |

- **Kalshi's props drift toward the public projections in the last day.** The information gets priced in, but late.
- **The drift is tiny:** about a quarter of a cent a contract.
  - Kalshi's taker fee is 0.07·P·(1 − P), 175 bps at a 50¢ price.
  - Its maker fee is a quarter of that, 44 bps.
  - So the last-day drift cannot pay. A larger move might exist further out, but Kalshi's candles here start 24 hours before kickoff.
- **This squares with §13.** Against the close the projections show only a trace of information, because the market has absorbed most of it by then.

**The forward test is running.** `weekly_prospective.sh` and `score_week.R` implement §14's program, and week 9 runs on a schedule from the session's private store:
- the production run at Tuesday 18:00Z and Friday 21:00Z;
- venue and props snapshots on Thursday and an hour before each kickoff window;
- Kalshi's settlements and candles on 2026-11-10, then `score_week.R`.

It scores the model against every venue's last snapshot, the model's bets with their CLV, the props tests, and every side that beat Pinnacle, by closing EV and by result. `score_week.R` was checked on week 7, where it reproduces §13's point estimates, and on week 8's snapshots.

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

**Venues and value betting:**
- Kaunitz, Zhong and Kreiner, "Beating the bookies with their own numbers – and how the online sports betting market is rigged" ([arXiv 1710.02824](https://pdf.arxiv.org/pdf/1710.02824)).
- Hubáček and Šír, "Beating the market with a bad predictive model", *International Journal of Forecasting* 2023 ([RePEc](https://econpapers.repec.org/RePEc:eee:intfor:v:39:y:2023:i:2:p:691-719)).
- Hubáček, Šourek and Železný, "Exploiting sports-betting market using machine learning", *International Journal of Forecasting* 2019 ([RePEc](https://econpapers.repec.org/RePEc:eee:intfor:v:35:y:2019:i:2:p:783-796)).
- Whelan, "The truth about closing line value" ([blog](https://www.karlwhelan.com/?p=2595)).
- [Polymarket's fees](https://docs.polymarket.com/trading/fees), [SX Bet's best-odds endpoint](https://docs.sx.bet/api-reference/get-best-odds-v3.md) and Kalshi's `IncentiveProgram` ([SDK docs](https://cdn.jsdelivr.net/npm/kalshi-typescript@3.11.0/docs/IncentiveProgram.md)).

**Context:**
- On key numbers: [Action Network](https://www.actionnetwork.com/nfl/nfl-key-betting-numbers-spread-margins-of-victory-line-value), and the [margin-of-victory data, 1999–2025](https://www.deucescracked.com/blog/nfl-margin-of-victory-data-1999-2025).
- On in-play markets: "Beating the House" ([arXiv 1910.08858](https://arxiv.org/pdf/1910.08858)).
- On fill probability and returns: "The Market Maker's Dilemma" ([arXiv 2502.18625](https://arxiv.org/pdf/2502.18625)).
