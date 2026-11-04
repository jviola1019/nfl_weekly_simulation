# The props module's base projections, point in time, 2026 weeks 3–8 (exploratory)

The owner asked for this on 2026-11-02, once 2025 could enter as history.

## Method (`props_walkforward.R`)

- **The projection:** each week w uses the module's own `load_player_projections(2026, w)`, with #230's week filter. That is every player's equal-weight mean over 2024, 2025 (history) and the 2026 games before week w.
- **Anytime touchdowns** are a Poisson on the scoring-TD rate.
- **Not applied:** the module's defense and game-context adjustments and its simulation.
- **Scoring:** every week goes through `props_frame.R`'s `module_props()`, the code of `nfl_props_v1`'s P5 and P6, against Kalshi's close.
- **Week 2 cannot be scored.** Before it each player has one 2026 game, and the dispersion fit needs a second.

| Pooled, weeks 3–8 (15,810 contracts, 88 games) | Coefficient (95% CI) | One-sided p | Brier: Kalshi vs forecast |
|---|---|---|---|
| Base projections, information beyond Kalshi's close | 0.106 (−0.028 to +0.239) | 0.059 | 0.142 vs 0.152 |
| Family G's projection, the same test | 0.062 (−0.097 to +0.222) | 0.22 | 0.142 vs 0.153 |
| Base projections predict the move from 24 h before kickoff to the close (14,620 contracts) | **0.027 (0.018 to 0.035)** | **6.5×10⁻⁹** | — |

**Week by week,** the information coefficient runs from −0.25 (week 5) to +0.32 (week 4). None is significant alone (`out/props_walkforward_weekly.csv`).

## What it shows

It shows what Family G and the module's week 7 showed (`reports/2026-10-29/hypotheses/HYPOTHESES.md` §13, §15):
- at most a weak signal against Kalshi's close, and the projections' Brier is worse than Kalshi's;
- a clear drift toward the projections in the last day, of about a quarter of a cent a contract, too small to pay Kalshi's fee.

## Why it is exploratory

- Kalshi's weeks 2–7 were used by Family G, and week 7 by Family M.
- The confirmatory test of the module is `nfl_props_v1`'s P5 and P6 on weeks 9–18, with the module frozen at `4c1c377`.
