# The simulator's published number against the raw simulation and the market (week 9, 2026)

**Status: exploratory, one week.** It measures findings F1 and F2 of `reports/2026-11-05/verification/VERIFICATION.md`. Nothing is changed here.

## The question

The public pages describe the gold "Simulator" value as "the simulation's win probability after the production pipeline's 70% weight on the no-vig market". Is that what the number is?

## The answer: no

- **What the pipeline publishes** is `0.3 × blend + 0.7 × market` (`R/sim_bundle.R`, `shrink_probability_toward_market()`). The blend comes from the engine's ridge blend, its isotonic map and the margin alignment, and it is already close to the market.
- **A plain 30/70 mix** of the raw simulation and the market, which is what the wording describes, would sit two to three times further from the market.

| Bundle (15 games each) | Code | Published outside the raw-to-market range | Mean gap to market: raw | a 30/70 mix | published |
|---|---|---|---|---|---|
| `2026-w09-sim-20261103T184056Z` | `4c1c377` | 6 of 15 | 0.091 | 0.027 | 0.012 |
| `2026-w09-sim-20261103T205214Z` | `63807cb` | 6 of 15 | 0.093 | 0.028 | 0.013 |
| `2026-w09-sim-20261105T205729Z` | `85fd35a` | 5 of 15 | 0.078 | 0.023 | 0.008 |

**Two games from the last bundle:**

| Game | Raw simulation | Market | Published | A 30/70 mix | Implied blend |
|---|---|---|---|---|---|
| NYJ at KC | 0.579 | 0.817 | 0.814 | 0.746 | 0.806 |
| LV at SF | 0.728 | 0.804 | 0.822 | 0.781 | 0.863 |

## What it does and does not show

- **It shows** that the wording is wrong, and why a game page's margin chart (the raw simulation) disagrees with the "Simulator" probability beside it.
- **It does not show** whether the blend is better or worse than the raw simulation or the market. These are three runs of the same 15 games, and no outcome is scored here.

## What follows

- **The wording** on the public pages is the owner's decision. The proposal:
  - say what the number is: the pipeline's blend of the simulation and the market, after the 70% weight;
  - show the raw simulation's win probability beside it.
- **Whether the blend earns its place** belongs to the term-admission work (G2, audit M8).

## Reproduce

```bash
Rscript reports/2026-11-10/published-vs-raw/published_vs_raw.R \
  reports/2026-11-10/published-vs-raw/inputs/2026-w09-sim-20261103T184056Z \
  reports/2026-11-10/published-vs-raw/inputs/2026-w09-sim-20261103T205214Z \
  reports/2026-11-10/published-vs-raw/inputs/2026-w09-sim-20261105T205729Z
```

`out.txt` holds the output. `inputs/` holds each bundle's `manifest.json` and `game_predictions.json`: the first is the dispatcher's Tuesday run, and the other two are local runs of `run_week.R` for week 9.
