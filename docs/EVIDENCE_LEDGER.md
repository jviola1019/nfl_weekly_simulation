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
| C-POSW | Position injury weights "validated p < 0.001" | `p < 0\.001` | unvalidated | No saved test output found; re-test in Phase 3 | reports/2026-09-28/AUDIT.md (M7) |
| C-SHRINK | "60%" / "70%" market shrinkage | – | unvalidated | Effective weight ≈65.5% via two stages plus anti-shrink (M2, M3); fixed in Phase 1 | reports/2026-09-28/AUDIT.md (M2, M3) |
| PROP_GAME_CORR_PASSING | 0.40 | – | unvalidated | Config value; to be estimated point-in-time in Phase 4 | config.R |
| PROP_GAME_CORR_RUSHING | 0.09 | – | unvalidated | as above | config.R |
| PROP_GAME_CORR_RECEIVING | 0.30 | – | unvalidated | as above | config.R |
| PROP_GAME_CORR_TD | 0.17 | – | unvalidated | as above | config.R |
