# nfl_preclose_v1.1: results so far (Tune 2023, Confirm 2024, the 2026 pilot)

## Status

| Step | When | Commit |
|---|---|---|
| Signed, before PC-C2 existed for any season | 2026-11-02 21:26 UTC | `ebae533` |
| **Amendment 1:** the code registered, with known answers | — | `6002e04` |
| **Amendment 2:** a column fix in the 2026 runner, made before it produced any number | — | `c8bcc5d` |
| **Amendment 3 = version 1.1:** the 2026 opener track withdrawn (`AMENDMENT_1_1.md`), made before week 9 | — | `53b58cd` |
| **Amendment 4:** the review's fixes (`REVIEW_1.md`); no choice changes, and Tune/Confirm reproduce the same result_sha256 | 2026-11-03 | `e8cc66a` |

- **The Holdout (2025, sealed) decides** and is not built yet: the owner opens it once, with `nfl_games_v2`.
- **2026 weeks 9–18 are prospective.** The weekly scheduler saves each week's predictions on Tuesday at 18:30 UTC (`prospective_dispatch.R`). They are scored once, after week 18.

## Known answers (`run_preclose.R known-answer`, `out/` beside this file)

| Check | Result |
|---|---|
| PC-C2's builder on IS-B against v1's C2, 1,942 games, 2018–2024 | Maximum difference 5×10⁻¹¹ |
| Elo on IS-B against v1's C1 | Maximum difference 5×10⁻¹¹ |
| Elo on IS-A at ESPN BET 2023–2024 | 353 picks, −27.40 bps, as `opener_timing_elo.R` |
| T1: C2 at ESPN BET 2023 | 141 picks, +85.08 bps, as `opener_clv_t1.csv` |

## Tune 2023 and Confirm 2024 (`run_preclose.R score`; result_sha256 `a2bc9d0e`)

**Every P6 control passes:** the leak canary, the anchor copy, reproducibility, the anchor null, the permuted-x null and the placebo band. OA's λ is 1: Tune log loss 0.6387, against 0.6463 at 0.1 and 0.6393 at 10.

| Candidate | Window | Games | Brier skill against the opener (95% CI) | DM p | CLV of picks (95% CI) | Flat ROI |
|---|---|---|---|---|---|---|
| PC-C2 | Tune 2023 | 205 | −2.2% (−8.4 to +4.3) | 0.80 | +54 bps (−18 to +137), 144 picks | +2.0% |
| OA[E1] | Tune 2023 | 92 | +1.0% (−3.8 to +6.4) | 0.39 | +120 bps (−8 to +254), 67 picks | +11.8% |
| LM[E1] | Tune 2023 | 92 | −0.06% (−0.6 to +0.7) | 0.58 | no pick | — |
| PC-C2 | Confirm 2024 | 284 | **−6.6% (−10.8 to −3.0)** | 0.995 | +45 bps (−6 to +99), 205 picks | −15.9% |
| OA[E1] | Confirm 2024 | 284 | −2.7% (−5.6 to −0.5) | 0.99 | **+135 bps (+47 to +231)**, 128 picks | −16.0% |
| LM[E1] | Confirm 2024 | 284 | −0.08% (−0.5 to +0.3) | 0.65 | no pick | — |

- **No candidate passes P1 or P2 in either window.** None beats the opener on accuracy.
- **P3 (calibration) passes in 2024.**
- **P4 fails for LM:** its movement slope is −3.1 in 2023 and −0.8 in 2024. LM's predicted moves are too small ever to reach τ, so it makes no pick.
- **P7 is not tripped.**
- **CLV is positive but smaller than on IS-B.** On information certainly known at the opener (results through week w−2, the previous starter), C2's CLV roughly halves against IS-B: +54 against +85 in 2023, +45 against +93 in 2024.
- **OA's 2024 CLV is significant** (+135 bps on 128 picks), but its picks lose at one book's opener prices (−16%), as T1's did.
- **P5 (value)** pools Confirm with the sealed Holdout, so it cannot be judged yet.

## The 2026 pilot, weeks 1–8 (`run_2026.R pilot`, `out/2026/`; reported separately, never pooled)

**The opener track is invalid and withdrawn** (`AMENDMENT_1_1.md`). ESPN's 2026 DraftKings "open" is the line DraftKings set before the season (`dk_opener_timing.R`):
- Elo knowing no 2026 game gains +315 bps (+194 to +440) against it.
- The open-to-close move follows the season's Elo updates at 0.79 and the previous week's at 0.82.
- The mean move grows from 4.4 probability points in week 1 to 11.4 in week 7.

So the pilot's +572 bps for PC-C2 measures a stale line.

**The Tuesday track** prices C2 and E1 on IS-T (results through week w−1, the previous starter) against Kalshi's KXNFLGAME mid at Tuesday 18:00 UTC, with CLV measured to Kalshi's close. 119 games, all with a Tuesday price.

| Candidate | Brier skill against the Tuesday mid (95% CI) | CLV of picks (95% CI) | One-sided p (BH) | Taker return: the ask plus the fee, held to settlement |
|---|---|---|---|---|
| C2 | −1.1% (−7.0 to +4.6) | **+49 bps (+1 to +92)**, 82 picks | 0.022 (0.044) | +19.0% (−3.7% to +39.1%) |
| E1 | +0.9% (−4.2 to +5.6) | +27 bps (−23 to +72), 88 picks | 0.127 (0.127) | +20.5% (+2.8% to +39.0%) |

- **These are amendment 4's numbers** (`REVIEW_1.md`). They count the one tie (week 5, NYG–WAS) at half pay. Before it the table had 81 and 87 picks, and C2's +49 bps and E1's +28 bps.
- **The 18:00 UTC state price gives the same CLV:** every game had a candle ending at 18:00 UTC.
- **C2's row meets v1.1's rule here,** a BH-adjusted p below 0.05. In a pilot that confirms nothing.

- **C2 predicts where Kalshi's price moves between Tuesday and kickoff.** The size is similar to T1's at ESPN BET's opener.
- **This is a pilot, chosen after looking.** v1.1 made the Tuesday track the 2026 test after these numbers were read, and its test is weeks 9–18. Eight weeks of returns at ±20% decide nothing.

## What it means

- **On information known at the opener, no model beats the opener's accuracy.** The EPA model's prices still move toward its side, by about half as much as with the previous week's results.
- **That movement doesn't pay at one book's opener.** The overround is larger.
- **At Kalshi's Tuesday price the pilot points the same way.** The prospective weeks 9–18 will say whether it holds, and the sealed Holdout decides the opener track.
