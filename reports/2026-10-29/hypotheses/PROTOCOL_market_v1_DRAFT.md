# nfl_market_v1: game-line leads (DRAFT, not recommended for registration yet)

**Status:** a draft for the owner. **Recommendation: do not register it for 2026.**
- None of its leads passed BH in the exploration.
- Two of them cannot reach useful power in one season (`out/protocol_power.csv`).

| ID | Lead (one-sided) | Seen | Power on 2026 weeks 8–18 | Needed for 80% at the seen effect |
|---|---|---|---|---|
| M1 | The key-number shape on Kalshi's own median beats its spread ladder (exploratory) | +1.2% Brier skill, p 0.12 | 0.43 | about 438 games |
| M2 | Unders, outdoors, wind ≥ 15 mph (Borghesi 2008) | 54.5% over 2005–2024, q 0.27 | 0.09 | about 790 bets, decades of windy games |
| M3 | Cold home team against a warm visitor (Borghesi 2007) | 61.9% on 63 bets, q 0.27 | 0.10 | about 105 bets, roughly 28 seasons |

## If the owner wants it anyway

- **M1** could run as a 2026–2027 protocol: about two seasons of Kalshi spread ladders, with `key_numbers.R`'s shape-only model fixed as it is.
- **M2 and M3** are already tested on 20 and 17 post-study seasons. Fresh data adds about 17 and 4 games a season, so they are better treated as answered (not supported after BH) than as open.

**Why not 2026:** a protocol that cannot reach power spends the owner's confirmation budget without a decision at the end.
