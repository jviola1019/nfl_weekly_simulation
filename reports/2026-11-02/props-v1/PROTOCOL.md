# nfl_props_v1: a pre-registered test of Kalshi prop pricing and of our props model, 2026 weeks 9–18

**Signed 2026-11-02, before week 9's first kickoff (2026-11-06 01:15 UTC).** The owner's instruction of 2026-11-02 approved signing (the draft's owner decisions 1 and 4). This file is frozen. Its sha256, the weeks and the scoring code's hashes are in `backtest/eval_windows/nfl_props_v1.json`, and any change needs a new version. The draft it replaces is `reports/2026-10-29/hypotheses/PROTOCOL_props_v1_DRAFT.md`.

## What it confirms

Six one-sided hypotheses, found or sharpened in the exploration of 2026 weeks 1–7 (`reports/2026-10-29/hypotheses/HYPOTHESES.md`). Each is tested only on weeks 9–18.

| ID | Hypothesis (one-sided) | Statistic, clustered by game | Seen (weeks 1–7) |
|---|---|---|---|
| P1 | Protected contracts are underpriced against their unprotected twins | mean of (payout gap − price gap) > 0 | +0.97¢, 12,205 pairs, 43 games |
| P2 | The binary ladder's mean predicts the stat beyond the scalar ladder's price | slope of (realized − scalar mean) on (ladder mean − scalar mean) > 0 | 0.81, 842 pairs, 75 games |
| P3 | The interception ladder is compressed | calibration slope of KXNFLPASSINT > 1 | 1.26 (1.07–1.46), 616 contracts |
| P4 | Position-group teammates of a player absent by snap counts are underpriced | calibration-in-the-large coefficient > 0 | +0.12 (−0.04 to +0.28) |
| P5 | Our props model's projected means add information to Kalshi's close | coefficient of (logit model − logit close), close as offset, > 0 | 0.26 (−0.09 to +0.61), week 7 only |
| P6 | Our props model's projection predicts Kalshi's move from 24 hours before kickoff to the close | slope of (logit close − logit 24 h) on (logit model − logit 24 h) > 0 | 0.043 (0.022–0.064), week 7 only |

- **The seen effects are selected.** P3, P4 and P5 were found by looking, so their power at the seen effect (`reports/2026-10-29/hypotheses/out/protocol_power.csv`, computed for weeks 8–18) is an upper bound. With weeks 9–18 the standard errors are about 5% larger.
- **P5 and P6 rest on one week** (week 7, 14 games). Family G's projection, a different model, gave 0.032 on P6's statistic over weeks 2–7 (p 2×10⁻¹⁴).
- **Price relations:** P1, P2 and P6 are price relations. Week 7's P6 drift is about a quarter of a cent a contract, below Kalshi's fees, so confirming P6 alone is not a betting edge.
- **Known answer:** `props_v1_score.R --known-answer` on weeks 1–7 reproduces every seen effect above to four significant figures (`known_answer/props_v1_results.csv`; checked by `tests/testthat/test-props-v1-protocol.R`).

## The props model under test

- **Code:** the props module at commit `4c1c377`, the code whose week-7 run produced the evidence for P5 and P6.
  - **Checkout:** a dedicated checkout of that commit, which later changes to main do not touch.
  - **Packages:** a frozen package set, the week-7 run's own (`module_packages.csv`, 219 packages, R 4.5.1).
  - **Not included:** the later fixes to the module (#216, #220 and #230) are not part of this test. A fixed module needs its own protocol.
- **Runs:** `run_week.R <week> 2026`, started by `prospective_dispatch.R` at Tuesday 18:00 UTC before each week, retried until the week's first kickoff.
  - Each run's outputs are saved by `weekly_prospective.sh`.
  - **For P5 and P6 only the earliest run saved before the week's first kickoff counts.**
  - A week without such a run is left out and never rebuilt.
  - A Friday 21:00 UTC run is also made; it is exploratory.

## Data

- **Games:** the 2026 regular season, weeks 9–18 (151 games on the schedule of 2026-11-02).
- **Outcomes:** Kalshi's own settlements (`reports/2026-10-28/feasibility/kalshi_settled.R`).
- **Prices:** the close at kickoff, the last hourly candle ending at or before the scheduled kickoff (`kalshi_candles.R`), within the 10¢ spread limit.
- **No-snap settlements:** a contract settled at the pre-game fair price has no outcome and is left out. The exception is P1, whose payout gap uses every settlement.
- **P1–P4's fetch:**
  - **When and what:** one fetch after week 18 covers every market closing between the day before week 8's first kickoff and three days after week 18's last.
  - **Week 8** only gives P4 each player's previous game. It is never scored.
  - **If that fetch fails,** the union of the weekly fetches is used instead.
- **P5 and P6:** the weekly matched contracts. `score_week.R` writes them for each week after its games, from the saved run, and from Kalshi's settlements and candles. Each week's contracts may be rebuilt with the registered `score_week.R` from the saved run and Kalshi's data.
- **P4's absences:** nflverse snap counts.
- **No 2025 data.** Every request is windowed to 2026, and every script stops on a 2025 row. Kalshi's 2025 history stays sealed (the draft's owner decision 3).

## Tests and decisions

- **The code is fixed now.** `props_v1_score.R` runs every test, using the exploration's code with a filter to the scored weeks:
  - P1 and P2: `kalshi_consistency.R`'s A3 and A5;
  - P3: `props_close.R`'s series fit;
  - P4: `kalshi_behaviour.R`'s B1s;
  - P5 and P6: `props_frame.R`'s information test and timing fit, on the stacked weekly contracts.
- **The registered code:** the scorer and every script it or the weekly runs depend on, with their sha256 in the registration file. The scorer refuses to run unless they and this file are unchanged and committed.
- **It runs once,** after week 18's games and Kalshi's settlements: `--weeks=9:18`.
- **Correction:** Holm over P1–P6, at a one-sided 5%. A hypothesis is **confirmed** if its Holm-adjusted p is below 0.05.
- **Economic confirmation:** a confirmed hypothesis is also economically confirmed if the 95% interval of its after-cost return lies above 0. Games are resampled, B = 2,000, seed 20261102.

  | ID | After-cost return |
  |---|---|
  | P1 | The taker pair (both asks, both taker fees). The maker pair at the mids is also reported, conditional on fills |
  | P2 | The taker on the scalar ladder, priced at the binary ladder's mean |
  | P3 | None registered: a price relation only |
  | P4 | Buying YES at the ask on every flagged contract |
  | P5 | Our model's taker bets at the close, after the fee |
  | P6 | Taker bets at the 24-hour price when the model is 5 or more points away, held to settlement |

- **Fees** are Kalshi's: 0.07·P·(1 − P) taker and 0.0175·P·(1 − P) maker.
- **A confirmed P1 or P2 is a price relation, not a betting edge,** until a live test shows maker fills at the tested prices.

## Interim reports, deviations

- **Weekly reports are interim.** `score_week.R`'s weekly results may be read, labelled interim. Nothing is stopped, changed or chosen on them.
- **Deviations are reported** with the final result:
  - a missing run, fetch or week;
  - a schedule change;
  - an nflverse correction;
  - a change in Kalshi's API.

  None of them changes a test.
- **A new version:** a defect found in the registered code before the final run is fixed only in a new version of this protocol, never in place.
