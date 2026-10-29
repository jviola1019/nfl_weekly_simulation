# Can a model be both better than the market and statistically significant?

2026-10-28 to 2026-10-29. The owner asked:
- what else should be done to find a model that is statistically significantly better than the market, and whether one can exist;
- to make sure the dates, calibrators, bias and variance, and research are fully validated;
- to consider all props.

Every number below comes from a file in this folder, written by the script named beside it, or from the earlier committed studies cited.

**A correction to the first version of this report** (earlier on 2026-10-28). It said Kalshi's prop prices showed a favorite–longshot bias (slope 1.15). That was wrong. The probe used Kalshi's `occurrence_datetime` as the kickoff, but that field falls 3 hours after kickoff, so 74% of its "pre-kickoff" prices were mid-game (§1, Props).

## The short answer

| Target | Can a significant edge be shown? | Why |
|---|---|---|
| **Game outcomes against the close** | **No, not with any NFL data that exists.** | The best of 39 blends reaches +0.068% Brier skill. Detecting it would take 20,836 games, about four times every NFL game with a closing moneyline (4,997, 2006–2024). On all of those games, the smallest detectable skill is 0.39% (median over the 39). |
| **Game outcomes against the opener (closing-line value)** | **Possibly, and testable within a few seasons.** | In 2023 the close beat the opener by 2.29% of its Brier score. A model that anticipates part of that move earns closing-line value (CLV). A true +100 bps CLV needs about 230 picks (375 with 8 candidates); an NFL season has about 285 games. |
| **Kalshi props, all 74 single-game series** | **Not from the prices themselves. Possibly from better information, testable within a season.** | Kalshi's prices at kickoff are close to calibrated. Over 2026 weeks 1–7 (88,439 contracts, 107 games), player props' calibration slope is 0.958 (95% CI 0.917–0.999), and no series departs after BH. The only significant pooled departure, a compression in the scalar ladders, does not carry out of sample. A recalibration fit on weeks 1–5 does not beat weeks 6–7; traded walk-forward, it loses 15.7% after costs. No mutually exclusive set can be bought for a sure profit. An edge has to come from knowing what the price does not yet know, and must show up as CLV: +100 bps needs about 412 player-game picks. |

So the answer to "can it exist?":
- **Against the close, an edge may exist, but it is too small to prove.** The closing line is the best public forecast; this repository's work and the literature agree.
- **There is no calibration edge.** The game models were already calibrated, and the calibration maps add only noise. Kalshi's prop prices are close to calibrated: no series departs after BH, and the one significant pooled lean does not carry out of sample.
- **A significant edge is possible only from information,** against the opener and in props. That means news, usage or projections the price has not absorbed. The test is a pre-registered CLV test with after-cost accounting; both are planned below.

## 1. The evidence, verified

### Power against the close (`power.R`, `power_close.csv`, `power_summary.txt`)

The noise a test faces is the per-game spread of the Brier difference between a model and the no-vig close. #205 and #209 committed every Tune prediction (1,365 games, 2018–2022) for 39 candidates. Their per-game SD runs 0.0014–0.0915 (median 0.0232).

| | Minimum detectable Brier skill (one-sided 5%, 80% power), median over 39 candidates |
|---|---|
| Tune, 1,365 games | 0.74% |
| Every game with a closing moneyline, 2006–2024 (4,997) | 0.39% |

Seven candidates have positive Tune skill, and the best is S1 at +0.068%. At their own noise they would need:

| Candidate | Games needed |
|---|---|
| S1 | 20,836 |
| R1 | 74,338 |
| O1 | 63,708 |
| GLMNET | 146,467 |
| S1_MIN | 725,522 |
| XGB (isotonic) | 6.1 million |
| G2_GAPS | 9.1 million |

**No feasible sample can confirm an accuracy edge on the close.** That is why the close is this project's benchmark, not its target.

### The opener's ceiling (`opener_ceiling.csv`)

The data are ESPN BET's moneyline, 2023: 205 non-tie games with both an open and a close, from D1's archive (`nfl_preclose_v1`'s Tune season).
- **Brier:** open 0.22253, close 0.21743. The close is better by 0.00510 (week-block 95% CI −0.00107 to 0.01246; paired t p 0.077), which is 2.29% of the open's Brier.
- **Log loss:** open 0.63562, close 0.62464.
- **Movement:** the no-vig probability moved in 91.2% of games, with an SD of 439 bps.

That gap is the most a pre-close model could gain on accuracy: it would have to know the close at the open. It is about 34 times the best edge any blend shows on the close (2.29% against 0.068%).

**CLV power,** from `reports/2026-09-29/clv-power/output.txt`, the A2 study.
- **Its noise:** sigma 514 bps, from 2024–25 ESPN BET, read once, as disclosed.
- **Its formula:** two-sided 5%, 80% power, Bonferroni over the candidates, and a design effect of 1.11.

| True CLV | Picks needed at 80% power, 1 candidate | 8 candidates |
|---|---|---|
| +50 bps | 919 | 1,497 |
| +100 bps | 230 | 375 |
| +150 bps | 103 | 167 |

By contrast, flat ROI at −110 needs about 7,938 bets to detect +3%.

### Props: every Kalshi series (`props/`)

**What the captures hold** (`props_probe.R`, `props/props_inventory.csv`).
- **191 Kalshi NFL series** in total. 121 had markets in 2026 weeks 6–7 (games Oct 15–19 and Oct 22–26, releases W43 and W44). 70 were empty.
- **74 series are tied to single games:**

  | Kind | Series | Of which |
  |---|---|---|
  | Player props | 34 | 27 binary, including 6 "protected" twins and 3 head-to-heads; 7 scalar ladders and escalators that pay a fraction of $1 growing with a stat |
  | Game props | 37 | quarters, halves, team totals and specials |
  | Game lines | 3 | |

- **47 are season-long or novelty markets** (awards, trades, Super Bowl), out of scope.

**Outcomes: Kalshi's own settlements** (`kalshi_settled.R`, `props/kalshi_settled*.csv.gz`).
- **The fetch.** One keyless pass over `/markets?status=settled`, windowed by close time so that nothing from 2025 is requested. It returned 34,131 contracts for weeks 6–7 and 68,884 for weeks 1–5, with no failed requests.
- **Binary contracts** settle 1 or 0.
- **Most-yards contracts** split a tie 1/N.
- **Scalar contracts** settle at their payout.
- **A contract settled at the pre-game fair price** carries no outcome and is excluded. That happens to a player who never took a snap, or to a protected contract's player who left at the half. Kalshi marks it `result: "scalar"`, so the rule keys on the result, never on the value, which can round to 0 or 1.
- **Checked against an independent source** (`props/props_validation.csv`). For the 11 counting-stat ladders, outcomes were rebuilt from nflverse's 2026 player stats and snap counts:
  - Kalshi's settlement and the rebuild agree on 10,506 of 10,506 contracts.
  - All 165 of Kalshi's fair-price settlements are players nflverse shows without a snap.

**Prices at kickoff: Kalshi's hourly candles** (`kalshi_candles.R`, `props/kalshi_candles*.csv.gz`).
- **The close** is the last hourly candle ending at or before the scheduled kickoff, a median 5 minutes before it.
- **The fetch:** 1,076 requests, none failed.
- **Coverage:** 32,601 contracts got a close in the weeks 6–7 fetch, and 65,194 in the weeks 1–5 fetch.
- **Why not the captures?** The capture archive's own game-day runs can land after the 1 p.m. kickoffs (see Dates). Its last capture is analysed beside the close in `props/captured/`.

**Calibration at kickoff, weeks 1–7** (`props_close.R`, `props/close/close_calibration.csv`).
- **The data:** 88,439 contracts with a spread of 10¢ or less, 107 games and 2,900 player-games.
- **Method:** a logit on the price, clustered by game (t with 106 df).
- **Reading the slope:** 1 is calibrated; above 1, the prices are compressed toward 50¢ (a favorite–longshot bias); below 1, they are too extreme.

| Group | Contracts | Slope (95% CI) | Detectable at 80% power | Calibration-in-the-large |
|---|---|---|---|---|
| Player props (24 series fitted alone) | 54,877 | 0.958 (0.917–0.999), p 0.046 | ±0.059 | +0.006 (p 0.88) |
| Scalar ladders (6) | 2,254 | 1.12 (1.04–1.20), p 0.003 | ±0.11 | −0.078 (p 0.045) |
| Game props (34) | 26,333 | 1.02 (0.95–1.10) | ±0.10 | −0.003 |
| Game lines (3) | 4,975 | 0.99 (0.84–1.14) | ±0.21 | −0.018 |
| **All** | **88,439** | **0.981 (0.941–1.02)** | **±0.057** | **0.000** |

**No single series departs after BH** over the 67 series fitted alone:
- the smallest slope q is 0.24;
- the smallest calibration-in-the-large q is 0.12, outside the exclusive sets.

Two adjustments to the per-series family:
- **The exclusive sets** are left out of the calibration-in-the-large family. They are:
  - the half and quarter winners, and half-time/full-time;
  - the race to a score;
  - the win margin;
  - the first team to score a touchdown;
  - the most rushing yards;
  - the moneyline.

  In each game their outcomes sum to 1, so that test only measures whether the prices sum to 1. Their coherence is checked below.
- **Rare outcomes are not fitted alone.** A series needs 10 events and 10 non-events (`close_coverage.csv`). That rule set aside six series:
  - safety and tie, 1 event each;
  - overtime, 9;
  - D/ST touchdown, 8;
  - both teams scoring in every quarter, 8;
  - the rushing-yards escalator, whose payouts sum to 9.

The six raw p-values under 0.05 among 67 tests are about what chance gives.

**Two pooled results depart, in opposite directions.**
- **Player props** lean slightly too extreme, the reverse of a favorite–longshot bias.
  - Contracts priced 5–10¢ won 8.2% against 7.4%, and those priced 50–70¢ won 57.0% against 58.6% (`close_reliability.csv`).
  - It does not survive a Bonferroni correction over the five pooled fits (0.23).
  - By week, the slope runs 0.88–1.01 (`close_calibration_by_week.csv`).
- **The scalar ladders are compressed,** and that does survive Bonferroni (0.017).
  - A scalar pays a mean 10¢, so the dollar value is small.
  - It does not carry out of sample. A recalibration fit on weeks 1–5 gains +0.70% on weeks 6–7 (p 0.083); walk-forward it loses 1.36%; and traded, it makes +1.1% on 14 bets and −0.4% on 370 (below).
- **The one series compressed in both windows** is interceptions: 1.53 in weeks 6–7, and 1.26 (1.07–1.46, q 0.24) over weeks 1–7. It is a hypothesis to pre-register, not a finding.

**Out of sample** (`props/close/close_oos.csv`). The recalibration is a logit refit on earlier weeks. The taker buys at the ask, or No at 1 − bid, when the refit price beats it after Kalshi's taker fee (0.07 × P × (1 − P)).

| | Brier skill (paired by game) | Taker bets | Return after the spread and fee (95% CI, games resampled) |
|---|---|---|---|
| Player props, weeks 1–5 → 6–7 | +0.04% (p 0.32) | 226 | −49.8% (−74.0% to −18.9%) |
| Player props, walk-forward (weeks 2–7) | −0.01% (p 0.79) | 123 | −53.6% (−90.4% to −6.9%) |
| Game props, walk-forward | −0.27% (p 0.99) | 1,483 | −9.4% (−22.0% to +2.0%) |
| Scalar ladders, weeks 1–5 → 6–7 | +0.70% (p 0.083) | 14 | +1.1% (−4.6% to +6.2%) |
| Scalar ladders, walk-forward | −1.36% (p 0.92) | 370 | −0.4% (−1.4% to +0.5%) |
| Game lines, walk-forward | −0.72% (p 0.97) | 1,633 | −13.8% (−29.3% to +1.3%) |
| **All, walk-forward** | **−0.09% (p 0.98)** | **2,423** | **−15.7% (−30.1% to −1.7%)** |

**No sure profits** (`props/close/close_coherence.csv`):
- **The check:** 12 series are exclusive sets, with exactly one contract settling Yes per event. At kickoff, none of their 1,661 events could have been bought whole, as all Yes or all No, for a sure profit after the fee. The closest came within 0.16¢.
- **What that explains:** the significant calibration-in-the-large of the exclusive sets. Their mids sum to 0.85–1.00, but their asks sum to 1.01–1.19.
- **A first draft of this check** mixed quotes from different captures and showed apparent sure profits. They vanish when every contract is priced at the same moment.

**Movement, and CLV power** (`props/props_movement.csv` for weeks 6–7; `props/close/close_late_movement.csv` for weeks 1–7).
- **From the first capture to kickoff** (a median 68 hours), player-prop prices moved in 92% of contracts. The median move was 200 bps and the SD 724 bps.
- **The last day:**

  | Window before kickoff | Median move | SD |
  |---|---|---|
  | 24 hours | 100 bps | 205 bps |
  | 3 hours | 50 bps | 136 bps |
  | 1 hour | 0 | 93 bps |

  Most of the information arrives before the last day.
- **Picks a CLV test needs,** by the A2 formula: one contract a pick, before the design effect for picks that share a game. The within-game ICC is 0.022, so k picks from one game multiply n by 1 + 0.022(k − 1).

  | Pick placed | Price SD to kickoff | +100 bps | +50 bps |
  |---|---|---|---|
  | At the first capture | 724 bps | 412 (671 with 8 candidates) | 1,646 (2,682) |
  | 24 hours before | 205 bps | 34 (54) | 133 (216) |

  A full board has about 400 player-games a week.

**The first version's error, measured** (`props/props_cutoff_check.csv`, `props/props_occurrence_gaps.csv`).
- **The cause:** Kalshi's `occurrence_datetime` is the scheduled kickoff plus 180 minutes on 57 of 58 games, and plus 200 on one.
- **The scale:** with it as the cutoff, 6,300 of 8,564 contracts (74%) were priced from a mid-game capture.
- **The effect on the ten original ladders:**

  | | Calibration slope | Median move | SD of a player-game's move |
  |---|---|---|---|
  | Mid-game captures (the first version) | 1.157 (1.064–1.250) | 450 bps | 1,047 bps |
  | Kalshi's close at kickoff | 1.018 (0.925–1.111) | 150 bps | 284 bps |

- **Where the bug lived:** only in the first version of this probe. No production code reads that field. D1's closing rule uses the schedule's `kickoff_utc` and drops every post-kickoff row (`R/odds/closing.R`).

### Calibrators (`calibrators.R`, `calibrators.csv`)

#205 fit three calibration maps walk-forward on top of seven base models: Platt, spline and isotonic.
- **Brier:** 2 of the 21 calibrated variants improve on their own model, both XGBoost and both negligible (−0.00021 and −0.00006). None is significant (every BH q ≥ 0.93).
- **Log loss:** one improves, and none significantly.
- **Isotonic** is the worst: it lowers the calibration slopes to about 0.87, the signature of an overfit map.
- **The base models were already calibrated** (slopes 0.98–1.10), so the maps only add noise.
- **The engine's own calibrator** is invalid (audit M4) and disabled; the engine shrinks 70% toward the market instead.
- **On props,** the same holds: a recalibration of Kalshi's prices loses out of sample (above).

**Calibrators are not a source of edge here.**

### Dates (`dates_audit.R`, `dates_checks.csv`, `dates_violations.csv`, `capture_delays.R`, `capture_delays.csv`, and the props probe)

Ten schedule checks; one has violations. Two timing faults were found outside the schedule.

| Check | Result |
|---|---|
| `kickoff_utc` equals the ET game day and game time, with daylight saving | 0 of 6,732 off; 0 of 698 games near the DST changes |
| The 259 games without a game time (all 1999) | 0 off: each sits at 1 p.m. ET |
| Every game lies between August 1 and March 1 of its season | 0 of 6,991 off |
| No season after 2024 (the seal) | 0 |
| Weeks are ordered; no game kicks off after the next week's cutoff | 0 of 550 weeks |
| Venue time zones are valid Olson names | 48 of 48 |
| The late-change rows carry the schedule's kickoff | 77 of 77 |
| **Rest days equal the days since each team's previous game** | **34 of 13,153 team-games differ** |
| **Kalshi's `occurrence_datetime` against the scheduled kickoff** | **3 hours after it, for all 58 captured games** |
| **The capture workflow's start times:** 10 scheduled slots since the schedule took effect (2026-10-19), none skipped | **2 h 12 min to 3 h 57 min late (median 3 h 16 min)** |

**The rest-day finding.** nflverse's rest columns follow the original schedule for late-season games moved to Saturday (2019, 2021). They also count the cancelled 2022 BUF–CIN game, so BUF and CIN show 6 days of rest where they had 15.
- 25 Tune games are affected.
- Rebuilding the five rest features from the days actually rested changes 0 of 15 S1 verdicts (`rest_sensitivity.csv`).
- It is recorded as defect REST-FLEX on the five rest features, to be fixed with G1's point-in-time features.

**Kalshi's occurrence time** is not a kickoff, and the props scripts never use it as one. `props_common.R` takes kickoffs from the schedule.

**The capture timing.** GitHub starts scheduled runs late, and on 2026-10-25 the delay beat the workflow's 3 h 45 min buffer.
- The 13:15Z early-games capture started at 17:03Z, after 8 games had kicked off: the 13:30Z international game and the seven 17:00Z games. Those games' last capture is Saturday's.
- Monday Night Football's capture on 2026-10-26 started 14 minutes before kickoff.
- `capture_delays.R` pairs each cron slot with its run, in order. Its input is `capture_runs.json`, the `gh run list` output.
- Closes now come from Kalshi's candles. The capture schedule needs a fix (§3).

**Opener timing.** D1's 2023–24 archive labels prices open and close, as ESPN does, without timestamps. From 2026 on, the captures carry their own times.

### Bias and variance

On the close (A3b's S5):
- Every model's calibration slope is consistent with 1.
- The anchor plus all 36 features loses out of sample at every training length (log loss 0.6188 at best, against 0.6097).
- C2's smoothing curve is U-shaped, best at 8.
- The close's own errors have a bias of −0.52 points on the margin.

On props, the prices at kickoff are calibrated to within about ±0.06 on the slope. Two pooled results depart:
- **Player props** lean slightly too extreme, so the outcomes vary a little less than the prices imply. This is not significant after Bonferroni.
- **The scalar ladders** are compressed, significantly so in-sample.

Neither carries out of sample, so there is no variance to correct.

### The research, reproduced (`rerun_research.sh`, `compare_research.R`, `rerun_compare.csv`)

Every A3 study was rerun from scratch with a fresh HOME:
- the flex-game rebuild;
- the research table;
- the cluster, late-change, joint, joint-linear, power and S4 sections;
- the S4-null diagnostic and the late-movement test.

Each output was compared with its committed file at zero tolerance. **All 11 are identical.** The rerun found two faults, both fixed here:
- **The `s4` section overwrote `s4_power.csv`** with its superseded 5-replicate look, wherever it ran after the `power` section. It now writes `s4_power_initial.csv`.
- **The inline `Rscript -e` comparison crashed** with exit 139 on Windows, and is now a script file.

The A3b verification (`reports/2026-10-28/verification/`) independently checks 56 of 56 numbers.

## 2. Literature

**Closing lines are broadly efficient, with small, contested exceptions.**
- Szalkowski and Nelson (2012), on 2002–2011, found the opener's mean square error slightly below the close's, not significantly ([arXiv 1211.4000](https://arxiv.org/pdf/1211.4000)).
- Moskowitz (2021, *Journal of Finance*, "Asset Pricing and Sports Betting") is reported to find that line movements overreact from open to close, with returns too small to cover costs. This is cited second-hand.
- Most claims of profitable angles come from theses and blogs: for example the [Claremont theses](https://scholarship.claremont.edu/cgi/viewcontent.cgi?article=5145&context=cmc_theses) and the [line-movement study](https://www.researchgate.net/publication/372441761_Inefficient_Forecasts_at_the_Sportsbook_An_Analysis_of_Real-Time_Betting_Line_Movement).

**Props are called the softest market, but no peer-reviewed study measures it.** The claims are industry ones: lower limits and higher holds ([4for4](https://www.4for4.com/2022/preseason/9-strategies-beat-nfl-player-prop-market), [Sports Betting Odds Calculator](https://www.sportsbettingoddscalculator.com/market-efficiency)).

**Kalshi's sports prices are close to calibrated near the event, and its favorite–longshot bias sits in the cheap contracts.**
- **Le (2026),** 429,000 Kalshi and Polymarket contracts ([arXiv 2602.19520](https://arxiv.org/abs/2602.19520), Table 4 and §5.1). Sports markets are "close to calibrated at short-to-medium horizons (slopes 0.90–1.10 from 0 to 48 hours)": 1.10 in the last hour, 0.90–1.08 out to two days. They become underconfident beyond a month (1.74).
  - The first version of this report said sports were best calibrated more than a week out. That was the reverse of the paper.
- **Bürgi, Deng and Whelan,** "Makers and Takers: The Economics of the Kalshi Prediction Market" ([CEPR DP 20631](https://ideas.repec.org/p/cpr/ceprdp/20631.html); [CESifo WP](https://www.ifo.de/en/cesifo/publications/2025/working-paper/makers-and-takers-economics-kalshi-prediction-market)). The study covers over 300,000 Kalshi contracts:
  - low-price contracts win less often than they need to break even after fees;
  - high-price contracts earn small positive returns;
  - makers earn more than takers.
  - Its UCD and VoxEU pages refused this session (HTTP 403) and were not re-read.
- **An open analysis of 46,168 resolved markets** pools all categories ([GitHub, prediction-market-calibration](https://github.com/hrishi-tailor/prediction-market-calibration)):
  - Kalshi's slope rises from 1.02 thirty days out to 1.22 one hour out (1.08 at one day with the tails excluded);
  - buying longshots at the ask loses 34–89% per dollar;
  - no price bucket earns a significant return after spreads and fees.
- **Kalshi's fee.** A taker pays 0.07 × P × (1 − P) per contract, rounded up per order; makers pay none on most sports series. These are third-party descriptions ([Stokastic](https://www.stokastic.com/articles/prediction-markets/kalshi-fees-vs-dfs-rake)). Kalshi's own fee PDF returned HTTP 429 and was not retried.

The 2026 prices at kickoff fit the sports-specific evidence: slopes of 0.96–1.02 for player props, game props and game lines. Their cheap contracts do not show the cross-category bias: player props priced 5–10¢ won slightly more often than priced.

## 3. What else should be done, in order

**1. Now, owner actions (time-critical).**
- **Run the capture backfill before 2026-12-28:** `gh workflow run capture-archive.yml -f days=90`.
  - Kalshi's prices for 2026 weeks 1–5 can now be rebuilt from its candles (`props_close.R`).
  - ESPN's prop lines and game odds in those captures cannot be rebuilt, and nor can each capture's decision-time snapshot.
- **Sign spec §4's S4 amendment.**
- **Merge the stack.** D1 (#224) carries the openers.
- **Decide on Kalshi's 2025 history** for props.
  - Under a signed `nfl_props_v1` it would be the Tune season, so that hypotheses are fixed before 2026's weeks are read.
  - That is 5,335 anytime-TD player-games from 2025 week 1, and the receiving, rushing and passing yards ladders from 2025-10-06 (`reports/2026-09-29/DATA_SOURCES_SPIKE.md`, on the roadmap branch).
  - Weeks 1–7 of 2026 have now been read, and the interception ladder's lean came from them. So 2026's later weeks, not weeks 1–7, would confirm it.

**2. Props, prospective 2026 (where a significant result is most testable).**
- **The data, each week:** `kalshi_settled.R` and `kalshi_candles.R` give every contract's outcome and its price at kickoff, about 1,000 requests at one a second. Then `props_close.R` rescores.
- **Fix the capture schedule.** The decision-time snapshots must land before kickoff.
  - Options: earlier Sunday crons, a Saturday-night run, or a dispatch from a reliable runner.
  - Add a slot for the 9:30 a.m. ET international games. The 13:15Z slot falls 15 minutes before them, so a run 2–4 hours late misses them.
  - The close no longer depends on the captures.
- **The model:** the props module's projections from current-season stats through week w−1, shrunk toward the prior season (P1, C2). The correlated game simulation links them to the game.
- **Pre-register `nfl_props_v1`** before scoring:
  1. **CLV.** The module's picks beat the price at kickoff, with one contract per player-game. Picks placed at the first capture need about 412 at a true +100 bps.
  2. **Interceptions.** The ladder's compression persists on weeks the hypothesis did not come from: slope > 1, one test.
  3. **Costs.** Both survive the spread and the taker fee. A maker strategy pays no fee but needs fill data, so it can only be tested live.
- **Do not chase a calibration edge.** The prices are close to calibrated, and recalibrating them loses money after costs.

**3. Games, against the opener.**
- A4's opener screen on Tune 2023, then candidate models through S3 and the S4 nulls.
- Historical openers (track H), to grow Tune from 205 games into the thousands.
- Then sign `nfl_preclose_v1`, score Confirm 2024, open the 2025 holdout once, and track CLV prospectively in 2026.

**4. Games, against the close.** Stop searching for an accuracy edge. Keep the close as the benchmark and the calibration reference.

**5. Data quality.**
- REST-FLEX in G1.
- Weather that is never stale (C2).
- Props projections that are never stale (C2).
- Capture times for every opener from 2026 on.
- Kickoffs only from the schedule, never from a venue's own event time.

**What any claim needs:**
- pre-registration;
- one confirmatory test per hypothesis family, with BH or Bonferroni;
- power of at least 80% at the minimum effect that matters;
- walk-forward fits only;
- valid nulls (S4's anchor null);
- a sealed holdout used once;
- after-cost accounting for any betting claim;
- a reproducible hash.

## Limits

- **One season of props, a little over half of it played.** There are 107 games in weeks 1–7, and 28 in the weeks with captures. The game-clustered intervals rest on 107 clusters; the captured weeks' 28 fall under the 30 at which this project's screen switches to the wild bootstrap. These are measurements of the market, not a test of a model.
- **Kalshi's close** is the last hourly candle at or before kickoff. It is a top-of-book quote, with depth unchecked, and a bettor pays the ask.
- **The fantasy contracts** settle on Sleeper's published points, which nflverse does not reproduce. Those series rely on Kalshi's settlement alone; the nflverse check covers the 11 counting ladders.
- **The opener ceiling** uses one season and one book.
- **The power figures for games** assume the noise of the 39 existing candidates. A model far from the market would have a larger SD and a larger minimum effect.
- **Nothing here reads 2025,** the sealed holdout and Kalshi's 2025 prop history. Every Kalshi request is windowed to 2026 closes, and every script stops on a 2025 row.
