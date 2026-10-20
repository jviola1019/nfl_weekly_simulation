# Design: beating the market before the close (pre-close validation, `nfl_preclose_v1`)

**Status:** **approved by the owner on 2026-10-20.** The answers were "Approve as designed": few confirmatory candidates, and the 36-feature opener screen kept exploratory with its MDE; and "Port builder + inputs": v2's feature builder, input builder and `backtest/data_v2/` go into `backtest/vvf/`. Nothing in it is scored yet. It specifies master-plan steps A3 (variable ledger plus validation framework) and A4–A5 (the pre-close protocol), in `docs/superpowers/plans/2026-10-19-preclose-and-app-master-plan.md`. Task-level plans are written from it with `superpowers:writing-plans` and dry-run before execution.

**Owner requests** (2026-10-19, verbatim): "attempt to defeat market prior to close time. Use full testing, model architecture, variable fixing, ANOVA/statistical validations for variables … If cannot pass, still show modeling on HTML but note largely at top." Decision time: "Opener + live snapshots".

## 1. What we already know, and what it implies

| Evidence | Number | Source |
|---|---|---|
| No candidate beats the no-vig **close** | Model-only candidates are 4.5–5.6% worse on Brier; anchored blends are indistinguishable from the close | `reports/2026-09-29/backtest-games-v1/RESULT.md:3` |
| 36 point-in-time features **beyond the close** (LR / F screen, Tune 2018–22, about 1,370 games) | Moneyline: min q 0.49; joint χ² 26.9, p = 0.63. Spread: time-zone travel −0.88 pts per zone, q = 0.15 | `reports/2026-09-30/validation-sprint/REPORT.md` §1 (PR #205) |
| CLV from the ESPN BET **opener** to the close (2024) | C2 +93 bps [+40, +149], 214 picks; K[E1] +66 bps [+8, +125], 199 picks. Both below the 400-pick gate | v1 `RESULT.md:103-110` |
| Per-pick CLV noise | σ = 514 bps; 400 picks gives power 0.831 for +100 bps with 8 candidates (Bonferroni) | `reports/2026-09-29/clv-power/output.txt` |
| Opener coverage (D1 archive) | Both opener and close: 2023 **205** of 285 (weeks 1–5 have no opener); 2024 **284** of 285 | D1 plan, Task 9 |
| **Power of an opener-anchored screen** | Minimum detectable effect per SD, in log-odds (80% power, α = 0.05) — see the table below | `reports/2026-10-20/preclose-design/mde.R` → `mde_output.txt` |

| n | Single test | 36 features (Bonferroni) |
|---|---|---|
| 205 | 0.417 | 0.601 |
| 284 | 0.354 | 0.511 |
| 489 | 0.270 | 0.389 |

For scale, 0.25 log-odds at p = 0.5 is 6.2 probability points.

**Implications:**
1. **A close-anchored null does not answer the pre-close question.** Information that reaches the market between open and close (injury reports, weather forecasts, QB news, informed money) is already in the close. The pre-close question has two parts: (a) is the outcome predictable beyond the **opener**, and (b) is the **movement** from open to close predictable?
2. **A broad opener-anchored screen cannot confirm anything on 2023–24.** With n = 205 (Tune 2023) it detects only effects of about 0.42 log-odds per SD or more, roughly 10 probability points per SD. Real NFL effects are far smaller. So the confirmatory part of the protocol tests **few, pre-declared hypotheses**. The 36-feature opener screen is **exploratory**: it is reported, and it never promotes a candidate.
3. **Confirmation comes from data not used for any choice:** the 2025 Holdout, scored once, and the prospective 2026 season.

## 2. Decision times and information sets

A feature may enter a decision only if it was **known at** that decision time. Every feature in the ledger (§5) declares its `known_at` class:

| `known_at` class | Becomes known | Examples |
|---|---|---|
| `schedule` | When the schedule is published | Rest days, division, roof and surface, neutral site, weekday, kickoff slot, venue, travel distance, time-zone shift |
| `results_w-2` | After week w−2's last game | Team form, Elo, EPA, the GLMM prior, using results through week w−2 |
| `results_w-1` | After week w−1's last game, Monday night or Tuesday | The same, through w−1 |
| `qb_prev_start` | After week w−1 | The previous game's starting QB |
| `injury_<day>` | When that day's report is published (Wed, Thu, Fri) | Status-weighted injury index |
| `weather_fcst_<t>` | When the forecast issued at time t | Forecast wind and temperature |
| `gameday` | Kickoff | Actual starters, observed weather: post-hoc diagnostics only |

**Decision points:**

| Point | Price | Information set | Use |
|---|---|---|---|
| **Opener** (historical, 2023–25) | ESPN BET opener, no-vig | **IS-A (primary):** `schedule`, `results_w-2`, `qb_prev_start` | Confirmatory |
| Opener | Same | **IS-B (secondary):** IS-A plus `results_w-1` | Labelled "may not be executable", until the opener-timing study (master plan A0) shows openers post after w−1's games |
| **Tue 18:00Z** (prospective 2026) | Kalshi mid at the first hourly candle at or after 18:00Z; ESPN capture from the Tue run (A0) | IS-B (results through w−1 are known by Tuesday) | Prospective |
| **Fri 21:00Z** (prospective 2026, exploratory) | Kalshi mid at or after 21:00Z; ESPN capture | IS-B plus `injury_fri` | Exploratory: tests open-to-close information |

`vvf_assert_known_at(features, decision)` stops when any feature's class falls after the decision point. It generalises `bt_assert_asof` (`backtest/common.R:38`) from dates to classes.

## 3. Targets and anchors

- **Outcome:** y = 1 if the home team wins; ties are excluded. The **anchor** is `lp_open` = logit of the no-vig opener (proportional devig of ESPN BET's moneyline pair).
- **Movement:** Δ = logit(p_close) − logit(p_open), at the same venue (ESPN BET), where both exist.
- **Spread and total** (secondary family): residuals against the opener's spread and total lines, where ESPN carries them. Coverage: 192 of 285 in 2023, 284 in 2024.

## 4. The validation framework (`backtest/vvf/`)

The framework uses no new packages (`sandwich`, `lmtest` and `car` are locked). It ports `bt2_screen_one` and `bt2_screen_joint` (PR #205, `backtest/v2/screen.R`) with attribution, along with the point-in-time feature builder and inputs they need (`backtest/v2/features.R`, `build_inputs.R`, `backtest/data_v2/`, sha256-locked).

**S0, provenance.** Every feature has a ledger row (§5). The stages refuse any feature that has no row or whose `known_at` falls after the decision.

**S1, screen (the "ANOVA" question)**, for each feature x and each family:
- **Outcome:** `glm(y ~ 1 + x, offset = lp_anchor, binomial)` against `glm(y ~ 1, offset = lp_anchor)`, a likelihood-ratio χ²(1). This equals `anova(m0, m1, test = "Chisq")`; a known-answer test checks that.
- **Movement:** `lm(Δ ~ 1 + x)` against `lm(Δ ~ 1)`, an F test.
- **Robust SE:** week-clustered (`sandwich::vcovCL`, HC0). With fewer than 30 week clusters the robust p comes instead from a **wild cluster bootstrap-t**: Rademacher weights, B = 9,999, a fixed seed, and the null imposed.
- **Combined p:** p = max(p_model, p_robust).
- **Correction:** BH within each family and anchor. Report the effect per SD and its CI, the **MDE per SD** at the observed n (the formula in `mde.R`), and a verdict: "no evidence (MDE = …)" against "signal (q < 0.05)".
- **The anchor is a parameter,** so the same code reruns v2's close-anchored screen. Reproducing v2's §1 numbers (joint χ² 26.9, p = 0.63; the time-zone spread effect −0.88, q = 0.15) is a **known-answer test** of the port.

**S2, structure:**
- **Collinearity:** VIF ≤ 5 among features entered together (`car::vif`). If a pair exceeds that, keep the one declared first and log the other.
- **Season stability:**
  - per-season signs;
  - a feature × season LR test;
  - for the opener windows, which cover only 2023–24, the season halves (weeks ≤ 9 against later). These are labelled weak.

**S3, incremental skill** (the only stage that can support a claim):
- Base model: logit(p) = lp_anchor + β·x, refit every week on all earlier weeks (expanding window), predicting week w.
- Paired loss differences (Brier and log loss) against the anchor alone.
- Week-block bootstrap, B = 10,000 (`bt_boot_counts`, `bt_score_window`).
- DM-HLN (`bt_dm_hln`).
- BH over a **declared order** of hypotheses.

**S4, controls** (any failure voids the run):
- **Leak canary:** append an absurd future game; every feature value for earlier games is unchanged (`bt_control_canary`).
- **Placebo:** 200 independent N(0,1) noise features through S1 at α = 0.05. The rejection rate must lie in [0.020, 0.080], the binomial 95% band around 0.05 for 200 draws.
- **Shuffled labels:** permute y within week (`bt_shuffle_scores`); every S3 skill CI must include 0.
- **Anchor copy:** a candidate equal to the anchor gives skill exactly 0.
- **Reproducibility:** a second run gives the same `result_sha256`.

**Known-answer tests:**
- **Planted effect:** with y simulated from logit p = lp_open + 0.5·z (n = 2,000, z standardised), S1 rejects with p < 0.01.
- **Null rate:** over 500 null simulations, the false-positive rate is within the binomial band.
- **Port fidelity:** the LR statistic equals the deviance difference in `anova()`, and v2's §1 numbers are reproduced.

## 5. The variable ledger (`docs/VARIABLE_LEDGER.md`, generated)

A machine-readable registry, `backtest/vvf/registry.R`, has one entry per variable:
- name, definition and source (file and function);
- the `known_at` class;
- unit test(s);
- known defects and their audit IDs;
- the fixing phase;
- the latest S1, S2 and S3 results per anchor, with the run sha.

`scripts/write_variable_ledger.R` renders it. A docs-truth test fails if the document and the registry disagree.

The fixes the master plan names (HFA/rho/points-cap windows, the GLMM prior, the QB starter, the `LAR`/`LA` time zone, injuries, weather, neutral-site travel, the turnover NA rule, the silent substitutions, the duplicate loaders) are tracked as defects on their variables' rows. Each is closed by the phase that owns it.

## 6. `nfl_preclose_v1`: candidates, endpoints, gates

**Confirmatory candidates.** Their hyperparameters are frozen before Tune is scored, and BH runs across these four:

| ID | Definition | Hypothesis |
|---|---|---|
| **PC-C2** | v1's C2 (EPA GLM, halflife 8, λ 100) on IS-A features | The model's view at the opener beats the opener |
| **OA[E1]** | Ridge logistic `y ~ lp_open + logit(E1)`. λ is chosen once from {0.1, 1, 10} by walk-forward log loss on Tune 2023, then frozen. Training rows are earlier games with an opener, at least 100 of them | The anchored blend beats the opener |
| **LM[E1]** | Movement model Δ̂ = a + b·(logit E1 − lp_open), OLS, walk-forward | The model predicts where the line moves |
| **C3@open** | `predict_week(asof = opener)` from G1, with admitted terms only | The simulator at the opener. Included only if G1 is merged before the freeze |

E1 and K[E1] are reported descriptively. The 36-feature opener screen (S1) is **exploratory**.

**Picks for CLV:**
- **Side:** for the home team when p_model − p_open ≥ τ, for the away team when p_open − p_model ≥ τ, with τ = 0.03 (v1's threshold).
- **CLV in bps** = 10,000 × (p_close_novig(side) − p_open_novig(side)), at the same venue (`bt_clv`).

**Endpoints.** The Holdout decides. Confirm is secondary evidence.

| Gate | Rule |
|---|---|
| P1 accuracy | Brier skill against the no-vig opener > 0, with the week-block bootstrap 95% CI lower bound > 0 |
| P2 significance | DM-HLN one-sided p < 0.05 after BH across the confirmatory candidates |
| P3 calibration | The calibration slope CI covers 1, and ECE ≤ ECE(opener) + 0.005 |
| P4 movement (LM only) | Slope b > 0 with CI lower bound > 0. Movement skill 1 − Σ(Δ̂ − Δ)² / ΣΔ² > 0 |
| P5 value | The A2 CLV gate: at least 400 picks pooled over Confirm and Holdout, mean ≥ +100 bps, CI lower bound > 0 |
| P6 controls | Everything in S4 passes |
| P7 implausibility | A candidate whose skill against the opener **exceeds the close's own skill against the opener** voids the run, as evidence of a leak |

**Windows:**
- Base-model training: 2010–22.
- **Tune 2023:** 205 games, used for the only free choice (OA's λ).
- **Confirm 2024:** 284 games.
- **Holdout 2025:** built and scored once, by a single build shared with `nfl_games_v2` (A2 decision 3), after the owner signs.
- **Prospective 2026** (§7).

**Disclosures** (part of the protocol text):
- v1 already looked at 2024 opener CLV for C1, C2, E1 and K[E1]. 2024 is therefore secondary evidence for PC-C2.
- 2025 ESPN opener and close prices, together with 2025 scores, were read once, on 2026-09-29, by `reports/2026-09-29/clv-power/clv_power.R` for the A2 power analysis. No model, threshold or feature was chosen on them. The 400-pick gate's σ came from that study.
- A test makes backtest code refuse that file.

**Realism.** With σ = 514 bps, a +100 bps edge needs about 375 picks across the candidates. v1 made 214 picks from 284 games, and Confirm plus Holdout gives roughly 400. **A null is the expected outcome, and it will be published**, and the app's banner (master plan B1) states it at the top of every page.

## 7. The prospective 2026 track
- **Decision points:** Tuesday 18:00Z (primary) and Friday 21:00Z (exploratory), as in §2.
- **Prices:** the Kalshi mid at the first hourly candle at or after the decision time, plus the ESPN capture once A0 is live (merged 2026-10-19, #214). The close follows D1's closing rule.
- **Lock:** each week's bundle is written and archived before the first kickoff of the window. `backtest/v2/track_append.R` already refuses late bundles; the plan ports it.
- **Evaluation:** a single look after week 18, with every weekly report labelled interim. The 2026 sample is reported separately and never pooled into Tune.

## 8. Owner checkpoints this design creates
1. Approve this design: the information sets, the confirmatory candidates, the gates, and the treatment of the exploratory screen.
2. Port v2's builder and data into `backtest/vvf/`. This follows the decision to "port the screen code" and extends it to the inputs the screen needs.
3. Sign `nfl_preclose_v1`'s PROTOCOL.md: its hash goes into `backtest/eval_windows/nfl_preclose_v1.json`, an owner-approved new file.
4. Open the 2025 Holdout, once, for both protocols.
