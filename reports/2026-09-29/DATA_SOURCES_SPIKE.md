# Keyless data sources: spike results (2026-09-29)

Phase 0, Task 5. This is measurement only. The code is in `scripts/spike/` and
the raw tables are in `reports/2026-09-29/spike/*.csv`. Every number below comes
from those CSVs. Where a number is derived, the formula is given.

| Script | Command (repo root) | Status | Runtime | Requests | Failed |
|---|---|---|---|---|---|
| Kalshi coverage | `Rscript scripts/spike/kalshi_coverage.R --max-minutes=55` | COMPLETE | 20.9 min | 2373 | 0 |
| ESPN BET bias | `Rscript scripts/spike/espn_bet_bias.R --max-minutes=55` | COMPLETE, 466/466 games | 6.4 min (network run); 1.3 min (re-analysis from page cache) | 600 (network run); 0 (re-analysis) | 0 |
| ESPN game odds | `Rscript scripts/spike/espn_game_odds_coverage.R` | COMPLETE, 40/40 games | 0.4 min | 40 | 0 |

There were no HTTP 401, 403 or 429 responses and no keys. The failure ledgers
(`kalshi_failures.csv`, `espn_bet_failures.csv`, `espn_game_odds_failures.csv`)
have headers and no rows.

## Headline

- **Kalshi is the usable historical prop source.** It has anytime TD from
  2025-09-04 (2025 week 1) and receiving, rushing and passing yards from
  2025-10-06.
  - In the candle sample, 170/173 random markets had at least one hourly candle
    in the 48 h before kickoff.
  - 161/173 (93.1%) had a pre-kickoff price, meaning a trade or a two-sided
    quote.
- **GO (primary definition):** anytime TD plus all three yardage markets clear
  ≥300 settled player-games with a pre-kickoff price.
  - They clear it even at the event-level 95% lower bound. The tightest margin
    is passing yards: 390 vs 300.
  - These counts extrapolate from one random market per sampled event, and
    assume the same priced rate within an event (section 4).
- **The spec rule is met under the primary definition.**
  - The GO window is the 2025 season, plus 2026 weeks 1–3 for the yardage,
    receptions and first-TD series. The 2026 anytime-TD series (KXNFLTD) rests
    on n=3 and must be re-measured.
  - Under a stricter trade-in-the-final-hour reading, passing yards drops below
    300 (276), and the rule would not be met (section 4).
  - No measured market is NO-GO under the primary definition. Unmeasured ESPN
    props are labeled NOT MEASURED.
- **ESPN BET props (provider 58): the verdict is LINE-MOVEMENT ONLY for all
  four tested markets, under the rule as written.**
  - The row-level test is confounded: unpriced rows are alternate-ladder rungs,
    not main lines that lost their price (section 2).
  - ESPN BET anytime-TD rows carry prices in only two weeks: 7 player-games in
    2024 week 8, and 294 in 2025 week 1. That leaves 265 settled player-games,
    so ESPN offers effectively no historical anytime-TD prices.
- **ESPN game odds:** open and close moneylines are present for every sampled
  game from 2023 on. In 2022 only close is present; in 2018–2021 neither is.
  From 2025 week 15, ESPN's game-odds provider is DraftKings (100), not ESPN BET
  (58).

## 1. Kalshi coverage per series

Source: `spike/kalshi_series_summary.csv` (per series), `spike/kalshi_events.csv`
(per event) and `spike/kalshi_candle_sample.csv` (per candle check).

"Events" means settled events from `/events?series_ticker=S&status=settled`
(cursor-paged). "Player-games" means distinct `custom_strike.football_player`
among a regular- or post-season event's markets settled `yes`/`no`. Preseason
events are excluded because they are not in the nflreadr schedule.

| Series | Events | First event | Last event | Events matched to schedule | Markets | Settled (yes/no) | Other result (voided) | Settled player-games |
|---|---|---|---|---|---|---|---|---|
| KXNFLANYTD | 285 | 2025-09-04 | 2026-02-08 | 285 | 5482 | 5335 | 147 | 5335 |
| KXNFLTD | 54 | 2026-08-06 | 2026-09-28 | 48 | 2318 | 2224 | 94 | 1090 |
| KXNFL2TD | 279 | 2025-09-04 | 2026-02-08 | 279 | 2163 | 2136 | 27 | 2136 |
| KXNFLFIRSTTD | 333 | 2025-09-04 | 2026-09-28 | 333 | 6714 | 6513 | 201 | 6512 |
| KXNFLRECYDS | 258 | 2025-10-06 | 2026-09-28 | 252 | 14845 | 14681 | 164 | 2573 |
| KXNFLRSHYDS | 253 | 2025-10-06 | 2026-09-28 | 247 | 7221 | 7169 | 52 | 1168 |
| KXNFLPASSYDS | 277 | 2025-10-06 | 2026-09-28 | 251 | 4439 | 4381 | 58 | 491 |
| KXNFLREC | 209 | 2025-10-27 | 2026-09-28 | 209 | 11304 | 11221 | 83 | 2140 |
| KXNFLGAME | 429 | 2025-07-31 | 2026-09-28 | 331 | 36 (sample of 18 events) | 36 | 0 | n/a (game market) |
| KXNFLSPREAD | 398 | 2025-08-21 | 2026-09-28 | 333 | 322 (sample of 19) | 322 | 0 | n/a |
| KXNFLTOTAL | 398 | 2025-08-21 | 2026-09-28 | 333 | 388 (sample of 19) | 388 | 0 | n/a |

Market counts for the eight player series cover **every** event (3173 events
listed across all series). For the three game-level series they come from the
sample only. Extrapolated to all events, that is about 858, 6745 and 8128
settled markets (`est_settled_markets_all_events`).

**Pre-kickoff candle availability.** For 3 events per series per calendar month
(seeded, 173 events), I pulled hourly candles for [kickoff − 48 h, kickoff] on
two markets:
- the highest-volume market (the brief's check);
- a seeded-random market, which is the unbiased estimate, since the top-volume
  market overstates liquidity.

Kickoff is nflreadr `gameday` + `gametime` (ET), converted to UTC. "Candle"
means at least one candle with `end_period_ts ≤ kickoff`. "Priced" means the last
such candle has a traded close price, or a two-sided quote (yes_bid > 0 and
yes_ask < 1).

| Series | Sampled events | Top-volume: candle / priced | Random: candle / priced | Random: traded in last pre-kickoff hour | Median yes spread (random) |
|---|---|---|---|---|---|
| KXNFLANYTD | 16 | 100% / 100% | 100% / 93.8% | 75.0% | 0.030 |
| KXNFLTD | 3 | 100% / 100% | 33.3% / 33.3% | 33.3% | 0.010 |
| KXNFL2TD | 16 | 100% / 100% | 93.8% / 81.2% | 56.2% | 0.040 |
| KXNFLFIRSTTD | 19 | 100% / 94.7% | 100% / 84.2% | 73.7% | 0.030 |
| KXNFLRECYDS | 16 | 100% / 100% | 100% / 100% | 68.8% | 0.060 |
| KXNFLRSHYDS | 16 | 100% / 100% | 100% / 100% | 81.2% | 0.045 |
| KXNFLPASSYDS | 16 | 100% / 100% | 100% / 100% | 56.2% | 0.050 |
| KXNFLREC | 15 | 100% / 93.3% | 100% / 93.3% | 33.3% | 0.060 |
| KXNFLGAME | 18 | 100% / 100% | 100% / 100% | 100% | 0.010 |
| KXNFLSPREAD | 19 | 100% / 100% | 100% / 100% | 78.9% | 0.010 |
| KXNFLTOTAL | 19 | 100% / 100% | 100% / 89.5% | 84.2% | 0.020 |
| **All** | **173** | **171/173 = 98.8% priced** | **161/173 = 93.1% priced** | | |

The last two columns are derived from `kalshi_candle_sample.csv`:
`last_pre_trade_price` not NA, and `last_pre_yes_ask − last_pre_yes_bid`.

Pre-kickoff candles exist from the first sampled month of each series. For
anytime TD, that is September 2025, at 3/3 random markets priced. Coverage does
not start in December 2025.

## 2. ESPN BET prop archive: priced share and selection-bias test

Source: `spike/espn_bet_market_season.csv`, `spike/espn_bet_bias.csv`,
`spike/espn_bet_bias_by_season.csv`, `spike/espn_bet_unpriced_structure.csv`,
`spike/espn_bet_priced_by_week.csv`, `spike/espn_bet_all_markets.csv` and
`spike/espn_bet_games.csv`.

The scan covered all 272 games of the 2024 regular season and all 194 games of
2025 weeks 1–13. Every game returned `ok`, with 600 pages in total. A row is
priced when `espn_row_is_priced()` finds an American price on over or under,
open or current. A player-game is priced when any of its rows is priced.

| Market | Season | Games | Rows | Priced rows | Priced share (rows) | Player-games | Priced player-games | Priced share (player-games) | Open-priced + settled player-games | Rows updated after kickoff |
|---|---|---|---|---|---|---|---|---|---|---|
| Anytime TD | 2024 | 271 | 12229 | 7 | 0.06% | 5703 | 7 | 0.12% | 7 | 92.7% |
| Anytime TD | 2025 | 194 | 14437 | 588 | 4.07% | 4700 | 294 | 6.26% | 258 | 99.2% |
| Receiving yards | 2024 | 271 | 20532 | 4330 | 21.1% | 3007 | 2089 | 69.5% | 2039 | 93.3% |
| Receiving yards | 2025 | 194 | 23309 | 4240 | 18.2% | 2132 | 2103 | 98.6% | 2046 | 98.9% |
| Receptions | 2024 | 270 | 18574 | 5074 | 27.3% | 2883 | 2528 | 87.7% | 2443 | 94.7% |
| Receptions | 2025 | 194 | 16007 | 4182 | 26.1% | 2094 | 2091 | 99.9% | 2042 | 99.1% |
| Rushing yards | 2024 | 267 | 8777 | 1864 | 21.2% | 1279 | 900 | 70.4% | 898 | 93.6% |
| Rushing yards | 2025 | 194 | 13428 | 2152 | 16.0% | 1082 | 1071 | 99.0% | 1068 | 99.1% |

Across all ESPN BET prop markets, 36.7% of rows were priced in 2024 (55143 of
150100) and 28.9% in 2025 (58380 of 201928). That is consistent with the
probe's 20–35%. Anytime TD is priced in only two weeks: 2024 week 8 (7
player-games) and 2025 week 1 (294 player-games, 68.7% of that week). Every
other week has 0 priced rows (`espn_bet_priced_by_week.csv`).

**Bias test (the brief's rule, copied exactly).** It's **USABLE** when p ≥ 0.05
and |diff| < 0.03; otherwise **LINE-MOVEMENT ONLY**.

Setup:
- "Hit" means TDs ≥ the rung for anytime TD, and stat > `open$target$value` for
  over/unders.
- `diff` is the priced hit rate minus the unpriced hit rate, from
  `bias_test()` (a two-sided `prop.test`).
- Rows are excluded, and counted, when the athlete has no gsis match, has no
  weekly stat row, or the row has no open target.

| Market | Priced n | Priced hit rate | Unpriced n | Unpriced hit rate | diff | p-value | Verdict |
|---|---|---|---|---|---|---|---|
| Anytime TD | 516 | 0.1628 | 22215 | 0.0975 | +0.0652 | 9.3e-07 | **LINE-MOVEMENT ONLY** |
| Receiving yards | 8356 | 0.5045 | 34200 | 0.3675 | +0.1370 | 8.9e-117 | **LINE-MOVEMENT ONLY** |
| Receptions | 8988 | 0.4733 | 24705 | 0.3695 | +0.1038 | 2.0e-66 | **LINE-MOVEMENT ONLY** |
| Rushing yards | 4006 | 0.4728 | 18067 | 0.3771 | +0.0957 | 3.6e-29 | **LINE-MOVEMENT ONLY** |

By season (`espn_bet_bias_by_season.csv`), every testable market-season is
LINE-MOVEMENT ONLY. Anytime TD 2024 is UNTESTABLE because it has 0 priced rows
with an outcome.

**Read this verdict with its confound.** The rule compares two different kinds
of row:
- **Priced rows are main lines.** Each has one over row and one under row, at
  2.00–2.07 priced rows per priced over/under player-game.
- **Unpriced rows are almost all alternate-ladder rungs.**
  - In 2024, 100% of unpriced rows have whole-number targets (50, 60, 70 yards;
    1+/2+/3+ TD). Not one unpriced player-game contains a half-point row, so
    the archive never shows a main line that lost its price.
  - In 2025, ladders also use half points. Still, 98.8% (receiving yards),
    99.9% (receptions) and 99.2% (rushing yards) of unpriced rows sit inside a
    player-game that also has a priced main line.
- **Ladder rungs sit above the main line.** The mean open target is 35.3 priced
  vs 48.1 unpriced for receiving yards, 3.13 vs 4.10 for receptions, and 39.7
  vs 49.1 for rushing yards.

So the hit-rate gap measures where the ladder rungs sit, not whether retaining a
price is selective. Priced main lines hit at 0.47–0.50, which is what a fair
main line should do.

The data cannot run a valid selection-bias test, because it contains no
population of stripped main lines. The actual selection is at the player-game
level. In 2024, 30.5% (receiving yards), 12.3% (receptions) and 29.6% (rushing
yards) of player-games are ladder-only, with no main line at all. That is a
choice by the book about what to offer, or a loss in the archive, and the data
cannot tell which.

The verdicts stand as written under the brief's rule. Phase 2 should decide
whether to redesign the test before ESPN BET counts toward any GO.

**Pre-kickoff timing.**
- 92.7–99.2% of rows have `lastUpdated` after kickoff, so `current` is not a
  pre-kickoff price.
- Every priced player-game also has an `open` American price.
- `open` has no timestamp. That it was posted before kickoff is presumed from
  its name and not verified.

**Athlete matching** (`espn_bet_athlete_matching.csv`):
- 4 of 698 distinct athletes (304 rows) have no `espn_id → gsis_id` match. They
  are excluded and counted.
- 13 `espn_id`s map to more than one gsis id; the first was kept.
- A missing weekly stat row means the player recorded no stat that week. Those
  rows are excluded, not scored 0: 3297 anytime-TD rows, 1007 receiving yards,
  691 receptions and 70 rushing yards.

## 3. ESPN game odds: open/close coverage by season

Source: `spike/espn_game_odds_by_season.csv` (5 seeded-random regular-season
games per season) and `spike/espn_game_odds_providers.csv` (per provider).

| Season | Games | Open ML | Close ML | Open + close ML | Current ML | Open total | Close total | Providers with open/close |
|---|---|---|---|---|---|---|---|---|
| 2018 | 5 | 0 | 0 | 0 | 5 | 0 | 0 | none (Caesars, Westgate, Wynn, consensus… current only) |
| 2019 | 5 | 0 | 0 | 0 | 5 | 0 | 0 | none |
| 2020 | 5 | 0 | 0 | 0 | 5 | 0 | 0 | none |
| 2021 | 5 | 0 | 0 | 0 | 5 | 0 | 0 | none |
| 2022 | 5 | 0 | 5 | 0 | 5 | 0 | 5 | ESPN BET (58): close only |
| 2023 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | ESPN BET (58) |
| 2024 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | ESPN BET (58) |
| 2025 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | ESPN BET (58) through week 11; DraftKings (100) in weeks 15, 17 and 18 |

This confirms the probe's claim that open and close are available from 2023
onward. The switch from ESPN BET to DraftKings in late 2025 fits the ESPN BET
prop archive ending around week 13. Whether DraftKings (provider 100) propBets
exist for 2025 weeks 14 onward was **not measured**; that is a follow-up.

## 4. GO / NO-GO per market

**Spec rule (copied exactly from the brief):** anytime TD plus at least 3
yardage markets, each with ≥300 settled player-games that have a pre-kickoff
price.

The labels in this section:
- **GO** means measured, and at or above the rule. GO markets are backtested
  historically in Phase 5.
- **NO-GO** means measured, and below the rule. NO-GO markets are
  prospective-only, labeled that way.
- **NOT MEASURED** means this spike took no measurement, so the market is
  neither GO nor NO-GO. It stays prospective-only until it is measured.

### How the counts are built, and what they assume

- **The sampling unit is the event.**
  - For each series, 3 events per calendar month were drawn with a seed.
  - For each drawn event, one market was drawn uniformly at random from that
    event's markets, and checked for a pre-kickoff price (section 1).
  - k/n counts events: n sampled events, k of which had a random market that
    was priced. So the Clopper–Pearson 95% lower bound,
    `qbeta(0.025, k, n − k + 1)`, is an **event-level binomial bound**. It is
    not a bound over markets or player-games.
- **The extrapolation assumes the rate holds everywhere.** Player-games with a
  pre-kickoff price = settled player-games (exact, from every event) × k/n.
  That **assumes the priced rate is the same for every market within an event,
  and across the events of the series.** This was not tested. Three things
  weaken it:
  - Months are equally weighted, not weighted by event count.
  - A player-game with several strikes counts as priced if any strike is
    priced, while the check looked at one market.
  - Liquidity varies by player and by strike. Top-volume markets were priced
    98.8% of the time, random markets 93.1%.
- **"Priced"** means the last candle at or before kickoff has a traded close
  price, or a two-sided quote (yes_bid > 0 and yes_ask < 1). A stricter
  trade-only reading is tested below.
- **ESPN BET** counts only when its verdict is USABLE, and it is not USABLE for
  any market (section 2).

### Primary table (priced = trade or two-sided quote)

The margin column is (settled × CP lower bound) − 300. The source for every
number is `kalshi_series_summary.csv` (settled player-games) and
`kalshi_candle_sample.csv` (k/n).

| Market | Source used | Window with prices | Settled player-games | k/n (events) | CP 95% lower of rate | Point: settled × k/n | Lower: settled × CP lower | Margin at lower vs 300 | Decision |
|---|---|---|---|---|---|---|---|---|---|
| **Anytime TD** | Kalshi KXNFLANYTD | 2025-09-04 → 2026-02-08 | 5335 | 15/16 | 0.6977 | 5002 | 3722 | +3422 | **GO** |
| **Receiving yards** | Kalshi KXNFLRECYDS | 2025-10-06 → 2026-09-28 | 2573 | 16/16 | 0.7941 | 2573 | 2043 | +1743 | **GO** |
| **Rushing yards** | Kalshi KXNFLRSHYDS | 2025-10-06 → 2026-09-28 | 1168 | 16/16 | 0.7941 | 1168 | 928 | +628 | **GO** |
| **Passing yards** | Kalshi KXNFLPASSYDS | 2025-10-06 → 2026-09-28 | 491 | 16/16 | 0.7941 | 491 | 390 | **+90 (tightest)** | **GO** |
| Receptions | Kalshi KXNFLREC | 2025-10-27 → 2026-09-28 | 2140 | 14/15 | 0.6805 | 1997 | 1456 | +1156 | **GO** |
| 2+ TD | Kalshi KXNFL2TD | 2025-09-04 → 2026-02-08 | 2136 | 13/16 | 0.5435 | 1736 | 1161 | +861 | **GO** |
| First TD | Kalshi KXNFLFIRSTTD | 2025-09-04 → 2026-09-28 | 6512 | 16/19 | 0.6042 | 5484 | 3935 | +3635 | **GO** |
| Anytime TD, 2026 source alone | Kalshi KXNFLTD (1+/2+/3+ strikes) | 2026 wks 1–3 | 1090 | 1/3 | 0.0084 | 363 | 9 | −291 | **LOW CONFIDENCE (n=3).** Not used for the anytime-TD verdict; see below |
| Other ESPN-only props (rush+rec yards, longest reception/rush, carries, passing TDs/attempts/completions, 1st-half/1st-quarter, tackles, …) | none | – | – | – | – | – | – | – | **NOT MEASURED** (prospective-only until measured) |

ESPN BET, all four tested markets: not USABLE (LINE-MOVEMENT ONLY), so ESPN
contributes 0 to every count above. Even if ESPN anytime TD were usable, it
would fall below the rule: it has 7 + 258 = 265 open-priced settled
player-games (`espn_bet_market_season.csv`, 2024 + 2025). There are 7 + 294 =
301 open-priced player-games before requiring an outcome, but only 265 have a
weekly stat row.

Game-level markets (moneyline, spread, total) are not player-games, so the rule
does not apply to them. ESPN game odds give open and close from 2023, and
Kalshi GAME, SPREAD and TOTAL cover 2025 onward.

**Tightest margin (primary definition):** passing yards. 491 × 0.7941 = 390,
which is **90** above 300.
- If every pre-kickoff rate were as low as its Clopper–Pearson lower bound,
  **no GO verdict would flip**. The smallest lower-bound count among GO markets
  is 390.
- For passing yards to fall below 300, its rate would have to drop below
  300/491 = 0.611. The sample was 16/16.

**Under the primary definition, no measured market is NO-GO.**

### Stricter reading: a trade in the final pre-kickoff hour

Here "priced" requires `last_pre_trade_price` to be non-missing, meaning a trade
printed in the last hourly candle at or before kickoff. A two-sided quote alone
does not count. This is stricter than the rule's "a pre-kickoff price". The
columns come from `kalshi_candle_sample.csv`, random picks.

| Market | k/n traded | CP 95% lower | Point | Lower | Decision under this reading |
|---|---|---|---|---|---|
| Anytime TD (KXNFLANYTD) | 12/16 | 0.4762 | 4001 | 2541 | GO |
| Receiving yards | 11/16 | 0.4134 | 1769 | 1064 | GO |
| Rushing yards | 13/16 | 0.5435 | 949 | 635 | GO |
| **Passing yards** | **9/16** | 0.2988 | **276** | **147** | **NO-GO** (below 300 even at the point estimate: −24 at point, −153 at lower) |
| Receptions | 5/15 | 0.1182 | 713 | 253 | GO at point; **below 300 at the lower bound (−47)** |
| 2+ TD | 9/16 | 0.2988 | 1202 | 638 | GO |
| First TD | 14/19 | 0.4880 | 4798 | 3178 | GO |

**Spec rule outcome:**
- **MET under the primary definition** (trade or two-sided quote). Anytime TD
  and receiving, rushing and passing yards are GO, with lower-bound margins of
  +3422, +1743, +628 and +90.
- **NOT MET under the stricter trade-only reading.** Passing yards drops to
  NO-GO (276 / 147), which leaves only two yardage markets.

A two-sided quote is an executable price: one can buy at the ask. That is why it
is the primary definition. The median random-market spread was 0.03–0.06
(section 1). Phase 5 must fix the price definition, and the maximum acceptable
spread, before it relies on passing yards.

### KXNFLTD: low confidence, re-measure in Phase 2

KXNFLTD's rate rests on **n = 3 events** (1/3 priced), so it is low-confidence.
- The two unpriced random picks were a 2+ strike and a 3+ strike. They opened
  1.4 h and 1.0 h after kickoff, so they could not have had a pre-kickoff price.
- The 1+ strikes that were checked were all priced: 1 random pick and 3
  top-volume picks, the latter biased toward liquidity.
- The anytime-TD GO above rests on KXNFLANYTD (2025) alone. The 2026 KXNFLTD
  counts (1090 settled player-games) are **not** added to it.

Before the historical props backtest uses any 2026 anytime-TD prices, Phase 2
must re-measure:
1. **The pre-kickoff price rate at the market level for KXNFLTD 1+ strikes.**
   Use every 2026 regular-season event (48 events, 2280 markets in
   `kalshi_events.csv`), via the live `/series/KXNFLTD/markets/{T}/candlesticks`
   endpoint, since these are past the historical cutoff.
2. **`open_time` against kickoff for every strike,** to count the strikes
   created in-game.
3. **Market-level rates for the GO series,** replacing this event-level
   extrapolation. Check all markets of the sampled events, or a larger n. This
   applies above all to passing yards, whose margin is the thinnest (+90).

### Caveats that bind Phase 5

1. **The historical window is short.**
   - Anytime TD covers 2025 weeks 1–22 (2026 weeks 1–3 pending the KXNFLTD
     re-measure).
   - The yardage series start 2025-10-06, about 2025 week 5.
   - No 2024 prop prices are usable under the rule.
2. **Kalshi yardage and reception markets are threshold ladders** ("70+
   receiving yards"), not over/under main lines. The backtest must price
   P(stat ≥ k) per strike.
3. **The GO counts are extrapolations.** They rest on the event-level sample and
   the within-event equal-rate assumption stated above, not on a count of every
   market's candles.

## 5. Deviations and failures

Failed requests are 0 in every run: Kalshi 0/2373, ESPN BET 0/600 (plus 0/0 in
the cache re-analysis), ESPN game odds 0/40. The sample runs had 0 failures in
30 + 3 + 2 requests.

Places where a source behaved differently from its description, and choices
that differ from the brief:

1. **Kalshi historical cutoff.**
   - `GET /historical/cutoff` returns `market_settled_ts = 2026-07-31T00:00:00Z`.
   - Markets settled after it are **not** under `/historical/markets`. That
     covers every 2026 event, including all of KXNFLTD. They appear only under
     `/markets?event_ticker=`.
   - Their candles are only under `/series/{S}/markets/{T}/candlesticks`;
     `/historical/markets/{T}/candlesticks` returns HTTP 404 for them (seen in
     the probe).
   - The script reads the cutoff and tries the matching endpoint first, falling
     back to the other. Market-listing requests: 1663 historical, 341 live.
2. **Kalshi candle field names.** Historical candles carry `price.close`,
   `yes_bid.close`, `yes_ask.close` and `volume`, not `*_dollars` / `volume_fp`.
   The script accepts either.
3. **Kalshi coverage start.** Candles exist from each series' first events (2025
   week 1 for anytime TD), not "from about December 2025". The yardage series
   start 2025-10-06 and receptions 2025-10-27. KXNFL2TD has no 2026 events;
   2026 2+ TD markets live as strikes inside KXNFLTD.
4. **Kalshi team codes.** Jacksonville is `JAC`. The Rams are `LA` in 2025
   tickers and `LAR` in 2026 tickers. Both are accepted.
   - 272 events did not match the nflreadr 2024–2026 schedule, and all are
     preseason: 1 in 2025-07 (the Hall of Fame game), 80 in 2025-08 and 191 in
     2026-08.
   - They are excluded from the candle sample and from player-game counts.
5. **Scope choices in the Kalshi script.**
   - Candles were also checked on a seeded-random market, not only the
     top-volume one (brief). The top-volume market overstates availability:
     98.8% vs 93.1%.
   - Exact market listing was run for the 8 player series only. The 3
     game-level series are sample-based to keep runtime bounded, and the GO rule
     does not need them.
6. **Kalshi strikes created in-game.** In the KXNFLTD sample, 2 of 3 random
   markets (2+ and 3+ strikes) have `open_time` 1.0–1.4 h after kickoff. A 2+
   TD strike in KXNFL2TD opened 1.3 h before kickoff and had no candle.
7. **The ESPN bias test is confounded.** See section 2. The verdicts follow the
   rule exactly, but the rule cannot separate price-retention bias from where
   ladder rungs sit.
8. **ESPN anytime-TD outcome.**
   - The brief says "TD ≥ 1". Rows are ladders: 1/2/3 in 2024 and 0.5/1.5/2.5
     in 2025.
   - The 1+ rung (target 1 or 0.5) uses TD ≥ 1 exactly as specified. The 2+
     and 3+ rungs use TD ≥ 2 and TD ≥ 3; scoring them "TD ≥ 1" would be wrong.
   - TDs are rushing_tds + receiving_tds. Passing TDs are excluded; return TDs
     are not counted.
9. **ESPN over/under outcome** is `stat > open target`, as specified. For 2024
   whole-number ladder rungs (read as "X+"), a stat exactly equal to X counts
   as a miss. That slightly understates unpriced hit rates and does not affect
   priced main lines, which use half points.
10. **ESPN timing.** `lastUpdated` falls after kickoff for 92.7–99.2% of rows,
    which matches the probe. The `open` price has no timestamp.
11. **ESPN game odds provider switch.** ESPN BET (58) is replaced by DraftKings
    (100) from 2025 week 15 in the sample. The ESPN BET prop archive
    (`odds/58/propBets`) was scanned only through 2025 week 13, per the brief.
12. **Run history.**
    - The first full Kalshi run was stopped by me about 3 minutes in, to add
      the 2024 schedule for matching. By then it had finished stage 1 and about
      85 sampled events, roughly 250–300 requests. This is an estimate: its
      ledger was never written, and no errors appeared in its log. It was rerun
      from scratch; the reported run is the second one.
    - ESPN BET was fetched once over the network (600 requests), then
      re-analysed from its gitignored page cache to add
      `espn_bet_unpriced_structure.csv` and `espn_bet_priced_by_week.csv`.
      `espn_bet_bias.csv` was byte-identical between the two runs, and both
      runs are recorded in `espn_bet_run_meta.csv`.
    - The 3-game ESPN smoke test ran while the Kalshi full run was in progress.
      Those were different hosts, and each host's traffic stayed serial and
      throttled. All full runs were sequential.
