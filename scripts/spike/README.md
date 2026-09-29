# scripts/spike: keyless data spike (measurement code, not production)

These scripts measure what the keyless odds sources actually provide. Their
output is `reports/<run-date>/DATA_SOURCES_SPIKE.md`, which decides which prop
markets get a historical backtest in Phase 5. They are throwaway measurement
code: Phase 2 provider code replaces them, and nothing in the pipeline sources
them.

All HTTP goes through `capture_http_get()` in `R/capture_raw.R`, using the
`CAPTURE_*` settings in `config.R`. That means a truthful user agent, a timeout,
bounded retry, and one request per `CAPTURE_MIN_INTERVAL_SEC` per host.
Requests run serially. Every failed request becomes a row in a `*_failures.csv`
file with its HTTP status, and none are dropped.

Run from the repo root. Each script takes `--sample` for a small smoke run and
`--out=DIR` to redirect the CSVs (the default is `reports/2026-09-29/spike`).

| Script | What it measures | Full-run cost |
|---|---|---|
| `kalshi_coverage.R` | Settled events per Kalshi NFL series, settled markets and player-games (every event for player series; a sample for game series), and pre-kickoff hourly candles for a per-month sample. | 2373 requests / 21 min on 2026-09-29. `--max-minutes` caps it (default 55); a capped run is marked PARTIAL. |
| `espn_bet_bias.R` | ESPN BET (`odds/58/propBets`) priced share per market and season for 2024 REG and 2025 weeks 1–13, the priced vs unpriced selection-bias test, and the ladder structure behind it. | 466 games, 600 pages / 6.4 min. Page bodies are cached (gitignored) under `data/raw_capture/spike_cache/`, so re-analysis makes no requests. |
| `espn_game_odds_coverage.R` | ESPN game odds: whether open, close, and moneyline exist, per provider, for 5 games per season from 2018 to 2025. | 40 requests. |

`spike_helpers.R` holds the three unit-tested helpers:
`kalshi_event_date()`, `espn_row_is_priced()` and `bias_test()`. Their tests are
in `tests/testthat/test-spike-helpers.R`.

`tests/testthat/fixtures/spike/kalshi_markets_settled.json` is a trimmed real
`/historical/markets` response, captured 2026-09-29, for Phase 2 parser tests.
