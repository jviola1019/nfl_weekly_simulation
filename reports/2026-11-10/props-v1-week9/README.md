# nfl_props_v1, week 9: the decision run's props are placeholders, so P5 and P6 have no contracts

**Status: a deviation, recorded for the final report.** Nothing is changed here: no registered file, no test, no week.

## What happened

1. **2026-11-03 18:00Z, the Tuesday run** (the frozen module at `4c1c377`). At its props stage every player-stats download came back empty. The run's log, for each game:

   ```
   Loading player stats for seasons: 2024, 2025, 2026
     nflreadr returned 0 rows
     No 2026 data available, using fallback projections...
   Loading player stats for seasons: 2023, 2024, 2025
     nflreadr returned 0 rows
   ...
     Loaded 14 players for ARI @ SEA (using fallback)
   ```

   The network failed around then: the same hour's snapshots and predictions failed on DNS errors (the store's `logs/dispatch.log`).
2. **The module substituted placeholder players** ("ARI QB1", "BAL RB2"). This is audit finding P6, known and open. The protocol tests the module as it was, so the fix is not part of the test.
3. **`run_week.R` exited 0,** so the run was saved as week 9's decision run and nothing retried it.
4. **2026-11-10 17:26Z, the weekly score:** `score_week.R` stopped in `module_props()` with "Argument mu must be a nonempty numeric vector": a regression on zero rows. `weekly_prospective.sh` returned 0 all the same, so the dispatcher marked the step done.

## The evidence (`out.txt`)

| | Count |
|---|---|
| Week 9 Kalshi contracts settled | 7,360 |
| Of those, yes or no, two-sided, within the 10¢ spread at the close | 6,715 |
| Prop contracts in the series P5 and P6 score | 5,610, for 328 players |
| Props in the decision run (`run_20261103T180007Z`) | 450 |
| Of those, placeholder players | 450 |
| Contracts matched to a module prop | **0** |

The run of Monday 2026-11-09 holds 612 props and no placeholder. It is the exploratory run, and it was made after 14 of the 15 games.

## What the protocol says

- "For P5 and P6 only the earliest run saved before the week's first kickoff counts."
- "A week without such a run is left out and never rebuilt."
- Deviations, among them "a missing run, fetch or week", are reported with the final result, and "none of them changes a test".

**So:**
- **Week 9 gives P5 and P6 nothing:** 15 of the 151 games. With 136 games left, their standard errors grow by about 5% (√(151/136)).
- **P1 to P4 are unaffected.** They use only Kalshi's settlements and prices, and week 9's are complete.

## Three places where a failure stayed silent

| Where | What it did |
|---|---|
| `nflreadr::load_player_stats()` | Returned 0 rows without an error |
| The props module, then `run_week.R` | Substituted placeholders and exited 0 |
| `weekly_prospective.sh` | Returns 0 whatever its steps return. The dispatcher's retries therefore never start for a failed run, snapshot, fetch or score |

The third matters beyond week 9. The protocol says a Tuesday run is "retried until the week's first kickoff", but a run that fails is marked done and is not retried.

## Proposal for the owner: a new protocol version, not done here

The protocol allows a defect in the registered code to be fixed "only in a new version of this protocol, never in place". A version 1.1 would change procedure only:

- **A decision run with placeholder players is not saved.** It counts as failed and is retried until the week's first kickoff.
- **`weekly_prospective.sh` returns its steps' failures,** so the dispatcher's retries work as the protocol describes.
- **`score_week.R` writes zero contracts** for a week without a match, and says so, where it now stops.

It changes no hypothesis, statistic, week or price. Week 9 stays lost. It has to be signed before the first Tuesday run it covers.

## Reproduce

```bash
# from the repository root; the store is private
Rscript reports/2026-11-10/props-v1-week9/diagnose_score_week.R <store>/w09 9
```
