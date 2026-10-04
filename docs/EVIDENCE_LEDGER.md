# Evidence ledger

Every quantitative or "validated" claim about this model is listed here with its status.
A claim becomes **validated** only through a backtest run that passed the promotion gates
(spec §5 Phase 3/5). Statuses: validated · reproducible · unvalidated · withdrawn.

| claim_id | claim | pattern | status | reason | evidence |
|---|---|---|---|---|---|
| C-BRIER | Brier 0.211/0.214 on 2022–2024 | `0?\.21[14]\b` | withdrawn | No script with saved output reproduces it; 0.2115 hardcoded | reports/2026-09-28/AUDIT.md (M7) |
| C-GAMES | 2,282 games 2022–2024 | `2,?282` | withdrawn | 2022–2024 has ≈855 games | reports/2026-09-28/AUDIT.md (M7) |
| C-ACC | 67.1% accuracy | `67\.1\s*%` | withdrawn | Hardcoded, cites nonexistent RESULTS.md | reports/2026-09-28/AUDIT.md (M7) |
| C-SPLINE | Spline calibration −6.9% Brier | `(?<![0-9])6\.9\s*%` | withdrawn | Calibrator trained on outcome-leaked probabilities | reports/2026-09-28/AUDIT.md (M4) |
| C-RANK | "#2 vs professional models", 538 0.215 / FPI 0.218 | `Rank\s*#?2\|#2 vs professional\|FiveThirtyEight \(0\.215\)\|FPI \(0\.218\)` | withdrawn | Mock benchmark data | reports/2026-09-28/AUDIT.md (M7) |
| C-CORR | Prop correlations r=0.75/0.60/0.50/0.40 "empirically validated" with CIs | `r = 0\.75\|0\.75 \[0\.72\|empirically validated` | withdrawn | Config uses 0.40/0.09/0.30/0.17; no saved analysis | reports/2026-09-28/AUDIT.md (D1) |
| C-PROD | Model status "production-ready" | `[Pp]roduction-[Rr]eady` | withdrawn | No backtest has passed the promotion gates; status is "unvalidated research model" | reports/2026-09-28/AUDIT.md (D1) |
| C-ADJ | Injury, weather and other adjustments "statistically validated" / "validated with p < 0.05" | `statistically validated\|validated with p` | withdrawn | No saved test output reproduces the p-values; adjustments are config values | reports/2026-09-28/AUDIT.md (D1) |
| C-POSW | Position injury weights "validated p < 0.001" | `p < 0\.001` | unvalidated | No saved test output found; re-test in Phase 3 | reports/2026-09-28/AUDIT.md (M7) |
| C-SHRINK | "60%" / "70%" market shrinkage | – | unvalidated | Single 70% market weight since Phase 1a (was ≈65.5% via two stages plus anti-shrink, M2, M3). For the Elo+EPA ensemble, Tune selects a 95% market weight (BT-V1-B2W); the simulator is judged in nfl_games_v2 | reports/2026-09-28/AUDIT.md (M2, M3) |
| C-MU-TERMS | The simulated mean is expected drives × points per drive, plus home field for the home team (`MU_TERMS_ADMITTED` = base, hfa); every other adjustment is computed and logged, not simulated | – | unvalidated | The explicit form of what the engine already simulated (audit M22: 16 of 16 games identical). A term is added only through the Plan 1b-3 walk-forward admission rule | reports/2026-10-01/phase1b-1-evidence/m22_terms.out.txt; reports/2026-09-29/golden-master/2024-w15/ATTRIBUTION.md#phase-1b-1-210-explicit-model (CI-attributed: composing the admitted terms changed no output) |
| PROP_GAME_CORR_PASSING | 0.40 | – | unvalidated | Config value; to be estimated point-in-time in Phase 4 | config.R |
| PROP_GAME_CORR_RUSHING | 0.09 | – | unvalidated | as above | config.R |
| PROP_GAME_CORR_RECEIVING | 0.30 | – | unvalidated | as above | config.R |
| PROP_GAME_CORR_TD | 0.17 | – | unvalidated | as above | config.R |
| BT-V1-BRIER | No game candidate (Elo, EPA GLM, their ensemble, market blends, calibrated ensemble) beats the no-vig closing moneyline on Brier, Confirm 2023–2024, 570 games | – | reproducible | Negative result of the pre-registered walk-forward backtest nfl_games_v1; all controls passed; result_sha256 7244a0bc… | reports/2026-09-29/backtest-games-v1/RESULT.md |
| BT-V1-C0 | No-vig closing moneyline: Brier 0.2098, log loss 0.6081 on 2023–2024 (570 non-tie games) | – | reproducible | Benchmark C0 in nfl_games_v1 | reports/2026-09-29/backtest-games-v1/metrics.json |
| BT-V1-B2W | Fixed-weight shrink of the Elo+EPA ensemble toward the close selects a 0.95 market weight (top of the 0.50–0.95 grid) | – | reproducible | Tune 2018–2022 log loss falls monotonically as the model weight falls | reports/2026-09-29/backtest-games-v1/metrics.json |
| BT-V1-CLV | EPA GLM picks at the ESPN BET opener: mean CLV +93 bps, 95% CI +40 to +149 (2024, 214 picks) | – | unvalidated | Descriptive only: below the 400-pick single-look gate (A2), one season, four candidates examined, flat ROI −7%; candidate for a single pre-registered prospective hypothesis | reports/2026-09-29/backtest-games-v1/RESULT.md |
