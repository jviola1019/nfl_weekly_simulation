# nfl_preclose_v1: beating the opener with what was known at the opener

**Signed 2026-11-02.** The owner's instruction of 2026-11-02 to complete the listed decisions included signing this protocol and letting 2025 enter as model history, never scored. This file is frozen. Its sha256 is in `backtest/eval_windows/nfl_preclose_v1.json`, and any change needs a new version.

The design is `docs/superpowers/specs/2026-10-20-preclose-validation-design.md`, approved 2026-10-20 (§2, §3, §6, §7). This text fixes every choice that design left open; where they differ, this text governs.

## The question

Do models built only from information known when the opener is posted beat that opener? There are two ways to beat it:
- **accuracy beyond the opener:** Brier skill against the opener's no-vig probability;
- **predicting the move:** closing-line value (CLV), the move from the open to the close.

## Information set IS-A (confirmatory)

A game of week w of season s uses only:

| Class | What | Cutoff |
|---|---|---|
| `schedule` | Home field (not neutral) and rest days, as v1's `d_rest`, capped at ±7 | Known in advance |
| `results_w-2` | Team EPA states (v1's C2 estimator) and Elo ratings | Every game that kicked off before the first kickoff of week w−1 of season s. For w = 1 or 2, no game of season s |
| `qb_prev_start` | The QB who started the team's previous game, with his own EPA state at the same cutoff | — |

- **Playoffs:** a playoff week w (19–22) uses the first kickoff of week w−1 the same way.
- **IS-B, secondary and exploratory:** IS-A plus week w−1's results and the game's actual starter. This is v1's C1 and C2 as committed.
  - The post-hoc diagnostic `opener_timing_elo.R` suggests ESPN BET's 2023–2024 openers already priced week w−1's results.
  - IS-B stays secondary all the same.

## Anchor, targets and venues

- **The outcome:** y = 1 when the home team wins; ties are excluded.
- **The anchor:** p_open, the proportional no-vig moneyline opener, with lp_open = logit(p_open).
- **The close** is the same venue's: p_close. The move is Δ = logit(p_close) − lp_open.
- **Venues:**
  - 2023–2024: ESPN BET, from D1's archive (`backtest/data/odds_archive/`).
  - 2026: DraftKings as ESPN reports it (provider 100), fetched after each game by `fetch_espn_open_close.R`.
  - 2025: ESPN BET, sealed.

## Candidates (confirmatory; BH across the three)

| ID | Definition |
|---|---|
| **PC-C2** | v1's C2 (EPA ridge logistic, halflife 8, λ 100, v1's ten features) with every feature on IS-A, for target and training games alike. It is refit each week on every earlier game: seasons from 2008, no ties, kickoff before the target week's IS-A cutoff |
| **OA[E1]** | Ridge logistic y ~ 1 + lp_open + logit(E1ᴬ), with the intercept unpenalized, as v1's B1 does with the close.<br>• **E1ᴬ** is v1's E1 (`bt_e1`, the logit average) of PC-C2 and v1's Elo on IS-A (K 20, home field 30, regression 0.45).<br>• **Training:** refit each week on earlier games with an opener, at least 100 of them.<br>• **λ:** chosen once from {0.1, 1, 10} by log loss on Tune 2023, then frozen |
| **LM[E1]** | The move model Δ̂ = a + b·(logit E1ᴬ − lp_open), OLS, refit each week on earlier games with an open and a close, at least 100 of them |

- **C3@open is not included.** G1 is not merged at signing, and the design admits C3@open only if it is.
- **OA and LM training rows** are games that kicked off before the target week's IS-A cutoff, the first kickoff of week w−1, so their results were known at the opener.
  - They never include 2025: its prices are sealed.
  - A 2026 prediction trains on 2023–2024 and the earlier 2026 weeks.

## Windows

| Window | Use |
|---|---|
| Training history | PC-C2 is fit on games from 2008 up to each target week's cutoff (features from 2006, as v1) |
| **Tune 2023** | The only free choice: OA's λ. Every candidate is scored there too |
| **Confirm 2024** | Secondary evidence |
| **Holdout 2025** | Sealed. Built and scored once, shared with `nfl_games_v2`, after the owner opens it (checkpoint 8). **It decides** |
| **2026, weeks 9–18** | Prospective. Predictions are made before each week's games; one look after week 18 |
| 2026, weeks 1–8 | A pilot, computed after this signing (the predictions are point-in-time by construction). Reported separately, never pooled |

**2025 enters only as history:** its games, play-by-play and QB starts feed the 2026 features and fits. No 2025 prediction, price or score is computed.

## Picks and CLV

- **Picks:** home when p_model − p_open ≥ 0.03, away when p_open − p_model ≥ 0.03 (v1's τ). For LM, p_model = expit(lp_open + Δ̂).
- **CLV in bps** = 10,000 × (p_close(side) − p_open(side)), at the same venue (`bt_clv`).

## Gates (the design's §6)

| Gate | Rule |
|---|---|
| P1 accuracy | Brier skill against p_open > 0, with the week-block bootstrap's 95% lower bound > 0 (`bt_score_window`, B = 10,000, seed 20260929) |
| P2 significance | DM-HLN (`bt_dm_hln`, h = 1) on the per-game Brier difference against p_open, one-sided p < 0.05 after BH across the three candidates |
| P3 calibration | Calibration slope CI covers 1 (`bt_calibration`), and ECE ≤ ECE(p_open) + 0.005 (`bt_ece`, 10 bins) |
| P4 movement (LM only) | Slope b > 0 with a CI lower bound > 0, and movement skill 1 − Σ(Δ̂ − Δ)² / ΣΔ² > 0 |
| P5 value | At least 400 picks pooled over Confirm and Holdout, mean ≥ +100 bps, CI lower bound > 0 (`bt_clv`) |
| P6 controls | VVF S4: the leak canary, the placebo band, the anchor copy and reproducibility, plus the anchor null and the permuted-x null (below) |
| P7 implausibility | A candidate whose Brier skill against p_open exceeds the close's own voids the run, as evidence of a leak |

- **P6's null, a ruling at signing.** The design's within-week label shuffle fails by construction for a model anchored to the market. Shuffled labels break the anchor, so a feature that tracks the anchor then "beats" it (`reports/2026-10-28/a3-research/RESEARCH.md`). P6 therefore gates on the researched nulls, which `backtest/vvf/s4_controls.R` implements, and reports the shuffle without gating on it. This is the S4 amendment.
- **Verdict:** a candidate is confirmed when it passes P1–P3 and P6 on the Holdout without tripping P7 (and P4, for LM). Its value is confirmed by P5. Confirm and 2026 are reported beside it with the same statistics.

## The Tuesday track (the design's §7; prospective, exploratory)

- **Decision:** Tuesday 18:00 UTC before each week, information set IS-B (results through w−1 are known by then).
- **Candidates:** v1's C2 and E1 (IS-B), with 2025 as history.
- **Price:** the Kalshi `KXNFLGAME` mid at the first hourly candle at or after 18:00 UTC. The close is Kalshi's last candle at or before kickoff. The ESPN capture's price from the same Tuesday is reported where it exists.
- **Statistics:** P1–P3 and the CLV of τ-picks against the Tuesday mid.
- **Windows:** weeks 9–18 are prospective, with one look after week 18. Weeks 1–8 are a pilot.

## Disclosures (what was already seen)

- **v1** looked at 2024 opener CLV for C1, C2, E1 and K[E1], all on IS-B.
- **T1** (2026-11-02) looked at 2023 for the same IS-B candidates. C2 gained +85 bps and Elo nothing.
- **T2** looked at SBR's 2018–2021 spreads for C1 and C2 (IS-B).
- **The timing diagnostic** looked at Elo on IS-A at ESPN BET 2023–2024 (−27 bps, null) and at SBR.
  - **E1ᴬ's Elo half has therefore been seen.**
  - **PC-C2 itself has never been computed** on any season.
- **2025 ESPN prices,** with 2025 scores, were read once on 2026-09-29 by `reports/2026-09-29/clv-power/clv_power.R` for the power analysis. No choice was made on them.
- **Power:** with σ = 514 bps per pick, a +100 bps edge needs about 375 picks. Confirm plus Holdout gives roughly 400. **A null is the expected outcome, and it will be published.**

## Code

- **Registered later, choices fixed now.** The scoring code is written after signing, from this text, and committed before any confirmatory number is read. It is registered by its sha256 in an amendment that may change no choice above.
- **Known-answer tests come first:**
  - PC-C2's builder with no lag (IS-B, the actual starter) reproduces v1's C2 predictions.
  - The Elo on IS-A matches `opener_timing_elo.R`'s.
  - `bt_clv` reproduces T1's 2023 numbers from v1's C2.
