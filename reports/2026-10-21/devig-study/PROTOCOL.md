# M3: which devig gives the most accurate market probability? (pre-registered)

**Written and committed before any result was computed:** 2026-10-21. Owner-approved Track M of the plan revised on 2026-10-20.

## Question
The market baseline C0 devigs the closing moneyline proportionally. Do other standard devig methods give better-calibrated or more accurate home-win probabilities against outcomes? If one does, C0, and every protocol that uses it, should change before `nfl_preclose_v1` is signed.

## Data
- **Source:** `backtest/data/games.csv`, the frozen nflverse inputs committed for `nfl_games_v1`. Its sha256 is hashed in `backtest/eval_windows/nfl_games_v1.json`.
- **Rows:**
  - seasons **2006–2022** only, so the Tune and Confirm windows 2023–2024 of the pre-close and v2 protocols are left untouched;
  - the file holds no 2025 data;
  - regular season and playoffs;
  - both closing moneylines present;
  - the game decided, so ties are excluded.
- **Outcome:** `y = 1` when the home team wins.

## Methods
Here q_h and q_a are the implied probabilities of the two American prices, and S = q_h + q_a.
1. **Proportional** (the current C0, the reference): p_h = q_h / S.
2. **Additive:** p_h = q_h − (S − 1)/2, clamped to (0.001, 0.999).
3. **Power:** p_i = q_i^k, with k solving q_h^k + q_a^k = 1.
4. **Shin:** for two outcomes, p_i = [sqrt(z² + 4(1 − z) q_i² / S) − z] / (2(1 − z)), with z solving p_h + p_a = 1.
5. **Odds ratio** (equivalently a logit shift): p_i = q_i / (c + q_i − c·q_i), with c solving p_h + p_a = 1.

## Metrics and inference
- **Primary metric:** mean log-loss. **Secondary:** mean Brier, the calibration slope and intercept (logistic regression of y on logit p), and the favourite–longshot bias (mean of y − p in the favourite bins).
- **Paired differences** against proportional, game by game. Each gets a 95% interval from a week-block bootstrap with B = 10,000 and seed 20261021, where a block is a season and week (`bt_boot_counts` in `backtest/metrics.R`). Each also gets a Diebold–Mariano test with the HLN correction (`bt_dm_hln`).
- **Multiplicity:** Holm across the four alternative methods, for the primary metric.

## Decision rule (fixed now)
An alternative replaces proportional as C0's devig only if all three hold:
- (a) its log-loss difference against proportional is negative, with a Holm-adjusted p below 0.05;
- (b) the upper bound of its 95% bootstrap interval for the Brier difference is at most 0;
- (c) the mean log-loss improvement is at least 0.0005. Below that, the change is not worth breaking comparability with v1.

Otherwise proportional stays. All five methods are reported either way, including nulls.

## Outputs
`devig.R` (reproducible, with no network) and `RESULTS.md` in this folder. The results go into the ledger and the evidence pages under M3.
