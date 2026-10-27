# A3a: Variable Ledger, Provenance, Screen and Structure (VVF S0–S2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v2's feature builder, input builder and sha256-locked inputs (PR #205) into `backtest/vvf/`; add the variable registry with `known_at` classes and the S0 guard, the S1 screen with the anchor as a parameter, and the S2 structure checks; prove the port by reproducing v2's §1 numbers; render `docs/VARIABLE_LEDGER.md` from the registry; and diagnose F11 (calibration games simulated at 21.5–21.5), with the engine's loud failure held behind an owner STOP.

**Architecture:** Every file is new and lives under `backtest/vvf/`, beside the v1 harness it reuses (`backtest/common.R`, `candidates/`, `metrics.R`). `common.R` holds the seal guards and the locked loaders; `features.R` builds one anchor-free table and `vvf_anchor_features()` adds the anchor-relative columns, so the same table serves the close today and the opener when D1 lands; `registry.R` is the single source for each variable's `known_at` class, defects and evidence, `provenance.R` (S0) refuses what a decision cannot know, and `s1_screen.R` and `s2_structure.R` run only after S0 passes. `reproduce_v2.R` is the port's known-answer test, and `ledger.R` renders the ledger from the registry plus the committed results.

**Tech Stack:** R 4.5.1 with renv; data.table 1.17.8, sandwich 3.1-1 (`vcovCL`), car 3.1-3 (`vif`), jsonlite, digest, testthat 3; base R for the wild cluster bootstrap. `lmtest` is locked and not needed.

**Spec:** `docs/superpowers/specs/2026-10-20-preclose-validation-design.md` (approved 2026-10-20): §2 known_at classes and decision points, §4 S0–S2 and the known-answer tests, §5 the ledger, §6 disclosures. Also: master plan `docs/superpowers/plans/2026-10-19-preclose-and-app-master-plan.md` Track A (A3a defect table, A3b); the amendment `.superpowers/research/a3-amendment-2026-10-21.md` (the A3a/A3b split; the seal); the coordinator's findings of 2026-10-22 (F11, M3). The companion plan `2026-10-20-a3b-validation-framework.md` adds S3–S5 and the controls.

## Global Constraints

- **Owner decision 2026-10-20 (verbatim):** "Port builder + inputs": v2's feature builder, input builder and `backtest/data_v2/` go into `backtest/vvf/`, with attribution, tests and the 2025 guards. PR #205 stays a draft.
- **No new packages** (spec §4, verbatim): "The framework uses no new packages (`sandwich`, `lmtest` and `car` are locked)." `renv.lock` and `DESCRIPTION` stay byte-identical.
- **The 2025 seal:** "The 2025 game Holdout stays sealed: no backtest reads, builds or scores 2025 game data." Every VVF loader asserts `VVF_MAX_INPUT_SEASON` (2024, v2's `BT2_MAX_INPUT_SEASON`) and the sealed seasons: `VVF_SEALED_SEASONS` (2025), joined with `config.R`'s `SEALED_SEASONS` once PR #218 (`fix/seal-diagnostics`, unmerged) defines it. Main does not have it; the code reads it when present and needs no change when #218 merges.
- **The 2024–2025 price file:** never read `reports/2026-09-29/clv-power/espn_open_close_2024_2025.csv`; a test makes backtest code refuse it (spec §6).
- **Out of scope:** the `nfl_preclose_v1` protocol, candidates and scoring (A4); the opener inputs (D1, executing in parallel on `feat/d1-odds-layer`; do not depend on it); S3–S5 and the controls (A3b).
- **Not edited:** `config.R`, `backtest/eval_windows/*.json`, any frozen `PROTOCOL.md`, `R/data_validation.R`. `NFLsimulation.R` is not edited: Task 12 was dropped on 2026-10-26.
- **Network (Task 2's builder only):** keyless sources, at most 1 request per second, a truthful user agent, a 20 s timeout, and never a workaround for HTTP 403 or 429. The values come from `config.R` (`CAPTURE_USER_AGENT`, `CAPTURE_TIMEOUT_SEC`, `CAPTURE_MIN_INTERVAL_SEC`). The tests are offline.
- **No silent fallbacks:** a constant feature is reported "not testable", a dropped feature is logged with its reason, and a cached calibration stops the F11 diagnosis.
- **Platforms:** CI is Linux. Writers emit LF (`bt_write_text`, `fwrite(eol = "\n")`); the ledger is ASCII so its bytes match on every OS. No `system2` call is added.
- **Numbers:** every number below came from a script run in the dry run, which is named next to it.
- **Golden master:** predict "no differences": no task touches an engine file.
- **Per task:** one commit; the message is the subject line, a blank line, then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Every task ends with `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R` exiting 0, run with `HOME=<an empty scratch dir>`. Push and the draft PR come at the end; merging needs the owner.
- **Windows and Git Bash:** write files with the file tools; pass `C:/...` paths to R; list a directory before deleting anything.

## Review Focus

1. **A sealed season arrives through a loader, a raised ceiling or a rebuild** (for example `max_season = 2026` for a prospective run): 2025 is still refused. Pinned by Task 1's "season guard" test (`vvf_guard_seasons(2025L, 2026L, ...)` errors), Task 2's two seal tests and Task 3's feature-guard test.
2. **A feature known only after the decision enters an opener screen**, such as the actual starting QB, a retractable roof's state, or an injury row updated on Saturday: S0 refuses it before any model is fit. Pinned by Task 4's S0 test and its "only 21 of v2's 36 features are admissible at IS-A" test, and by Task 5's screen test (`d_c1` at `open_isa` errors).
3. **Fewer than 30 week clusters** (the opener windows have about 13 to 18 weeks): the week-clustered normal test over-rejects there, so the wild cluster bootstrap must hold its size. Pinned by Task 5's 12-cluster null test, which measured 0.058 (score) and 0.054 (bootstrap-t) over 500 simulations against the band [0.032, 0.070].
4. **Aliased or collinear features**, such as `inj_diff_all` (the sum of the groups) or `d_e1` (the mean of `d_c1` and `d_c2`): they must not inflate a joint test's degrees of freedom (v2's moneyline joint test used df 30 for 29 estimable coefficients) or crash `car::vif`. Pinned by Task 5's joint test (df equals `anova()`'s) and Task 6's VIF test (aliased logged, the declared-first feature kept).
5. **The ledger drifts from the registry or the results**, through a hand edit or a re-run that changes a hash: the docs-truth test fails. Pinned by Task 8's ledger tests and Task 7's committed-hash test.

---

## Setup (once, before Task 1)

- [ ] **S1: R library.** In the worktree: `Rscript -e "for (p in c('data.table','sandwich','car','testthat','withr')) cat(p, as.character(packageVersion(p)), '\n')"`. Expected: `data.table 1.17.8`, `sandwich 3.1.1`, `car 3.1.3`, `testthat 3.3.2`, `withr 3.0.2`. If a package is missing, run `Rscript -e "renv::restore(prompt = FALSE)"`; `git diff --exit-code renv.lock` must stay clean.
- [ ] **S2: PR #205's commits.** `git fetch origin feat/validation-sprint-v2 && git cat-file -t 759dd1c`. Expected: `commit`. Tasks 1 and 7 copy files from it byte for byte.
- [ ] **S3: Baseline.** With `HOME=<empty scratch dir>`: `Rscript scripts/run_tests.R` gives `tests=455 passed=1756 failed=0 errors=0 skipped=1 unapproved_skips=0` and exit 0 (the one skip is `KNOWN-DEFECT P13`); `Rscript scripts/verify_repo_integrity.R` gives `Total: 63 passed, 0 failed` and `[VERIFICATION PASSED]`. Both were measured on main `4c1c377` on 2026-10-22.

## File map

| File | Task | Responsibility |
|---|---|---|
| `backtest/vvf/common.R` | 1 | Constants, the seal guards, the forbidden-file guard, sha256-locked loaders, LF writers, the result hash, geometry |
| `backtest/vvf/data/` (5 files) | 1 | Byte-identical copies of PR #205's `backtest/data_v2/` (seasons 2009–2024) |
| `tests/testthat/helper-vvf.R` | 1 | `vvf_test_env()`: source the v1 helpers and named VVF files into a fresh environment |
| `backtest/vvf/build_inputs.R` | 2 | The ported input builder, with injectable loaders and the network rules |
| `backtest/vvf/features.R` | 3 | The ported feature builder and `vvf_anchor_features()` |
| `backtest/vvf/registry.R` | 4 | known_at classes, decision points, one row per variable, disclosures |
| `backtest/vvf/provenance.R` | 4 | S0: `vvf_assert_known_at()` |
| `backtest/vvf/s1_screen.R` | 5 | S1: LR and F tests, robust p (vcovCL or wild bootstrap), BH, MDE, verdicts, joint tests |
| `backtest/vvf/s2_structure.R` | 6 | S2: VIF with declared-first precedence, per-period signs, feature × period tests |
| `backtest/vvf/reproduce_v2.R`, `tests/testthat/fixtures/vvf/` | 7 | The port's known-answer test against v2's committed screen |
| `reports/2026-10-22/vvf-v2-repro/` | 7 | The committed close-anchored S1/S2 results the ledger shows |
| `backtest/vvf/ledger.R`, `scripts/write_variable_ledger.R`, `docs/VARIABLE_LEDGER.md` | 8 | The generated ledger |
| `scripts/diagnose_mu_na.R` | 9 | F11: which mean term is NA, found from the call frames, with no engine edit |
| `reports/2026-10-26/f11-bye-week-main/` | 10 | The bye-week positive control on main (2024 week 5) |
| `CHANGELOG.md`, `CLAUDE.md`, `HANDOFF.md` | 11 | Docs |

---

### Task 1: Shared helpers, the seal and the ported inputs (haiku)

**Files:**
- Create: `backtest/vvf/common.R`, `backtest/vvf/data/{SOURCES.json,game_context.csv,injuries_team.csv,injuries_qb.csv,venues.csv}`, `tests/testthat/helper-vvf.R`
- Test: `tests/testthat/test-vvf-common.R`

**Interfaces:**
- Consumes: `bt_load_inputs()`, `bt_write_text()` (`backtest/common.R`).
- Produces: `VVF_MAX_INPUT_SEASON` (2024L), `VVF_SEALED_SEASONS` (2025L), `VVF_FIRST_PRED_SEASON` (2010L), `VVF_DATA_DIR`; `vvf_config_value(name, config_path = "config.R", required = TRUE)`; `vvf_sealed_seasons(config_path = "config.R") -> integer`; `vvf_guard_seasons(seasons, max_season, what, sealed)`; `vvf_assert_readable(path)`; `vvf_read_csv(path, ...)`; `vvf_sha256(path)`; `vvf_result_sha256(paths) -> chr(64)`; `vvf_write_csv(x, path)`, `vvf_write_text(text, path)`, `vvf_write_json(x, path)`; `vvf_load_inputs(data_dir, max_season) -> list(game_context, injuries_team, injuries_qb, venues)`; `vvf_load_v1_inputs(max_season, window_path) -> bt_load_inputs() list, games cut at max_season`; `vvf_franchise()`, `vvf_haversine_km()`, `vvf_utc_offset_h()`, `vvf_local_hour()`. In tests: `vvf_test_env(vvf_files, v1_files = "common.R")` and `VVF_TEST_V1_FILES`.

- [ ] **Step 1: Write the test helper and the failing test.**

Create `tests/testthat/helper-vvf.R`:

> `tests/testthat/helper-vvf.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

Create `tests/testthat/test-vvf-common.R`:

> `tests/testthat/test-vvf-common.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 2: Run it and see it fail.**

Run: `Rscript -e "testthat::test_dir('tests/testthat', filter = 'vvf-common', reporter = 'summary')"`
Expected: an error at `test-vvf-common.R:5:1`: `'.../backtest/vvf/common.R' is not an existing file`.

- [ ] **Step 3: Copy the inputs from PR #205, byte for byte.**

```bash
mkdir -p backtest/vvf/data
for f in SOURCES.json game_context.csv injuries_team.csv injuries_qb.csv venues.csv; do
  git show 759dd1c:backtest/data_v2/$f > backtest/vvf/data/$f
done
sha256sum backtest/vvf/data/*.csv | cut -c1-16
```
Expected, in order: `9c0d4fbf5aac0bc3` (game_context), `5342fd211dc9c4ad` (injuries_qb), `8e459b7c0ca8d411` (injuries_team), `39c290f2b66e2ae5` (venues). These are the first 16 characters of the sha256s in `SOURCES.json`; the loader checks all 64.

- [ ] **Step 4: Write the implementation.** Create `backtest/vvf/common.R`:

> `backtest/vvf/common.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 5: Run the test and see it pass.**

Run: the Step 2 command. Expected: `vvf-common: ` followed by 34 dots, then `DONE`, with no failure. (The test allows exactly one other mention of the forbidden file: `backtest/build_inputs.R:106`, v1's builder, which read it on 2026-09-29. That is disclosed in the registry and is an owner checkpoint below.)

- [ ] **Step 6: Gates and commit.**

```bash
HOME=<empty scratch dir> Rscript scripts/run_tests.R
HOME=<empty scratch dir> Rscript scripts/verify_repo_integrity.R
git add backtest/vvf/common.R backtest/vvf/data tests/testthat/helper-vvf.R tests/testthat/test-vvf-common.R
git commit -m "feat(vvf): seal guards, the forbidden 2024-2025 price file, and PR #205's locked inputs" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The ported input builder (haiku)

**Files:**
- Create: `backtest/vvf/build_inputs.R`
- Test: `tests/testthat/test-vvf-build-inputs.R`

**Interfaces:**
- Consumes: Task 1's `vvf_guard_seasons`, `vvf_config_value`, `vvf_load_v1_inputs`, `vvf_write_csv`, `vvf_write_json`, `vvf_sha256`, `vvf_franchise`, `%||%`.
- Produces: `VVF_SEASONS_BUILD` (2009:2024); `vvf_position_group(pos)`; `vvf_http_get_text(url, user_agent, timeout_sec)`; `vvf_build_venues(ids, http_get, sleep) -> list(venues, meta)`; `vvf_build_context(sch, games) -> list(ctx, meta)`; `vvf_build_injuries(inj, games) -> list(team, qb, meta)`; `vvf_build_inputs(out_dir, seasons, load_schedules, load_injuries, http_get, sleep)`. The plan never runs the live build; the committed inputs stay v2's.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-vvf-build-inputs.R`:

> `tests/testthat/test-vvf-build-inputs.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 2: Run it and see it fail.**

Run: `Rscript -e "testthat::test_dir('tests/testthat', filter = 'vvf-build-inputs', reporter = 'summary')"`
Expected: an error at `test-vvf-build-inputs.R:6:1`: `'.../backtest/vvf/build_inputs.R' is not an existing file`.

- [ ] **Step 3: Write the implementation.** Create `backtest/vvf/build_inputs.R`:

> `backtest/vvf/build_inputs.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 4: Run the test and see it pass.** Expected: `vvf-build-inputs: ` followed by 19 dots, then `DONE`.

- [ ] **Step 5: Gates and commit.** Run both gates as in Task 1, then:

```bash
git add backtest/vvf/build_inputs.R tests/testthat/test-vvf-build-inputs.R
git commit -m "feat(vvf): port v2's input builder with injectable loaders, the seal before any request, and the network rules" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The ported feature builder and the anchor (haiku)

**Files:**
- Create: `backtest/vvf/features.R`
- Test: `tests/testthat/test-vvf-features.R`

**Interfaces:**
- Consumes: v1's `bt_week_schedule`, `bt_elo_run`, `bt_epa_features`, `bt_epa_walk_forward`, `bt_e1`, `bt_logit`, `bt_clip`, `bt_novig_home`, `BT_EPA_FIRST_TRAIN_SEASON`; Task 1's `vvf_guard_seasons`, `vvf_franchise`, `vvf_haversine_km`, `vvf_utc_offset_h`, `vvf_local_hour`.
- Produces: `VVF_V1_SELECTIONS`, `VVF_ANCHORS` (`close = "p_c0"`, `open = "p_open"`); `vvf_base_predictions(inp_v1, max_season, sel) -> list(pred, weeks)`; `vvf_build_features(base, inp, max_season) -> data.table` (one row per game: v2's features except the anchor-relative ones, plus `lp_c0`, `ats_resid`, `tot_resid`, `cold_obs`, `windy_obs`); `vvf_anchor_features(d, anchor = c("close", "open")) -> data.table` with `p_anchor`, `lp_anchor`, `d_c1`, `d_c2`, `d_e1`, `home_dog`, `big_fav`, `delta` (open only), and the attribute `vvf_anchor`; `vvf_referee_tendencies`, `vvf_qb_out`, `vvf_injury_index`, `vvf_home_venues`.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-vvf-features.R`:

> `tests/testthat/test-vvf-features.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 2: Run it and see it fail.**

Run: `Rscript -e "testthat::test_dir('tests/testthat', filter = 'vvf-features', reporter = 'summary')"`
Expected: `'.../backtest/vvf/features.R' is not an existing file`.

- [ ] **Step 3: Write the implementation.** Create `backtest/vvf/features.R`:

> `backtest/vvf/features.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 4: Run the test and see it pass.** Expected: `vvf-features: ` followed by 24 dots, then `DONE`.

- [ ] **Step 5: Gates and commit.**

```bash
git add backtest/vvf/features.R tests/testthat/test-vvf-features.R
git commit -m "feat(vvf): port v2's feature builder; anchor-relative features follow the close or the opener" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The registry and S0 provenance (sonnet)

Judgment lives in the `known_at` classes. The spec's §2 classes are used as written, with two additions, both stated in the code and the ledger:
- **The `anchor` pseudo-class.** It covers the decision's own price, so `lp_anchor`, `home_dog` and `big_fav` are known at every decision.
- **A `posthoc` flag**, v2's own flag, for observed weather. It is refused at every decision.

The `close` decision admits `gameday`, because starters are announced before the close. That is how v2's screen used the actual QB.

The conservative calls, each a defect row, are:
- `roof_closed` is `gameday`, because a retractable roof's state is set on game day (audit F6).
- The injury features are `gameday`, because v2's inputs used the kickoff − 6 h rule, so a Saturday update counts.
- The referee features are `gameday`, because the assignment date is not recorded.
- `d_c2`, `d_e1` and `qb_change_diff` are `gameday`, because they use the actual starter.
- `d_c1` is `results_w-1`, because an Elo rating moves only when its team plays.

**Files:**
- Create: `backtest/vvf/registry.R`, `backtest/vvf/provenance.R`
- Test: `tests/testthat/test-vvf-registry.R`

**Interfaces:**
- Consumes: nothing from earlier tasks (data.table only).
- Produces: `VVF_KNOWN_AT` (data.table `class`, `becomes_known`, 11 classes in time order); `VVF_DECISIONS` (named list `open_isa`, `open_isb`, `tue_18z`, `fri_21z`, `close` → class vectors, nested); `VVF_DECISION_INFO`; `vvf_registry() -> data.table(name, kind, group, definition, source, known_at, posthoc, unit_test, n_params, defects <list of lists id/text/fix/phase/audit/status>, evidence)`; `VVF_V2_FEATURES` (36, v2's order, `lp_anchor` for v2's `lp_c0`); `VVF_V2_SITUATIONAL` (30); `vvf_disclosures() -> data.table(id, text, source)`; `vvf_assert_known_at(features, decision, registry = vvf_registry())`, which stops with `known-at violation ...`.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-vvf-registry.R`:

> `tests/testthat/test-vvf-registry.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 2: Run it and see it fail.**

Run: `Rscript -e "testthat::test_dir('tests/testthat', filter = 'vvf-registry', reporter = 'summary')"`
Expected: `'.../backtest/vvf/registry.R' is not an existing file`.

- [ ] **Step 3: Write the registry.** Create `backtest/vvf/registry.R`:

> `backtest/vvf/registry.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 4: Write S0.** Create `backtest/vvf/provenance.R`:

> `backtest/vvf/provenance.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 5: Run the test and see it pass.** Expected: `vvf-registry: ` followed by dots, then `DONE`, with no failure (the count depends on the defect loop; 134 in the dry run).

- [ ] **Step 6: Gates and commit.**

```bash
git add backtest/vvf/registry.R backtest/vvf/provenance.R tests/testthat/test-vvf-registry.R
git commit -m "feat(vvf): the variable registry with known_at classes and defects, and S0 (vvf_assert_known_at)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: S1, the screen (sonnet)

The algorithms are fixed by the spec:
- **Outcome family:** an LR test against `glm(y ~ 1, offset = lp_anchor)`.
- **Movement, spread and total families:** an F test against `lm(r ~ 1)`.
- **Robust p:** `vcovCL` with HC0 at 30 or more week clusters. Below 30, a wild cluster bootstrap with the null imposed: Rademacher weights, B = 9,999 and seed 20261020.
  - The linear families use the restricted bootstrap-t: refit, CR0 t, vectorised in chunks of 1,000.
  - The outcome family uses the restricted score bootstrap (Kline and Santos, 2012). A 0/1 outcome cannot be redrawn additively, so a refit bootstrap does not apply; the score form needs no refit.
  - p = (1 + #{|t*| ≥ |t|}) / (B + 1), so it is never 0.
- **Combined p:** p = max(p_model, p_robust), then BH within each family.
- **MDE:** the `mde.R` formula, (z₀.₉₇₅ + z₀.₈) / √(n · mean(p(1 − p))) for the outcome, and (z + z) · σ / √n for the linear families. A Bonferroni-k version, `mde_per_sd_family`, is reported too.

Port change: v2 counted aliased coefficients in the outcome joint test's df (`length(coef(m1)) - 1`). Here df = `m0$df.residual - m1$df.residual`, as `anova()` computes it. Task 7 shows what that changes.

**Files:**
- Create: `backtest/vvf/s1_screen.R`
- Test: `tests/testthat/test-vvf-s1.R`

**Interfaces:**
- Consumes: Task 4's `vvf_assert_known_at`, `vvf_registry`; Task 3's anchored table (columns `y`, `lp_anchor`, `wk`, the features and the targets; attribute `vvf_anchor`).
- Produces: `VVF_ALPHA` (0.05), `VVF_POWER` (0.80), `VVF_Q_SIGNAL` (0.05), `VVF_MIN_CLUSTERS` (30L), `VVF_WILD_B` (9999L), `VVF_WILD_SEED` (20261020L), `VVF_FAMILIES_CLOSE` (`outcome = "y", spread = "ats_resid", total = "tot_resid"`); `vvf_rademacher(G, B, seed)`; `vvf_wild_p_linear(r, x, cluster, B, seed)`; `vvf_wild_p_score(y, lp, x, cluster, B, seed)`; `vvf_mde_per_sd(n, family, v, sigma, alpha, power, k)`; `vvf_s1_one(dat, family, feature, response, B, seed) -> one row` (`n, n_clusters, mean_x, sd_x, test, stat, p_test, estimate, se_robust, ci_lo, ci_hi, p_robust, robust_method, p, effect_per_sd, effect_ci_lo, effect_ci_hi, mde_per_sd`); `vvf_s1_joint(dat, family, features, response) -> one row` (`n, n_clusters, k_entered, k, test, stat, df, p_test, wald_robust, p_wald_robust, features, aliased`); `vvf_s1_screen(d, features, decision, families, joint_sets, registry, B, seed) -> list(features, joint, n, anchor, decision)`, where `features` adds `q_bh`, `mde_per_sd_family`, `verdict`, `anchor` and `decision`.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-vvf-s1.R`:

> `tests/testthat/test-vvf-s1.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 2: Run it and see it fail.**

Run: `Rscript -e "testthat::test_dir('tests/testthat', filter = 'vvf-s1', reporter = 'summary')"`
Expected: `'.../backtest/vvf/s1_screen.R' is not an existing file`.

- [ ] **Step 3: Write the implementation.** Create `backtest/vvf/s1_screen.R`:

> `backtest/vvf/s1_screen.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 4: Run the test and see it pass.** Expected: `vvf-s1: ` followed by 43 dots, then `DONE` (about 70 s; the 500-simulation tests dominate). The rates behind the known-answer tests (dry-run scratch script `s1_rates.R`, same seeds):
  - **Null, 40 clusters, 500 simulations, band [0.032, 0.070]:** the LR rejection rate is 0.068, and the combined p's is 0.062.
  - **Null, 12 clusters:** wild score bootstrap 0.058, wild bootstrap-t 0.054.
  - **150 clusters, wild against vcovCL:** linear 0.1731 against 0.1743, outcome 0.0081 against 0.0078.
  - **The planted 0.5 effect (n = 2,000):** p = 5.06e-22 with 100 clusters, estimate 0.483. With 15 clusters the wild p is at its floor, 1e-4.

- [ ] **Step 5: Gates and commit.**

```bash
git add backtest/vvf/s1_screen.R tests/testthat/test-vvf-s1.R
git commit -m "feat(vvf): S1 screen with the anchor as a parameter, wild cluster bootstrap below 30 clusters, BH, MDE and known-answer tests" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: S2, structure (sonnet)

The VIF depends only on the design, so it is computed from `lm(target ~ features)` for every family. The order of the steps:
1. Constant features are logged first.
2. Aliased features are logged next: those `lm` returns as NA, which are the later-declared ones.
3. While any VIF exceeds 5, the later-declared of the features over the limit is dropped and logged.

Season stability compares `y ~ factor(period) + x` with `y ~ factor(period) * x` (the anchor offset applies to the outcome). The periods are seasons, or season halves (week ≤ 9) when the window has two seasons or fewer.

**Files:**
- Create: `backtest/vvf/s2_structure.R`
- Test: `tests/testthat/test-vvf-s2.R`

**Interfaces:**
- Consumes: Task 4's `vvf_assert_known_at`; Task 5's `VVF_FAMILIES_CLOSE`.
- Produces: `VVF_VIF_MAX` (5), `VVF_HALF_WEEK` (9L); `vvf_s2_vif(dat, features, response) -> list(kept, vif, dropped = data.table(feature, reason))`; `vvf_s2_stability(dat, family, feature, response) -> one row` (`periods, n_periods, pooled, by_period, sign_consistent, test, int_stat, int_df, int_p`); `vvf_s2_structure(d, features, decision, families, registry) -> list(vif = data.table(family, kept, dropped, reasons, max_vif), stability)`.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-vvf-s2.R`:

> `tests/testthat/test-vvf-s2.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 2: Run it and see it fail.**

Run: `Rscript -e "testthat::test_dir('tests/testthat', filter = 'vvf-s2', reporter = 'summary')"`
Expected: `'.../backtest/vvf/s2_structure.R' is not an existing file`.

- [ ] **Step 3: Write the implementation.** Create `backtest/vvf/s2_structure.R`:

> `backtest/vvf/s2_structure.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 4: Run the test and see it pass.** Expected: `vvf-s2: ` followed by 24 dots, then `DONE`.

- [ ] **Step 5: Gates and commit.**

```bash
git add backtest/vvf/s2_structure.R tests/testthat/test-vvf-s2.R
git commit -m "feat(vvf): S2 structure (VIF with declared-first precedence, per-period signs, feature x period tests)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The port's known-answer test: v2's §1 reproduced (sonnet)

**Files:**
- Create: `backtest/vvf/reproduce_v2.R`, `tests/testthat/fixtures/vvf/v2_screen_features.csv`, `tests/testthat/fixtures/vvf/v2_screen_joint.csv`, `reports/2026-10-22/vvf-v2-repro/` (generated)
- Test: `tests/testthat/test-vvf-v2-reproduction.R`

**Interfaces:**
- Consumes: Tasks 1–6 (all of `common.R`, `features.R`, `registry.R`, `provenance.R`, `s1_screen.R`, `s2_structure.R`) and v1's candidate files.
- Produces: `VVF_V2_TUNE` (2018:2022), `VVF_V2_MAX_SEASON` (2022L), `VVF_V2_FAMILY_MAP` (`ml/ats/tot` → `outcome/spread/total`), `VVF_V2_RESULT_FILES`; `vvf_v2_table() -> list(d, base)`; `vvf_v2_base_check(base, path)`; `vvf_v2_run(x) -> list(s1, s2)`; `vvf_v2_compare(s1, fixture_dir) -> list(rows, max_rel_diff)`; `vvf_v2_headline(res)`; `vvf_v2_write(res, out_dir, base_check, fidelity)`. The committed run directory `reports/2026-10-22/vvf-v2-repro/` (`s1_features.csv`, `s1_joint.csv`, `s2_vif.csv`, `s2_stability.csv`, `run_meta.json` with `result_sha256`) is what Task 8's ledger reads.

- [ ] **Step 1: Copy v2's committed screen as fixtures, byte for byte.**

```bash
mkdir -p tests/testthat/fixtures/vvf
git show 759dd1c:reports/2026-09-30/validation-sprint/screen/features.csv > tests/testthat/fixtures/vvf/v2_screen_features.csv
git show 759dd1c:reports/2026-09-30/validation-sprint/screen/joint.csv > tests/testthat/fixtures/vvf/v2_screen_joint.csv
sha256sum tests/testthat/fixtures/vvf/*.csv | cut -c1-20
```
Expected: `aac7e722f2c760297be6` (features), `681ed78d1d00dcd79e0e` (joint): 115 and 7 lines.

- [ ] **Step 2: Write the failing test.** Create `tests/testthat/test-vvf-v2-reproduction.R`:

> `tests/testthat/test-vvf-v2-reproduction.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 3: Run it and see it fail.**

Run: `Rscript -e "testthat::test_dir('tests/testthat', filter = 'vvf-v2-reproduction', reporter = 'summary')"`
Expected: `'.../backtest/vvf/reproduce_v2.R' is not an existing file`.

- [ ] **Step 4: Write the implementation.** Create `backtest/vvf/reproduce_v2.R`:

> `backtest/vvf/reproduce_v2.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 5: Run the reproduction and commit its outputs.**

Run: `HOME=<empty scratch dir> Rscript backtest/vvf/reproduce_v2.R --out reports/2026-10-22/vvf-v2-repro`
Expected (dry run, Windows, R 4.5.1, 1 min 42 s):
```
base vs v1: 1372 games, max |diff| 5.00e-11
S1 vs v2: 108 rows, max relative difference 4.54e-06
outcome joint (situational): chi2 26.9332, 30 entered, df 29, p 0.5753 (v2's df 30: p 0.6268)
outcome min q: 0.4879 (abs_tz_away)
spread abs_tz_away: -0.8792 [-1.4625, -0.2959], p 0.0041, q 0.1468
result_sha256: 339f63e0591b8bad234049624f3be2ebee23b0af4dfc7cf1eb5e01c054cca288
```
The script stops if the base predictions differ from v1's by more than 1e-9 or any S1 column differs from v2's by more than 1e-5 (relative). On another platform `result_sha256` may differ only through the last of the six significant digits written; the numbers above may not.

**What reproduces, and the one difference.** v2's REPORT.md §1 numbers are reproduced:
- the moneyline joint χ² 26.9;
- the minimum q 0.49 (`abs_tz_away`);
- the spread time-zone effect −0.88 [−1.46, −0.30], p = 0.004, q = 0.15.

All 108 single-feature rows match v2's CSV to its six digits. v2's joint **p = 0.63 is reproduced only under v2's df rule** (30, which counts the aliased `inj_diff_all`). With the 29 estimable coefficients that `anova()` uses, p = 0.575. The conclusion ("nothing beyond the close") is unchanged. The ledger and any reuse of the figure should quote 0.575 with this note.

- [ ] **Step 6: Run the test and see it pass.** Expected: `vvf-v2-reproduction: ` followed by 31 dots, then `DONE` (the test recomputes everything: about 30 s of work, several minutes of wall time on a busy machine).

- [ ] **Step 7: Gates and commit.**

```bash
git add backtest/vvf/reproduce_v2.R tests/testthat/fixtures/vvf tests/testthat/test-vvf-v2-reproduction.R reports/2026-10-22/vvf-v2-repro
git commit -m "test(vvf): the port reproduces v2's close-anchored screen (108 rows; joint df counts estimable terms)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The variable ledger, generated (haiku)

**Files:**
- Create: `backtest/vvf/ledger.R`, `scripts/write_variable_ledger.R`, `docs/VARIABLE_LEDGER.md` (generated)
- Test: `tests/testthat/test-vvf-ledger.R`

**Interfaces:**
- Consumes: Task 4's `vvf_registry`, `VVF_KNOWN_AT`, `VVF_DECISIONS`, `VVF_DECISION_INFO`, `vvf_disclosures`, `VVF_V2_FEATURES`; Task 1's `vvf_read_csv`, `vvf_write_text`; Task 7's committed run directory.
- Produces: `VVF_LEDGER_RUNS` (one row per anchor: `anchor, decision, stages, window, dir`; A3b adds S3); `vvf_md_cell(x)`; `vvf_md_table(header, rows)`; `vvf_ledger_results(run)`; `vvf_render_ledger(registry, runs, disclosures) -> character()` (one element per line, ASCII).

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-vvf-ledger.R`:

> `tests/testthat/test-vvf-ledger.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 2: Run it and see it fail.**

Run: `Rscript -e "testthat::test_dir('tests/testthat', filter = 'vvf-ledger', reporter = 'summary')"`
Expected: `'.../backtest/vvf/ledger.R' is not an existing file`.

- [ ] **Step 3: Write the renderer.** Create `backtest/vvf/ledger.R`:

> `backtest/vvf/ledger.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 4: Write the script and generate the ledger.** Create `scripts/write_variable_ledger.R`:

> `scripts/write_variable_ledger.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

Run: `Rscript scripts/write_variable_ledger.R`. Expected: `wrote docs/VARIABLE_LEDGER.md`, a 162-line file. Spot-check, for example, the `abs_tz_away` row: `| 0.488 / 0.147 / 0.896 | VIF dropped, VIF 5.001 > 5; signs stable; x season p 0.823 |`.

- [ ] **Step 5: Run the test and see it pass.** Expected: `vvf-ledger: ` followed by dots, then `DONE`, with no failure.

- [ ] **Step 6: Gates and commit.**

```bash
git add backtest/vvf/ledger.R scripts/write_variable_ledger.R docs/VARIABLE_LEDGER.md tests/testthat/test-vvf-ledger.R
git commit -m "docs(vvf): docs/VARIABLE_LEDGER.md generated from the registry and the committed results, with a docs-truth test" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The F11 diagnosis script, with no engine edit (sonnet)

`simulate_game_nb()` warns `invalid mu_home=NA, using fallback 21.5` and goes on. The script runs `run_week.R` in its own process. A calling handler catches each such warning, without muffling it, and walks `sys.frames()` to find two frames:
- the frame of `week_inputs_and_sim_2w()`, which holds `g`, `cut_season` and `cut_week`;
- the `lapply()` closure below it, which holds `i`.

It records that game's mean terms. The cut season is checked against the seal, and the target season must not be sealed. A cached calibration stops the script, because it would hide F11.

**Files:**
- Create: `scripts/diagnose_mu_na.R`
- Test: `tests/testthat/test-diagnose-mu-na.R`

**Interfaces:**
- Consumes: `load_script_functions()` (`tests/testthat/helper-extract.R`); Task 1's `vvf_sealed_seasons`, `vvf_write_csv`.
- Produces: `DMN_TERMS`, `DMN_PATTERN`; `dmn_find_game(frames) -> data.frame | NULL`; `dmn_capture(run, sealed) -> list(rows, warnings_sealed, warnings_unlocated)`; `dmn_summarise(rows) -> data.table(term, n_na, n_games)`; `dmn_main(args)`.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-diagnose-mu-na.R`:

> `tests/testthat/test-diagnose-mu-na.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 2: Run it and see it fail.**

Run: `Rscript -e "testthat::test_dir('tests/testthat', filter = 'diagnose-mu-na', reporter = 'summary')"`
Expected: `Error in file(filename, "r"): cannot open the connection` (the script does not exist yet).

- [ ] **Step 3: Write the script.** Create `scripts/diagnose_mu_na.R`:

> `scripts/diagnose_mu_na.R`: the dry run's file, committed verbatim on `feat/a3a-vvf`.

- [ ] **Step 4: Run the test and see it pass.** Expected: `diagnose-mu-na: ` followed by 13 dots, then `DONE`.

- [ ] **Step 5: Gates and commit.**

```bash
git add scripts/diagnose_mu_na.R tests/testthat/test-diagnose-mu-na.R
git commit -m "feat(f11): diagnose which mean term is NA in the calibration backtest, from the call frames, with no engine edit" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: The bye-week regression check (sonnet; Step 2 waits for #223 and the F11b fix)

F11's cause was found on 2026-10-26 (`reports/2026-10-21/OUTPUT_AUDIT.md`): `hfa_tbl` held only the slate's teams, so every calibration game of a team on a bye was a coin flip. PR #223 fixes it. `scripts/diagnose_mu_na.R` stays as the regression check for that fix; this task edits no engine file.

**Files:**
- Create: `reports/2026-10-26/f11-bye-week-main/` (`mu_na_summary.csv`, `mu_na_teams.csv`, `mu_na_terms.csv`)

- [ ] **Step 1: The positive control on main.** Run: `HOME=<fresh> Rscript scripts/diagnose_mu_na.R 5 2024 reports/2026-10-26/f11-bye-week-main`. The byes of 2024 week 5 are DET, LAC, PHI and TEN. Expected (measured in the dry run on 2026-10-26, 37 minutes):
  - 328 calibration games have a missing mean;
  - `home_hfa` is missing in 171 and `away_hfa` in 172, the bye teams' games (F11);
  - the four drive inputs are missing in 16, which is every 2019 Raiders game, 8 at home and 8 away. This is F11b: the play-by-play files the 2019 Raiders as `LV` and the schedule as `OAK`.
- [ ] **Step 2 (after #223 and the F11b fix merge): the regression check.** The same command on the merged main. Expected: no game with a missing mean. Commit its output as `reports/<date>/f11-bye-week-fixed/`.
- [ ] **Step 3: Commit Step 1's output.**

```bash
git add reports/2026-10-26/f11-bye-week-main
git commit -m "test(f11): the bye-week positive control on main: 328 calibration games with a missing mean (F11, and F11b's 2019 Raiders)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---


### Task 11: Docs (haiku)

**Files:**
- Modify: `CHANGELOG.md`, `CLAUDE.md` (§6 file inventory), `HANDOFF.md`

- [ ] **Step 1: CHANGELOG.** Add an "A3a" entry under `[Unreleased]`. It covers:
  - the port: PR #205's builder, features and locked inputs for 2009–2024;
  - the registry and S0, then S1 and S2;
  - the reproduction of v2's §1, with Task 7's numbers;
  - the generated ledger and the F11 diagnosis script;
  - the disclosure that v1's `backtest/build_inputs.R:106` reads the 2024–2025 price file and drops 2025 after reading it.
- [ ] **Step 2: CLAUDE.md §6.** Add these entries:
  - `backtest/vvf/`, the validation framework for S0–S2;
  - `docs/VARIABLE_LEDGER.md`, generated and never edited by hand;
  - `scripts/write_variable_ledger.R`;
  - `scripts/diagnose_mu_na.R`.
- [ ] **Step 3: HANDOFF.** Add an A3a context-reset packet: objective, done, not done, confirmed facts, open risks and next target (A3b).
- [ ] **Step 4: Gates.** `test-docs-truth.R` and `test-repo-hygiene.R` pass; the full suite and the integrity check exit 0 with a fresh HOME.
- [ ] **Step 5: Commit.**

```bash
git add CHANGELOG.md CLAUDE.md HANDOFF.md
git commit -m "docs(vvf): A3a in the changelog, the file inventory and the handoff" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---


### Task 12: Dropped (2026-10-26)

The owner-STOP edit of `simulate_game_nb()` is no longer needed. #223's `assert_finite_means()` stops a calibration week before a missing mean can reach `simulate_game_nb()`. The slate path's `safe_mu` stays with G1.

---


## Dry-run evidence (2026-10-22 to 2026-10-26, `a3dry`, detached at main `4c1c377`)

- **Baseline** (fresh HOME):
  - `run_tests.R`: 455 tests, 1,756 passed, 0 failed, 1 allowlisted skip;
  - integrity: 63 passed.
- **Every task** ran RED as its Step 2 says, then GREEN with the counts above.
- **Task 7:**
  - base against v1: 1,372 games, max |diff| 5.00e-11;
  - S1 against v2: 108 rows, max relative diff 4.54e-06;
  - the outcome joint test: χ² 26.9332 with 30 entered and df 29, p 0.5753 (v2 counted df 30, p 0.6268);
  - the spread's `abs_tz_away`: −0.8792 [−1.4625, −0.2959], p 0.0041, q 0.1468;
  - result_sha256: `339f63e0591b8bad234049624f3be2ebee23b0af4dfc7cf1eb5e01c054cca288`.
- **Task 10:** Step 1, as above.

## Owner checkpoints

1. **The disclosure.** v1's `backtest/build_inputs.R:106` reads `reports/2026-09-29/clv-power/espn_open_close_2024_2025.csv` and drops 2025 only after reading it (spec §6). The VVF test allows exactly that one site.
2. **F11b's fix:** franchise codes or schedule codes. It is an engine edit, and Task 10 Step 2 waits for it.
3. **The merge.**

## Self-review

- **Spec coverage:**
  - S0: Task 4;
  - S1: Task 5;
  - S2: Task 6;
  - the known-answer tests: Tasks 5 and 7;
  - the ledger: Task 8;
  - the port: Tasks 1–3;
  - F11: Tasks 9 and 10.
  - S3–S5 and the controls are A3b.
- **Interfaces:** Tasks 2–9 consume Task 1's helpers, as named in each Interfaces block.
- **Placeholders:** none. Every file named in a task is the dry run's file, committed verbatim on `feat/a3a-vvf`.

## Execution

Native (inline), with one Haiku whole-branch review at the end (owner decision of 2026-10-26).

