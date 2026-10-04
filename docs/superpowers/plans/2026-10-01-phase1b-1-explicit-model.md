# Phase 1b-1: Explicit Game Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the game model's simulated means an explicit, logged sum of named terms, with only two terms admitted: drives × points per drive, and home field. These are exactly what the engine already simulates, so means are unchanged. The plan also:
- derives score SDs, NB sizes and score correlation from those means (M22b);
- stops loudly instead of silently rebuilding a broken mean;
- fixes the schedule bugs that feed the means and the calibration history: neutral sites (M24), rest days (M23), and the Sleeper look-ahead (M20).

**Architecture:**
- **Means.** The adjustment chain in `NFLsimulation.R` stays as written but no longer decides the simulated means. `R/mu_terms.R` reads every term the chain computed into a per-game table and sums the admitted ones (`config.R` `MU_TERMS_ADMITTED`). It stops on a non-finite admitted term. The other terms are logged to `run_logs/mu_terms_*.rds` so their sizes stay visible.
- **Variance.** Score SDs, NB sizes and rho are computed once, from the composed means.
- **Schedule context.** Neutral site, home-field points and rest points become pure functions in `R/schedule_context.R`. The current week and the calibration-history simulator both use them.
- **Commits.** Each fix is one commit, so the golden-master CI attributes every output change to one cause.

**Tech Stack:** R 4.5.1 with renv; testthat 3.3.2 (`local_mocked_bindings`, `load_script_functions()` from `tests/testthat/helper-extract.R`); dplyr; nflreadr 1.5.0; the GitHub Actions golden-master workflow.

**Spec:** `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` §5 Phase 1. Its point-in-time items (M5, M6, M8, M9) are Plan 1b-2; see the roadmap at the end.
- **Findings:** M20, M22, M22b, M23 and M24 are in `reports/2026-09-29/AUDIT-ADDENDUM.md` (draft PR #200). M22b and M24 were added with this plan; see "Measured baseline" below.
- **Owner decision, 2026-10-01:** "Explicit model, earn each term". No term is added to the means until the walk-forward backtest admits it (Plan 1b-3).

## Global Constraints

- **Owner approval of this plan is required before Task 1.** Approval covers:
  - the `NFLsimulation.R` edits named in each task;
  - a new `config.R` setting, `MU_TERMS_ADMITTED`, whose default reproduces today's means;
  - the golden-master changes predicted for Tasks 4–6.
- **Branch.** Work on `fix/phase1b-1-explicit-model` in a worktree:
  - Create it from the latest `main`: `git worktree add ../nfl-worktrees/phase1b1 -b fix/phase1b-1-explicit-model origin/main`.
  - Copy the gitignored `.Rprofile` from the main checkout into the worktree so renv activates.
  - If #203 (M19) has merged, branch after it. It re-records the golden master.
  - This branch is fix-only. No new term is admitted and nothing is tuned.
- **One commit per task.** The golden-master workflow records every commit of the PR, so each output change is attributed to the task that caused it.
- **TDD.** In every task, write the failing test and run it before the code.
- **Gate after every task.** Both must exit 0; quote their summary lines in the task report:
  - `Rscript scripts/run_tests.R`
  - `Rscript scripts/verify_repo_integrity.R`
- **No 2025 data.** Nothing here reads, builds or scores the 2025 season. The golden-master fixture is 2024 week 15.
- **No file deletions.** The code blocks inside `NFLsimulation.R` that a task replaces are removed in that task; nothing else.
- **Golden master on Windows (audit T8).** A local `compare` always differs in the 8 blend columns: up to 0.0118 in `home_p_2w_blend_raw` and 0.30 in `margin_blend`, from the invalid step-function calibrator. Locally, only check the simulator columns. CI (Linux) is the authority.
  - **Erratum (2026-10-04):** the Windows blend-column differences were a stale calibration cache (unbumped `calib_cache_key`), not an operating-system effect. With the v3 key a local compare shows no differences; see `reports/2026-09-29/golden-master/2024-w15/ATTRIBUTION.md`.
- **Windows.**
  - Write R files with a file-writing tool; bash heredocs collapse `\\`.
  - Pass `C:/...` paths to R.
  - List a directory before any `rm -rf`.
- **Numbers in docs** come only from a script run: the CI attribution or `reports/2026-10-01/phase1b-1-evidence/`.
- **Commit trailer:** `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Merging needs owner approval.

## Measured baseline (2026-10-01)

The scripts and their saved outputs are in `reports/2026-10-01/phase1b-1-evidence/`. Run them from the repo root. The saved run is `run_logs/games_ready_20260929_224207.rds`, a local run of 2024 week 15, the golden-master week.

| Check | Result |
|---|---|
| Simulated means vs the rescue formula (`NFLsimulation.R:6271-6284`) | `mu_home` = drives × PPD + `HFA_pts` and `mu_away` = drives × PPD, **bit-identical in 16/16 games**. So composing `base + hfa` reproduces today's output. |
| Turnover term (`home_to_adj`, `away_to_adj`) | Non-finite in 16/16. nflverse schedules have no turnover columns, which is the M22 root cause. |
| The 15 named terms summed vs the legacy chain's `total_mu` (erratum: 13 terms; turnover and weather enter after `total_mu`) | max \|difference\| 1.4e-14. No `pmax` clamp bound, so the term table is an exact decomposition. |
| Legacy term sizes, points per side (min..max, mean \|x\|) | location −16.18..+14.42 (6.98); special teams −5.73..+5.73 (2.43); glmm −2.94..+2.05; hfa −2.04..+3.24; situational −1.36..+1.64; rest −0.85..+1.00; everything else ≤ 1.09 in size. One legacy side mean is 1.11 points. |
| **M22b:** legacy `total_mu` (sets SDs, NB sizes and rho today) vs simulated total | Gap up to **28.0 points**: CHI @ MIN 22.4 vs 50.3. |
| M22b prediction (score SDs from the simulated means) | `sd_goal` moves from 9.50–16.84 to 13.02–16.84. `sd_home`/`sd_away` change by −0.31..+1.39 and rise in 10 of 16 games. CHI @ MIN changes most. |
| **M23**, 2024 wk 15 (first slate row: Thursday LA @ SF) | Short-rest teams: **24/32 today** vs 4/32 from each team's own game. Rest days are wrong for 30/32 teams. |
| nflverse `home_rest`/`away_rest` vs own-date rest, 2024 | Equal in all 538 team-games from week 2 on. Week 1 is 7 for all teams (own-date 207–246). The columns are populated for all 224 unplayed 2026 games. |
| **M24** | The engine's neutral-site column candidates are absent. nflverse `location` for 2015–2024: Home 2,690, Neutral 53 (42 regular season, 11 postseason). 2026 unplayed games: Home 218, Neutral 6, no missing values. |
| M24 prediction | League HFA 1.7061 → 1.7203. The 2024 wk 15 home teams' `HFA_pts` change by −0.33..+0.20; 7 teams move more than 0.05: ARI, CLE, JAX, LAC, NO, SF, TEN. |

### Dry run of this plan (2026-10-01)

Every code block in this plan was applied verbatim to throwaway worktrees of `main` (`cb7eaac`) by `reports/2026-10-01/phase1b-1-evidence/dry-run/apply_plan.R`. Nothing was committed, and the worktrees were then removed.

- Every replacement anchor matched exactly once in `NFLsimulation.R`, `config.R` and `scripts/golden_master.R`.
- The new test files pass at the counts each task states: 23, 20, 13, 24 and 17.
- With all seven tasks applied, the full gates pass:
  - `scripts/run_tests.R`: 421 tests, 1,581 passed, 0 failed, 0 errors, 1 allowlisted skip (KNOWN-DEFECT P13), 0 unapproved; exit 0.
  - `scripts/verify_repo_integrity.R`: 60/60; exit 0.
- Full engine on 2024 week 15, Windows (`dry-run/analyze.out.txt`, `dry-run/compare_*.out.txt`):
  - **After Tasks 1–3:** means, SDs and rho are bit-identical to the pre-fix run. The golden-master compare shows only the 8 T8 blend columns, at their known magnitudes.
  - **After Tasks 1–7:**
    - The engine runs to completion.
    - `HFA_pts` changes by −0.329..+0.205 for the 7 predicted teams, and `mu_home` moves by exactly that (residual 4e-15). `mu_away` is identical.
    - `sd_goal` spans 13.02–16.84, and score SDs change by −0.32..+1.39, rising in 10 games. `total_mu` equals the simulated total.
    - 4 of 32 teams are on short rest: SF, LA, DAL and CIN.
- The dry run found four defects in an earlier draft of this plan, all fixed here:
  - a structural check that matched `simulate_game_nb`'s own guard;
  - a 1-d array from `tapply()` in `compute_rest_table()`;
  - `NB_SIZE_MIN`/`NB_SIZE_MAX` missing from the variance test's environment;
  - wrong expectation counts.
- The dry run validates the plan. It does not replace the per-task gates or the CI attribution.

## Review Focus

1. **A non-finite admitted term** (missing turnover data, a failed join). The run must stop and name the term and the game ids. It must never simulate a substitute mean. → Task 2 tests `compose_mu()`; Task 3 removes the rescue.
2. **Neutral-site games, including the Super Bowl** with its playoff HFA multiplier. The listed home team gets zero home-field points, and neutral games are left out of the HFA estimate. → Task 5 tests `home_field_points(..., playoff_mult = 1.2, neutral_site = TRUE)`.
3. **Thursday and Monday games, byes, week 1.** Each team's rest comes from its own schedule row. A bye earns the bye bonus and not the long-rest bonus. Week 1 is neutral. → Task 6 tests.
4. **Re-running a completed week** (backtest, golden master, last season) when nflverse injuries fail. Today's Sleeper report must not be used. A live slate gets rows stamped with the slate's own season and week. → Task 7 tests.
5. **Golden-master runs whose inputs differ**: an injury fallback, a weather fallback, a missing market. The attribution must flag the input drift instead of blaming the code. → Task 1 tests.

---

### Task 1: Golden master records and compares input statuses

**Files:**
- Modify: `scripts/golden_master.R`
- Test: `tests/testthat/test-golden-master-compare.R` (append)

**Interfaces:**
- Produces:
  - `gm_input_status()` → named list `injury, weather, market, calibration, weather_fallback_games, market_missing_games` from `get_data_quality()`. The game-id vectors are sorted.
  - `gm_write_inputs(inputs, dir)` writes `<dir>/inputs.csv` with columns `field,value`; vectors are joined with `;`.
  - `gm_read_inputs(dir)` → named list of strings, or `NULL` when there is no `inputs.csv`.
  - `gm_input_drift(a, b)` → names of fields whose values differ. It returns empty when either side is `NULL`, so records made before this change compare as before.
- Behavior:
  - `record` writes `inputs.csv` and `meta.json$inputs`.
  - `compare` prints `INPUT DRIFT: <field> golden=<x> current=<y>` and exits 1.
  - `attribute` prints `INPUT DRIFT at <sha7> vs baseline <sha7>: <fields>`.
  - `attribute` stays base-R only: the CI job runs `Rscript --vanilla` without renv.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-golden-master-compare.R`:

```r
test_that("gm_input_drift names the inputs that changed", {
  a <- list(injury = "full", weather = "full", market = "full", calibration = "none")
  expect_equal(gm_input_drift(a, a), character())
  expect_equal(gm_input_drift(a, modifyList(a, list(injury = "partial", market = "partial"))), c("injury", "market"))
  expect_equal(gm_input_drift(NULL, a), character())   # records made before inputs were kept
})

test_that("input statuses survive a write and read", {
  dir <- withr::local_tempdir()
  inputs <- list(injury = "full", weather = "partial_fallback", market = "full", calibration = "none",
                 weather_fallback_games = c("2024_15_WAS_NO", "2024_15_KC_CLE"), market_missing_games = character())
  gm_write_inputs(inputs, dir)
  back <- gm_read_inputs(dir)
  expect_equal(back$weather_fallback_games, "2024_15_KC_CLE;2024_15_WAS_NO")
  expect_equal(back$market_missing_games, "")
  expect_equal(gm_input_drift(inputs, back), character())
  expect_null(gm_read_inputs(withr::local_tempdir()))
})

test_that("gm_input_status reads the data-quality tracker", {
  withr::defer(reset_data_quality())
  reset_data_quality()
  update_injury_quality("partial", missing_seasons = "2024")
  update_weather_quality("partial_fallback", fallback_games = c("b", "a"))
  s <- gm_input_status()
  expect_equal(s$injury, "partial")
  expect_equal(s$weather, "partial_fallback")
  expect_equal(s$weather_fallback_games, c("a", "b"))
})

test_that("gm_attribute flags input drift between recorded commits", {
  root <- withr::local_tempdir()
  write_run <- function(name, p, injury) {
    dir.create(file.path(root, name))
    utils::write.csv(data.frame(game_id = c("a", "b"), p = p), file.path(root, name, "final_numeric.csv"), row.names = FALSE)
    writeLines("{}", file.path(root, name, "meta.json"))
    gm_write_inputs(list(injury = injury, weather = "full", market = "full", calibration = "none"), file.path(root, name))
  }
  write_run("c1", c(0.5, 0.6), "full")
  write_run("c2", c(0.5, 0.7), "partial")
  out <- capture.output(gm_attribute(root, c("c1", "c2")))
  expect_true(any(grepl("INPUT DRIFT at c2 vs baseline c1: injury", out, fixed = TRUE)))
})
```

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `Rscript -e "testthat::test_file('tests/testthat/test-golden-master-compare.R')"`
  - Expected: FAIL with `could not find function "gm_input_drift"`. The 3 existing tests still pass.

- [ ] **Step 3: Implement.** In `scripts/golden_master.R`, insert this after `GM_COMPARE_TOL <- 1e-6`:

```r
# Input statuses change the output without any code change (audit M20: a run that lost the
# nflverse injury file and fell back to Sleeper differed in 69 columns). Every record keeps
# them, and compare/attribute flag drift instead of attributing it to code.
gm_input_status <- function() {
  if (!exists("get_data_quality", mode = "function")) stop("golden_master: get_data_quality() is not loaded")
  q <- get_data_quality()
  list(injury = q$injury$status, weather = q$weather$status, market = q$market$status,
       calibration = q$calibration$method,
       weather_fallback_games = sort(as.character(q$weather$fallback_games)),
       market_missing_games = sort(as.character(q$market$missing_games)))
}

gm_flat <- function(v) paste(sort(as.character(unlist(v))), collapse = ";")

# inputs.csv rather than JSON: `attribute` runs under Rscript --vanilla without jsonlite
gm_write_inputs <- function(inputs, dir) {
  utils::write.csv(data.frame(field = names(inputs), value = vapply(inputs, gm_flat, character(1)), row.names = NULL),
                   file.path(dir, "inputs.csv"), row.names = FALSE)
}

gm_read_inputs <- function(dir) {
  path <- file.path(dir, "inputs.csv")
  if (!file.exists(path)) return(NULL)
  x <- utils::read.csv(path, colClasses = "character", na.strings = character())
  stats::setNames(as.list(x$value), x$field)
}

gm_input_drift <- function(a, b) {
  if (is.null(a) || is.null(b)) return(character())
  keys <- union(names(a), names(b))
  keys[vapply(keys, function(k) !identical(gm_flat(a[[k]]), gm_flat(b[[k]])), logical(1))]
}
```

Make these edits in the same file:
1. In `gm_run_model()`, change the returned list to:

```r
  list(data = as.data.frame(final[, c("game_id", names(final)[num & names(final) != "game_id"])]),
       seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
       inputs = gm_input_status())
```

2. In `gm_attribute()`, insert this right after `base <- gm_read(file.path(root, commits[1]))`:

```r
  base_inputs <- gm_read_inputs(file.path(root, commits[1]))
  for (cm in c(paste0(commits[1], "-rep2"), commits[-1])) {
    drift <- gm_input_drift(base_inputs, gm_read_inputs(file.path(root, cm)))
    if (length(drift)) cat(sprintf("INPUT DRIFT at %s vs baseline %s: %s\n", substr(cm, 1, 7),
                                   substr(commits[1], 1, 7), paste(drift, collapse = ", ")))
  }
```

3. In `gm_main()`, record branch: after the `utils::write.csv(run$data, ...)` line, add `gm_write_inputs(run$inputs, dir)`. Also add `inputs = run$inputs` to the `meta <- list(...)` call.
4. In `gm_main()`, replace the compare branch with:

```r
  } else if (mode == "compare") {
    golden_inputs <- gm_read_inputs(dir)
    drift <- gm_input_drift(golden_inputs, run$inputs)
    for (f in drift) cat(sprintf("INPUT DRIFT: %s golden=%s current=%s\n", f, golden_inputs[[f]], gm_flat(run$inputs[[f]])))
    d <- gm_diff(gm_read(dir), run$data, tol = GM_COMPARE_TOL)
    if (nrow(d)) print(d, row.names = FALSE) else cat("golden master: no differences\n")
    if (nrow(d) || length(drift)) quit(status = 1)
  } else stop("mode must be record, compare or attribute")
```

- [ ] **Step 4: Run the tests and confirm they pass.**
  - Run: same command as Step 2.
  - Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 23 ]`: the 12 existing expectations plus 11 new.
- [ ] **Step 5: Gates.** Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R`; both must exit 0.
- [ ] **Step 6: Commit.**

```bash
git add scripts/golden_master.R tests/testthat/test-golden-master-compare.R
git commit -m "test(golden-master): record input statuses and flag input drift (M20 follow-up)"
```

**Expected golden-master change:** none. Only the script changes, and CI runs the head's script for every commit, so every record of this PR carries `inputs.csv`.

---

### Task 2: The mean-term table and its composition (`R/mu_terms.R`)

**Files:**
- Create: `R/mu_terms.R`
- Test: `tests/testthat/test-mu-terms.R`

**Interfaces:**
- Produces:
  - `MU_TERM_NAMES`: character, in the canonical summation order: `base, hfa, glmm, qb, rest, injury, travel, div_conf, pressure, explosive, location, special_teams, situational, turnover, weather`.
  - `MU_COMPONENT_COLUMNS`: the `games_ready` columns that `mu_components()` reads.
  - `mu_components(games, pressure_pts)` → `list(home = data.frame, away = data.frame)`. Each has `game_id` plus one column per `MU_TERM_NAMES`, in points; the away `hfa` is 0. It stops if a column is missing.
  - `compose_mu(components, admitted)` → `data.frame(game_id, mu_home, mu_away)`. It sums the admitted terms in `MU_TERM_NAMES` order. It stops when:
    - a term is unknown;
    - `"base"` is not admitted;
    - an admitted term is non-finite (the message names the side, the term and the game ids);
    - a composed mean is ≤ 0.
- Consumed later: Task 3 calls `mu_components(games_ready, pressure_pts = PRESSURE_MISMATCH_PTS)` and `compose_mu(mu_terms, MU_TERMS_ADMITTED)`.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-mu-terms.R`:

```r
# Audit M22: the simulated means are the sum of named, admitted terms. Every other term the
# adjustment chain computes is kept in a table, so its size is visible, but not simulated.

mu_fixture <- function() {
  g <- as.data.frame(stats::setNames(replicate(length(MU_COMPONENT_COLUMNS), c(0, 0), simplify = FALSE),
                                     MU_COMPONENT_COLUMNS))
  g$game_id <- c("g1", "g2")
  g$exp_drives_home <- c(11.2, 10.4); g$exp_ppd_home <- c(2.31, 1.97)
  g$exp_drives_away <- c(10.9, 10.6); g$exp_ppd_away <- c(2.05, 2.12)
  g$mu_home_model <- g$exp_drives_home * g$exp_ppd_home
  g$mu_away_model <- g$exp_drives_away * g$exp_ppd_away
  g$HFA_pts <- c(1.72, -0.40)
  g$glmm_w <- c(0.35, 0.35); g$mu_home_glmm <- c(24, NA); g$mu_away_glmm <- c(20, 21)
  g$home_location_boost <- c(-23.1, 4.0)
  g$home_to_adj <- c(NA, NA); g$away_to_adj <- c(NA, NA)   # nflverse has no turnover columns (M22)
  g
}

test_that("every term is computed for both sides; the away side has no home field", {
  comp <- mu_components(mu_fixture(), pressure_pts = 0.6)
  expect_named(comp$home, c("game_id", MU_TERM_NAMES))
  expect_named(comp$away, c("game_id", MU_TERM_NAMES))
  expect_equal(comp$away$hfa, c(0, 0))
  expect_equal(comp$home$location, 0.7 * c(-23.1, 4.0))
  expect_equal(comp$home$glmm, c(0.35 * (24 - 11.2 * 2.31), 0))   # a missing GLMM prediction adds nothing
})

test_that("base + hfa reproduces the pre-fix simulated means bit for bit (audit M22)", {
  g <- mu_fixture()
  mu <- compose_mu(mu_components(g, 0.6), c("base", "hfa"))
  expect_identical(mu$mu_home, pmax(g$exp_drives_home * g$exp_ppd_home + dplyr::coalesce(g$HFA_pts, 0), 0))
  expect_identical(mu$mu_away, pmax(g$exp_drives_away * g$exp_ppd_away, 0))
  expect_identical(mu$game_id, g$game_id)
})

test_that("terms are summed in one fixed order, whatever order config lists them", {
  comp <- mu_components(mu_fixture(), 0.6)
  expect_identical(compose_mu(comp, c("hfa", "glmm", "base")), compose_mu(comp, c("base", "hfa", "glmm")))
})

test_that("a non-finite admitted term stops the run and names the term and games", {
  comp <- mu_components(mu_fixture(), 0.6)
  expect_error(compose_mu(comp, c("base", "turnover")), "home.*turnover \\[g1, g2\\]")
})

test_that("a non-finite term that is not admitted is ignored", {
  expect_silent(compose_mu(mu_components(mu_fixture(), 0.6), c("base", "hfa")))
})

test_that("unknown terms, a missing base and missing columns are rejected", {
  g <- mu_fixture()
  comp <- mu_components(g, 0.6)
  expect_error(compose_mu(comp, c("base", "turnovers")), "unknown term")
  expect_error(compose_mu(comp, "hfa"), "'base'")
  expect_error(mu_components(g[, setdiff(names(g), "HFA_pts")], 0.6), "HFA_pts")
})

test_that("a mean that is not positive stops instead of being clamped", {
  g <- mu_fixture()
  g$HFA_pts <- c(-30, 0)
  expect_error(compose_mu(mu_components(g, 0.6), c("base", "hfa")), "not positive.*g1")
})
```

- [ ] **Step 2: Run the test and confirm it fails.**
  - Run: `Rscript -e "testthat::test_file('tests/testthat/test-mu-terms.R')"`
  - Expected: FAIL with `object 'MU_COMPONENT_COLUMNS' not found`.

- [ ] **Step 3: Implement.** Create `R/mu_terms.R`:

```r
# Explicit composition of the simulated mean scores (audit M22, Plan 1b-1).
#
# The adjustment chain in NFLsimulation.R computes many terms, in points per side. Until
# Plan 1b-1 a non-finite turnover term silently reduced the simulated means to drives x
# points per drive (+ home field). The means are now the sum of the terms named in
# config.R MU_TERMS_ADMITTED. Every other term is still computed and logged
# (run_logs/mu_terms_*.rds) so its size stays visible; it enters the means only after the
# pre-registered walk-forward backtest admits it (Plan 1b-3).

MU_TERM_NAMES <- c("base", "hfa", "glmm", "qb", "rest", "injury", "travel", "div_conf",
                   "pressure", "explosive", "location", "special_teams", "situational",
                   "turnover", "weather")

MU_COMPONENT_COLUMNS <- c(
  "game_id", "exp_drives_home", "exp_ppd_home", "exp_drives_away", "exp_ppd_away", "HFA_pts",
  "glmm_w", "mu_home_glmm", "mu_away_glmm", "mu_home_model", "mu_away_model",
  "home_off_points_adj", "away_off_points_adj", "home_rest_points", "away_rest_points",
  "home_injury_off_total", "away_injury_off_total", "home_injury_def_total", "away_injury_def_total",
  "travel_mu_adj_home", "travel_mu_adj_away", "div_conf_adj",
  "home_press_mismatch", "away_press_mismatch", "expl_edge_home", "expl_edge_away",
  "home_location_boost", "away_location_penalty", "st_impact_home", "st_impact_away",
  "rz_impact_home", "rz_impact_away", "third_down_edge_home", "third_down_edge_away",
  "to_edge_home", "to_edge_away", "penalty_edge_home", "penalty_edge_away",
  "situational_home", "situational_away", "momentum_home", "momentum_away",
  "div_adjustment_home", "div_adjustment_away", "home_to_adj", "away_to_adj",
  "env_total_adj", "mu_home_adj", "mu_away_adj",
  "wind_interaction_home", "wind_interaction_away", "cold_interaction_home", "cold_interaction_away")

#' Per-game points for every mean term, home and away (audit M22)
#'
#' Each term repeats the expression the adjustment chain in NFLsimulation.R adds to the
#' legacy mean, so the terms sum to that chain's total exactly where no clamp binds.
#' @param games games_ready after the environment block
#' @param pressure_pts config PRESSURE_MISMATCH_PTS (points per +10% pressure mismatch)
#' @return list(home = , away = ): data frames of game_id plus one column per MU_TERM_NAMES
mu_components <- function(games, pressure_pts) {
  missing <- setdiff(MU_COMPONENT_COLUMNS, names(games))
  if (length(missing)) stop("mu_components: games is missing ", paste(missing, collapse = ", "), call. = FALSE)
  g <- games
  home <- data.frame(
    game_id       = g$game_id,
    base          = g$exp_drives_home * g$exp_ppd_home,   # expected drives x points per drive
    hfa           = g$HFA_pts,
    glmm          = g$glmm_w * (dplyr::coalesce(g$mu_home_glmm, g$mu_home_model) - g$mu_home_model),
    qb            = g$home_off_points_adj,
    rest          = g$home_rest_points,
    injury        = g$home_injury_off_total + g$away_injury_def_total,
    travel        = dplyr::coalesce(g$travel_mu_adj_home, 0),
    div_conf      = g$div_conf_adj,
    pressure      = -pressure_pts * g$home_press_mismatch,
    explosive     = 0.16 * 5 * g$expl_edge_home,
    location      = 0.7 * g$home_location_boost,
    special_teams = 0.7 * g$st_impact_home,
    situational   = 0.7 * (g$rz_impact_home + g$third_down_edge_home + g$to_edge_home +
                           g$penalty_edge_home + g$situational_home + g$momentum_home +
                           g$div_adjustment_home),
    turnover      = g$home_to_adj,
    weather       = g$env_total_adj / 2 + g$mu_home_adj + g$wind_interaction_home + g$cold_interaction_home,
    stringsAsFactors = FALSE
  )
  away <- data.frame(
    game_id       = g$game_id,
    base          = g$exp_drives_away * g$exp_ppd_away,
    hfa           = 0,
    glmm          = g$glmm_w * (dplyr::coalesce(g$mu_away_glmm, g$mu_away_model) - g$mu_away_model),
    qb            = g$away_off_points_adj,
    rest          = g$away_rest_points,
    injury        = g$away_injury_off_total + g$home_injury_def_total,
    travel        = dplyr::coalesce(g$travel_mu_adj_away, 0),
    div_conf      = g$div_conf_adj,
    pressure      = -pressure_pts * g$away_press_mismatch,
    explosive     = 0.16 * 5 * g$expl_edge_away,
    location      = 0.7 * g$away_location_penalty,
    special_teams = 0.7 * g$st_impact_away,
    situational   = 0.7 * (g$rz_impact_away + g$third_down_edge_away + g$to_edge_away +
                           g$penalty_edge_away + g$situational_away + g$momentum_away +
                           g$div_adjustment_away),
    turnover      = g$away_to_adj,
    weather       = g$env_total_adj / 2 + g$mu_away_adj + g$wind_interaction_away + g$cold_interaction_away,
    stringsAsFactors = FALSE
  )
  list(home = home, away = away)
}

#' Simulated means: the sum of the admitted terms (audit M22)
#'
#' Terms are summed in MU_TERM_NAMES order, so the result does not depend on how config
#' lists them. A non-finite admitted term or a mean that is not positive stops the run;
#' nothing is substituted.
#' @param components output of mu_components()
#' @param admitted character vector of term names; must include "base"
#' @return data.frame(game_id, mu_home, mu_away)
compose_mu <- function(components, admitted) {
  unknown <- setdiff(admitted, MU_TERM_NAMES)
  if (length(unknown)) stop("compose_mu: unknown term(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  if (!"base" %in% admitted) stop("compose_mu: 'base' (drives x points per drive) must be admitted", call. = FALSE)
  if (!identical(components$home$game_id, components$away$game_id)) {
    stop("compose_mu: home and away components are not aligned", call. = FALSE)
  }
  terms <- MU_TERM_NAMES[MU_TERM_NAMES %in% admitted]
  side_mu <- function(comp, side) {
    bad <- lapply(terms, function(t) comp$game_id[!is.finite(comp[[t]])])
    names(bad) <- terms
    bad <- bad[lengths(bad) > 0]
    if (length(bad)) {
      stop(sprintf("compose_mu: admitted term not finite (%s): %s", side,
                   paste(sprintf("%s [%s]", names(bad), vapply(bad, paste, character(1), collapse = ", ")),
                         collapse = "; ")), call. = FALSE)
    }
    mu <- Reduce(`+`, lapply(terms, function(t) comp[[t]]))
    if (any(mu <= 0)) {
      stop(sprintf("compose_mu: %s mean not positive for %s", side, paste(comp$game_id[mu <= 0], collapse = ", ")),
           call. = FALSE)
    }
    mu
  }
  data.frame(game_id = components$home$game_id,
             mu_home = side_mu(components$home, "home"),
             mu_away = side_mu(components$away, "away"),
             stringsAsFactors = FALSE)
}
```

- [ ] **Step 4: Run the test and confirm it passes.**
  - Run: same command as Step 2.
  - Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 15 ]`.
- [ ] **Step 5: Gates.** Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R`; both must exit 0. `setup.R` loads every `R/*.R`, so the new module loads in the suite.
- [ ] **Step 6: Commit.**

```bash
git add R/mu_terms.R tests/testthat/test-mu-terms.R
git commit -m "feat(model): mean-term table and explicit composition, not yet wired (M22)"
```

**Expected golden-master change:** none. The engine does not call the module yet.

---

### Task 3: The engine simulates the composed means (M22)

**Files:**
- Modify:
  - `NFLsimulation.R`: the module-loading block (`:42-69`), the rescue block (`:6271-6284`), and the run-log writes (`:8459-8462`)
  - `config.R`: the new setting after `CONFERENCE_GAME_ADJUST` (`:254`); `.validate_config()` (`:926`)
  - `docs/EVIDENCE_LEDGER.md`
- Test: `tests/testthat/test-mu-terms.R` (append)

**Interfaces:**
- Consumes: `mu_components()` and `compose_mu()` (Task 2).
- Produces:
  - `MU_TERMS_ADMITTED` in config, default `c("base", "hfa")`.
  - `mu_terms`, the term table, in the engine's global environment.
  - `run_logs/mu_terms_<run_id>.rds`.
  - Task 4 inserts its variance step right after the composition line.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-mu-terms.R`:

```r
test_that("the engine simulates the composed means; the silent rescue is gone (audit M22)", {
  src <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]
  expect_true(any(grepl('source(file.path(base_path, "mu_terms.R"))', code, fixed = TRUE)))
  expect_equal(sum(grepl("compose_mu(mu_terms, MU_TERMS_ADMITTED)", code, fixed = TRUE)), 1L)
  expect_false(any(grepl("exp_drives_home * exp_ppd_home + dplyr::coalesce(HFA_pts, 0)", code, fixed = TRUE)))   # the rescue
  expect_equal(sum(grepl('saveRDS(mu_terms, file.path(log_dir, paste0("mu_terms_", run_id, ".rds")))', code, fixed = TRUE)), 1L)
})

test_that("config admits only drives x points per drive and home field (audit M22)", {
  expect_identical(MU_TERMS_ADMITTED, c("base", "hfa"))
})
```

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `Rscript -e "testthat::test_file('tests/testthat/test-mu-terms.R')"`
  - Expected: FAIL. Three engine expectations fail, and the config test fails with `object 'MU_TERMS_ADMITTED' not found`.

- [ ] **Step 3: Load the module fail-loud.** In `NFLsimulation.R`, inside the top `local({ ... })` block, after the `if (file.exists(playoffs_path)) { ... }` block and before the closing `})`, add:

```r
  # Required modules (Plan 1b-1): a load failure stops the run
  source(file.path(base_path, "mu_terms.R"))
```

- [ ] **Step 4: Add the config setting.** In `config.R`, insert after the line `CONFERENCE_GAME_ADJUST <- 0.0`:

```r

# =============================================================================
# SIMULATED MEAN COMPOSITION (audit M22, Plan 1b-1)
# =============================================================================

#' @description Terms summed into the simulated mean scores. "base" is expected drives x
#'   points per drive; "hfa" is home-field points for the home team. Every other term in
#'   R/mu_terms.R MU_TERM_NAMES is computed and logged (run_logs/mu_terms_*.rds) but enters
#'   the means only after the pre-registered walk-forward backtest admits it (Plan 1b-3).
#' @default c("base", "hfa")
MU_TERMS_ADMITTED <- c("base", "hfa")
```

In `.validate_config()`, after the `# SHRINKAGE validation` block, add:

```r
  # MU_TERMS_ADMITTED validation (audit M22); term names are checked by compose_mu()
  if (!is.character(MU_TERMS_ADMITTED) || !"base" %in% MU_TERMS_ADMITTED) {
    errors <- c(errors, "MU_TERMS_ADMITTED must be a character vector that includes \"base\".")
  }
```

- [ ] **Step 5: Replace the rescue.** In `NFLsimulation.R`, replace this block (currently `:6270-6284`):

```r
# If any mu is NA after all adjustments, rebuild it from safe inputs
games_ready <- games_ready %>%
  mutate(
    mu_home = dplyr::if_else(
      is.finite(mu_home),
      mu_home,
      pmax(exp_drives_home * exp_ppd_home + dplyr::coalesce(HFA_pts, 0), 0)
    ),
    mu_away = dplyr::if_else(
      is.finite(mu_away),
      mu_away,
      pmax(exp_drives_away * exp_ppd_away, 0)
    )
  )
```

with:

```r
# Simulated means: the sum of the admitted terms (audit M22). The chain above still computes
# every other term; they are logged in mu_terms but not simulated until the walk-forward
# backtest admits them. compose_mu() stops on a non-finite admitted term.
mu_terms <- mu_components(games_ready, pressure_pts = PRESSURE_MISMATCH_PTS)
mu_final <- compose_mu(mu_terms, MU_TERMS_ADMITTED)
stopifnot(identical(mu_final$game_id, games_ready$game_id))
games_ready <- games_ready %>%
  mutate(mu_home = mu_final$mu_home, mu_away = mu_final$mu_away)
```

- [ ] **Step 6: Log the term table.** In `NFLsimulation.R`, after the line `saveRDS(games_ready, file.path(log_dir, paste0("games_ready_", run_id, ".rds")))`, add:

```r
saveRDS(mu_terms, file.path(log_dir, paste0("mu_terms_", run_id, ".rds")))
```

- [ ] **Step 7: Add the ledger row.** In `docs/EVIDENCE_LEDGER.md`, add after the `C-SHRINK` row:

```markdown
| C-MU-TERMS | The simulated mean is expected drives × points per drive, plus home field for the home team (`MU_TERMS_ADMITTED` = base, hfa); every other adjustment is computed and logged, not simulated | – | unvalidated | The explicit form of what the engine already simulated (audit M22: 16 of 16 games identical). A term is added only through the Plan 1b-3 walk-forward admission rule | reports/2026-10-01/phase1b-1-evidence/m22_terms.out.txt |
```

- [ ] **Step 8: Run the tests and confirm they pass.**
  - Run: same command as Step 2.
  - Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 20 ]`.
- [ ] **Step 9: Gates.** Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R`; both must exit 0.
- [ ] **Step 10: Local golden-master check.**
  - Run: `Rscript scripts/golden_master.R compare 15 2024 reports/2026-09-29/golden-master/2024-w15`
  - Expected: the 8 T8 blend columns only, with the magnitudes in `reports/2026-09-30/VERIFICATION.md` (Windows). There should be no `mu_*`, `sd_*`, `k_*` or `home_p_2w_model` rows.
  - Then confirm the log was written. Single quotes keep bash and PowerShell from expanding `$`:
    `Rscript -e 'x <- readRDS(sort(list.files("run_logs", "^mu_terms_", full.names = TRUE), decreasing = TRUE)[1]); print(round(sapply(names(x$home)[-1], function(t) max(abs(c(x$home[[t]], x$away[[t]])))), 2))'`
  - Expected: location 16.18, special_teams 5.73 and turnover `NA`, matching the measured baseline.
- [ ] **Step 11: Commit.**

```bash
git add NFLsimulation.R config.R docs/EVIDENCE_LEDGER.md tests/testthat/test-mu-terms.R
git commit -m "fix(model): simulate the composed means and stop on a non-finite term (M22)"
```

**Expected golden-master change (CI):** none. The means are bit-identical; see the measured baseline.

---

### Task 4: Score SDs, NB sizes and correlation from the simulated means (M22b)

**Files:**
- Modify `NFLsimulation.R`:
  - the SD/NB block (`:5076-5089`);
  - the rho block (`:5118-5122`), which is replaced by the new function definition;
  - the environment block's SD lines (`:6121-6122`);
  - the compose step (Task 3).
- Test: `tests/testthat/test-score-variance.R`

**Interfaces:**
- Consumes: the compose step (Task 3). `sd_total_curve()`, `nb_size_from_musd()` and `rho_from_game()` are already defined at top level in `NFLsimulation.R`.
- Produces: a new top-level `score_variance_from_mu(games)`.
  - Input: data frame with `mu_home, mu_away, sd_home_fit, sd_away_fit, sd_home_adj, sd_away_adj`.
  - Output: the same data frame plus or replacing `total_mu, sd_goal, sd_home, sd_away, k_home, k_away, spread_est, rho_game`.
  - The engine calls it exactly once, right after the means are composed.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-score-variance.R`:

```r
# Audit M22b: score SDs, NB sizes and the score correlation must come from the means the
# simulator uses. Until Plan 1b-1 they came from the legacy chain's total (22.4 for
# CHI @ MIN in 2024 week 15, against 50.3 simulated).
sim_path <- file.path(PROJECT_ROOT, "NFLsimulation.R")
v_env <- load_script_functions(sim_path, c("NB_SIZE_MIN", "NB_SIZE_MAX", "sd_total_curve", "nb_size_from_musd",
                                           "rho_from_game", "score_variance_from_mu"))
v_env$RHO_SCORE <- 0.05   # rho_from_game's default global, estimated from data in a real run

games <- data.frame(game_id = c("g1", "g2"), mu_home = c(27.4, 20.0), mu_away = c(22.9, 17.5),
                    sd_home_fit = c(10.2, 2.0), sd_away_fit = c(9.4, 8.0),
                    sd_home_adj = c(0, 0.6), sd_away_adj = c(0, -0.3))

test_that("SDs blend the fitted SD with the curve at the simulated total", {
  out <- v_env$score_variance_from_mu(games)
  goal <- v_env$sd_total_curve(games$mu_home + games$mu_away)
  expect_equal(out$total_mu, games$mu_home + games$mu_away)
  expect_equal(out$sd_goal, goal)
  expect_equal(out$sd_home, pmax(pmax(0.6 * games$sd_home_fit + 0.4 * goal / sqrt(2), 5) + games$sd_home_adj, 5))
  expect_equal(out$sd_away, pmax(pmax(0.6 * games$sd_away_fit + 0.4 * goal / sqrt(2), 5) + games$sd_away_adj, 5))
  expect_equal(out$sd_home[2], 5.6)   # the 5.0 floor binds before the environment shift
})

test_that("NB sizes and rho use the simulated means and the final SDs", {
  out <- v_env$score_variance_from_mu(games)
  expect_equal(out$k_home, mapply(v_env$nb_size_from_musd, games$mu_home, out$sd_home))
  expect_equal(out$k_away, mapply(v_env$nb_size_from_musd, games$mu_away, out$sd_away))
  expect_equal(out$rho_game, v_env$rho_from_game(out$total_mu, abs(games$mu_home - games$mu_away)))
})

test_that("the engine derives variance once, after composing the means (audit M22b)", {
  code <- readLines(sim_path, warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  i_compose <- grep("compose_mu(mu_terms, MU_TERMS_ADMITTED)", code, fixed = TRUE)
  i_var <- grep("games_ready <- score_variance_from_mu(games_ready)", code, fixed = TRUE)
  expect_length(i_var, 1L)
  expect_true(length(i_compose) == 1L && i_var > i_compose)
  expect_false(any(grepl("sd_home\\s*=\\s*0\\.6\\s*\\*\\s*sd_home\\s*\\+", code)))          # legacy-total blend gone
  expect_false(any(grepl("sd_home\\s*=\\s*pmax\\(sd_home \\+ sd_home_adj", code)))         # env SD step moved
  expect_equal(sum(grepl("rho_from_game(total_mu, spread_est)", code, fixed = TRUE)), 1L)
})
```

- [ ] **Step 2: Run the test and confirm it fails.**
  - Run: `Rscript -e "testthat::test_file('tests/testthat/test-score-variance.R')"`
  - Expected: FAIL with `load_script_functions: not found in NFLsimulation.R: score_variance_from_mu`.

- [ ] **Step 3: Keep the fitted SDs.** In `NFLsimulation.R`, replace the block that starts `games_ready <- games_ready |>` right after `sd_total_curve` (currently `:5076-5089`):

```r
games_ready <- games_ready |>
  dplyr::mutate(
    total_mu = mu_home + mu_away,
    sd_goal  = sd_total_curve(total_mu),
    sd_home  = 0.6 * sd_home + 0.4 * (sd_goal / sqrt(2)),
    sd_away  = 0.6 * sd_away + 0.4 * (sd_goal / sqrt(2)),
    sd_home  = pmax(sd_home, 5.0),
    sd_away  = pmax(sd_away, 5.0)
  ) |>
  # Calculate negative binomial size parameters for prediction intervals
  dplyr::mutate(
    k_home = purrr::map2_dbl(mu_home, sd_home, nb_size_from_musd),
    k_away = purrr::map2_dbl(mu_away, sd_away, nb_size_from_musd)
  )
```

with:

```r
# Fitted score SDs (team scoring variability + QB uncertainty). The total-based blend, the
# NB sizes and rho are computed from the simulated means by score_variance_from_mu() at the
# compose step (audit M22b); this chain's mu is a diagnostic sum, not the simulated mean.
games_ready <- games_ready |>
  dplyr::mutate(sd_home_fit = sd_home, sd_away_fit = sd_away)
```

- [ ] **Step 4: Define the variance function where rho was applied.** Replace the block right after the `rho_from_game` definition (currently `:5118-5122`):

```r
games_ready <- games_ready %>%
  mutate(
    spread_est = abs(mu_home - mu_away),
    rho_game   = rho_from_game(total_mu, spread_est)
  )
```

with:

```r
# Score SDs, NB sizes and the score correlation from the simulated means (audit M22b).
# sd_*_fit: fitted team scoring SD plus the QB adjustment; sd_*_adj: environment SD shift.
score_variance_from_mu <- function(games) {
  games |>
    dplyr::mutate(
      total_mu   = mu_home + mu_away,
      sd_goal    = sd_total_curve(total_mu),
      sd_home    = pmax(pmax(0.6 * sd_home_fit + 0.4 * (sd_goal / sqrt(2)), 5.0) + sd_home_adj, 5.0),
      sd_away    = pmax(pmax(0.6 * sd_away_fit + 0.4 * (sd_goal / sqrt(2)), 5.0) + sd_away_adj, 5.0),
      k_home     = purrr::map2_dbl(mu_home, sd_home, nb_size_from_musd),
      k_away     = purrr::map2_dbl(mu_away, sd_away, nb_size_from_musd),
      spread_est = abs(mu_home - mu_away),
      rho_game   = rho_from_game(total_mu, spread_est)
    )
}
```

- [ ] **Step 5: Remove the environment block's SD step.** It moves into the function above. In the environment `mutate()` (currently `:6119-6123`), replace:

```r
    mu_home = pmax(mu_home + env_total_adj/2 + mu_home_adj + wind_interaction_home + cold_interaction_home, 0),
    mu_away = pmax(mu_away + env_total_adj/2 + mu_away_adj + wind_interaction_away + cold_interaction_away, 0),
    sd_home = pmax(sd_home + sd_home_adj, 5.0),
    sd_away = pmax(sd_away + sd_away_adj, 5.0)
  )
```

with:

```r
    mu_home = pmax(mu_home + env_total_adj/2 + mu_home_adj + wind_interaction_home + cold_interaction_home, 0),
    mu_away = pmax(mu_away + env_total_adj/2 + mu_away_adj + wind_interaction_away + cold_interaction_away, 0)
  )
```

- [ ] **Step 6: Call it after the composition.** Directly after the Task 3 lines `games_ready <- games_ready %>% mutate(mu_home = mu_final$mu_home, mu_away = mu_final$mu_away)`, add:

```r
games_ready <- score_variance_from_mu(games_ready)
```

- [ ] **Step 7: Confirm nothing else reads the moved columns before the compose step.**
  - Run: `awk 'NR>5070 && NR<6290 && /total_mu|sd_goal|k_home|k_away|rho_game|spread_est/ {print NR": "$0}' NFLsimulation.R`
  - Expected: only lines inside `week_inputs_and_sim_2w` (its own local `g`), the new function, and the compose step.
- [ ] **Step 8: Run the test and confirm it passes.**
  - Run: same command as Step 2.
  - Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 13 ]`.
- [ ] **Step 9: Gates.** Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R`; both must exit 0.
- [ ] **Step 10: Local golden-master check.**
  - Run the Task 3 compare command.
  - Expected: `sd_home`, `sd_away`, `k_*`, `total_uncertainty`, and the score-distribution and probability columns change; `mu_home` and `mu_away` do not.
  - Compare the `sd_home` and `sd_away` max |Δ| with the prediction (≤ 1.39).
- [ ] **Step 11: Commit.**

```bash
git add NFLsimulation.R tests/testthat/test-score-variance.R
git commit -m "fix(model): score SDs, NB sizes and rho from the simulated means (M22b)"
```

**Expected golden-master change (CI):**
- `mu_*` are unchanged.
- `sd_home` and `sd_away` move by −0.31..+1.39 and rise in about 10 of 16 games; CHI @ MIN moves most.
- `k_*`, `rho`-dependent columns, and every score-distribution, model-probability and blend column change.

---

### Task 5: Neutral sites (M24)

**Files:**
- Create: `R/schedule_context.R`
- Modify `NFLsimulation.R`:
  - the module-loading block;
  - after the venue normalization (`:2697-2699`);
  - the `week_slate` transmute (`:2761-2772`);
  - the HFA sample (`:3563-3575`);
  - `HFA_pts` (`:4593-4598`);
  - `week_inputs_and_sim_2w` (`:5355-5358`, `:5477`).
- Test: `tests/testthat/test-schedule-context.R`

**Interfaces:**
- Produces:
  - `neutral_site_flag(sched)` → logical, one value per row, `location == "Neutral"`. It stops when the column is missing or a value is missing or unknown.
  - `home_field_points(home_hfa, league_hfa, playoff_mult, neutral_site)` → points for the home team. It uses team HFA, or the league HFA when the team value is missing. The result is multiplied by `playoff_mult`, capped at ±6, and is 0 at a neutral site.
  - New columns: `sched$neutral_site` and `week_slate$neutral_site`. They flow into `games_ready` and the calibration-history slates.
- Task 6 adds `compute_rest_table()` to the same file.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-schedule-context.R`:

```r
# Schedule context for the game model. Audit M24: nflverse marks neutral sites with
# location == "Neutral"; the engine looked for neutral_site/neutral/is_neutral, found none,
# and gave the listed home team full home field at international games and the Super Bowl.

test_that("nflverse location marks neutral sites (audit M24)", {
  s <- data.frame(game_id = c("2024_01_GB_PHI", "2024_15_KC_CLE"), location = c("Neutral", "Home"))
  expect_identical(neutral_site_flag(s), c(TRUE, FALSE))
})

test_that("a missing location column or value stops", {
  expect_error(neutral_site_flag(data.frame(game_id = "g1")), "no 'location' column")
  expect_error(neutral_site_flag(data.frame(game_id = c("g_home", "g_na"), location = c("Home", NA))), "for g_na$")
  expect_error(neutral_site_flag(data.frame(game_id = "g_away", location = "Away")), "for g_away$")
})

test_that("a neutral site gets no home-field points, even in the Super Bowl (audit M24)", {
  expect_equal(home_field_points(home_hfa = 2.1, league_hfa = 1.7, playoff_mult = 1.2, neutral_site = TRUE), 0)
  expect_equal(home_field_points(2.1, 1.7, 1.2, FALSE), 2.1 * 1.2)
})

test_that("home-field points fall back to the league value and are capped at 6", {
  expect_equal(home_field_points(c(NA, 9, -8), 1.7, 1, c(FALSE, FALSE, FALSE)), c(1.7, 6, -6))
})

test_that("the engine flags neutral sites and uses the flag for home field (audit M24)", {
  code <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_true(any(grepl('source(file.path(base_path, "schedule_context.R"))', code, fixed = TRUE)))
  expect_true(any(grepl("sched$neutral_site <- neutral_site_flag(sched)", code, fixed = TRUE)))
  expect_true(any(grepl("season %in% seasons_hfa, !neutral_site)", code, fixed = TRUE)))
  expect_true(any(grepl("home_field_points(home_hfa, league_hfa, .playoff_hfa_mult, neutral_site)", code, fixed = TRUE)))
  expect_true(any(grepl("margin_shift = dplyr::if_else(neutral_site, 0,", code, fixed = TRUE)))
  expect_false(any(grepl('intersect(c("neutral_site","neutral","is_neutral")', code, fixed = TRUE)))
})
```

- [ ] **Step 2: Run the test and confirm it fails.**
  - Run: `Rscript -e "testthat::test_file('tests/testthat/test-schedule-context.R')"`
  - Expected: FAIL with `could not find function "neutral_site_flag"`.

- [ ] **Step 3: Implement the functions.** Create `R/schedule_context.R`:

```r
# Schedule context for the game model: neutral sites (audit M24) and rest (audit M23).
# Pure functions of nflverse schedule columns, used for the current week and for the
# calibration-history simulator in NFLsimulation.R.

#' Neutral-site flag (audit M24)
#'
#' nflverse marks neutral sites (international games, the Super Bowl) with
#' location == "Neutral". A missing column or an unknown value stops the run.
#' @param sched schedule rows with a `location` column (and `game_id` for messages)
#' @return logical vector, one value per row
neutral_site_flag <- function(sched) {
  if (!"location" %in% names(sched)) {
    stop("neutral_site_flag: schedule has no 'location' column (audit M24)", call. = FALSE)
  }
  loc <- as.character(sched$location)
  bad <- is.na(loc) | !loc %in% c("Home", "Neutral")
  if (any(bad)) {
    ids <- if ("game_id" %in% names(sched)) sched$game_id[bad] else which(bad)
    stop("neutral_site_flag: missing or unknown location for ", paste(utils::head(ids, 10), collapse = ", "),
         call. = FALSE)
  }
  loc == "Neutral"
}

#' Home-field points for the home team (audit M24)
#'
#' Team HFA (the league value when missing) times the playoff multiplier, capped at +/-6,
#' and zero at a neutral site.
home_field_points <- function(home_hfa, league_hfa, playoff_mult, neutral_site) {
  pts <- dplyr::coalesce(home_hfa, league_hfa) * playoff_mult
  pts <- pmin(pmax(pts, -6), 6)
  dplyr::if_else(neutral_site, 0, pts)
}
```

- [ ] **Step 4: Load the module.** In the `NFLsimulation.R` top block, after the Task 3 line `source(file.path(base_path, "mu_terms.R"))`, add:

```r
  source(file.path(base_path, "schedule_context.R"))
```

- [ ] **Step 5: Flag neutral sites.** In `NFLsimulation.R`, after the venue normalization (`sched <- sched |> mutate(venue = if (!is.na(venue_col)) ...)`), add:

```r

# Neutral-site flag (audit M24): nflverse marks neutral sites with location == "Neutral"
sched$neutral_site <- neutral_site_flag(sched)
```

- [ ] **Step 6: Carry the flag into the slate.** In the `week_slate <- sched %>% filter(...) %>% transmute(` block, replace:

```r
    home_team,
    away_team,
    venue = as.character(venue)   # <-- only the normalized column
```

with:

```r
    home_team,
    away_team,
    neutral_site,
    venue = as.character(venue)   # <-- only the normalized column
```

- [ ] **Step 7: Leave neutral games out of the HFA estimate.** Replace:

```r
# --- League home-field advantage (points), data-driven over recent seasons ---
# pick neutral-site flag if present
neutral_col <- intersect(c("neutral_site","neutral","is_neutral"), names(sched))

# start with REG games in target seasons
sched_hfa <- sched |>
  dplyr::filter(game_type == "REG", season %in% seasons_hfa)

# remove neutral-site games if a flag exists
if (length(neutral_col)) {
  sched_hfa <- sched_hfa |>
    dplyr::filter(!.data[[neutral_col[1]]])
}
```

with:

```r
# --- League home-field advantage (points), data-driven over recent seasons ---
# REG games in the target seasons, without neutral sites (audit M24)
sched_hfa <- sched |>
  dplyr::filter(game_type == "REG", season %in% seasons_hfa, !neutral_site)
```

- [ ] **Step 8: Zero home field at neutral sites.** Replace:

```r
games_ready <- games_ready %>%
  mutate(
    HFA_pts = coalesce(home_hfa, league_hfa),  # if you have team-specific, prefer that
    HFA_pts = HFA_pts * .playoff_hfa_mult,     # Apply playoff multiplier
    HFA_pts = pmin(pmax(HFA_pts, -6), 6)       # cap at +/-6
  ) %>%
```

with:

```r
games_ready <- games_ready %>%
  mutate(
    # team HFA (league when missing) x playoff multiplier, capped at +/-6; 0 at a neutral site (audit M24)
    HFA_pts = home_field_points(home_hfa, league_hfa, .playoff_hfa_mult, neutral_site)
  ) %>%
```

- [ ] **Step 9: Do the same in the calibration-history simulator.** In `week_inputs_and_sim_2w()`:
  - Replace `    dplyr::select(game_id, game_date, home_team, away_team, home_score, away_score) |>` with `    dplyr::select(game_id, game_date, home_team, away_team, home_score, away_score, neutral_site) |>`.
  - Replace `      margin_shift = (home_hfa - away_hfa)/2,` with `      margin_shift = dplyr::if_else(neutral_site, 0, (home_hfa - away_hfa)/2),   # audit M24`.
  - This applies to the occurrence inside `week_inputs_and_sim_2w`, currently `:5477`. The occurrence at `:4547` is an unused diagnostic and stays.
- [ ] **Step 10: Run the test and confirm it passes.**
  - Run: same command as Step 2.
  - Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 13 ]`.
- [ ] **Step 11: Gates.** Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R`; both must exit 0.
- [ ] **Step 12: Local golden-master check.**
  - Run the Task 3 compare command.
  - Expected: `mu_home` changes in some or all 16 games; `mu_away` does not.
  - Then compare `HFA_pts` in the two newest runs, Task 4's and this one:
    `Rscript -e 'f <- sort(list.files("run_logs", "^games_ready_", full.names = TRUE), decreasing = TRUE)[1:2]; a <- readRDS(f[2]); b <- readRDS(f[1]); print(data.frame(game = b$game_id, before = round(a$HFA_pts, 3), after = round(b$HFA_pts, 3), delta = round(b$HFA_pts - a$HFA_pts, 3)))'`
  - Expected: deltas in about −0.33..+0.20, with ARI, CLE, JAX, LAC, NO, SF and TEN beyond 0.05. The engine standardizes historical team codes, so small differences from the prediction are expected. A different sign or set of teams is not; stop and report it.
- [ ] **Step 13: Commit.**

```bash
git add R/schedule_context.R NFLsimulation.R tests/testthat/test-schedule-context.R
git commit -m "fix(model): neutral sites get no home field and leave the HFA estimate (M24)"
```

**Expected golden-master change (CI):**
- `mu_home` changes by the `HFA_pts` change; `mu_away` is unchanged.
- SDs, NB sizes, rho and the probabilities follow the new home means.
- The blend columns also change, because the calibration history uses the new team HFA.

---

### Task 6: Rest from each team's own game (M23)

**Files:**
- Modify:
  - `R/schedule_context.R`
  - `NFLsimulation.R`: the `week_slate` transmute, the current-week rest block (`:4075-4103`), and the as-of rest block in `recent_form_at_sim()` (`:5218-5249`)
- Test: `tests/testthat/test-schedule-context.R` (append)

**Interfaces:**
- Consumes: the `team_games` columns `team, season, week`. These are the engine's completed REG and POST team-games.
- Produces: `compute_rest_table(slate, team_games, season, week, short_penalty = REST_SHORT_PENALTY, long_bonus = REST_LONG_BONUS, bye_bonus = BYE_BONUS)` → `tibble(team, days_rest, rest_points)`, one row per slate team.
  - The slate needs `game_id, home_team, away_team, home_rest, away_rest`, where the rest columns are nflverse days of rest.
  - `bye_prev` means the team's latest game this season, before `week`, was two or more weeks earlier.
  - It stops if rest days are missing or a team appears twice.
- New columns: `week_slate$home_rest` and `week_slate$away_rest`.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-schedule-context.R`:

```r
rest <- function(slate, tg, season = 2024L, week = 15L) {
  compute_rest_table(slate, tg, season, week, short_penalty = -0.85, long_bonus = 0.5, bye_bonus = 1)
}
no_games <- data.frame(team = character(), season = integer(), week = integer())

test_that("rest comes from each team's own game, not the week's first kickoff (audit M23)", {
  # 2024 week 15 opened on Thursday (LA @ SF); DAL @ CAR was Sunday, CHI @ MIN Monday
  slate <- data.frame(game_id = c("2024_15_LA_SF", "2024_15_DAL_CAR", "2024_15_CHI_MIN"),
                      home_team = c("SF", "CAR", "MIN"), away_team = c("LA", "DAL", "CHI"),
                      home_rest = c(4, 7, 8), away_rest = c(4, 7, 8))
  tg <- data.frame(team = c("SF", "LA", "CAR", "DAL", "MIN", "CHI"), season = 2024L, week = 14L)
  r <- rest(slate, tg)
  expect_equal(r$rest_points[match(c("SF", "LA"), r$team)], c(-0.85, -0.85))
  expect_equal(r$rest_points[match(c("CAR", "DAL", "MIN", "CHI"), r$team)], c(0, 0, 0, 0))
})

test_that("a Sunday game after a Monday game is short rest", {
  slate <- data.frame(game_id = "g", home_team = "LV", away_team = "ATL", home_rest = 6, away_rest = 6)
  r <- rest(slate, data.frame(team = c("LV", "ATL"), season = 2024L, week = 14L))
  expect_equal(r$rest_points, c(-0.85, -0.85))
})

test_that("a team off a bye gets the bye bonus, not the long-rest bonus", {
  slate <- data.frame(game_id = "g", home_team = "KC", away_team = "DEN", home_rest = 14, away_rest = 10)
  tg <- data.frame(team = c("KC", "DEN"), season = 2024L, week = c(13L, 14L))
  r <- rest(slate, tg)
  expect_equal(r$rest_points[r$team == "KC"], 1)     # last game in week 13: bye in week 14
  expect_equal(r$rest_points[r$team == "DEN"], 0.5)  # 10 days without a bye: long rest
})

test_that("week 1 is neutral: seven days and no game yet this season", {
  slate <- data.frame(game_id = "g", home_team = "PHI", away_team = "GB", home_rest = 7, away_rest = 7)
  tg <- data.frame(team = c("PHI", "GB"), season = 2023L, week = 20L)   # last games were last season
  expect_equal(rest(slate, tg, season = 2024L, week = 1L)$rest_points, c(0, 0))
})

test_that("missing rest days or a duplicated team stop the run", {
  bad <- data.frame(game_id = "g", home_team = "KC", away_team = "DEN", home_rest = NA, away_rest = 7)
  expect_error(rest(bad, no_games), "no rest days for g")
  dup <- data.frame(game_id = c("a", "b"), home_team = c("KC", "KC"), away_team = c("DEN", "LV"),
                    home_rest = 7, away_rest = 7)
  expect_error(rest(dup, no_games), "twice.*KC")
})

test_that("both rest tables in NFLsimulation.R use compute_rest_table (audit M23)", {
  code <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_equal(sum(grepl("compute_rest_table(", code, fixed = TRUE)), 2L)
  expect_false(any(grepl("week_slate$game_date[1]", code, fixed = TRUE)))
  expect_false(any(grepl("fake_slate_date", code, fixed = TRUE)))
})
```

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `Rscript -e "testthat::test_file('tests/testthat/test-schedule-context.R')"`
  - Expected: FAIL with `could not find function "compute_rest_table"`. The structural test also fails.

- [ ] **Step 3: Implement.** Append to `R/schedule_context.R`:

```r

#' Rest points for each team on a slate (audit M23)
#'
#' Rest days come from the schedule row of the team's own game (nflverse home_rest /
#' away_rest), not from the week's first kickoff. A bye means the team's latest game this
#' season was two or more weeks earlier; it earns the bye bonus instead of the long-rest
#' bonus. nflverse gives week 1 seven days, so week 1 is neutral.
#' @param slate one row per game: game_id, home_team, away_team, home_rest, away_rest
#' @param team_games completed games, one row per team-game: team, season, week
#' @return tibble(team, days_rest, rest_points), one row per slate team
compute_rest_table <- function(slate, team_games, season, week,
                               short_penalty = REST_SHORT_PENALTY, long_bonus = REST_LONG_BONUS,
                               bye_bonus = BYE_BONUS) {
  per_team <- data.frame(game_id = c(slate$game_id, slate$game_id),
                         team = c(slate$home_team, slate$away_team),
                         days_rest = as.numeric(c(slate$home_rest, slate$away_rest)),
                         stringsAsFactors = FALSE)
  if (anyDuplicated(per_team$team)) {
    stop("compute_rest_table: a team appears twice on the slate: ",
         paste(unique(per_team$team[duplicated(per_team$team)]), collapse = ", "), call. = FALSE)
  }
  if (any(!is.finite(per_team$days_rest))) {
    stop("compute_rest_table: no rest days for ",
         paste(unique(per_team$game_id[!is.finite(per_team$days_rest)]), collapse = ", "), call. = FALSE)
  }
  prior <- team_games[team_games$season == season & team_games$week < week, c("team", "week")]
  last_week <- if (nrow(prior)) tapply(prior$week, prior$team, max) else integer()
  prev <- as.vector(last_week[per_team$team])   # tapply returns a 1-d array; drop dim and names
  bye_prev <- !is.na(prev) & (week - prev) >= 2
  rest_points <- ifelse(per_team$days_rest <= 6, short_penalty, 0) +
    ifelse(per_team$days_rest >= 9 & !bye_prev, long_bonus, 0) +
    ifelse(bye_prev, bye_bonus, 0)
  tibble::tibble(team = per_team$team, days_rest = per_team$days_rest, rest_points = rest_points)
}
```

- [ ] **Step 4: Carry the rest columns into the slate.** In the `week_slate` transmute, replace the Task 5 line `    neutral_site,` with:

```r
    neutral_site,
    home_rest,
    away_rest,
```

- [ ] **Step 5: Current-week rest.** In `NFLsimulation.R`, replace everything from `# Compute days since last game for each team (before the slate week)` through `  dplyr::select(team, days_rest, rest_points)`, which is `last_game` and `rest_tbl`, with:

```r
# Rest from each team's own game (nflverse home_rest/away_rest), not the week's first
# kickoff (audit M23)
rest_tbl <- compute_rest_table(week_slate, team_games, SEASON, WEEK_TO_SIM)
```

The `recent_form <- recent_form |> left_join(rest_tbl, by = "team") ...` lines after it stay as they are.

- [ ] **Step 6: Calibration-history rest.** In `recent_form_at_sim()`, replace everything from `  # rest effects at the cutpoint` through `    dplyr::select(team, rest_points)`, which is `last_game_cut`, `fake_slate_date` and `rest_tbl_cut`, with:

```r
  # rest effects at the cutpoint: each team's own game (audit M23)
  cut_slate <- sched |>
    dplyr::filter(.data$season == cut_season, .data$week == cut_week, game_type == "REG") |>
    dplyr::distinct(game_id, home_team, away_team, home_rest, away_rest)
  rest_tbl_cut <- compute_rest_table(cut_slate, team_games, cut_season, cut_week) |>
    dplyr::select(team, rest_points)
```

The following `rf |> dplyr::left_join(rest_tbl_cut, by = "team") ...` stays.

- [ ] **Step 7: Run the tests and confirm they pass.**
  - Run: same command as Step 2.
  - Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 24 ]`.
- [ ] **Step 8: Gates.** Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R`; both must exit 0.
- [ ] **Step 9: Local check.** Run the Task 3 compare command.
  - Simulator columns (`mu_*`, `sd_*`, `k_*`, `home_p_2w_model`) should not change compared with Task 5, because current-week rest is a non-admitted term.
  - Print the rest term from the newest `run_logs/mu_terms_*.rds`. Expect −0.85 for SF and LA (the Thursday game) and 0 for the Sunday/Monday teams without a bye.

```bash
Rscript -e 'x <- readRDS(sort(list.files("run_logs", "^mu_terms_", full.names = TRUE), decreasing = TRUE)[1]); print(data.frame(game = x$home$game_id, home_rest = x$home$rest, away_rest = x$away$rest))'
```

- [ ] **Step 10: Commit.**

```bash
git add R/schedule_context.R NFLsimulation.R tests/testthat/test-schedule-context.R
git commit -m "fix(model): rest from each team's own game in both rest tables (M23)"
```

**Expected golden-master change (CI):** simulator columns are unchanged. Only the blend columns change, because the calibration-history simulations use the corrected rest. If a simulator column changes, stop and investigate before Task 7.

---

### Task 7: Sleeper only for a slate with games still to play (M20)

**Files:**
- Modify:
  - `R/sleeper_api.R` (append)
  - `NFLsimulation.R`: the module-loading block; `safe_load_injuries()` (signature `:3139`, fallback `:3278-3325`); both call sites (`:3331-3334`, `:3800-3803`)
- Test: `tests/testthat/test-sleeper-fallback.R`

**Interfaces:**
- Produces:
  - `sleeper_fallback_allowed(slate_dates, today = Sys.Date())`: TRUE when any slate game is today or later.
  - `sleeper_as_injury_rows(sleeper_df, season, week)` → tibble of nflverse-style injury rows stamped with the slate's season and week. It stops if either is missing.
  - `safe_load_injuries(seasons, prefer_fast = TRUE, allow_live_fallback = FALSE, stamp_season = NA_integer_, stamp_week = NA_integer_, ...)`.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-sleeper-fallback.R`:

```r
# Audit M20: Sleeper serves only today's injury report. Before Plan 1b-1 the engine used it
# for any week when nflverse injuries failed, stamped with the calendar year, so a re-run of
# 2024 week 15 could price 2026 injuries.
sim_path <- file.path(PROJECT_ROOT, "NFLsimulation.R")
inj_env <- load_script_functions(sim_path, "safe_load_injuries")
sleeper_rows <- data.frame(team = "KC", position = "WR", game_status = "Out",
                           injury_body_part = "Knee", player = "Test Player")

test_that("the live report is allowed only while the slate has games to play", {
  expect_true(sleeper_fallback_allowed(as.Date(c("2026-10-01", "2026-10-04")), today = as.Date("2026-10-02")))
  expect_true(sleeper_fallback_allowed(as.Date("2026-10-04"), today = as.Date("2026-10-04")))
  expect_false(sleeper_fallback_allowed(as.Date(c("2024-12-12", "2024-12-16")), today = as.Date("2026-10-01")))
  expect_false(sleeper_fallback_allowed(as.Date(NA), today = as.Date("2026-10-01")))
})

test_that("Sleeper rows carry the slate's season and week, not the calendar year", {
  r <- sleeper_as_injury_rows(sleeper_rows, season = 2026L, week = 5L)
  expect_equal(r$season, 2026L)
  expect_equal(r$week, 5L)
  expect_equal(r$status, "Out")
  expect_error(sleeper_as_injury_rows(sleeper_rows, season = NA, week = 5L), "season and week")
})

test_that("a completed slate never takes today's Sleeper report (audit M20)", {
  local_mocked_bindings(load_injuries = function(...) tibble::tibble(), .package = "nflreadr")
  called <- FALSE
  assign("load_injuries_sleeper", function(...) { called <<- TRUE; list(success = TRUE, data = sleeper_rows) },
         envir = inj_env)
  withr::defer(rm("load_injuries_sleeper", envir = inj_env))
  withr::defer(reset_data_quality())
  out <- inj_env$safe_load_injuries(2024, prefer_fast = FALSE, allow_live_fallback = FALSE,
                                    stamp_season = 2024L, stamp_week = 15L)
  expect_equal(nrow(out), 0L)
  expect_false(called)
  expect_equal(get_data_quality()$injury$status, "unavailable")
})

test_that("a live slate takes Sleeper rows stamped with its season and week", {
  local_mocked_bindings(load_injuries = function(...) tibble::tibble(), .package = "nflreadr")
  assign("load_injuries_sleeper", function(...) list(success = TRUE, data = sleeper_rows), envir = inj_env)
  withr::defer(rm("load_injuries_sleeper", envir = inj_env))
  withr::defer(reset_data_quality())
  out <- inj_env$safe_load_injuries(2026, prefer_fast = FALSE, allow_live_fallback = TRUE,
                                    stamp_season = 2026L, stamp_week = 5L)
  expect_equal(out$season, 2026L)
  expect_equal(out$week, 5L)
  expect_equal(get_data_quality()$injury$status, "partial")
})

test_that("both injury loads in NFLsimulation.R pass the slate check (audit M20)", {
  code <- readLines(sim_path, warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_equal(sum(grepl("allow_live_fallback = sleeper_fallback_allowed(week_slate$game_date)", code, fixed = TRUE)), 2L)
  expect_false(any(grepl('season = as.integer(format(Sys.Date(), "%Y"))', code, fixed = TRUE)))
  expect_true(any(grepl('source(file.path(base_path, "sleeper_api.R"))', code, fixed = TRUE)))
})
```

- [ ] **Step 2: Run the test and confirm it fails.**
  - Run: `Rscript -e "testthat::test_file('tests/testthat/test-sleeper-fallback.R')"`
  - Expected: FAIL with `could not find function "sleeper_fallback_allowed"` and `unused argument (allow_live_fallback = FALSE)`.

- [ ] **Step 3: Implement the helpers.** Append to `R/sleeper_api.R`:

```r

# =============================================================================
# FALLBACK FOR THE GAME MODEL (audit M20)
# =============================================================================

#' May today's Sleeper injury report stand in for a slate?
#'
#' Sleeper serves only the current report. That is information about games still to be
#' played; for a slate whose games are all in the past it would be look-ahead.
#' @param slate_dates game dates of the slate
#' @param today the run date
sleeper_fallback_allowed <- function(slate_dates, today = Sys.Date()) {
  d <- as.Date(slate_dates)
  any(!is.na(d)) && max(d, na.rm = TRUE) >= as.Date(today)
}

#' Sleeper injury rows in nflverse injury columns, stamped with the slate's season and week
sleeper_as_injury_rows <- function(sleeper_df, season, week) {
  if (!isTRUE(is.finite(season)) || !isTRUE(is.finite(week))) {
    stop("sleeper_as_injury_rows: season and week are required", call. = FALSE)
  }
  tibble::tibble(
    season = as.integer(season), week = as.integer(week),
    team = sleeper_df$team, position = sleeper_df$position,
    status = sleeper_df$game_status, report_primary_injury = sleeper_df$injury_body_part,
    full_name = sleeper_df$player
  )
}
```

- [ ] **Step 4: Load the module.** In the `NFLsimulation.R` top block, after `source(file.path(base_path, "schedule_context.R"))`, add:

```r
  source(file.path(base_path, "sleeper_api.R"))
```

- [ ] **Step 5: Change the signature.** Replace `safe_load_injuries <- function(seasons, prefer_fast = TRUE, ...) {` with:

```r
safe_load_injuries <- function(seasons, prefer_fast = TRUE, allow_live_fallback = FALSE,
                               stamp_season = NA_integer_, stamp_week = NA_integer_, ...) {
```

- [ ] **Step 6: Replace the fallback.** Replace everything from `  # If nflreadr failed, try Sleeper API as fallback` through the end of the `if (nrow(injuries) == 0) { message("⚠ No injury data loaded...` block's three messages (currently `:3278-3323`) with:

```r
  # Sleeper serves only today's report: use it only for a slate with games still to play,
  # stamped with that slate's season and week (audit M20)
  if (nrow(injuries) == 0 && !isTRUE(allow_live_fallback)) {
    message("Sleeper injury fallback skipped: the slate's games are complete, so today's report would be look-ahead (audit M20).")
  }
  if (nrow(injuries) == 0 && isTRUE(allow_live_fallback)) {
    message("nflreadr returned no injury data, trying Sleeper API fallback...")
    sleeper_result <- tryCatch({
      load_injuries_sleeper(use_cache = TRUE, verbose = TRUE)
    }, error = function(e) {
      message(sprintf("Sleeper API error: %s", conditionMessage(e)))
      list(data = tibble::tibble(), success = FALSE)
    })

    if (isTRUE(sleeper_result$success) && nrow(sleeper_result$data) > 0) {
      injuries <- sleeper_as_injury_rows(sleeper_result$data, stamp_season, stamp_week)
      message(sprintf("✓ Sleeper API fallback loaded %d injury records for %s week %s",
                      nrow(injuries), stamp_season, stamp_week))
      if (exists("update_injury_quality", mode = "function")) {
        update_injury_quality("partial", missing_seasons = as.character(seasons))
      }
    }
  }

  if (nrow(injuries) == 0) {
    message("⚠ No injury data loaded. Model will run with zero injury impact for all teams.")
    message("  Tried: nflreadr (primary); the Sleeper fallback runs only for a slate with games still to play")
```

Keep the `} else { message(sprintf("✓ Successfully loaded %d total injury records", ...` branch and the rest of the function as they are.

- [ ] **Step 7: Update both call sites.** Replace the main call:

```r
inj_all <- safe_load_injuries(
  seasons = sort(unique(sched$season)),
  file_type = getOption("nflreadr.prefer", default = "rds")
)
```

with:

```r
inj_all <- safe_load_injuries(
  seasons = sort(unique(sched$season)),
  allow_live_fallback = sleeper_fallback_allowed(week_slate$game_date),
  stamp_season = SEASON,
  stamp_week = WEEK_TO_SIM,
  file_type = getOption("nflreadr.prefer", default = "rds")
)
```

Then replace the `live_refresh` call:

```r
  inj_all  <- safe_load_injuries(
    seasons  = SEASON,
    file_type = getOption("nflreadr.prefer", default = "rds")
  )
```

with:

```r
  inj_all  <- safe_load_injuries(
    seasons  = SEASON,
    allow_live_fallback = sleeper_fallback_allowed(week_slate$game_date),
    stamp_season = SEASON,
    stamp_week = WEEK_TO_SIM,
    file_type = getOption("nflreadr.prefer", default = "rds")
  )
```

- [ ] **Step 8: Run the test and confirm it passes.**
  - Run: same command as Step 2.
  - Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 17 ]`.
  - Then run `Rscript -e "testthat::test_file('tests/testthat/test-sleeper-api.R')"`. Expected: no new failures; any skips must be the allowlisted LIVE ones.
- [ ] **Step 9: Gates.** Run `Rscript scripts/run_tests.R` and `Rscript scripts/verify_repo_integrity.R`; both must exit 0.
- [ ] **Step 10: Commit.**

```bash
git add R/sleeper_api.R NFLsimulation.R tests/testthat/test-sleeper-fallback.R
git commit -m "fix(model): Sleeper injury fallback only for slates with games to play (M20)"
```

**Expected golden-master change (CI):** none. nflverse 2024 injuries load, so the fallback is not reached. `inputs.csv` should show injury `full` at every commit.

---

### Task 8: Close-out: attribution, golden master, docs, PR

**Files:**
- Modify:
  - `reports/2026-09-29/golden-master/2024-w15/` (`final_numeric.csv`, `meta.json`, new `inputs.csv`, and `ATTRIBUTION.md`)
  - `CHANGELOG.md`, `CLAUDE.md` (the R/ inventory), `HANDOFF.md`, `docs/EVIDENCE_LEDGER.md`
  - `reports/2026-09-29/AUDIT-ADDENDUM.md`: on `main` if #200 has merged, otherwise on #200's branch

- [ ] **Step 1: Full gates on the branch head.** Run each command and quote its summary lines:
  - `Rscript scripts/run_tests.R`: exit 0, with only allowlisted skips.
  - `Rscript scripts/verify_repo_integrity.R`: exit 0.
- [ ] **Step 2: Push and open a draft PR.** Run `git push -u origin fix/phase1b-1-explicit-model`, then:

```bash
gh pr create --draft --base main --title "Phase 1b-1: explicit game model (M22, M22b, M24, M23, M20)" --body-file <scratchpad>/pr1b1.md
```

The body lists the 7 commits, their tests, and the predicted golden-master changes from the table in Step 3. It ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 3: Read the CI attribution and check it against the predictions.** Get the log with `gh run view <run> --log --job <attribute job>`. For each commit, record the changed columns, the number of games, and max |Δ|.

| Commit | Predicted change (Linux CI) |
|---|---|
| Task 1 (input statuses) | none beyond ≤ 4e-9 fit noise |
| Task 2 (term table) | none |
| Task 3 (compose, M22) | none |
| Task 4 (M22b) | `mu_*` unchanged; `sd_home`/`sd_away` −0.31..+1.39, rising in about 10/16 games; `k_*`, rho and all distribution and probability columns change |
| Task 5 (M24) | `mu_home` moves by ΔHFA (−0.33..+0.20; 7 games beyond 0.05); `mu_away` unchanged; SDs, probabilities and the blend follow |
| Task 6 (M23) | simulator columns unchanged; blend columns change |
| Task 7 (M20) | none |

Any `INPUT DRIFT` line means the inputs differed between records. Re-run the workflow (`gh run rerun <run>`) before attributing anything. A change that is not in this table, or one whose sign or size contradicts the prediction, stops the close-out. Investigate it and report it to the owner, as Phase 1a did with M16 → M18/M19. Do not re-record over it.

- [ ] **Step 4: Write the attribution.** Append a section `## Phase 1b-1 (#<PR>): explicit model` to `reports/2026-09-29/golden-master/2024-w15/ATTRIBUTION.md`:
  - the workflow run and attribute job ids;
  - the determinism line;
  - one table row per commit: commit, fix, columns changed, games, max |Δ|, verdict against the prediction;
  - the head-vs-baseline summary;
  - the input statuses.
- [ ] **Step 5: Re-record the golden master from the CI artifact.**

Set `SCRATCH` to the session scratchpad as a `C:/...` path, `RUN` to the workflow run id, and `HEAD` to the full head sha:

```bash
gh run download "$RUN" -n "gm-$HEAD" -D "$SCRATCH/gm1b1"
ls -la "$SCRATCH/gm1b1/$HEAD"
Rscript -e 'd <- commandArgs(TRUE)[1]; m <- jsonlite::fromJSON(file.path(d, "meta.json")); stopifnot(identical(m$csv_sha256, digest::digest(file = file.path(d, "final_numeric.csv"), algo = "sha256"))); cat("sha ok", m$csv_sha256, "\n")' "$SCRATCH/gm1b1/$HEAD"
```

Copy `final_numeric.csv`, `meta.json` and `inputs.csv` from that folder into `reports/2026-09-29/golden-master/2024-w15/`. List the target folder before and after copying. In `ATTRIBUTION.md`, record the new `csv_sha256` and the run id as the current golden master.

- [ ] **Step 6: Run the matrix locally.** Run `Rscript scripts/run_matrix.R`.
  - Expected on Windows: 9/10. `golden-master` fails only on the 8 T8 blend columns, with no `INPUT DRIFT`.
    - Erratum (2026-10-04): with the v3 cache key the local result is 10/10, and the T8 blend differences do not occur.
  - Expected on Linux: 10/10.
  - Quote the summary.
- [ ] **Step 7: Update the docs.**
  - `CHANGELOG.md` (under `[Unreleased]`): add an entry `### Explicit game model (audit M22, M22b, M24, M23, M20; Plan 1b-1)`. It has one bullet per fix, giving what was wrong (the numbers from "Measured baseline"), what changed, the test file, and the CI-attributed output change.
  - `docs/EVIDENCE_LEDGER.md`: point `C-MU-TERMS` evidence at `ATTRIBUTION.md#phase-1b-1`.
  - `CLAUDE.md`, §6 "R/ Library": add `R/mu_terms.R` (explicit mean composition, M22) and `R/schedule_context.R` (neutral sites, home-field points, rest).
  - `reports/2026-09-29/AUDIT-ADDENDUM.md`: mark M20, M22, M22b, M23 and M24 as fixed in #<PR>. The M22b and M24 rows were added on #200 with this plan.
  - `HANDOFF.md`: Plan 1b-1 done, with the PR link and the gate output. The next target is Plan 1b-2 (roadmap below).
- [ ] **Step 8: Commit, push, and confirm CI is green.** The golden-master attribution for the re-record commit must say `no differences` against Task 7. Then ask the owner to approve the merge.

```bash
git add reports/2026-09-29/golden-master/2024-w15 CHANGELOG.md CLAUDE.md HANDOFF.md docs/EVIDENCE_LEDGER.md
git commit -m "docs(golden-master): attribute and re-record Phase 1b-1 (M22, M22b, M24, M23, M20)"
git push
```

---

## Roadmap after Plan 1b-1 (one plan each, written when the previous one lands)

**Plan 1b-2: point-in-time `predict_week()` and the C3 candidate.** Spec M5, M6, M8, M9.
- **`features_asof(season, week)`.** Every input uses only games that kicked off before the slate. Today:
  - `seasons_hfa` includes the whole current season;
  - `hfa_tbl` (full-sample HFA) is joined into the historical simulations;
  - rho and PPG use all seasons.
- **One `predict_week(season, week, asof)`.** `run_week.R` and the backtest both call it. It replaces `week_inputs_and_sim_2w`, the reduced calibration-history model (M6/M8 train/serve skew).
- **GLMM prior.** Fit on prior seasons only, with a season term (M9). It stays a non-admitted term until Plan 1b-3.
- **Silent substitutions.** Remove `simulate_game_nb`'s 21.5 / 10.0 substitutions and `safe_mu`/`safe_sd`, now that `compose_mu()` guarantees finite positive means.
- **Gates:** a leak canary (an absurd future game leaves the feature hash unchanged), and a production = backtest bit-parity test.
- **Walk-forward simulator candidate C3.** Tune 2018–2022, about 90 weeks at 10k trials per week. It joins the v2 protocol draft (#205) before the owner signs it.

**Plan 1b-3: earn each term, then variance and calibration.**
- **Admission rule, pre-registered** (hashed before any scoring). For each non-admitted term, in a declared order:
  - the Tune walk-forward skill of (admitted + term) vs (admitted) must have a week-block bootstrap CI lower bound > 0 and a Diebold–Mariano (HLN) BH-adjusted p < 0.05;
  - magnitudes are re-estimated walk-forward, not taken from the legacy constants;
  - location (±16 points per side) and special teams (±5.7) are tested like every other term.
- **Variance.** PIT and CRPS of the margin and total distributions. Re-estimate `sd_total_curve` and rho.
- **M4 calibration.** Compare no map against Platt. The validation sprint found that no map helps; isotonic and spline are used only if they pass the gates.
- **Protocol.** Freeze C3 into `nfl_games_v2`; the owner signs it. Score Confirm 2023–2024, then the 2025 holdout exactly once.

**Plan 1b-4: simulator bundle and web charts.**
- Add `score_distributions` per game (margin and total histograms) to the R→web bundle, with the contract schema, ingest, and the `/games/[id]` and `/evidence` charts.
- **M21 weather:**
  - key weather by `stadium_id`;
  - use Open-Meteo historical forecasts from 2021 and the ERA5 archive for older seasons;
  - measure travel to the actual venue at neutral sites;
  - weather enters the means only through the Plan 1b-3 rule.
