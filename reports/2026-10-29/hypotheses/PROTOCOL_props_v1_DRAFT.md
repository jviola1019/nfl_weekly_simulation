# nfl_props_v1: a pre-registered test of Kalshi prop mispricings (DRAFT, not registered)

**Status:** a draft for the owner, not yet signed. Registering it is an owner step:
- an entry in `backtest/eval_windows/` with this file's sha256;
- this file is then frozen, and any change needs a new version.

## What it confirms

Two significant mispricings from the exploration (`HYPOTHESES.md`, 2026 weeks 1–7), plus two leads that were not significant. Each is tested only on games played after registration.

| ID | Hypothesis (one-sided) | Statistic, clustered by game | Seen in weeks 1–7 | Power on weeks 8–18 |
|---|---|---|---|---|
| P1 | Protected contracts are underpriced against their unprotected twins | mean of (payout gap − price gap) > 0 | +0.97¢, p 9×10⁻⁸ | ≈1.00 |
| P2 | The binary ladder's mean predicts the stat beyond the scalar ladder's price | slope of (realized − scalar mean) on (ladder mean − scalar mean) > 0 | 0.81, p 1×10⁻⁴ | ≈1.00 |
| P3 | The interception ladder is compressed | calibration slope > 1 | 1.26 (1.07–1.46) | 0.95 |
| P4 | Position-group teammates of a player absent by snap counts are underpriced | calibration-in-the-large > 0 | +0.12, p 0.067 | 0.57 |
| P5 | The props module's projected means add information to Kalshi's close | coefficient of (logit model − logit close) with the close as offset > 0 (HYPOTHESES.md §13) | 0.26 (−0.09 to +0.61), p 0.066, week 7 only | ≈1.00 on weeks 9–18 |

- **Power** comes from `out/protocol_power.csv`, at the effect seen.
- **The seen effects are selected,** so their power is an upper bound. P3, P4 and P5 were found by looking.
- **P5 rests on one week.** At Family G's smaller coefficient of 0.09, a season gives roughly three chances in four (`P-G`).
- **P5 was added 2026-11-02,** after the owner asked whether our model beats any book.

**Secondary, reported but not confirmatory:**
- P1's pair trade as a maker at the mids, net of the 0.0175 maker fee (+0.50¢ per pair in weeks 1–7);
- P2's taker trade (+1.7% in weeks 1–7, CI −0.6 to +3.5).

**Deferred:** CLV of the props module's picks. The module prices no market yet (none of its props has a market line or odds), so it makes no picks. CLV is registered once it reads Kalshi's, Smarkets' and Pinnacle's prices.

## Data

- **Games:** every 2026 regular-season game kicking off after the registration commit, through week 18.
- **Outcomes:** Kalshi's own settlements (`reports/2026-10-28/feasibility/kalshi_settled.R`, with `--from` at the registration date).
- **Prices:** the close at kickoff (`kalshi_candles.R`), within the 10¢ spread limit.
- **No-snap settlements:** a contract settled at the pre-game fair price has no outcome, except in P1, where the payout gap uses every settlement.
- **Absences (P4):** nflverse snap counts and the final injury report.
- **Projections (P5):**
  - The module's `baseline_props.csv` from a `run_week.R` run made before each week's first kickoff, kept with that run's manifest.
  - A week without such a run is left out, never rebuilt. The module has no week filter (`sports/nfl/props/data_sources.R:62-158`), so a run made after the games would see them.
- **No 2025 data.** Every request is windowed to 2026 closes, and every script stops on a 2025 row.

## Tests and decisions

- **The code is fixed now:**
  - `kalshi_consistency.R` (A3 for P1, A5 for P2);
  - `props_close.R` (the series fits for P3);
  - `kalshi_behaviour.R` (B1s for P4);
  - for P5, `model_vs_books.R`'s props section, which today reads week 7 only. It must be generalised to every week with a saved run, and committed, before registration.
- **Each runs once,** after week 18, on the new games only.
- **Holm over P1–P5** at a one-sided 5%.
- **A hypothesis is confirmed** if its Holm-adjusted p < 0.05.
- **It is economically confirmed** only if its after-cost return's 95% interval (games resampled) lies above 0.
- **A confirmed P1 or P2 is a price relation,** not a betting edge, until a live test shows maker fills at the tested prices. That live test is the owner's decision.
- **No interim looks,** and no changes after registration.

## Owner decisions

1. Sign and register this protocol before week 9 kicks off, so that most of weeks 8–18 count.
2. Whether a live maker test of P1 (small size, protected YES bid against unprotected YES offer) is wanted. It is the only way to measure fills and adverse selection.
3. Kalshi's 2025 history stays sealed here. A separate protocol could use it as a tuning season.
4. Whether to include P5. It needs a `run_week.R` run before every week, which is manual until the weekly schedule (#215) is merged.
