# Game backtest protocol `nfl_games_v2` (DRAFT, not frozen)

**Status: DRAFT for owner review.** Nothing below may be scored until the owner approves it. Then this file is renamed `PROTOCOL.md`, its sha256 is written into `backtest/eval_windows/nfl_games_v2.json`, and both are committed before any Confirm or Holdout scoring, exactly as in v1. After that, any change means a new version.

- **Builds on:** `reports/2026-09-29/backtest-games-v1/PROTOCOL.md` (frozen). The data, windows, walk-forward mechanics, metrics and statistics are unchanged unless stated below.
- **Evidence behind the choices:** `reports/2026-09-30/validation-sprint/` (Tune window only).

## 1. Questions

1. **Moneyline:** does any market-anchored blend give home-win probabilities with a lower Brier score than the no-vig close, on data never used for any choice?
2. **Spread (one pre-registered hypothesis, H-TZ):** do away teams cover less the more time zones they cross (the one effect the Tune screen flagged, q = 0.15)?

A null result is reported as a null result.

## 2. What was seen before this protocol (disclosure)

- **Moneyline:**
  - The v1 Tune and Confirm results were viewed: no candidate beat the close.
  - The decisions to anchor every candidate on the market and to drop pure models were informed by v1, **including Confirm**.
  - So for moneyline, Confirm 2023–24 is **secondary** evidence only, and the decisive window is the sealed 2025 Holdout.
- **Spread and totals:** no one has analysed 2023–2025 for spreads or totals. The Tune screen (2018–2022) produced H-TZ. For H-TZ, 2023–2025 are unseen.
- **Holdout 2025:** sealed. No 2025 row has been read, built or scored by any backtest or sprint code.

## 3. Data

- **v1 inputs:** `backtest/data/` (unchanged, sha-locked).
- **v2 context inputs:** `backtest/data_v2/` (sha-locked in `SOURCES.json`).
- **At freeze:**
  - Both are rebuilt for seasons ≤ 2025 and locked.
  - The 2025 rows are appended only by the build that creates the Holdout inputs, and only after the freeze.
  - That build runs once and records the sha256 of every raw file.

## 4. Candidates (frozen hyperparameters; nothing is tuned after the freeze)

The reference is **C0**: the no-vig closing moneyline (nflverse consensus, proportional devig).

| Label | Definition (as implemented in `backtest/v2/models.R` at the freeze commit) | Why it is in |
|---|---|---|
| **L1** | Ridge logistic `y ~ 1 + logit(C0) + logit(E1)`, λ = 0.1, intercept unpenalised. Refit weekly on every earlier game from 2010 (this is v1's B1[E1]). | The simplest anchored blend |
| **G1** | Elastic net (α = 0.25), market term unpenalised, model-vs-market gaps plus 28 situational features, standardised on the training weeks. λ = `lambda.1se` from season-grouped CV on the training weeks only. | Best Tune point estimate (+0.03%) |
| **X1** | xgboost anchored on the market (`base_margin = logit(C0)`), same features. eta 0.02, depth 2, min_child_weight 30, subsample 0.8, colsample 0.8, λ 10. Rounds by early stopping on the most recent 267 training games, then refit. | Owner asked for boosting; the best boosted variant |
| **C3** | The production simulator, only if Phase 1b makes it point-in-time before the Holdout is scored (A2 decision 3). Otherwise it is not scored in v2. | – |

**Calibration:** none for every candidate. On Tune, calibration maps did not help anchored blends, and isotonic hurt. Four candidates at most, which is fewer than v1's eight, so the power per test is higher.

## 5. Endpoints and gates (moneyline)

These are the same gates as v1 (G1–G4), applied on the **Holdout (2025)**:
- **G1:** Brier skill vs C0 > 0, with the 95% week-block bootstrap CI (B = 10,000) lower bound > 0.
- **G2:** Diebold–Mariano (HLN) one-sided p < 0.05 after Benjamini–Hochberg across the scored candidates.
- **G3:** the calibration slope CI covers 1, and ECE ≤ ECE(C0) + 0.005.
- **G4:** all controls pass (leak canary, shuffled labels, market copy, reproducibility).

**Confirm (2023–24)** is scored with the same code and reported as secondary evidence. It cannot promote a candidate by itself.

**Betting value (separate from Brier):**
- CLV at the opener where decision-time prices exist: ESPN 2023–2025 after the Part B item 16 coverage check, and Kalshi.
- CLV bps = 10000 × (p_close_novig − p_taken_novig) for the side taken.
- The 400-pick gate from A2 applies (mean ≥ +100 bps with the CI lower bound > 0).

## 6. H-TZ (spread)

- **Model:** OLS of (home margin − spread_line) on `abs_tz_away` over all 2023–2025 games with a spread line and no push.
- **Test:** one-sided test that the coefficient is < 0, with week-clustered robust SE, α = 0.05.
- **Secondary:** flat bets on the home side when `abs_tz_away ≥ 2`, at the closing spread price. Report the hit rate against the break-even rate at the prices taken (Wilson CI), and ROI.
- H-TZ is a single test, so no multiplicity correction applies.

## 7. Scoring events

1. **After approval and the freeze:** Confirm (moneyline, secondary) is scored once.
2. **Once C3 is point-in-time (or the owner decides to go without it):**
   - The 2025 Holdout inputs are built, and moneyline and H-TZ are scored **once**.
   - Nothing is refit or reselected afterwards.
   - The result, including a null, goes into `RESULT.md` and `docs/EVIDENCE_LEDGER.md`.
3. **Prospective 2026 weeks** are graded as they finish (`backtest/v2/track_append.R`) and reported as a separate, growing sample.

## 8. Controls

These are the same as v1, plus the v2 shuffled-label control on the blend layer (`bt2_control_shuffle`). A failed control voids the run.
