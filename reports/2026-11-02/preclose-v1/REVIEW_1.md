# Review 1 of `nfl_preclose_v1`'s code and its dispositions (amendment 4)

**The review.** One fresh read-only review of this branch (2026-11-03), on the owner's one-review-per-branch rule. Every finding was checked against the code and the data before acting.

**What amendment 4 does and does not change.** Amendment 4 re-registers the fixed files. It changes no choice in `PROTOCOL.md` or `AMENDMENT_1_1.md`: every fix makes the code do what the text says.

**Its timing:**
- **No prospective number had been computed.** Week 9 had not kicked off, and no 2026 prediction had been saved to the live store.
- **The Holdout is still sealed.**

## Fixed

| # | Finding | Fix |
|---|---|---|
| 2 (Critical) | `run_2026.R` saved rows for weeks w and w+1 and scored each game on its earliest saved row. A week-(w+1) game would then have been scored on the prediction made a week early, without week w's results. That is not IS-T | `predict` writes only the week's own games. `pc_select_saved()` (new `prospective.R`) keeps each game's row from its own week's run, saved before that week's first kickoff. It asserts one row per game and reports coverage. A test, mutation-checked, rejects a stale row |
| 4 (Important) | The private history kept 2025's closing moneylines, and `bt_prepare_games()` computed a 2025 no-vig price in memory. Nothing used it, but `PROTOCOL.md` says no 2025 price is computed | `build_history.R` writes 2025's moneylines and spread as missing, and `run_2026.R` blanks them again before `bt_prepare_games()` |
| 5 (Important, part) | P7 never voided a run: only P6 set the status | `run_preclose.R` writes `p7_tripped` and a run `status` that is void on any P6 failure or P7 trip. Tune and Confirm tripped none, so their numbers are unchanged |
| 7 (Minor) | Ties were dropped before the Tuesday track's CLV and return, so the "tie pays half" rule never ran | The Tuesday track's CLV and return use every played game, a tie paying half. Brier still uses decided games. A test checks the signs, the fee and the half payout |
| 8 (Minor) | Elo's snapshots follow week changes. Weeks running backwards in kickoff order would mis-key them | `pc_elo()` stops on that, and on a team playing twice in a week. Neither happens in 2006–2026 (checked), and a test checks the refusal |
| 9 (Minor) | The Tuesday price is the first candle at or after 18:00 UTC, which can fall after the decision | The rule stays as registered. The state at 18:00 UTC (the last candle at or before it) is reported beside it as `mean_clv_bps_state` |
| 12 (Minor) | The registration still called the Tuesday track IS-B | The registration says IS-T (amendment 1's ruling) |

## Rulings (no change)

| # | Finding | Ruling | Cost if wrong |
|---|---|---|---|
| 1 (Critical as filed) | IS-A's QB is the starter of the team's previous game, often week w−1's, after IS-A's results cutoff | **This is the protocol's own definition** (`qb_prev_start`, from the approved design's §2), not a code error. The QB is known once week w−1's game kicks off. `opener_timing_elo.R` shows ESPN BET's openers already price week w−1's results, so they are posted after those games and the starter is known at the opener. The code follows the signed text, and changing the QB rule would be a new choice made after Tune and Confirm were read | Some look-ahead in starter identity, only for an opener posted before week w−1's kickoffs and only in games whose starter changed |
| 3 (Important as filed) | E1's Tuesday Elo is each game's pre-game rating, which might include same-week results | **Elo updates only a game's two teams, and a team plays once a week.** So a pre-game rating equals the rating at the week's first kickoff (checked: no team plays twice in a week in 2006–2026, and `pc_elo()` now asserts it). The pilot's E1 numbers are unaffected | None in this data. The assertion stops a future schedule that breaks it |
| 5 (rest) | P5 and the Holdout verdict are not implemented | **They need the sealed Holdout.** Its stage (P5 pooled over Confirm and the Holdout, and the verdict) is written and registered before the owner opens it | None, as long as that is done first |
| 10 | Missing tests | Added for the prospective selection, the Tuesday CLV and return, and Elo's week-order refusal. Gate and P7 tests are left to the Holdout stage | — |
| 11 | `AMENDMENT_1_1.md` does not say the pilot's C2 row met the rule (BH p 0.044) | Stated in `RESULT.md`. `AMENDMENT_1_1.md` is registered and stays as it is | — |
| 13 | Was Tune or Confirm scored before the code was registered? | **No.** The score stage refuses until code is registered (`run_preclose.R`: it stops on an empty `code` list), and its only run used `6002e04`, amendment 1 (`out/run_meta.csv`) | — |
