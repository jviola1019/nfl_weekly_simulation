# A3b: Incremental Skill, Controls and Diagnostics (VVF S3–S5) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add S3 (walk-forward incremental skill over the anchor), the S4 negative controls, and the S5 diagnostics (validation and learning curves, the fit gap, Murphy decomposition, calibration, bias–variance, CRPS/PIT, smoothing checks, loss ANOVA). Run them close-anchored on Tune 2018–2022. The ledger shows S3, the admission of each variable and the input ERD, verified against the data.

**Architecture:** Every module is new under `backtest/vvf/`, beside A3a's S0–S2. The code was built and tested in the dry-run tree `../nfl-worktrees/a3dry` (A3 planner log steps 9–13). Each task copies its test from there first (RED), then its code (GREEN), and commits. New work beyond the dry run, from the owner's request of 2026-10-28 and the research it asked for (`reports/2026-10-28/a3-research/`):
- S3 calls A3a's anchor and seal guards (done in Task 1).
- S4 gets researched nulls: y drawn from the anchor (consistency resampling) and x permuted within week. Each is judged by S3's own claim rule, not by "every interval includes 0".
- The joint test gets a p of record that holds its size: a restricted wild cluster score bootstrap with diagonal studentization.
- The run gains a learning curve and the fit gap.
- The ledger gains S3, an admission column and the input ERD.

**Tech Stack:** R 4.5.1 (renv), data.table, testthat 3, sandwich (locked); `forecast` (locked) for the ETS alpha. No new package.

**Spec:** `docs/superpowers/specs/2026-10-20-preclose-validation-design.md` §4 (S3, S4) on #211, and the A3 amendment `.superpowers/research/a3-amendment-2026-10-21.md` (S5) in the roadmap worktree. A3a's plan, `docs/superpowers/plans/2026-10-27-a3a-validation-framework.md`, gives the conventions this plan follows. Revised 2026-10-28 after the research; Tasks 1 and 3–6 were complete before the revision.

## Global Constraints

- **Stacked on `feat/a3a-vvf`** (PR #225, `1c48ed4`). The branch is `feat/a3b-vvf`, in worktree `../nfl-worktrees/a3b`.
- **No new packages:** `renv.lock` and `DESCRIPTION` stay byte-identical.
- **The 2025 seal:** no stage reads, builds or scores 2025. Every evaluation season passes `vvf_guard_seasons`, and every table passes `vvf_guard_table` (A3a).
- **Confirm stays unscored:** nothing here scores 2023–2024 for admission. A variable that passes Tune becomes a candidate for G3's Confirm run, under its signed protocol.
- **Not edited:** `config.R`, the engine files, `backtest/eval_windows/*.json`, any `PROTOCOL.md`, `R/data_validation.R`.
- **Numbers:** every number in a doc comes from a committed result file or a run log named next to it.
- **LF writers and ASCII ledger,** as in A3a.
- **Commits:** one per task, each ending with the attribution trailer of the model that makes the commit.
- **Gates** (the owner accepted the full suite at checkpoints, with planning, ERD and documentation verification):
  - With a fresh HOME, `scripts/run_tests.R` and `scripts/verify_repo_integrity.R` exit 0 after Task 6, after Task 12, and after the review's fix pass.
  - Each task runs its own tests RED, then GREEN.
- **Owner STOP:** amending spec §4's shuffled-labels control. Until the owner signs it:
  - the run's `s4_status` of record follows the spec's control;
  - the proposed status is reported beside it as `s4_status_amended`.

## Review Focus

1. **An anchor-offset model scored against shuffled labels.** Permuting `y` alone miscalibrates the offset, so features that track the anchor show false skill. A valid null must not claim skill for a feature that only tracks a calibrated anchor. Pinned by Task 2's "anchor-tracking feature" test.
2. **A joint test with many coefficients over few clusters.** The cluster-robust χ²(k) Wald over-rejects (size 0.40–0.54 in the research), and `solve()` fails when k ≥ G. The p of record must hold its size, and a one-season window must return a p, not an error. Pinned by Task 8's size and k > G tests.
3. **Tuning that leaks into evaluation.** A validation curve tuned on any evaluation season, or on a sealed season, must stop. Pinned by Task 3's `vvf_assert_nested` test.
4. **An input table that breaks its keys.** A duplicate key, an orphan foreign key or a third team row for a game must be reported before any stage runs. Pinned by Task 10's planted-violation tests.
5. **A result file changed without its hash.** The ledger and each `run_meta.json` must agree. Pinned by Task 11's docs-truth test and Task 9's hash test.

---

## Setup

- [x] **S1:** In `../nfl-worktrees/a3b`, `git log --oneline -1` showed `1c48ed4`; the dry run's A3b files are untracked in `a3dry`.
- [x] **S2: Baseline** (fresh HOME): `run_tests.R` reported 522 tests, 0 failed, 1 allowlisted skip (P13); integrity reported 63 passed.

## File map

| File | Task | Responsibility |
|---|---|---|
| `backtest/vvf/s3_skill.R`, `tests/testthat/test-vvf-s3.R` | 1 (done) | Walk-forward `anchor + b·x_c` refits; paired skill against the anchor; DM-HLN; BH over the declared order |
| `backtest/vvf/s4_controls.R`, `tests/testthat/test-vvf-s4.R` | 2 | Canary, placebo, the spec's shuffled labels, the anchor null, the permuted-x null, anchor copy, reproducibility; the report's two statuses |
| `backtest/vvf/s5_*.R`, `tests/testthat/test-vvf-s5-*.R` | 3–6 (done) | Curves, scores, smoothing, ANOVA |
| `reports/2026-10-28/a3-research/`, `backtest/vvf/registry.R` | 7 | The research evidence; the disclosures it settles |
| `backtest/vvf/s1_screen.R`, `tests/testthat/test-vvf-s1.R`, `reports/2026-10-22/vvf-v2-repro/` | 8 | The joint test's p of record; the v2 reproduction regenerated |
| `backtest/vvf/run_a3b_close.R`, `tests/testthat/test-vvf-a3b-close.R`, `reports/2026-10-28/vvf-a3b-close/` | 9 | The close-anchored Tune run and its committed results |
| `backtest/vvf/input_schema.R`, `tests/testthat/test-vvf-input-schema.R` | 10 | The input ERD and its checks against the data |
| `backtest/vvf/ledger.R`, `tests/testthat/test-vvf-ledger.R`, `docs/VARIABLE_LEDGER.md` | 11 | S3, admission and ERD in the ledger |
| `CHANGELOG.md`, `CLAUDE.md`, `HANDOFF.md`, `tests/testthat/test-docs-truth.R` | 12 | Docs and their verification |

Execution order: 2, 7, 8, 9, 10, 11, 12.

---

### Tasks 1, 3, 4, 5 and 6 (complete before the revision)

| Task | Commit | Tests |
|---|---|---|
| 1. S3, with `vvf_assert_anchor` and `vvf_guard_table` in `vvf_s3_screen` | `03d3c45` | vvf-s3, 6 |
| 3. S5 curves: `vvf_validation_curve`, `vvf_assert_nested`, `vvf_walk_forward`, `vvf_learning_curve`, `vvf_fit_gap` | `907ae1a` | vvf-s5-curves, 5 |
| 4. S5 scores: `vvf_murphy`, `vvf_calibration_label`, `vvf_bias_variance`, CRPS, NB PIT, edf | `ecd3ce5` | vvf-s5-scores, 6 |
| 5. S5 smoothing, with the engine's recency-weight checks | `c2ff092` | vvf-s5-smoothing, 7 |
| 6. S5 loss ANOVA and team effects | `b2b5642` | vvf-s5-anova, 3 |

- [ ] **Gate after Task 6** (fresh HOME): `run_tests.R` and `verify_repo_integrity.R` exit 0. Record the counts in the ledger.

### Task 2: S4 controls, with the researched nulls

**Files:** `backtest/vvf/s4_controls.R` and `tests/testthat/test-vvf-s4.R`, from the dry run, plus the additions below.

**Interfaces:**
- **Consumes:** Task 1's `vvf_s3_refit`, `vvf_s3_skill`, `vvf_s3_screen`; A3a's `vvf_seeded`, `vvf_assert_known_at`.
- **Produces:**
  - from the dry run: `vvf_control_canary`, `vvf_canary_append`, `vvf_control_placebo` (band 0.020–0.080), `vvf_shuffle_y`, `vvf_control_shuffle`, `vvf_control_anchor_copy`, `vvf_control_repro`.
  - `VVF_NULL_SEED <- 20261028L`.
  - `vvf_resample_y(d, seed = VVF_NULL_SEED) -> data.table`. Every labelled row's `y` is redrawn as Bernoulli(`p_anchor`). Everything else is kept, including the `vvf_anchor` attribute, and unlabelled rows stay `NA`.
  - `vvf_permute_x(d, features, seed = VVF_NULL_SEED) -> data.table`. Adds `perm_<f>` for each feature, permuted within `wk`. `y`, `lp_anchor` and `p_anchor` are untouched.
  - `vvf_s3_claims(skill) -> list(claims, above, below)`:
    - `claims` counts verdicts starting "incremental skill";
    - `above` counts `skill_lo > 0`;
    - `below` counts `skill_hi < 0`.
  - `vvf_control_null(d, features, decision, eval_seasons, null = c("anchor", "permuted_x"), registry = vvf_registry(), B = VVF_S3_B, seed = VVF_NULL_SEED) -> list(passed, null, claims, above, below, skill)`.
    - It runs S0 on `features`, then S3 under the null. `"anchor"` uses `vvf_s3_screen` on `vvf_resample_y(d)`. `"permuted_x"` uses `vvf_s3_refit` on each `perm_<f>`, scored with `vvf_s3_skill` as `p_<f>`.
    - `passed` is `claims == 0`: no feature is claimed by S3's own rule. An interval wholly below 0 is the expected cost of fitting noise.
  - `vvf_s4_report(controls, gating = names(controls)) -> list(table, all_passed, status)`. The status is `"complete"` when every gating control passed, else `"void"`. The table gains the column `gates`.
  - `VVF_S4_GATING_SPEC <- c("canary", "placebo", "shuffled_labels", "anchor_copy", "reproducibility")`.
  - `VVF_S4_GATING_AMENDED <- c("canary", "placebo", "anchor_null", "anchor_copy", "reproducibility")`.

- [ ] **Step 1:** Copy the dry run's `test-vvf-s4.R`. Append four tests, using the file's simulator for 40 weeks of 20 games with `lp_anchor ~ N(0.2, 0.8)` and `y ~ Bernoulli(plogis(lp_anchor))`:
  - `"the anchor null redraws y from the anchor and keeps everything else"`:
    - `lp_anchor`, `p_anchor`, the features and the attribute are identical, and `NA` labels stay `NA`;
    - `abs(mean(y*) - mean(p_anchor)) < 3 * sqrt(sum(p * (1 - p))) / n`.
  - `"under a calibrated anchor neither null claims a feature that only tracks it, and the spec's shuffle does"`:
    - `rest_diff := lp_anchor + N(0, 0.3)`;
    - `vvf_control_null(..., null = "anchor")$passed` and `vvf_control_null(..., null = "permuted_x")$passed` are `TRUE`;
    - `vvf_control_shuffle(...)$passed` is `FALSE`.
  - `"a planted effect is claimed on the data and removed by both nulls"`:
    - `y ~ Bernoulli(plogis(lp_anchor + 0.5 z))` with `rest_diff := z`;
    - `vvf_s3_screen` claims it;
    - both nulls give `claims == 0`.
  - `"the S4 status counts only the gating controls"`: two controls, one failing.
    - Gating on the passing one gives `"complete"`.
    - Gating on both gives `"void"`.
    - `table$gates` marks the gating rows.
- [ ] **Step 2:** Run the `vvf-s4` filter. Expected: RED, `s4_controls.R` missing.
- [ ] **Step 3:** Copy `s4_controls.R`. Add the functions and constants above. Update the header comment: the spec's control is kept and reported; the researched nulls and the claim-rule criterion follow `reports/2026-10-28/a3-research/RESEARCH.md`.
- [ ] **Step 4:** GREEN: all tests in the filter pass. Commit: `feat(vvf): S4 controls, with the anchor and permuted-x nulls judged by S3's claim rule (the spec's y shuffle fails by construction; owner decision) (A3b)`.

### Task 7: The research evidence and the disclosures it settles

**Files:**
- `reports/2026-10-28/a3-research/`: the `RESEARCH.md`, the result CSVs, `data/` and `scripts/` (including the 2026-10-27 S4 null diagnostic), plus `scripts/research-summary.R` and its output `summary.txt`;
- `backtest/vvf/registry.R` (`vvf_disclosures`) and `tests/testthat/test-vvf-registry.R`.

**Interfaces:** `vvf_disclosures()` keeps every id. It updates JOINT-WALD, CLUSTER-UNIT and A3-FLEX, and adds S4-NULL. Each `source` names a file in the research folder.

- [ ] **Step 1:** Write the failing test in `test-vvf-registry.R`: `"the research settles the joint test, the cluster unit, late changes and the S4 null, citing committed evidence"`.
  - The ids include `S4-NULL`.
  - Each of the four rows' `source` contains `reports/2026-10-28/a3-research/`, and every path in it exists.
  - The JOINT-WALD text contains `p_joint`.
- [ ] **Step 2:** RED. Then commit the research folder. `RESEARCH.md` covers, with every number from `summary.txt` (written by `research-summary.R` from the CSVs):
  - the S4 null, and the criterion, with the power of S3 to see a planted effect;
  - the joint test's size by method, for the outcome, spread and total families;
  - the cluster unit: ICC by unit, and the median design effect;
  - late schedule changes: the share of games, the tests against the close, the S1 sensitivity, and opener-to-close movement;
  - the admission rule;
  - the literature, with full citations;
  - the limits of the evidence.
- [ ] **Step 3:** Update the four disclosures from `summary.txt`. GREEN. Commit: `docs(vvf): the A3 research on the S4 null, the joint test, the cluster unit and late changes, and the disclosures it settles (A3b)`.

### Task 8: The joint test's p of record

**Files:** `backtest/vvf/s1_screen.R`, `tests/testthat/test-vvf-s1.R`, `reports/2026-10-22/vvf-v2-repro/` (regenerated).

**Interfaces:**
- **Produces:**
  - `vvf_wild_p_joint_score(X, resid, w, cluster, B = VVF_WILD_B, seed = VVF_WILD_SEED) -> numeric(1)`;
  - `vvf_s1_joint(...)` gains the columns `p_joint_wild`, `joint_wild_method` and `p_joint = max(p_test, p_joint_wild)`. `p_wald_robust` stays, as v2 fidelity, and is `NA` when the cluster-robust covariance is singular (k ≥ G).
- The algorithm. The signature does not determine it. `X` holds the estimable columns. `resid` and `w` are `y − p̂0` and `p̂0(1 − p̂0)` for the outcome family, or `r − r̄` and 1 for the linear families:

```r
Xc <- sweep(X, 2, colSums(X * w) / sum(w))    # efficient score: the intercept projected out
Sg <- rowsum(Xc * resid, cluster)             # G x k cluster scores at the restricted fit
S <- colSums(Sg); dg <- colSums(Sg^2)         # Rademacher: the bootstrap variance equals dg
t0 <- sum(S^2 / dg)                           # diagonal studentization, defined for k > G
W <- t(vvf_rademacher(nrow(Sg), B, seed))     # B x G
p <- (1 + sum(rowSums(sweep((W %*% Sg)^2, 2, dg, "/")) >= t0)) / (B + 1)
```

- [ ] **Step 1:** Write the failing tests in `test-vvf-s1.R`:
  - `"the joint wild score bootstrap holds its size where the cluster-robust Wald does not"`:
    - 200 null replicates, each 40 clusters × 10 rows, 15 features, and a week effect of SD 0.2;
    - `B = 199`;
    - the rejection rate of `p_joint_wild < 0.05` lies in [0.01, 0.10], and that of `p_wald_robust` exceeds 0.15.
  - `"a joint test with more coefficients than clusters returns a wild p and no Wald"`: 10 clusters and 15 features. `p_wald_robust` is `NA`, and `p_joint_wild` is finite.
  - `"a planted joint effect is detected"`: β = 0.4 on 3 of 15 features with n = 2,000, so `p_joint < 0.01`.
- [ ] **Step 2:** RED. Implement. GREEN (the `vvf-s1` filter).
- [ ] **Step 3:** Regenerate the reproduction with a fresh HOME: `Rscript backtest/vvf/reproduce_v2.R --out reports/2026-10-22/vvf-v2-repro`.
  - Expected: `test-vvf-v2-reproduction.R` passes unchanged, with χ² 26.9 on df 29 and p_test 0.575.
  - `s1_joint.csv` gains the new columns, and `run_meta.json` carries the new `result_sha256`.
  - Regenerate the ledger (`Rscript scripts/write_variable_ledger.R`).
- [ ] **Step 4:** Commit: `feat(vvf): the joint test's p of record is a restricted wild cluster score bootstrap with diagonal studentization (size 0.04-0.05 where the robust Wald gives 0.40-0.54) (A3b)`.

### Task 9: The close-anchored Tune run

**Files:**
- `backtest/vvf/run_a3b_close.R` and `tests/testthat/test-vvf-a3b-close.R`, from the dry run;
- `reports/2026-10-28/vvf-a3b-close/`: a new run on this branch. The dry run's `reports/2026-10-26/vvf-a3b-close/` is not copied.

**Interfaces:**
- **Consumes:** Tasks 1–8.
- **Produces:**
  - `VVF_A3B_RESULT_FILES`, which adds `s5_learning_curve.csv` and `s5_fit_gap.csv`;
  - `vvf_a3b_table()`, `vvf_a3b_results(tab, out_dir) -> result_sha256`, `vvf_a3b_controls(tab, results_sha)`;
  - `vvf_a3b_joint_fit(features) -> function(train, target) -> p`. The model is the anchor plus every estimable feature, as an unpenalized logit. It is centred and scaled on the training rows, with aliased columns dropped by QR. This is the high-variance end of the bias–variance trade-off.

- [ ] **Step 1:** Copy the test, and change its report directory to `reports/2026-10-28/vvf-a3b-close`. Append the test `"the learning curve and the fit gap score the joint model beside the anchor on the same games"`:
  - `n_train_seasons` is `2:8`;
  - each row carries `logloss_anchor`;
  - `s5_fit_gap.csv` has one row per Tune season.
- [ ] **Step 2:** RED: `run_meta.json` missing.
- [ ] **Step 3:** Copy the script, then change it:
  - `vvf_a3b_controls` adds `anchor_null` and `permuted_x` (Task 2).
  - The report writes `s4_status` (gating `VVF_S4_GATING_SPEC`, the status of record), `s4_status_amended` (`VVF_S4_GATING_AMENDED`) and `s4_amendment: "proposed 2026-10-28, unsigned"`.
  - `vvf_a3b_results` writes the learning curve with `n_train = 2:8`. The table starts in 2010, so 8 seasons is the most 2018 allows, where the amendment asked for 10.
  - It also writes the fit gap, each with the anchor's log loss on the same games.
- [ ] **Step 4:** Run `HOME=<fresh> Rscript backtest/vvf/run_a3b_close.R --out reports/2026-10-28/vvf-a3b-close` in the background. The dry run took 17.6 minutes; allow about 30. Expected:
  - `s4_status` is `void`, and `s4_status_amended` follows the anchor null;
  - S3 claims nothing;
  - the S5 files the dry run also wrote match it (C0 Brier 0.211116; C0 slope 1.047).
  - Any difference is diagnosed before committing.
- [ ] **Step 5:** GREEN. Commit: `test(vvf): the A3b close run on Tune 2018-2022 (no S3 claim; S4 void under the spec's shuffle, the anchor null as proposed) (A3b)`.

### Task 10: The input ERD, verified against the data

**Files:** `backtest/vvf/input_schema.R` and `tests/testthat/test-vvf-input-schema.R` (both new).

**Interfaces:**
- **Produces:**
  - `VVF_INPUT_SCHEMA`: one entry per table, each `list(name, source, key, refs)`. `refs` is a list of `list(cols, table, table_cols)`. The tables:
    - v1 `games`, `team_games`, `qb_games`, `espn_open_close`;
    - VVF `game_context`, `injuries_team`, `injuries_qb`, `venues`.
  - `vvf_check_inputs(tables, schema = VVF_INPUT_SCHEMA) -> data.table(check, table, detail, violations)`. `tables` is a named list of data.tables. The checks:
    - each key is unique;
    - each foreign key resolves;
    - every team row's team is one of its game's two franchises;
    - no game has more than two team rows;
    - no sealed season.
  - `vvf_render_erd(schema) -> character`: the lines of a Mermaid `erDiagram`.

- [ ] **Step 1:** Write the failing tests:
  - `"the committed inputs satisfy every key and reference in the schema"`: on the loaded v1 and VVF inputs, every `violations` is 0.
  - `"a duplicate key, an orphan reference and a third team row are each reported"`: plant each on a copy, and expect `violations == 1` on the matching check.
  - `"the ERD names every table and relation in the schema"`.
- [ ] **Step 2:** RED, then implement, then GREEN. Commit: `feat(vvf): the input ERD and its key and reference checks, zero violations on the committed inputs (A3b)`.

### Task 11: The ledger's S3, admission and ERD

**Files:** modify `backtest/vvf/ledger.R`, `tests/testthat/test-vvf-ledger.R` and `docs/VARIABLE_LEDGER.md` (regenerated).

**Interfaces:**
- **Consumes:** `vvf_ledger_results(run)`; Task 9's `s3_skill.csv` and `run_meta.json`; Task 10's schema, checks and ERD.
- **Produces:**
  - `VVF_LEDGER_RUNS` gains the A3b run (stages "S3, S4, S5").
  - The feature table gains `S3 close (skill [CI])`, formatted `%.4f [%.4f, %.4f]`.
  - It also gains `Admission`, from `vvf_admission(s1_q_outcome, s3_verdict, s4_status) -> character`, with this precedence:
    1. `"excluded: no incremental skill on Tune (S3)"`;
    2. `"excluded: no S1 signal (q >= 0.05)"`;
    3. `"held: S4 void"`;
    4. `"candidate: Confirm 2023-24 under G3"`.
  - A section "Input tables" holds the ERD and the check table.

- [ ] **Step 1:** Write the failing tests:
  - `"the ledger shows each feature's S3 skill and admission from the committed A3b run"`:
    - `lp_anchor`'s cell matches its `s3_skill.csv` row;
    - the A3b run's row shows its `result_sha256`.
  - `"admission follows S3, then S1, then S4"`: four calls, one per reason.
- [ ] **Step 2:** RED. Implement, and regenerate with `Rscript scripts/write_variable_ledger.R`.
- [ ] **Step 3:** GREEN. Commit: `docs(vvf): the ledger shows S3 skill, each variable's admission and the verified input ERD (A3b)`.

### Task 12: Docs, documentation verification and gates

- [ ] **Docs-truth test** (`test-docs-truth.R`): `"every repo path the main docs cite exists"`:
  - it covers backticked tokens with a slash in `CLAUDE.md`, `README.md` and `GETTING_STARTED.md`;
  - it checks only tokens whose first segment is a tracked top-level directory.
- [ ] **CHANGELOG:** an A3b entry, with numbers from Task 9's results and Task 7's `summary.txt`, and the S4 owner question.
- [ ] **CLAUDE.md §6:** the VVF line names S0–S5, `run_a3b_close.R`, `input_schema.R` and the research folder.
- [ ] **HANDOFF:** an A3b context-reset packet.
- [ ] **Commands verified:** run each command the new docs cite: the run usage line and `write_variable_ledger.R`.
- [ ] **Gates** (fresh HOME): the docs-truth and hygiene tests, the full suite and integrity, each exiting 0. Commit: `docs(vvf): A3b in the changelog, the file inventory and the handoff, with a docs path check`.

## Owner checkpoints

1. **Amend spec §4's shuffled-labels control.** The proposal: the anchor null, with the permuted-x null reported, each judged by S3's claim rule. The evidence is `reports/2026-10-28/a3-research/RESEARCH.md`. Until the owner signs, the run's `s4_status` of record is `void` under the spec's control.
2. **The joint test's p of record** (Task 8). `p_wald_robust` stays, labelled not size-controlled. Dropping it is the owner's call.
3. **The merge.** It comes after #225.

## Self-review

- **Coverage:**
  - spec §4 S3: Task 1;
  - S4's controls, with the researched nulls: Task 2;
  - the amendment's S5: Tasks 3–6 and 9. The learning curves and fit gap are new in 9; C3's curves, CRPS and PIT wait for G2;
  - the owner's 2026-10-28 requests:
    - the shuffling and the joint test: 2, 7 and 8;
    - the cluster unit and late changes: 7;
    - significance and admission: 11;
    - bias–variance: 9;
    - ERD: 10;
    - docs: 12.
- **Types:**
  - Task 1's `vvf_s3_refit`, `vvf_s3_skill` and `vvf_s3_screen` are what Task 2 consumes;
  - Task 2's gating constants are what Task 9 consumes;
  - Task 10's schema is what Task 11 renders;
  - `VVF_V2_FEATURES` and `VVF_V2_TUNE` come from A3a's `reproduce_v2.R`.
- **Placeholders:** none. Each dry-run file is named by path, and each new piece has its signature and its test.

## Execution

Native (inline). One Haiku whole-branch review at the end (the owner's decision of 2026-10-26).
