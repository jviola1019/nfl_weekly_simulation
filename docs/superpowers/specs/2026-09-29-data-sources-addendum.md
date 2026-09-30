# Data sources and data quality (spec addendum, 2026-09-29)

The owner asked (2026-09-29) for data that is "cleaned, accurate and logistically sound, professional, statistically significant", using APIs and sources that close the known gaps. Every source listed here was **probed live on 2026-09-29** and needs **no API key or free trial** (see the memory note "keyless-only"). This addendum governs the M20/M21 fixes (`reports/2026-09-29/AUDIT-ADDENDUM.md`), Phase 1b, Phase 2 (providers) and future shootout versions.

## 1. Verified keyless sources

| Need | Source | Coverage (verified) | Point-in-time? | Notes |
|---|---|---|---|---|
| Schedules, results, closing spread/total/moneyline | nflverse `load_schedules()` | 1999–2025, 7,276 games; 100% moneyline coverage 2018–2025 | Close only, no timestamp | Also `stadium_id` (39 distinct 2018–2025), `roof`, `surface`, gamebook `temp`/`wind`, rest days, starting-QB ids, referee. `spread_line` > 0 means home favored (nflverse docs). |
| Play-by-play with EPA/WP | nflverse `load_pbp()` | 1999→ (2024: 49,492 plays, 372 cols) | Yes (plays have dates) | Main feature source for the EPA model (C2) |
| Player stats, snap counts, depth charts, weekly rosters | nflverse `load_player_stats`, `load_snap_counts`, `load_depth_charts`, `load_rosters_weekly` | 2024 verified (18,983 / 26,615 / 37,312 / 46,579 rows) | Yes, by week | Props projections and injury impact |
| Injuries | nflverse `load_injuries()` | 2024: 6,215 rows | Yes (report week) | **The Sleeper fallback must be current-season only** (M20; still open on `main`) |
| Charting / tracking-derived | nflverse `load_ftn_charting` (2022→), `load_nextgen_stats`, `load_pfr_advstats`, `load_espn_qbr` | 2024 verified | By week/game | Optional C2 features; each must pass the leak canary |
| Officials | nflverse `load_officials()` | 2024 verified | Pre-game assignment | Candidate feature (referee tendencies); unvalidated |
| Player id crosswalk | nflverse `load_ff_playerids()` | 12,508 players | – | gsis ↔ espn ↔ others; used for joins, never fuzzy names |
| Game odds open/close by book | ESPN core API `…/competitions/{id}/odds` | **2023–2025** (ESPN BET open+close; 477 games 2024–2025 measured) | Open = decision-time proxy | Pre-2023 has no open/close. **This bounds CLV evaluation to 2023+.** |
| Game and prop prices with history | Kalshi public market data | ~Dec 2025→ (TD markets), 2026 live | Hourly candles | Exchange (bid/ask/fee), stored as its own venue |
| Prop openers (partial) | ESPN core `…/odds/58/propBets` | 2024 → ~wk13 2025 | Open only | Line movement only (spike: bias test confounded) |
| Weather (backtest, point-in-time) | Open-Meteo **historical-forecast** API | 2021→ (probe ok for 2021-06) | **Yes**: archived forecasts | CLE 2024-12-15 13:00: 38.1°F / 13.6 mph vs gamebook 40°F / 18 mph |
| Weather (older seasons) | Open-Meteo **archive (ERA5)** | Decades | No (observed) | Label as "observed proxy" in any pre-2021 backtest |
| Weather (live) | Open-Meteo forecast API | Now → +16 days | Yes | – |
| Stadium coordinates | OSM Nominatim (≤1 req/s, truthful UA) → committed `data/reference/stadiums.csv` | All `stadium_id`s | – | Built once with provenance; manual overrides for international venues |

## 2. Probed and rejected

| Source | Why rejected |
|---|---|
| AusSportsBetting historical xlsx (openers 2006→) | HTTP 403 to automated requests. **Blocks are never evaded.** |
| TheFootballLines downloads (openers 2007→) | HTTP 403 |
| Kaggle datasets | Require an account/login (key-like), which the keyless rule excludes |
| The Odds API historical, OddsPapi, SportsDataIO, BigDataBall | Paid, or key/trial required |
| Sportsbook sites (DK/FD/ScoresAndOdds private endpoints) | Terms-of-service risk; retired in Phase 2 |

## 3. What this means for "more accurate than the market"

**Result so far (backtest v1, #195; Confirm 2023–24, 570 games):** no candidate beats the no-vig close.
- The best, B1[E1] market-anchored stack, has skill +0.02% [−0.38%, +0.45%].
- C1 Elo, C2 EPA GLM and E1 are 4–6% worse than the close.
- CLV at the ESPN BET opener is descriptive only: C2 +93 bps [+40, +149] on 214 picks, below the 400-pick gate.

The data below is what a *next* version (v2, with C3 and richer features) can draw on.

The question has two parts, and the data supports them differently.

1. **Probability accuracy vs the no-vig close (Brier / log-loss).** The data is sufficient.
   - Closing lines plus features are available for 2018–2025: 2,219 non-tie games (market Brier 0.2108).
   - Paired per-game Brier differences are tight enough that a pre-registered test can detect improvements of about 0.002, the typical size of a real edge. The exact figure depends on the observed SD of the paired differences.
2. **Decision value (CLV).** Only **2023 onward** supports it keylessly (ESPN openers, then Kalshi, then forward capture). Measured per-bet CLV noise is σ = 514 bps. The pre-registered gate needs **400 picks** (A2): 83% power for a true +100 bps edge with 8 candidates. That is reachable from 2023–2025 openers only if the model recommends bets on about half of the games or more. Otherwise forward capture completes it.

No source closes the pre-2023 opener gap keylessly. The plan does not pretend otherwise: CLV claims rest on 2023+ only.

## 4. Cleaning and quality rules (apply to every loader)

1. **Joins by stable ids only:**
   - games: `game_id`
   - teams: nflverse abbreviations, with an alias table for LA/LAR, JAC/JAX, WAS/WSH, OAK/LV, SD/LAC, STL/LA
   - stadiums: `stadium_id`
   - players: `gsis_id` via `load_ff_playerids`

   Names are display text only. An unmatched key goes to an unmatched-entity report and is never fuzzy-joined.
2. **Point-in-time.** Every feature row carries its source timestamp. The backtest asserts `source_max_ts < kickoff` for every row (leak canary).
3. **No silent fallbacks.** Every fallback updates `data_validation.R` quality and emits a warning that names the games. The golden master should refuse to record unless injury data is "full". Once M11 is fixed, market must be "full" too, and weather once M21 is fixed. `main`'s golden master records no input statuses yet (M20 evidence).
4. **Reproducibility.**
   - Every run records nflreadr version, source statuses and counts in its manifest.
   - Phase 2 adds dated snapshots of nflverse releases (sha256), so a backtest can be re-run on byte-identical inputs.
5. **Accuracy checks against a second source, recorded as evidence:**
   - weather: Open-Meteo vs gamebook temp/wind MAE (part of the M21 fix)
   - moneylines: nflverse close vs ESPN close on overlapping 2023–2025 games (Phase 2)
   - injuries: nflverse vs ESPN injuries API for the current week (Phase 2, live only)
