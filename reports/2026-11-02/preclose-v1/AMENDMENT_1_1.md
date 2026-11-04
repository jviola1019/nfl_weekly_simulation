# nfl_preclose_v1.1: the 2026 opener track is withdrawn and the Tuesday track becomes 2026's test

**Made 2026-11-02, before week 9's first kickoff** (2026-11-06 01:15 UTC). No game of weeks 9–18 had been played or predicted.

`PROTOCOL.md` stays frozen. This file changes two of its choices, so the protocol becomes version 1.1. Its sha256 is in `backtest/eval_windows/nfl_preclose_v1.json` as amendment 3.

## Why

The 2026 pilot (weeks 1–8) scored the opener track against "DraftKings as ESPN reports it". That "open" is DraftKings' first line for the game, set before the season, not a weekly opener (`dk_opener_timing.R`, `out/2026/dk_opener_*.csv`):
- **Elo knowing no 2026 game gains CLV against it:** Elo at the season's start gains +315 bps (95% CI +194 to +440). Elo through week w−2 gains +461, and Elo through w−1 +564.
- **The open-to-close move follows what 2026 has shown.** Regressed on Elo's updates (8 week clusters), its coefficient is 0.79 on the season so far (0.58 to 1.00) and 0.82 on the week before (0.57 to 1.07).
- **The mean absolute move grows through the season,** from 4.4 probability points in week 1 to 11.4 in week 7.

So the opener track's 2026 numbers (PC-C2 +572 bps) measure a stale line, not the opener the design means. Weeks 9–18 would have the same flaw.

## What changes

1. **The 2026 opener track is withdrawn.** The pilot's numbers are reported as invalid, and no 2026 opener-track number counts. The Holdout's opener track (2025, ESPN BET) is unchanged and still decides.
2. **The Tuesday track becomes 2026's prospective test, for weeks 9–18:**
   - **Candidates:** C2 and E1 on IS-T: results through week w−1, and the starter of the team's previous game (amendment 1).
   - **Primary statistic:** the mean CLV of τ-picks (τ = 0.03) from Kalshi's Tuesday mid to Kalshi's close. Tested one-sided > 0 with the week-block bootstrap (B = 10,000, seed 20260929), with BH across the two candidates. A candidate is confirmed when its BH-adjusted p < 0.05.
   - **Reported beside it:**
     - Brier skill against the Tuesday mid;
     - the calibration slope;
     - the taker's return: the Tuesday ask plus Kalshi's taker fee, held to settlement, a tie paying half.
   - **The prices:** fixed by the original text, the first hourly candle at or after 18:00 UTC.
   - **Saving predictions:** each week's are written by `run_2026.R predict` before its games, and the one look comes after week 18.
3. **Everything else is unchanged:**
   - IS-A;
   - PC-C2, OA[E1] and LM[E1] on Tune, Confirm and the Holdout;
   - the gates and the disclosures.

## Disclosures

- **The pilot was read before this amendment:** the opener track's invalid numbers above, and the Tuesday track's weeks 1–8 (`out/2026/pilot_tuesday_track.csv`).

  | Candidate | CLV, weeks 1–8 | Taker return |
  |---|---|---|
  | C2 | +49 bps (+1 to +92), 81 picks | +18.9% (−4.3% to +39.3%) |
  | E1 | +28 bps (−24 to +72), 87 picks | +20.4% (+2.5% to +39.2%) |

  Choosing the Tuesday track after seeing them is a choice made on data. Its test is on weeks 9–18, which nobody has seen.
- **The CLV pick rule, τ and the bootstrap are the protocol's own,** unchanged.
