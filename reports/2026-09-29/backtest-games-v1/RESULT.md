# Game backtest `nfl_games_v1`: result

**Bottom line: no candidate is better than the no-vig closing line.** Elo, the EPA model, their ensemble and a calibrated ensemble are all worse than the close, by 4.5–5.6% of Brier on the 2023–2024 Confirm window. The market-anchored blends are statistically indistinguishable from the close. Every candidate is labeled **"not better than market"**. Under the honest default, the site shows market-equivalent probabilities and no picks.

| | |
|---|---|
| Protocol | [`PROTOCOL.md`](PROTOCOL.md), sha256 `664c42d1…8715149`, committed in `e9876fa` at 2026-09-29T19:58:33Z and pushed before scoring |
| Scored run | `result_sha256` `7244a0bc8ac63fec4d8d11b48b4b93be4ebf3fdba51b0fa3d6929cab336a3458`, code `c7d8bce`, R 4.3.3, data.table 1.14.10, jsonlite 1.8.8, digest 0.6.34 |
| Run status | **complete**: all five controls passed (`controls.json`) |
| Windows scored | Tune 2018–2022 (selection), Confirm 2023–2024. The 2025 Holdout is **sealed**, and its data are not in the inputs. |
| Reproduce | `Rscript backtest/walk_forward.R --window backtest/eval_windows/nfl_games_v1.json --stage score --out <dir>` gives the same `result_sha256` in the same environment |

## Confirm window, 2023–2024 (the honest comparison)

570 non-tie games (0 ties), regular season and playoffs pooled. The skill CIs come from a paired week-block bootstrap with B = 10,000. The DM test is one-sided (H1: the candidate beats C0), HLN-corrected and BH-adjusted across the eight candidates.

| Candidate | n | Brier | Log loss | Brier skill vs C0 [95% CI] | ECE | Calibration slope [95% CI] | DM p (BH) | Status |
|---|---|---|---|---|---|---|---|---|
| C0 market (close) | 570 | 0.2098 | 0.6081 | – | 0.0527 | 1.14 [0.88, 1.41] | – | benchmark |
| C1 Elo | 570 | 0.2216 | 0.6343 | -5.64% [-9.48%, -2.19%] | 0.0479 | 1.03 [0.75, 1.31] | 0.999 | not better than market |
| C2 EPA GLM | 570 | 0.2202 | 0.6295 | -4.94% [-8.15%, -1.89%] | 0.0550 | 0.98 [0.72, 1.23] | 0.999 | not better than market |
| E1 ensemble | 570 | 0.2192 | 0.6280 | -4.47% [-7.41%, -1.84%] | 0.0529 | 1.07 [0.79, 1.35] | 0.999 | not better than market |
| B1[C1] | 570 | 0.2098 | 0.6081 | +0.00% [-0.42%, +0.46%] | 0.0571 | 1.08 [0.83, 1.33] | 0.999 | not better than market |
| B1[C2] | 570 | 0.2099 | 0.6082 | -0.03% [-0.37%, +0.31%] | 0.0507 | 1.10 [0.85, 1.36] | 0.999 | not better than market |
| B1[E1] | 570 | 0.2098 | 0.6080 | +0.02% [-0.38%, +0.45%] | 0.0503 | 1.08 [0.83, 1.33] | 0.999 | not better than market |
| B2[E1] | 570 | 0.2100 | 0.6084 | -0.07% [-0.19%, +0.05%] | 0.0537 | 1.16 [0.89, 1.42] | 0.999 | not better than market |
| K[E1] | 570 | 0.2192 | 0.6284 | -4.49% [-7.55%, -1.77%] | 0.0407 | 0.93 [0.69, 1.18] | 0.999 | not better than market |

**How to read this:**
- **Model-only candidates:** C1, C2, E1 and K[E1] are clearly worse than the close. Their whole skill CI is below 0.
- **Market-anchored blends:** B1 and B2 land within ±0.5% of the close, with CIs spanning 0. Adding Elo or EPA information to the closing line gives no measurable gain.
- **Calibration:** every candidate passes the calibration gate G3. The close itself has slope 1.14 (CI 0.88–1.41) on 2023–2024.

### By phase

**Regular season:**

| Candidate | n | Brier | Log loss | Brier skill vs C0 [95% CI] | ECE | Calibration slope [95% CI] | DM p (BH) |
|---|---|---|---|---|---|---|---|
| C0 market (close) | 544 | 0.2094 | 0.6074 | – | 0.0518 | 1.17 [0.90, 1.44] | – |
| C1 Elo | 544 | 0.2218 | 0.6346 | -5.89% [-9.94%, -2.39%] | 0.0529 | 1.03 [0.75, 1.32] | 0.999 |
| C2 EPA GLM | 544 | 0.2195 | 0.6282 | -4.82% [-7.98%, -1.77%] | 0.0650 | 1.01 [0.75, 1.27] | 0.999 |
| E1 ensemble | 544 | 0.2189 | 0.6275 | -4.52% [-7.58%, -1.81%] | 0.0610 | 1.09 [0.81, 1.38] | 0.999 |
| B1[C1] | 544 | 0.2092 | 0.6070 | +0.09% [-0.34%, +0.57%] | 0.0545 | 1.10 [0.85, 1.36] | 0.999 |
| B1[C2] | 544 | 0.2093 | 0.6072 | +0.05% [-0.30%, +0.41%] | 0.0552 | 1.13 [0.87, 1.39] | 0.999 |
| B1[E1] | 544 | 0.2092 | 0.6069 | +0.12% [-0.29%, +0.56%] | 0.0529 | 1.11 [0.85, 1.36] | 0.999 |
| B2[E1] | 544 | 0.2096 | 0.6077 | -0.07% [-0.19%, +0.05%] | 0.0562 | 1.18 [0.91, 1.46] | 0.999 |
| K[E1] | 544 | 0.2189 | 0.6276 | -4.50% [-7.69%, -1.70%] | 0.0558 | 0.95 [0.70, 1.20] | 0.999 |

**Playoffs:**

| Candidate | n | Brier | Log loss | Brier skill vs C0 [95% CI] | ECE | Calibration slope [95% CI] | DM p (BH) |
|---|---|---|---|---|---|---|---|
| C0 market (close) | 26 | 0.2176 | 0.6222 | – | 0.3089 | -0.47 [-2.10, 1.16] | – |
| C1 Elo | 26 | 0.2190 | 0.6288 | -0.64% [-13.97%, +9.09%] | 0.2614 | -1.27 [-3.88, 1.34] | 0.994 |
| C2 EPA GLM | 26 | 0.2339 | 0.6574 | -7.52% [-29.10%, +8.46%] | 0.3313 | -0.92 [-2.58, 0.74] | 0.994 |
| E1 ensemble | 26 | 0.2250 | 0.6396 | -3.41% [-19.51%, +8.80%] | 0.3203 | -1.18 [-3.32, 0.96] | 0.994 |
| B1[C1] | 26 | 0.2216 | 0.6304 | -1.83% [-2.61%, -0.63%] | 0.3128 | -0.45 [-1.99, 1.09] | 0.994 |
| B1[C2] | 26 | 0.2214 | 0.6301 | -1.76% [-2.51%, -0.70%] | 0.3124 | -0.46 [-2.03, 1.11] | 0.994 |
| B1[E1] | 26 | 0.2217 | 0.6306 | -1.90% [-2.96%, -0.25%] | 0.3128 | -0.43 [-1.96, 1.10] | 0.994 |
| B2[E1] | 26 | 0.2177 | 0.6226 | -0.05% [-0.87%, +0.59%] | 0.3087 | -0.50 [-2.17, 1.16] | 0.994 |
| K[E1] | 26 | 0.2269 | 0.6434 | -4.31% [-20.69%, +8.62%] | 0.3181 | -1.03 [-2.90, 0.84] | 0.994 |

There are 26 playoff games over 8 weeks, so these intervals are too wide to separate anything. The B1 blends' playoff CIs sit below 0, but the pooled headline, as A2 decision 2 requires, shows no difference.

## Selections (Tune window only)

| Component | Selected | Grid |
|---|---|---|
| C1 Elo | K = 20, HFA = 30 Elo points, regress = 0.45 | 80 combinations |
| C2 EPA GLM | halflife = 8 team-games, λ = 100 | 15 combinations |
| B1 λ | C1: 0.1 · C2: 10 · E1: 0.1 | {0.1, 1, 10} |
| B2[E1] market weight w | **0.95**, the top of the designed grid | 0.50–0.95 |
| K[E1] method | Platt | Platt, isotonic |

**On the market weight:**
- For the ensemble, the fixed-weight shrink picked the largest market weight allowed (95%). Tune log loss fell monotonically as the weight on the model decreased.
- So under this data, a 70% market weight (today's pipeline) would put too much weight on these models.
- The simulator (C3) is judged the same way in `nfl_games_v2`.

**Tune (selection window; in-sample for the hyperparameters, so not an honest estimate):**

| Candidate | n | Brier | Log loss | Brier skill vs C0 [95% CI] | ECE | Calibration slope [95% CI] | DM p (BH) |
|---|---|---|---|---|---|---|---|
| C0 market (close) | 1365 | 0.2111 | 0.6097 | – | 0.0310 | 1.05 [0.89, 1.20] | – |
| C1 Elo | 1365 | 0.2224 | 0.6358 | -5.33% [-7.57%, -3.17%] | 0.0248 | 1.02 [0.84, 1.20] | 1.000 |
| C2 EPA GLM | 1365 | 0.2196 | 0.6289 | -4.04% [-6.05%, -2.06%] | 0.0449 | 1.06 [0.89, 1.24] | 1.000 |
| E1 ensemble | 1365 | 0.2195 | 0.6291 | -3.99% [-5.94%, -2.13%] | 0.0430 | 1.10 [0.92, 1.28] | 1.000 |
| B1[C1] | 1365 | 0.2113 | 0.6104 | -0.11% [-0.41%, +0.19%] | 0.0282 | 0.99 [0.84, 1.13] | 1.000 |
| B1[C2] | 1365 | 0.2111 | 0.6098 | +0.01% [-0.20%, +0.21%] | 0.0321 | 1.01 [0.86, 1.16] | 1.000 |
| B1[E1] | 1365 | 0.2111 | 0.6099 | -0.01% [-0.28%, +0.26%] | 0.0285 | 0.98 [0.84, 1.13] | 1.000 |
| B2[E1] | 1365 | 0.2112 | 0.6099 | -0.04% [-0.13%, +0.05%] | 0.0315 | 1.06 [0.91, 1.22] | 1.000 |
| K[E1] | 1365 | 0.2198 | 0.6302 | -4.13% [-6.09%, -2.22%] | 0.0425 | 0.92 [0.77, 1.08] | 1.000 |

## Closing-line value at the ESPN BET opener (2024, descriptive only)

**This is not a gate look.** The A2 betting-value gate needs 400 decision-time picks and is evaluated once. 2024 has 284 games with an ESPN BET opener, so no candidate can reach 400, and every status reads "not evaluable".

**Pick rule and metric:**
- Picks are made where the model differs from the no-vig opener by at least 3 percentage points.
- CLV is `10000 · (close − open)` for the side taken, no-vig at the same venue.

| Candidate | Picks | Home picks | Mean CLV (bps) [95% CI] | Flat ROI [95% CI] | Hit rate | Gate |
|---|---|---|---|---|---|---|
| C1 | 207 | 101 | -19 [-107, +61] | -0.3% [-17.7%, +18.9%] | 47.8% | not evaluable: 207 decision-time picks < 400 |
| C2 | 214 | 129 | +93 [+40, +149] | -7.0% [-22.8%, +9.3%] | 47.2% | not evaluable: 214 decision-time picks < 400 |
| E1 | 200 | 110 | +52 [-12, +117] | -2.7% [-18.4%, +13.2%] | 48.0% | not evaluable: 200 decision-time picks < 400 |
| K[E1] | 199 | 108 | +66 [+8, +125] | -1.6% [-16.5%, +13.6%] | 51.8% | not evaluable: 199 decision-time picks < 400 |

**Reading this:**
- **C2 (EPA GLM):** the ESPN BET line moved toward the model's side between open and close, by +93 bps on average (95% CI +40 to +149).
- **K[E1] (calibrated ensemble):** +66 bps (CI +8 to +125).

**Why this is only a lead, not a claim:**
- It covers one season.
- There are about 200 picks per candidate, half the pre-registered minimum.
- Four candidates were examined, and these intervals are not corrected for that.
- Flat ROI at the opening price is negative or null for every candidate.
- The starting-QB input may not be known at the opener (PROTOCOL §9).

**Next step:** the natural follow-up is to pre-register "C2 at the opener" as a **single** prospective hypothesis for 2026 forward capture, which avoids the multiplicity problem, and to add 2023 ESPN openers from upstream.

## Controls

| Control | Result | Passed |
|---|---|---|
| Leak canary (a): as-of assertion | A margin-plus-noise feature ending 3.5 h after kickoff was rejected | yes |
| Leak canary (b): assertion bypassed | C2 refit with the canary reached skill **+0.70**, and the implausibility guard flagged it | yes |
| Implausible-skill guard | Maximum candidate skill vs C0 on Confirm: +0.0002 (threshold 0.05) | yes |
| Shuffled labels (global permutation) | Every candidate's skill-CI lower bound vs climatology ≤ 0 (range −0.138 to −0.009) | yes |
| Market copy | C0 scored as a candidate gives skill 0 and a Brier difference of exactly 0. B1 on (C0, C0) recovers a total market slope of 1.055. | yes |
| Reproducibility | A second process gave the same `result_sha256` | yes |

## Run history

**First scoring run (void).** It ran at 19:59:58Z, and its reproducibility control failed. Its evidence is in [`run1-void/`](run1-void/). The cause was a harness bug, not a data or model problem:
- The re-run process was started with `--no-controls`.
- So gate G4 in the hashed `metrics.json` was FALSE there and TRUE in the first run.
- A second bug, unquoted `system2` arguments, broke the `protocol_commit` metadata.

**The fix.** Commit `c7d8bce` fixed both bugs without touching prediction, metric or selection code; PROTOCOL.md is unchanged.

**Why it's sound.** The re-run's `predictions.csv` and `metrics.json` are byte-identical to the void run's (`run1-void/SHA256SUMS`). That proves the fix changed no result.

## What this means for the project

1. **The honest default holds.** No game market passes its gates. The public site shows market-equivalent probabilities, labeled "unvalidated", with no picks (spec §4; A7 confirms).
2. **The bar for the simulator.** The Phase 1b point-in-time simulator (C3) joins as `nfl_games_v2`.
   - To be called better than the market it must beat a close these baselines can't touch.
   - A realistic success is B1[C3] ≈ C0 on Brier, plus positive CLV at decision time.
3. **The Holdout stays sealed** until `nfl_games_v2` (A2 decision 3). It is scored once, for every candidate together.
4. **Evidence-ledger rows:** `docs/EVIDENCE_LEDGER.md` (BT-V1-*).
