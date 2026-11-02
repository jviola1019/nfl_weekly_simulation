# Venue survey: which odds venues can be read without a key (track K1)

2026-10-29. The owner asked to test every betting site and sportsbook for arbitrage and price disparities. This survey records which venues can be read under the owner's rules. `venue_snapshot.R` then compares every usable venue at the same moment (HYPOTHESES.md §12).

**The rules applied:**
- No keys, logins or cookies. A venue that needs any key, even one embedded in its own web page, is excluded.
- A 403, a captcha or a geo-fence drops the venue. It is never retried or evaded.
- At most one request a second, with a truthful user agent (`config.R`'s `CAPTURE_USER_AGENT`).
- Raw sportsbook responses and per-venue prices stay private. The repository is public, so only aggregates are committed.

Statuses are in `out/venues/probe_status.csv`, written by `venue_probe.R`. Refused venues were probed once, at 19:25Z, and carried over without a second request. The others were probed again at 21:12Z.

## Usable venues

| Venue | Endpoint | What it gives | Price used | Fee used |
|---|---|---|---|---|
| **Action Network** (DraftKings, FanDuel, BetMGM, Caesars, BetRivers, bet365; plus Consensus and Open) | `api.actionnetwork.com/web/v1/scoreboard/nfl?period=game&bookIds=15,30,68,69,71,75,79,123&date=YYYYMMDD` | The whole NFL week: moneyline, spread, total and team totals for each book | American odds at NJ prices. `inserted` is when the line last changed. | None (in the odds) |
| **Pinnacle** | `guest.api.arcadia.pinnacle.com/0.1/leagues/889/matchups` and `/markets/straight` | Moneyline, spreads and totals with every alternate line, and team totals. Each market carries its maximum risk stake. | American odds | None (in the odds) |
| **Bovada** | `www.bovada.lv/services/sports/event/coupon/events/A/description/football/nfl?marketFilterId=def&preMatchOnly=true&lang=en` | Moneyline, spread, total | American odds | None (in the odds) |
| **Polymarket** | `gamma-api.polymarket.com/sports` (NFL is series 12185), then `/events?series_id=12185&closed=false&limit=50` | About 300 markets a game: moneyline, about 34 spread lines, 21 totals, 22 team totals, halves and quarters | The first outcome's best bid and ask | Taker 0.05 × P × (1 − P), where `feesEnabled` ([docs](https://docs.polymarket.com/trading/fees)) |
| **Smarkets** | `api.smarkets.com/v3/events/?type=american_football_match&state=upcoming&start_datetime_min=…&start_datetime_max=…`, then `/v3/events/{ids}/markets/`, `/v3/markets/{ids}/contracts/` and `/quotes/` | Moneyline (draw no bet), about 21 handicap and 21 over/under lines a game, and player props (yards, receptions, touchdown scorers) | Best bid and offer, in basis points | 2% of net winnings, an assumption from third-party guides |
| **Kalshi** | `api.elections.kalshi.com/trade-api/v2/markets?series_ticker=KXNFLGAME` (and `KXNFLSPREAD`, `KXNFLTOTAL`, `KXNFLTEAMTOTAL`)`&status=open` | Moneyline, spread, total and team-total ladders, plus the player-prop series of the earlier reports | Yes bid and ask | Taker 0.07 × P × (1 − P) |

**Also readable, but not in the snapshot:**
- **Kambi**, BetRivers NJ's offering (`eu-offering-api.kambicdn.com/offering/v2018/rsiusnj/listView/american_football/nfl/all/all/matches.json?lang=en_US&market=US`). Its list view carries only the spread, and BetRivers already comes through Action Network.
- **ESPN**'s core odds API, which carries DraftKings' lines. It is already in the capture archive.
- **Kalshi's incentive programs** (`/incentive_programs?status=active&type=liquidity`), in HYPOTHESES.md §9.

## Excluded venues

| Venue | What was asked | Result |
|---|---|---|
| DraftKings | `sportsbook-nash.draftkings.com/api/sportscontent/dkusnj/v1/leagues/88808` | 403 |
| Caesars | `api.americanwagering.com/regions/us/locations/nj/brands/czr/sb/v3/…` | 403 |
| BetMGM | `sports.nj.betmgm.com/cds-api/bettingoffer/fixtures?…&sportIds=11` | 403 |
| Fanatics | `sportsbook.fanatics.com/` | 403 |
| PrizePicks | `api.prizepicks.com/projections?league_id=9` | 403 |
| FanDuel | `sbapi.nj.sportsbook.fanduel.com/api/content-managed-page?…` without its embedded key | 400; the request needs that key |
| Underdog | `api.underdogfantasy.com/beta/v5/over_under_lines` | 426 |
| BetOnline | Its offering API (`api-offering.betonline.ag/…/offering-by-league`, the POST its page makes) | 401. The page itself loads, but has no prices. |
| SX Bet | `api.sx.bet/markets/active?sportIds=8` lists NFL markets keylessly | Every price endpoint needs an `x-sx-api-key` header: best odds, public orders and the order-book snapshot ([docs](https://docs.sx.bet/api-reference/get-best-odds-v3.md)) |

DraftKings, FanDuel, BetMGM and Caesars stay in the snapshot through Action Network.

Not probed, because no keyless public read endpoint was found:
- **Exchanges:** ProphetX, Novig, Sporttrade, Betfair and Matchbook. Betfair and Matchbook need a login.
- **Books:** Circa, Hard Rock Bet and theScore Bet.

## Quirks that affect the numbers

- **Action Network's book list changes between requests.** An anonymous request returns at most the eight books above. The 20:48Z response had no Caesars or bet365, and the 21:07Z one had both (`snapshot_summary` `action_network_books`).
- **Action Network's quotes are its feed, not each book's.** `inserted` is when a line last changed. A line can sit unchanged for hours and still be live, so the age of a quote cannot tell a stale feed from a still market.
- **Ties.**
  - Books refund a two-way moneyline on a tie, and so does Smarkets' draw-no-bet market.
  - Kalshi settled 2026's one tie, NYG at WAS in week 5, at $0.50 for each team's contract (`reports/2026-10-28/feasibility/props/kalshi_settled_w1-5.csv.gz`).
  - So a moneyline pair across a book and Kalshi pays differently only if the game ties. That happened in 0.34% of 2015–2024 regular-season games (`snapshot_summary` `tie_rate_2015_2024`).
- **Polymarket and Kalshi ladders include wide quotes.** Their asks count for arbitrage, but quotes wider than 10¢ are kept out of the no-vig comparisons (`venue_snapshot.R`).

## Who can trade where

The survey reads prices. It does not establish that the owner can trade at a venue:
- Action Network's prices are the books' New Jersey prices; other states' can differ.
- Pinnacle and Smarkets do not take US customers, and Bovada is not licensed in any US state. Pinnacle is used here as the sharp benchmark.
- The gamma API prices Polymarket's international exchange, which does not serve US users. Polymarket US is a separate exchange, not surveyed.
- Kalshi is a CFTC-regulated exchange.

## Results, week 8 (2026-10-29)

Three snapshots were taken before Thursday night's kickoff. The repeat snapshots planned for later that evening were not taken: the loop was stopped to switch script versions and not restarted before the session ended.

| Snapshot | Venues | Quotes | Two-sided markets | Arbitrages | Cheapest two-sided pair | Middles with EV > 0 | Sides beating Pinnacle's no-vig price (> 2%) |
|---|---|---|---|---|---|---|---|
| Game lines, 20:48Z | 8 | 5,512 | 1,658 | 0 | $1.000 | 0 of 2,817 | 13 (2) |
| Game lines, 21:07Z | 11 | 6,948 | 1,839 | 0 | $1.000 | 0 of 6,318 | 20 (2) |
| Player props, 21:22Z | 3 | 11,300 | 3,959 | **5** (best +1.39¢ per $1) | $0.986 | 1 middle costs under $1 | – |

Files: `out/venues/snapshots.csv`, `snapshot_summary__*`, `out/props/props_summary__*`.

**Game lines: no arbitrage, and small price differences.** From the 21:07Z snapshot:
- **The venues agree closely.**
  - Each venue's no-vig probability sits a mean 0.2–0.75 points from the median venue at the same line.
  - The exceptions are Pinnacle's team totals, at 1.0 points, and Smarkets, at 0.8–1.4.
  - Across venues, the median range of no-vig prices is 2.3 points on the moneyline, 1.8 on spreads, 1.5 on totals and 2.0 on team totals.
- **Line shopping is worth about a cent per dollar.**
  - The best price beats the median venue's by a mean of 1.30¢ per $1 of payout on moneylines, 0.69¢ on spreads and totals, and 1.42¢ on team totals.
  - The 90th percentile is 1.4–2.5¢.
- **The best prices are mostly at Pinnacle and the exchanges.**
  - On spread and total lines quoted by three venues or more, Pinnacle has the best price 34% of the time, Kalshi 23–27% and Polymarket 22–29%.
  - Each US book has it 3% of the time or less. Many of those lines are alternates that only Pinnacle and the exchanges quote.
  - On moneylines, DraftKings has the best price on 21% of sides.
- **The books' main lines differ a little.** They differ in 11 of 14 games on the spread and 9 of 14 on the total, by a mean of half a point.
- **Few prices beat Pinnacle's.**
  - Of 2,172 sides quoted at the same line as Pinnacle, 20 beat its no-vig price under both the proportional and the power devig. Two do so by more than 2%.
  - Another 25 look positive only under the proportional devig, which overstates longshots.
  - Of the 13 positive sides at 20:48Z, 12 were still positive at 21:07Z. The other closed when its book moved (`out/venues/persistence.csv`).

**Player props: small arbitrages exist, all through Smarkets.**
- 677 player-stat props were quoted at two venues or more, and 267 at all three of Kalshi, Smarkets and Pinnacle.
- Five over/under pairs cost less than $1, the best by 1.39¢. Every one had Smarkets on one side, and three were worth under 0.2¢, inside the uncertainty of the commission assumption.
- The largest was a backup quarterback's passing touchdowns. When a player does not play, books void the bet and Kalshi settles at the pre-game fair price, so even an arbitrage can carry that risk.
- No-vig prices across venues have a median range of 0.5–2.2 points by stat, and a 90th percentile of up to 4.5 points (receiving yards).

**Smarkets rate-limited the props run.** It answered 429 on 4 of its quote chunks after the capture layer's back-off. Both scripts now request 100 markets at a time with a 2-second pause.

**What the snapshots can and cannot say.**
- They show prices at one moment, not whether a bet could be filled or for how much. Pinnacle's limits are in each response; book limits and exchange depth are not.
- One evening of one week is far too little to say whether the positive sides are real value or noise.
- A prospective series of snapshots over weeks 9–18, with closing-line value as the measure, is in HYPOTHESES.md §14.
- **Week 9's series is scheduled** (HYPOTHESES.md §15; `weekly_prospective.sh`):
  - snapshots at each decision point and an hour before each kickoff window;
  - scored by `score_week.R` after Monday night's game, on 2026-11-10.
  - Its raw responses stay in the session's private store.
