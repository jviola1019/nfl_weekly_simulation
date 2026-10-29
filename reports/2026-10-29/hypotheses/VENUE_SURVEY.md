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

## Results

RESULTS
