# Keyless odds sources

The odds layer (`R/odds/`) reads three public sources. None needs an API key or a trial. This file lists what each one serves, how fast we may call it, what it covers and what we have and have not verified about its terms. Every number below comes from a script run on the date shown, or from `reports/2026-09-29/DATA_SOURCES_SPIKE.md`, and is marked so.

## Rules every request follows (`R/odds/http.R`)

- A truthful user agent (`CAPTURE_USER_AGENT`: names this project and its repository).
- A 20 second timeout (`CAPTURE_TIMEOUT_SEC`).
- At most **1 request per second per registrable domain** (`espn.com`, `kalshi.com`). This is a floor in code (`ODDS_MIN_INTERVAL_SEC`): `CAPTURE_MIN_INTERVAL_SEC` is 1 in `config.R`, and a smaller value is raised to 1.
- Backoff on HTTP 429/5xx and on network errors: up to `CAPTURE_MAX_TRIES` attempts (3), waiting 2 and then 4 seconds, or the server's `Retry-After` when it sends one, capped at 60 s.
- A 401/403, a 429 that survives the retries, or an HTML page where JSON was expected (a challenge or login page, declared by the provider or the capture through `odds_declare_blocked`) is **never worked around**. The domain is marked blocked for the rest of the process and no further request is sent to it. An empty body or JSON `null` is not a page: it is counted as a failed response, and the run goes on.
- The sha256 of every **successful** raw response is returned, written to the capture manifest (`data/raw_capture/manifest.ndjson`) or the archive fetch log, and recorded in `backtest/data/odds_archive/SOURCES.json`. Error responses are recorded by status and error text.

## Sources, endpoints and coverage

| Source | Endpoint (no key) | Gives | Coverage |
|---|---|---|---|
| **nflverse** (`nflreadr::load_schedules`) | GitHub release `nflverse-data/schedules` | Consensus closing moneyline, spread and total per game. No open, no timestamp. | Closing moneylines for 100% of games 2018–2025 (`HANDOFF.md`, confirmed facts). |
| **ESPN core** game odds | `https://sports.core.api.espn.com/v2/sports/football/leagues/nfl/events/{id}/competitions/{id}/odds` | Per provider: moneyline, spread and total with an `open` block and a `close` block. The blocks have **no timestamp**. | See the measured table below. ESPN BET (provider 58) is the book through 2025 week 11 at least; DraftKings (100) in weeks 15, 17 and 18 of 2025 and in 2026 (spike, section 3). 2022 has a close only; 2018–2021 have neither. |
| **ESPN core** prop lines | `.../odds/100/propBets` (DraftKings), `.../odds/58/propBets` (ESPN BET archive) | Prop **lines**, not prices. DraftKings propBets are live only (404 after the game). | ESPN BET archive: 2024 through about 2025 week 13; only a subset of rows keeps prices and `lastUpdated` is after kickoff for 93–99% of rows, so it is line movement only (spike, section 2). |
| **Kalshi** public market data | `https://api.elections.kalshi.com/trade-api/v2`: `/historical/cutoff`, `/markets?event_ticker=`, `/historical/markets?event_ticker=`, `/series/{S}/markets/{T}/candlesticks`, `/historical/markets/{T}/candlesticks` (`period_interval=60`) | Hourly yes bid/ask/last/volume candles for game (`KXNFLGAME`) and player contracts. | Anytime TD from 2025-09-04 (`KXNFLANYTD`; 2026 uses `KXNFLTD` strikes), receiving, rushing and passing yards from 2025-10-06, receptions from 2025-10-27, game series from 2025-07-31 (spike, section 1). 93.1% of a random sample of markets had a pre-kickoff price. The 2025 props are for P3 under its signed protocol; D1 uses 2026 markets only. |

Quirks the code handles: the Kalshi historical cutoff moves (2026-07-31 on 2026-09-29, 2026-08-14 on 2026-10-13), so it is read at run time and each event tries the cutoff side first and falls back on a 404; the two candle forms name fields differently (`price.close` and `price.close_dollars`); Jacksonville is `JAC` and the Rams `LA` or `LAR` in Kalshi tickers; some strikes open after kickoff and have no pre-kickoff candle (the receiving-yards fixture is such a market); `KXNFLTD` holds 1+/2+/3+/4+ strikes as separate markets and only 1+ and 2+ are mapped.

### ESPN game odds archive 2023–2024 (built 2026-10-27)

Built by `Rscript backtest/build_odds_archive.R <raw_dir>` on 2026-10-27 (UTC): 570 requests to `sports.core.api.espn.com`, 1 per second, 9.5 minutes, all 570 answered HTTP 200 on the first try, 16.4 MB of raw JSON as received (1.35 MB gzipped; not committed; the sha256 of each response is in `backtest/data/odds_archive/SOURCES.json`). The dry run of 2026-10-13 gave the same coverage. `--from-raw` rebuilds the three CSVs byte for byte from the stored responses and makes no request. Source of the table: `backtest/data/odds_archive/COVERAGE.csv`. "With both" counts games where both sides of the line exist in both the opener and the closer.

| Season | Market | Games | With opener | With closer | With both | Both |
|---|---|---|---|---|---|---|
| 2023 | moneyline | 285 | 207 | 282 | 205 | 71.9% |
| 2023 | spread | 285 | 192 | 281 | 192 | 67.4% |
| 2023 | total | 285 | 192 | 285 | 192 | 67.4% |
| 2024 | moneyline | 285 | 284 | 284 | 284 | 99.6% |
| 2024 | spread | 285 | 284 | 284 | 284 | 99.6% |
| 2024 | total | 285 | 284 | 284 | 284 | 99.6% |

Only ESPN BET (provider 58) appears in the archive. The provider reads ESPN BET and DraftKings (provider 100) and no other book; no 2023–2024 response carried a usable DraftKings line. In 2023, 80 regular-season games have no complete moneyline pair: 78 have no opener (16 in each of weeks 1 to 4 and 14 in week 5) and 2 more, in weeks 6 and 8, have no complete closer. All 13 playoff games are complete. In 2024 the single game without a pair is `2024_02_PIT_DEN`, which has no ESPN BET or DraftKings line at all. Each season has 285 games (272 regular season plus 13 playoff games). **2025 rows are not in the archive and the builder refuses them** (the Holdout is sealed; the G3 Holdout build appends them after the freeze).

The build reports its source status as `stale`, not `ok`, because it counts what ESPN never served (`source_detail` in `SOURCES.json`): the 2024 game above, 5 games of 2023 missing a moneyline, spread or total, 37 market blocks dropped for a missing side, line or readable price, and 14 spread or total lines kept with no price. Every game was fetched and stored. The build exits 1 when any game's response could not be stored: a failed request, a body that is not usable JSON, or a game never requested because a block stopped the run. Each is listed in `fetch_failures` with its reason.

The ESPN opener and closer have no timestamp, so their snapshots carry no `captured_at` (the archive CSV has no time column) and are labelled by `snapshot_kind` `open` or `close`. The closing rule (`R/odds/closing.R`) uses such a labelled close only when no timed snapshot exists for it; it has no gap, so it is never stale, and its timing is reported as `labelled`. Timestamped sources (Kalshi candles, forward capture) follow the full rule: the last snapshot at or before kickoff at the same line, stale when it is more than 60 minutes before kickoff. A close block in a response fetched before kickoff is not a close: the provider keeps it as an observed snapshot at the fetch time, and the rule judges it by its gap. For Kalshi the rule returns the closing candle's bid, ask and last; the consumer takes the mid with `kalshi_mid()`.

### Forward capture

`odds-capture.yml` runs `scripts/capture_odds_raw.R` in 8 cron windows per week. A live run of this code on 2026-10-27 at 04:30 UTC, after Monday Night Football, found the 14 games of the coming week within its 216 hour game horizon and none within its 36 hour prop horizon. It made 208 requests in 3 minutes 27 seconds, all HTTP 200 on the first try: 2 ESPN scoreboards, 14 ESPN game odds, the Kalshi series list and the markets of 191 per-game Kalshi NFL series. It wrote 20.1 MB of raw responses and a manifest line per request with its sha256.

## Terms-of-service matrix (spec Phase 2, audit S4 / A4)

"Verified" means checked by a run or a page read on the date shown. **The terms texts of ESPN, Kalshi and nflverse have not been reviewed by the owner; production use of the archive and the capture waits for the owner's sign-off.**

| Source | Access verified | Documented rate limit | Our rate | Block behaviour | Terms text | Owner sign-off |
|---|---|---|---|---|---|---|
| nflverse | Downloads via `nflreadr` (GitHub release assets), no key | GitHub's release download limits apply; none documented by nflverse | one download per run | n/a | License not read by the agent: **to review** | pending |
| ESPN core API | HTTP 200 without credentials: 2,400+ requests in the 2026-09-29 spike, 192 capture and 570 archive requests in the 2026-10-13 dry run, 570 archive and 16 capture requests on 2026-10-27; no 401/403/429 | None published (the endpoints are undocumented) | 1 request/second | stop on 401/403/429 or a challenge page | ESPN/Disney terms of use: **to review**; the endpoints are not an offered public API | pending |
| Kalshi public market data | HTTP 200 without credentials on the market, event, candle and cutoff endpoints (2026-10-13); 192 series and market requests on 2026-10-27 | Token buckets per tier, read bucket 200 tokens/second at the Basic tier, 429 on excess, exponential backoff recommended (`docs.kalshi.com/getting_started/rate_limits`, read 2026-10-13; the page describes authenticated requests and does not say whether public endpoints are metered) | 1 request/second | stop on 401/403/429 or a challenge page | Kalshi developer terms: **to review** | pending |

Retired and excluded (audit S1, owner rule keyless-only): the ScoresAndOdds private endpoint, OddsTrader, Covers, The Odds API (historical data needs a paid plan) and OddsPapi (needs a signup key).

## Live checks

`Rscript scripts/odds_live_smoke.R` (or the manual "Odds live smoke" workflow) makes a handful of requests at 1 per second and compares the live ESPN response for `2024_01_ARI_BUF` and the Kalshi cutoff and `KXNFLGAME-26OCT12BUFLAR` listing with the recorded fixtures. It is never part of `scripts/run_tests.R`. It exits 1 when a test fails and also when one is skipped, because a test skipped for an unreachable host checked nothing. On 2026-10-27 both tests passed with no skip.
