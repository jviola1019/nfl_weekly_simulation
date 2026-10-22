# Venue survey: keyless NFL odds sources (Track K1, draft)

**Owner's rule (2026-10-20).** "Add any sportsbooks with usable JSONs, clean and non-disruptive … Disregard terms of conditions."

**Guardrails kept:**
- no keys we register for, and no logins or session cookies;
- a 403, captcha or geo-fence drops the venue and is never evaded;
- at most 1 request per second, the capture's user agent (`nfl-weekly-simulation/2.9 (research; …)`), and a 20 s timeout;
- raw sportsbook payloads are never published.

**Method.** One request per endpoint, starting 2026-10-21T17:08Z. The bodies were kept in the session scratchpad and not committed.

| Venue | Endpoint (pattern) | Needs | Result | NFL content | History | Verdict |
|---|---|---|---|---|---|---|
| ESPN core odds | `sports.core.api.espn.com/v2/…/events/{id}/competitions/{id}/odds` | nothing | 200 for all 15 games inside 216 h (the 05:09Z live capture) | moneyline, spread and total, with open, close and current; **provider DraftKings (id 100) only** in 2026 | open and close from 2023 | **in use.** DraftKings prices arrive through ESPN. |
| Kalshi | `api.elections.kalshi.com/trade-api/v2/markets` | nothing | in use: 191 market pages in the Tuesday capture | game winner, touchdown props (`KXNFLTD`) | hourly candles under `/historical` | **in use** |
| Kambi (BetRivers NJ, `rsiusnj`) | `eu-offering-api.kambicdn.com/offering/v2018/rsiusnj/listView/american_football/nfl.json?lang=en_US&market=US` | nothing | 200, 4.8 KB, 28 events (weeks 7–8) | the list view has the main offer (point spread, American prices); the per-event view `…/betoffer/event/{id}.json` should list the rest (not yet probed) | none (live only) | **candidate provider** |
| Polymarket | `gamma-api.polymarket.com/sports` gives NFL series `12185`; then `/events?series_id=12185&closed=false` | nothing | 200, 4.7 MB, 73 open events | every week-7 game (for example Patriots vs. Bears 0.395 / 0.605, with about 306 markets per game: props, first touchdown scorer, quarters) plus futures | price history through the CLOB (`prices-history`, not yet probed) | **candidate provider.** Volume on upcoming games is thin: about $12k for NE–CHI and $3k for PIT–NO at 17:08Z. |
| Bovada | `www.bovada.lv/services/sports/event/coupon/events/A/description/football/nfl?...` | nothing | 200 with an empty array `[]` | none as probed | – | not usable as probed (a geo restriction or a moved path; not investigated further) |
| DraftKings (direct) | `sportsbook-nash.draftkings.com/api/sportscontent/dkusoh/v1/leagues/88808` | – | **403** (HTML, bot protection) | – | – | **dropped** (never evaded). DraftKings prices come through ESPN. |
| Caesars | `api.americanwagering.com/regions/us/locations/nj/brands/czr/sb/v3/...` | – | **403** (HTML) | – | – | **dropped** |
| FanDuel | `sbapi.<state>.sportsbook.fanduel.com/api/...` | an app key (`_ak`) embedded in FanDuel's web app | not probed | – | – | **owner decision**: a public embedded key is still a key |
| BetMGM | `sports.<state>.betmgm.com/cds-api/...` | an access id embedded in the web app | not probed | – | – | **owner decision** (same reason) |
| Pinnacle | `guest.api.arcadia.pinnacle.com/0.1/...` | an `X-API-Key` header embedded in the web app | not probed | – | – | **owner decision.** It is the sharpest market maker and the most useful benchmark for M4 (sharp-weighted consensus, lead–lag). |
| Circa, BetOnline, ProphetX, Novig | – | no public JSON found, or a login or bot protection | not probed | – | – | out of scope for now |

## What this means for Track M

- **Live venues today.** ESPN (DraftKings), Kalshi, Kambi (BetRivers) and Polymarket.
  - Two are sportsbooks with hold (DraftKings through ESPN, and BetRivers).
  - Two are exchanges or prediction markets (Kalshi and Polymarket).
  - That is enough to start M3 (the best devig, scored against outcomes), M4 (consensus against the best single venue), and M5 (best-of-N price and stale lines). All are prospective from 2026 week 7.
- **History is thin.**
  - ESPN keeps DraftKings open and close from 2023.
  - Kalshi keeps candles (2025 is sealed).
  - Polymarket keeps price history (not yet probed). If it reaches back through 2026 weeks 1–6, it gives earlier mid-week prices for those weeks.
  - Kambi has none.
- **The sharp benchmark is missing.** Pinnacle needs the owner's decision on embedded public keys.

## Next (K2)

- One provider each for Kambi and Polymarket, on D1's provider interface. Each has fixture tests from saved payloads and a schema-drift test.
- Kambi's per-event offers: one request per event, about 28 per run at 1 request per second.
- Polymarket CLOB `prices-history`, probed for coverage of 2026 only (never 2025).
