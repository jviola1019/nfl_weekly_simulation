# M3 results: which devig gives the most accurate market probability?

**Pre-registration.** `PROTOCOL.md`, commit `c393d5d`, pushed before this ran.

**How to reproduce.** `Rscript --vanilla reports/2026-10-21/devig-study/devig.R <repo root>`. It uses no network and reads only the frozen `backtest/data/games.csv`, seasons 2006–2022. It asserts that no season 2023 or later is present.

**Sample.** There are 4,576 games in 2006–2022.
- 4,427 have both closing moneylines and were decided.
- One has an overround outside (1, 1.25) and is dropped.
- **n = 4,426.**
- The solvers failed nowhere.

## Accuracy and calibration

| Method | Log-loss | Brier | Calibration slope | Intercept | Favourites (p ≥ 0.75): won − priced | Longshots (p ≤ 0.25): won − priced |
|---|---|---|---|---|---|---|
| proportional (current C0) | 0.609803 | 0.211302 | 1.025 | −0.0466 | +0.0234 | +0.0115 |
| additive | 0.609727 | 0.211310 | 0.993 | −0.0551 | +0.0163 | +0.0148 |
| power | 0.609739 | 0.211330 | 0.976 | −0.0596 | +0.0134 | +0.0167 |
| Shin | 0.609727 | 0.211310 | 0.993 | −0.0551 | +0.0163 | +0.0148 |
| odds ratio | 0.609722 | 0.211309 | 0.992 | −0.0554 | +0.0162 | +0.0152 |

For a two-outcome market, Shin's method reduces to the additive one. Their identical rows are expected and serve as a check on the code.

## Each method against proportional

Paired, game by game. The 95% intervals come from a week-block bootstrap (B = 10,000, seed 20261021). The test is Diebold–Mariano with the HLN correction, Holm-adjusted over the four alternatives.

| Method | Δ log-loss | 95% CI | DM p | Holm p | Δ Brier | 95% CI |
|---|---|---|---|---|---|---|
| additive | −0.000076 | [−0.000445, +0.000307] | 0.680 | 1 | +0.0000075 | [−0.000113, +0.000130] |
| power | −0.000064 | [−0.000645, +0.000542] | 0.826 | 1 | +0.0000274 | [−0.000156, +0.000214] |
| Shin | −0.000076 | [−0.000445, +0.000307] | 0.680 | 1 | +0.0000075 | [−0.000113, +0.000130] |
| odds ratio | −0.000081 | [−0.000472, +0.000326] | 0.678 | 1 | +0.0000072 | [−0.000118, +0.000135] |

## Decision (pre-registered): keep proportional

No method meets the rule (log-loss better with Holm p < 0.05, a Brier CI at or below 0, and at least 0.0005 better). Every difference is under 0.0001 log-loss, and every interval includes 0. C0 keeps the proportional devig, and the protocols are unaffected.

## What the closing moneyline looks like (descriptive, not a pre-registered test)

These figures come from `bt_calibration`, a Wald 95% interval.
- The proportional calibration slope is **1.025 [0.940, 1.110]**.
- The intercept-in-the-large is **−0.047 [−0.111, +0.017]**.
- Home teams won **56.0%** of these games and were priced at **57.0%**.
- Both intervals include the well-calibrated values (slope 1, intercept 0).

So over 17 seasons the devigged close shows no significant miscalibration, and no significant overpricing of the home team. The favourite–longshot pattern in the table is small: favourites (p ≥ 0.75) won 2.3 points more often than priced under proportional devig. It is not tested here.

**What this means for beating the market.** How the vig is removed is not a source of edge. Any edge has to come from information the close does not yet price (the pre-close track, M2) or from thinner markets (M7).
