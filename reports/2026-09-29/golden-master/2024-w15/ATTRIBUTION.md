# Golden master attribution: 2024 week 15 (Phase 1a)

The game model's numeric output (`run_logs/final_*.rds`, 16 games, N = 100,000 trials, seed 471) was recorded by `.github/workflows/golden-master.yml` at every commit of `fix/phase1a-wiring`, in parallel on R 4.5.1 with renv and nflreadr 1.5.0.

- **Run:** workflow run 36625811742; `attribute` job 109605752053.
- **Files here:**
  - `final_numeric.csv` and `meta.json`: the **current** golden master. It was recorded at `19bba55` in Phase 1a and re-recorded at `84df935` (M19, #203). The new record is the CI artifact `gm-84df935…` from workflow run 36767126473, `csv_sha256 795e476f…`. See "M19" below.
  - `baseline/`: the pre-fix record at `64aa0b4`.
- **Provenance:** both CSVs were reconstructed from the CI log. Their sha256 match the `csv_sha256` CI recorded (`73def369…`, `2f4ca1c5…`).
- **Runtime:** 379 s at baseline and 313 s at head, so the run_matrix `golden-master` timeout is 800 s.

| Commit | Fix | Output change vs the previous commit | Verdict |
|---|---|---|---|
| `64aa0b4` | Baseline: M1 plus the golden-master harness | Recorded twice. Only fitted `sd_*`, `k_*` and `total_uncertainty` differ, by ≤ 4e-9. | **Deterministic within 4e-9**: optimizer noise in a fitted variance model. `compare` uses a 1e-6 tolerance. |
| `1f7ba06` | M12: per-game randomized Sobol streams | Model probabilities (`home_p_2w_cal`, `_raw`, `_model`) change by ≤ 0.00064. Score means ≤ 0.0019, SDs ≤ 0.008. The blend (`home_p_2w_blend*`) changes by up to 0.0129 in 10–15 games. | **Explained.** Model columns move by Monte Carlo noise at N = 100k. The blend moves more because its training history is simulated: the calibration step re-simulates 2019–2023 (`Calibrating: season … week …`) through `simulate_game_nb`, now on distinct streams, so the stacker and its calibration map are refit. This exceeds the plan's 0.01 "report it" line, so it's reported here. |
| `3a31575` | M10: spread convention | None | As predicted: every game has a moneyline, so no spread fallback ran. |
| `461daf4` | M11: missing-market flagging | None (numeric) | As predicted. `market_available` is logical, not compared. |
| `ce8a2b8` | M2/M3: one market-weight stage | Blend changes in 3 games, ≤ 0.0085 (plus the 4e-9 fit noise) | **Explained.** The removed anti-shrink moved `p_raw` by 0.15·(p_raw − market) before `map_blend`. `map_blend` is a step function (`home_p_2w_blend_raw` takes only a few distinct values: 0.182 ×3, 0.566 ×2, 0.628 ×2, …), so only games that crossed a step changed. The single NFLmarket.R stage was already SHRINKAGE for regular-season games. |
| `7484098` | M14 and M17: date resolver | None | As predicted: nothing in the game model calls the resolver. |
| `2741512` | M15: snap percentages | None | As predicted: snap weighting is off by default. |
| `a877f14` | M16: offensive injury clamp and scope | **`mu_home`/`mu_away` unchanged in all 16 games.** SDs +0.13 to +0.17 in 15 games. Two NB sizes hit their clamps (for example `k_away` 50 → 5). | **Not as predicted. This led to two new defects, M18 and M19.** The plan expected predicted totals to rise by about 2–3 points (details below). |
| `19bba55` | KNOWN-DEFECT ID check (tests only) | Fit noise only (≤ 4e-9) | As predicted. |

**Head vs baseline:**
- Model win probabilities move by ≤ 0.0032.
- Blend probabilities move by ≤ 0.0175.
- Score SDs move by up to 0.33 (total).
- Means are unchanged beyond Monte Carlo noise (≤ 0.019 points).

## Why M16 did not move the means: new defects M18 and M19

**Reproduction, outside the pipeline.** Using the same nflverse 2024 injury file, `calc_injury_impacts()` before and after M16 was run on the week-15 slate (379 injury rows, all 32 teams):
- **Before:** every team's `inj_off_pts` is −1.5, the inverted clamp M16 fixed.
- **After:** the values range from 0 to −0.7.

**The contradiction.** That is a 0.8–1.5-point change per team, yet `mu_home` and `mu_away` are bit-identical across the commit.

**Conclusions:**
- **M18 (new).** The current-week injury points (`inj_team_effects`) do not reach `mu` in the pipeline, even though the run reports `Injuries: FULL`. They are computed and joined into `recent_form`, but the value used at `mu_*_qb_rest` (`NFLsimulation.R`, `home_injury_off_total`) is evidently not this one. The SD shift comes from another route: injury features in the historical calibration or variance fits.
- **M19 (new).** `inj_pick()` chooses the first status column present. nflverse injury data has no `game_status` or `status`, so it takes `practice_status` ahead of `report_status`. Game designations (Out, Doubtful, Questionable) are never read. "Did Not Participate" matches none of the penalty patterns, so it scores 0; only "Limited" (−0.10) counts.

Both are recorded in `reports/2026-09-29/AUDIT-ADDENDUM.md`. Fixing them changes core-engine output, so it needs owner approval (A1a covered M1–M16). Tracing M18 needs a runnable environment.

## Observation for Phase 1b (M4)

The blend's calibration map produces extreme values that the market doesn't support. For BAL @ NYG (market 8.8% home win, model 11.3%), `home_p_2w_blend_raw` is 0.003 and the displayed blend is 0.039. That calibrator is the invalid, outcome-leaked one (audit M4). Phase 1b disables it.

## M19 (#203): injury game designations

The record was made by `.github/workflows/golden-master.yml` on #203: workflow run 36767126473, `attribute` job 110068173753. The baseline was recorded twice (`b5d1ac4` and `b5d1ac4-rep2`) and differs only by fit noise (≤ 4e-9). The merges `526ec9d`, `37e92d8` and `eaa4138` show no differences.

**`84df935` against `eaa4138`:**

| Columns | Games changed | Max abs diff |
|---|---|---|
| `mu_home`, `mu_away` | **0** | – |
| `home_sd_pts`, `away_sd_pts`, `total_sd`, `margin_sd` | 16 | 0.19, 0.13, 0.16, 0.18 |
| `sd_home`, `sd_away` (fitted inputs) | 15 | 0.19, 0.14 |
| `k_home`, `k_away` (NB size) | 11, 9 | 1.7, 45 (one game moves between the clamps 5 and 50) |
| `home_mean_pts`, `away_mean_pts`, `total_mean` | 16 | 0.0029, 0.0016, 0.0045 (Monte Carlo, from the new SDs) |
| `home_p_2w_raw` / `_cal`, `home_win_prob` | 16 | ≤ 0.0029 |
| `home_p_2w_blend`, `home_win_prob_blend`, `margin_blend` | 15–16 | ≤ 0.0011, 0.24 |
| Integer interval columns (CI and PI bounds, `margin_median`) | 1–4 | 1–16 (one-point shifts, and the `k_away` game's interval) |

**Verdict: explained.**
- M19 changes which status column the injury readers use. The historical injury features, which feed the variance fits, now count Out/Doubtful/Questionable instead of practice participation. So the SDs move.
- The current-week injury points change too, but **the means cannot move**. Audit M22 (Critical, #200): the turnover prior is NaN for every team (nflverse schedules have no turnover columns). That makes every expected score NaN at the turnover join, and a safety block rebuilds it as drives × points per drive (+ home field). Every adjustment, injuries included, is lost.
- That is also the answer to the M16 contradiction above: M18's "injury points do not reach mu" is a symptom of M22.

**Head vs baseline (`84df935` vs `b5d1ac4`):** the same columns and sizes as above. Nothing between the baseline and `eaa4138` changed the output.
