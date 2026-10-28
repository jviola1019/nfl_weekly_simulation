# A3b: Incremental Skill, Controls and Diagnostics (VVF S3–S5) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add S3 (walk-forward incremental skill over the anchor), the S4 negative controls, and the S5 diagnostics (validation and learning curves, Murphy decomposition, calibration, bias–variance, CRPS/PIT, smoothing checks, loss ANOVA). Run them close-anchored on Tune 2018–2022, and show S3 in the ledger.

**Architecture:** Every module is new under `backtest/vvf/`, beside A3a's S0–S2. The code was built and tested in the dry-run tree `../nfl-worktrees/a3dry` (A3 planner log steps 9–13). Each task copies its test from there first (RED), then its code (GREEN), and commits. Four pieces are new work beyond the dry run:
- S3 calls A3a's anchor and seal guards.
- S4 gains a permuted-x null.
- The ledger gains an S3 column.
- The S4 diagnostic is committed as evidence.

**Tech Stack:** R 4.5.1 (renv), data.table, testthat 3; `forecast` (locked) for the ETS alpha. No new package.

**Spec:** `docs/superpowers/specs/2026-10-20-preclose-validation-design.md` §4 (S3, S4) on #211, and the A3 amendment `.superpowers/research/a3-amendment-2026-10-21.md` (S5) in the roadmap worktree. A3a's plan, `docs/superpowers/plans/2026-10-27-a3a-validation-framework.md`, gives the conventions this plan follows.

## Global Constraints

- **Stacked on `feat/a3a-vvf`** (PR #225, `1c48ed4`). The branch is `feat/a3b-vvf`, in worktree `../nfl-worktrees/a3b`.
- **No new packages:** `renv.lock` and `DESCRIPTION` stay byte-identical.
- **The 2025 seal:** no stage reads, builds or scores 2025. Every evaluation season passes `vvf_guard_seasons`, and every table passes `vvf_guard_table` (A3a).
- **Not edited:** `config.R`, the engine files, `backtest/eval_windows/*.json`, any `PROTOCOL.md`, `R/data_validation.R`.
- **Numbers:** every number in a doc comes from a committed result file or a run log named next to it.
- **LF writers and ASCII ledger,** as in A3a.
- **Commits:** one per task, each ending with the attribution trailer of the model that makes the commit.
- **Gates:** with a fresh HOME, `scripts/run_tests.R` and `scripts/verify_repo_integrity.R` exit 0 after Task 4, after Task 9, and after the review's fix pass. Each task runs its own tests RED, then GREEN (the waiver in A3a's plan; the owner confirms it).
- **Owner STOP:** amending spec §4's shuffled-labels control. Until the owner signs it, the run's S4 status follows the spec's control.

## Review Focus

1. **An anchor-offset model scored against shuffled labels.** Permuting `y` alone miscalibrates the offset, so features that track the anchor show false skill. The spec's null failed by construction on the real Tune table: 7 of 36 intervals lay wholly above 0, and the skill correlated 0.954 with |cor(x, anchor)| (`reports/2026-10-27/vvf-s4-null/`). The permuted-x null must find no interval wholly above 0. Pinned by Task 2's "permuted-x null" test.
2. **S3 scored at an opener decision with the close as its offset.** It must stop, as S1 and S2 do (A3a C1). Pinned by Task 1's anchor test.
3. **Tuning that leaks into evaluation.** A validation curve tuned on any evaluation season, or on a sealed season, must stop. Pinned by Task 3's `vvf_assert_nested` test.
4. **The newest game not weighted most.** The engine's recency weights must give the newest game weight 1 and halve every half-life, and the weighted mean must equal an EWMA with α = 1 − 2^(−1/h). Pinned by Task 5's engine checks.
5. **A result file changed without its hash.** The ledger's S3 column and `run_meta.json` must agree. Pinned by Task 8's docs-truth test and Task 7's hash test.

---

## Setup

- [ ] **S1:** In `../nfl-worktrees/a3b`, `git log --oneline -1` shows `1c48ed4`. `git -C ../nfl-worktrees/a3dry status --short` lists `backtest/vvf/s3_skill.R` and the other A3b files as untracked; they are the source.
- [ ] **S2: Baseline** (fresh HOME): `run_tests.R` reports 522 tests, 0 failed, 1 allowlisted skip (P13); integrity reports 63 passed.

## File map

| File | Task | Responsibility |
|---|---|---|
| `backtest/vvf/s3_skill.R`, `tests/testthat/test-vvf-s3.R` | 1 | Walk-forward `anchor + b·x_c` refits; paired skill against the anchor; DM-HLN; BH over the declared order |
| `backtest/vvf/s4_controls.R`, `tests/testthat/test-vvf-s4.R` | 2 | Canary, placebo, the spec's shuffled labels, the permuted-x null, anchor copy, reproducibility |
| `reports/2026-10-27/vvf-s4-null/` | 2 | The diagnostic's script, results and RESULT.md |
| `backtest/vvf/s5_curves.R`, `tests/testthat/test-vvf-s5-curves.R` | 3 | Validation curve with the one-SE rule, the nested guard, learning curve, fit gap |
| `backtest/vvf/s5_scores.R`, `tests/testthat/test-vvf-s5-scores.R` | 4 | Murphy decomposition, calibration label, bias–variance, CRPS, NB PIT, effective df |
| `backtest/vvf/s5_smoothing.R`, `tests/testthat/test-vvf-s5-smoothing.R` | 5 | EWMA, half-life, Kalman local level, ETS alpha, and the engine weight checks |
| `backtest/vvf/s5_anova.R`, `tests/testthat/test-vvf-s5-anova.R` | 6 | Loss differences by season and by part of season; team effects |
| `backtest/vvf/run_a3b_close.R`, `tests/testthat/test-vvf-a3b-close.R`, `reports/2026-10-27/vvf-a3b-close/` | 7 | The close-anchored Tune run and its committed results |
| `backtest/vvf/ledger.R`, `tests/testthat/test-vvf-ledger.R`, `docs/VARIABLE_LEDGER.md` | 8 | The S3 column |
| `CHANGELOG.md`, `CLAUDE.md`, `HANDOFF.md` | 9 | Docs |

---

### Task 1: S3, incremental skill

**Files:** `backtest/vvf/s3_skill.R`, `tests/testthat/test-vvf-s3.R` (both from the dry run), plus the new guard test.

**Interfaces:**
- **Consumes:**
  - from A3a: `vvf_assert_known_at`, `vvf_assert_anchor(anchor, decision)`, `vvf_guard_table(d, what)`, `vvf_guard_seasons`;
  - from v1: `bt_week_schedule`, `bt_score_window`.
- **Produces:**
  - `vvf_s3_refit(d, feature, weeks, min_train = 200L) -> data.table(game_id, p, beta)`, with attribute `vvf_s3`;
  - `vvf_s3_skill(d, cands, order, ref = "p_anchor", B = 10000L, seed) -> data.table`, with one row per candidate: skill and CI, Brier and log-loss differences, DM-HLN, `verdict`;
  - `vvf_s3_screen(d, features, decision, eval_seasons, registry, B, seed) -> list(skill, predictions, meta, anchor, decision)`.

- [ ] **Step 1:** Copy `tests/testthat/test-vvf-s3.R` from the dry run. Append:

```r
test_that("S3 refuses a close anchor at an opener decision and a table with a sealed season (A3a C1, I5)", {
  withr::local_dir(PROJECT_ROOT)
  reg <- vs3$vvf_registry()
  d <- sim_s3()                                  # the file's own simulator
  data.table::setattr(d, "vvf_anchor", "close")
  expect_error(vs3$vvf_s3_screen(d, "rest_diff", "open_isa", 2023L, registry = reg, B = 99L),
               "the close anchor is known only at close")
  s <- sim_s3()
  s[1, season := 2025L]
  expect_error(vs3$vvf_s3_screen(s, "rest_diff", "open_isa", 2023L, registry = reg, B = 99L), "sealed-season guard")
})
```

  `vs3` and `sim_s3` stand for the test file's own environment and simulator names; use whatever the copied file defines.
- [ ] **Step 2:** Run `testthat::test_dir('tests/testthat', filter = 'vvf-s3')`. Expected: an error that `backtest/vvf/s3_skill.R` is not an existing file.
- [ ] **Step 3:** Copy `backtest/vvf/s3_skill.R`. In `vvf_s3_screen`, call `vvf_assert_anchor(anchor, decision)` and `vvf_guard_table(d, "the S3 table")` right after the existing check for a missing anchor.
- [ ] **Step 4:** Run the filter again. Expected: all 6 tests pass.
- [ ] **Step 5:** Commit: `feat(vvf): S3 incremental skill, walk-forward anchor + b*x refits scored against the anchor (A3b)`.

### Task 2: S4, controls, with the permuted-x null

**Files:**
- `backtest/vvf/s4_controls.R` and `tests/testthat/test-vvf-s4.R`, from the dry run;
- `reports/2026-10-27/vvf-s4-null/`: `s4_null_diagnostic.R` (the session script), `s4_null_diagnostic.csv` and `RESULT.md`.

**Interfaces:**
- **Consumes:** Task 1's `vvf_s3_refit`, `vvf_s3_skill` and `vvf_s3_screen`.
- **Produces:**
  - from the dry run: `vvf_control_canary`, `vvf_canary_append`, `vvf_control_placebo` (band 0.020–0.080), `vvf_shuffle_y(d, seed, within = c("wk", "all"))`, `vvf_control_shuffle`, `vvf_control_anchor_copy`, `vvf_control_repro`, `vvf_s4_report(controls)`;
  - new: `vvf_permute_x(d, features, seed = VVF_SHUFFLE_SEED) -> data.table`, which adds a column `perm_<f>` for each feature, permuted within `wk`, and never touches `lp_anchor`;
  - new: `vvf_control_permuted_x(d, features, eval_seasons, B, seed) -> list(passed, detail, skill)`. It passes when no `skill_lo > 0`; an interval wholly below 0 is the expected cost of fitting noise.

- [ ] **Step 1:** Copy the dry run's `test-vvf-s4.R`. Append the test `"the permuted-x null keeps the anchor offset and finds no false skill; the spec's y shuffle finds it for an anchor-tracking feature"`:
  - Simulate 40 weeks of 20 games with `lp_anchor ~ N(0.2, 0.8)`, `y ~ Bernoulli(plogis(lp_anchor))` and `a := lp_anchor + N(0, 0.3)` (it tracks the anchor).
  - `vvf_control_permuted_x(d, "a", ...)$passed` is `TRUE`, and `lp_anchor` is unchanged by `vvf_permute_x`.
  - `vvf_control_shuffle(d, "a", ...)$passed` is `FALSE`.
- [ ] **Step 2:** Run the `vvf-s4` filter. Expected: RED, `s4_controls.R` missing.
- [ ] **Step 3:** Copy `s4_controls.R`. Add `vvf_permute_x` and `vvf_control_permuted_x`. The latter permutes into `perm_<f>`, refits each with `vvf_s3_refit(dp, paste0("perm_", f), weeks)`, merges the predictions as `p_<f>` beside `p_anchor`, and scores them with `vvf_s3_skill` (the shape the diagnostic used). In `vvf_s4_report`, report it as `permuted_x` beside `shuffled_labels`, and leave the status rule unchanged: the spec's control still decides.
- [ ] **Step 4:** Commit the diagnostic. Copy the scratchpad's `s4-null-diagnostic.R` and its CSV into `reports/2026-10-27/vvf-s4-null/`. Write `RESULT.md` from the CSV:
  - the spec's null: 7 of 36 wholly above 0 (`lp_anchor` 0.100, `home_dog` 0.058, `d_e1`, `d_c1`, `d_c2`, `big_fav`, `inj_diff_all`); skill correlates 0.954 with |cor(x, anchor)|;
  - the permuted-x null: 0 of 36 above 0, and 2 wholly below 0 (`d_c2`, `inj_diff_all`);
  - B = 2,000 on Tune 2018–2022;
  - the proposed §4 amendment (owner STOP).
- [ ] **Step 5:** Run the filter. Expected: all 7 tests pass. Commit: `feat(vvf): S4 controls, and a permuted-x null that keeps the anchor offset (the spec's y shuffle fails by construction; owner decision) (A3b)`.

### Task 3: S5, validation and learning curves

**Files:** `backtest/vvf/s5_curves.R`, `tests/testthat/test-vvf-s5-curves.R` (dry run).

**Interfaces:**
- `vvf_validation_curve(grid, predict_fun, d, seasons, B, seed)`: the grid is ordered simplest first, and the one-SE rule runs on paired differences.
- `vvf_assert_nested(tune_seasons, eval_seasons, sealed)`
- `vvf_walk_forward(d, fit_predict, eval_seasons, train_rows)`
- `vvf_learning_curve(fit_predict, d, eval_seasons, n_train = 2:10)`
- `vvf_fit_gap(d, fit_predict, eval_seasons)`

- [ ] **Steps:** Copy the test, then run it: RED, file missing. Copy the code, then run it: GREEN, 5 tests. Commit: `feat(vvf): S5 validation curves with the one-SE rule, nested-tuning guard, learning curves and the fit gap (A3b)`.

### Task 4: S5, scores

**Files:** `backtest/vvf/s5_scores.R`, `tests/testthat/test-vvf-s5-scores.R` (dry run).

**Interfaces:**
- `vvf_murphy(p, y, bins = 10L)`, satisfying BS = REL − RES + UNC + WBV − 2·WBC exactly
- `vvf_calibration_label(p, y)`
- `vvf_bias_variance(pred, obs)`
- `vvf_crps_probs`, `vvf_crps_nb`, `vvf_crps_sample`
- `vvf_pit_nb(y, mu, size, seed)`, `vvf_pit_histogram(u, bins)`
- `vvf_edf_ridge(X, w, lambda, unpenalized)`, `vvf_edf(fit)`

- [ ] **Steps:** RED, then GREEN (6 tests); commit `feat(vvf): S5 scores (exact Murphy decomposition, calibration slope, bias-variance, CRPS, randomized NB PIT, effective df) (A3b)`.
- [ ] **Gate:** run the full suite and the integrity check (fresh HOME). Both exit 0.

### Task 5: S5, smoothing checks

**Files:** `backtest/vvf/s5_smoothing.R`, `tests/testthat/test-vvf-s5-smoothing.R` (dry run).

**Interfaces:**
- `vvf_ewma(y, alpha)`
- `vvf_alpha_for_halflife(h)`, which is 1 − 2^(−1/h)
- `vvf_kalman_gain(q, r)`, `vvf_snr_for_gain(K)`, `vvf_kalman_local_level(y, q, r, m0, P0)`
- `vvf_team_ets_alpha(d, team_col, value_col, order_col)`

The engine checks read `NFLsimulation.R` without editing it:
- `recency_weights` and `rec_wts` give the newest game weight 1 and halve every half-life;
- `get_recent`/`get_recent_cut` sort newest first and respect the cut;
- the steady-state Kalman filter equals the EWMA.

- [ ] **Steps:** RED, then GREEN (7 tests); commit `feat(vvf): S5 smoothing checks: the engine's recency weights equal an EWMA, the Kalman steady state, ETS alpha (A3b)`.

### Task 6: S5, loss ANOVA and team effects

**Files:** `backtest/vvf/s5_anova.R`, `tests/testthat/test-vvf-s5-anova.R` (dry run).

**Interfaces:**
- `vvf_season_part(week, phase)`
- `vvf_loss_anova(d, cand, ref, by = c("season", "part"))`
- `vvf_team_effects(d, family, response)`

- [ ] **Steps:** RED, then GREEN (3 tests); commit `feat(vvf): S5 loss ANOVA by season and part of season, and team effects (A3b)`.

### Task 7: The close-anchored Tune run

**Files:** `backtest/vvf/run_a3b_close.R`, `tests/testthat/test-vvf-a3b-close.R` (dry run), and `reports/2026-10-27/vvf-a3b-close/` (a new run on this branch; the dry run's `reports/2026-10-26/vvf-a3b-close/` is not copied).

**Interfaces:**
- **Consumes:** Tasks 1–6.
- **Produces:** `VVF_A3B_RESULT_FILES`, `vvf_a3b_table()`, `vvf_a3b_results(tab, out_dir) -> result_sha256`, `vvf_a3b_controls(tab, results_sha)`.

- [ ] **Step 1:** Copy the test, and change its report directory to `reports/2026-10-27/vvf-a3b-close`. RED: `run_meta.json` missing.
- [ ] **Step 2:** Copy the script. In `vvf_a3b_controls`, add `permuted_x = vvf_control_permuted_x(tab$full, VVF_V2_FEATURES, VVF_V2_TUNE)`.
- [ ] **Step 3:** Run `HOME=<fresh> Rscript backtest/vvf/run_a3b_close.R --out reports/2026-10-27/vvf-a3b-close` in the background (the dry run took 17.6 minutes). Expected:
  - `s4_status` is `void` under the spec's control;
  - `permuted_x` passes;
  - the S5 results match the dry run's `reports/2026-10-26/vvf-a3b-close/` (C0 Brier 0.211116; E1 part-of-season ANOVA Brier p 0.0210).
  - Any difference is diagnosed before committing.
- [ ] **Step 4:** GREEN (3 tests). Commit: `test(vvf): the A3b close run on Tune 2018-2022 (S4 void under the spec's shuffle; the permuted-x null passes) (A3b)`.

### Task 8: The ledger's S3 column

**Files:** modify `backtest/vvf/ledger.R`, `tests/testthat/test-vvf-ledger.R` and `docs/VARIABLE_LEDGER.md` (regenerated).

**Interfaces:**
- **Consumes:** `vvf_ledger_results(run)`, which already reads `s1_features.csv` and `s2_vif.csv`; and Task 7's `s3_skill.csv`.
- **Produces:**
  - `VVF_LEDGER_RUNS` gains the A3b run;
  - the variable table gains the column `S3 close (skill [CI])`, formatted `%.4f [%.4f, %.4f]`, or `-` for a variable not in the run.

- [ ] **Step 1: Write the failing test.** In `test-vvf-ledger.R`, `"the ledger shows each feature's S3 skill from the committed A3b run"`:
  - `lp_anchor`'s cell matches its `s3_skill.csv` row;
  - the A3b run's row shows its `result_sha256` from `run_meta.json`.
- [ ] **Step 2:** RED. Then implement it and regenerate the ledger with `Rscript scripts/write_variable_ledger.R`.
- [ ] **Step 3:** GREEN. Commit: `docs(vvf): the ledger shows S3 skill from the A3b run (A3b)`.

### Task 9: Docs and gates

- [ ] **CHANGELOG:** an A3b entry with the numbers from Task 7's results and Task 2's RESULT.md, and the S4 owner question.
- [ ] **CLAUDE.md §6:** the S3–S5 files and `run_a3b_close.R`.
- [ ] **HANDOFF:** an A3b context-reset packet.
- [ ] **Gates:** `test-docs-truth.R`, `test-repo-hygiene.R`, the full suite and integrity (fresh HOME), each exiting 0. Commit: `docs(vvf): A3b in the changelog, the file inventory and the handoff`.

## Owner checkpoints

1. **Amend spec §4's shuffled-labels control** to the permuted-x null, judged one-sided (no skill interval wholly above 0). Evidence: `reports/2026-10-27/vvf-s4-null/RESULT.md`. Until then the run's S4 status is `void` under the spec's control.
2. **The merge.** It comes after #225.

## Self-review

- **Coverage:**
  - spec §4 S3: Task 1;
  - S4's five controls: Task 2;
  - the amendment's S5 (curves and the one-SE rule, learning curves, calibration slope, Murphy, bias–variance, CRPS, PIT, smoothing checks, ANOVA additions, complexity and edf): Tasks 3–6;
  - the run: Task 7;
  - the ledger: Task 8.
- **Types:** `vvf_s3_refit` and `vvf_s3_skill`, as Task 1 produces them, are what Task 2's `vvf_control_permuted_x` consumes; `VVF_V2_FEATURES` and `VVF_V2_TUNE` come from A3a's `reproduce_v2.R`.
- **Placeholders:** none. Each dry-run file is named by path, and each new piece has its signature and its test.

## Execution

Native (inline). One Haiku whole-branch review at the end (the owner's decision of 2026-10-26).
