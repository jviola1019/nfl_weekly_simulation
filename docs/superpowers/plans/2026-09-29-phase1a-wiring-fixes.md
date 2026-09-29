# Phase 1a Game-Model Wiring Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the output-changing wiring bugs in the game model: the CLI override (M1), the single market-weight stage (M2/M3), the spread sign (M10), silent market fill (M11), per-game random streams (M12), the date resolver (M14), snap percentages (M15) and the inverted injury clamp (M16). Record a golden master first, so every change in output is attributed to a specific fix.

**Architecture:** Minimal, test-first edits to the existing script-style pipeline. Functions defined at the top level of `NFLsimulation.R` are unit-tested by loading only their definitions (`load_script_functions()`), without running the 8,640-line script. The point-in-time and extraction refactor (M4, M5, M6, M8, M9) is out of scope; it is Phase 1b and gets its own plan once this lands.

**Tech Stack:** R 4.5.1, testthat, randtoolbox, nflreadr, lubridate, dplyr.

**Spec:** `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` §5 Phase 1. Audit IDs refer to `reports/2026-09-28/AUDIT.md` and `reports/2026-09-29/AUDIT-ADDENDUM.md`.

## Global Constraints

- **Branch:** `fix/phase1a-wiring`, created from `main` after the Phase 0 PRs (#191, #192, spike PR) merge. Fix-only; no features (CLAUDE.md).
- **Checkpoint A1a must be approved by the owner before Task 1.** It covers the edits to `NFLsimulation.R`, `NFLmarket.R` and the `config.R` defaults, plus deleting `get_playoff_shrinkage` and its test.
- **Interim market weight:** `SHRINKAGE` stays `0.70` (the current config value), applied once, to the de-vigged market probability. Playoff and Super Bowl variants are removed until a backtest supports them.
- **The regression test comes first** for every fix (TDD). Every change in golden-master output is listed in the task report, with the fix that caused it.
- **Gate at the end of each task:** `Rscript scripts/run_tests.R` exits 0 and `Rscript scripts/verify_repo_integrity.R` exits 0.
- **Skip bookkeeping:** remove the KNOWN-DEFECT skips for M14 and M15 once they're fixed. `tests/skip_allowlist.txt` is unchanged.
- **Windows:** write R scripts with a file-writing tool (bash heredocs collapse `\\`).
- **Commit trailer:** `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Stale derived config values after a CLI override.** `config.R` derives `.playoff_context` (`:649`) and the test window (`:212`) from `WEEK_TO_SIM`/`SEASON` while it is being sourced. A regular-season override must yield regular-season derived values. → Task 1 test.
2. **The golden-master run isn't deterministic** (props scraping, network data refresh), so diffs would be noise. → Task 2 runs the game model only (`RUN_PLAYER_PROPS <- FALSE`) and records the nflreadr version and the input-schedule hash. A second record of the same code must reproduce the same outputs exactly.
3. **The random-shift RNG change consumes RNG draws other code expects.** Callers call `set.seed()` right before simulating. → Task 3 tests that the same seed reproduces results bit-for-bit, and that the moments stay within Monte Carlo tolerance.
4. **A spread fallback fires with NA or an extreme spread.** → Task 4 tests NA → NA, ±30 → within (0,1), symmetry, and agreement in direction with moneylines on real 2024 rows.
5. **A game with no market line** must not be scored as if the market agreed with the model, and must not crash. → Task 5 tests the flag, the warning, the market-quality status and that downstream behavior is unchanged.

---

### Task 1: M1 — CLI week/season survive every config load

**Files:**
- Create: `R/run_config.R`, `tests/testthat/test-run-config.R`
- Modify: `config.R:33,40` (read options), `run_week.R:22-55` (arg parsing and overrides)

**Interfaces:**
- Produces: `parse_run_args(args)` → `list(week = <int or NA>, season = <int or NA>)`. It stops on invalid input.
- Produces: `set_run_options(parsed)`, which sets `options(nfl.week =, nfl.season =)` for non-NA values.
- `config.R` reads `getOption("nfl.season", 2025L)` and `getOption("nfl.week", 22L)`.

- [ ] **Step 1: Write the failing test** `tests/testthat/test-run-config.R`:
```r
test_that("parse_run_args validates and converts", {
  expect_equal(parse_run_args(character()), list(week = NA_integer_, season = NA_integer_))
  expect_equal(parse_run_args(c("15", "2024")), list(week = 15L, season = 2024L))
  expect_equal(parse_run_args("7"), list(week = 7L, season = NA_integer_))
  expect_error(parse_run_args("0"), "week")
  expect_error(parse_run_args("23"), "week")
  expect_error(parse_run_args(c("5", "1999")), "season")
  expect_error(parse_run_args("x"), "week")
})

test_that("config.R honours run options, including values derived while sourcing", {
  withr::local_options(nfl.week = 15L, nfl.season = 2024L)
  env <- new.env()
  withr::with_dir(PROJECT_ROOT, sys.source("config.R", envir = env))
  expect_equal(env$WEEK_TO_SIM, 15L)
  expect_equal(env$SEASON, 2024L)
  expect_equal(env$.playoff_context$phase, "regular_season")   # derived while sourcing (config.R:649)
  # a second load (as NFLsimulation.R does) keeps the override
  withr::with_dir(PROJECT_ROOT, sys.source("config.R", envir = env))
  expect_equal(env$WEEK_TO_SIM, 15L)
})

test_that("config.R defaults are unchanged without options", {
  withr::local_options(nfl.week = NULL, nfl.season = NULL)
  env <- new.env()
  withr::with_dir(PROJECT_ROOT, sys.source("config.R", envir = env))
  expect_equal(env$WEEK_TO_SIM, 22L)
  expect_equal(env$SEASON, 2025L)
})
```
`.auto_detect_playoff_context()` (`config.R:634`) returns `list(phase = "regular_season" | "playoffs", round = ...)`.

- [ ] **Step 2: Run it and confirm it FAILS.** `parse_run_args` doesn't exist, and `WEEK_TO_SIM` is 22.

- [ ] **Step 3: Implement.** `R/run_config.R`:
```r
# =============================================================================
# Run configuration: CLI week/season -> R options read by config.R (audit M1)
# =============================================================================

#' Parse `Rscript run_week.R [week] [season]` arguments
parse_run_args <- function(args) {
  out <- list(week = NA_integer_, season = NA_integer_)
  if (length(args) >= 1) {
    wk <- suppressWarnings(as.integer(args[[1]]))
    if (is.na(wk) || wk < 1L || wk > 22L) stop("Invalid week number: must be 1-22 (got '", args[[1]], "')", call. = FALSE)
    out$week <- wk
  }
  if (length(args) >= 2) {
    ss <- suppressWarnings(as.integer(args[[2]]))
    if (is.na(ss) || ss < 2011L || ss > 2030L) stop("Invalid season: must be 2011-2030 (got '", args[[2]], "')", call. = FALSE)
    out$season <- ss
  }
  out
}

#' Publish parsed values as options so every source("config.R") derives from them
set_run_options <- function(parsed) {
  if (!is.na(parsed$week)) options(nfl.week = parsed$week)
  if (!is.na(parsed$season)) options(nfl.season = parsed$season)
  invisible(parsed)
}
```
In `config.R`, change the two assignments (keeping their comments):
```r
SEASON <- as.integer(getOption("nfl.season", 2025L))  # CLI: Rscript run_week.R <week> <season>
WEEK_TO_SIM <- as.integer(getOption("nfl.week", 22L))  # <-- default week; CLI overrides via options
```
In `run_week.R`, replace everything from `# Parse command line arguments` through the end of the `# Apply command line overrides AFTER sourcing config` block with:
```r
# Parse command line arguments and publish them before config.R is sourced (audit M1:
# NFLsimulation.R re-sources config.R, so overrides must live in options, not globals)
source("R/run_config.R")
set_run_options(parse_run_args(commandArgs(trailingOnly = TRUE)))
source("config.R")
```
Leave `NFLsimulation.R:2422` (`source("config.R")`) unchanged. It now re-derives from the same options.

- [ ] **Step 4: Run the test and confirm it PASSES.**

- [ ] **Step 5: Smoke-test the real entry point.** Write `<scratchpad>/m1_smoke.R`:
```r
setwd("C:/Users/jviol/Downloads/nfl")
source("R/run_config.R"); set_run_options(parse_run_args(c("15", "2024"))); source("config.R")
source("config.R")   # simulate NFLsimulation.R's re-source
stopifnot(WEEK_TO_SIM == 15L, SEASON == 2024L); cat("M1 OK\n")
```
Expected output: `M1 OK`.

- [ ] **Step 6: Run the gates, then commit** `fix(M1): CLI week/season survive config re-source via options`.

---

### Task 2: Golden master (record the baseline before any output-changing fix)

**Files:**
- Create: `scripts/golden_master.R`, `tests/testthat/test-golden-master-compare.R`, `reports/<date>/golden-master/2024-w15/{final_numeric.csv, meta.json}`

**Interfaces:**
- Produces: `Rscript scripts/golden_master.R record <week> <season> <out_dir>` and `Rscript scripts/golden_master.R compare <week> <season> <golden_dir>`.
- Produces: `gm_diff(golden, current, tol = 0)` → data.frame(column, n_games_changed, max_abs_diff), used by Tasks 3–6 to attribute their output changes.

- [ ] **Step 1: Write the failing test** for the pure diff function:
```r
source(file.path(PROJECT_ROOT, "scripts", "golden_master.R"))   # defines functions; main() only runs via Rscript
test_that("gm_diff reports changed numeric columns per game", {
  g <- data.frame(game_id = c("a", "b"), p = c(0.5, 0.6), q = c(1, 2))
  c1 <- data.frame(game_id = c("b", "a"), p = c(0.6, 0.55), q = c(2, 1))
  d <- gm_diff(g, c1)
  expect_equal(d$column, "p"); expect_equal(d$n_games_changed, 1L); expect_equal(d$max_abs_diff, 0.05)
  expect_equal(nrow(gm_diff(g, g)), 0L)
  expect_error(gm_diff(g, c1[1, ]), "game_id")
})
```

- [ ] **Step 2: Run it and confirm it FAILS** (the script doesn't exist).

- [ ] **Step 3: Implement `scripts/golden_master.R`:**
```r
#!/usr/bin/env Rscript
# Golden master for the game model (audit plan Phase 1a).
#   record  <week> <season> <out_dir>    run the game model, store numeric outputs
#   compare <week> <season> <golden_dir> run again, print per-column differences
# Game model only (RUN_PLAYER_PROPS = FALSE) so the output is deterministic.

gm_diff <- function(golden, current, tol = 0) {
  if (!setequal(golden$game_id, current$game_id)) stop("gm_diff: game_id sets differ")
  current <- current[match(golden$game_id, current$game_id), , drop = FALSE]
  cols <- intersect(setdiff(names(golden), "game_id"), names(current))
  rows <- lapply(cols, function(cl) {
    a <- golden[[cl]]; b <- current[[cl]]
    diff <- abs(a - b); diff[is.na(a) & is.na(b)] <- 0; diff[xor(is.na(a), is.na(b))] <- Inf
    changed <- diff > tol
    if (!any(changed)) return(NULL)
    data.frame(column = cl, n_games_changed = sum(changed), max_abs_diff = max(diff))
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) data.frame(column = character(), n_games_changed = integer(), max_abs_diff = numeric()) else out
}

gm_run_model <- function(week, season) {
  source("R/run_config.R")
  set_run_options(list(week = as.integer(week), season = as.integer(season)))
  source("config.R")
  RUN_PLAYER_PROPS <<- FALSE
  started <- Sys.time()
  source("NFLsimulation.R")
  latest <- list.files("run_logs", pattern = "^final_.*\\.rds$", full.names = TRUE)
  latest <- latest[file.mtime(latest) >= started]
  if (!length(latest)) stop("golden_master: NFLsimulation.R wrote no run_logs/final_*.rds")
  final <- readRDS(latest[which.max(file.mtime(latest))])
  num <- vapply(final, is.numeric, logical(1))
  list(data = as.data.frame(final[, c("game_id", names(final)[num & names(final) != "game_id"])]),
       seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))
}

gm_main <- function(args) {
  mode <- args[[1]]; week <- args[[2]]; season <- args[[3]]; dir <- args[[4]]
  run <- gm_run_model(week, season)
  if (mode == "record") {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(run$data, file.path(dir, "final_numeric.csv"), row.names = FALSE)
    meta <- list(week = week, season = season, n_games = nrow(run$data),
                 git_sha = system2("git", c("rev-parse", "HEAD"), stdout = TRUE),
                 n_trials = N_TRIALS, seed = SEED, r_version = R.version.string,
                 nflreadr = as.character(utils::packageVersion("nflreadr")),
                 run_seconds = round(run$seconds),
                 csv_sha256 = digest::digest(file = file.path(dir, "final_numeric.csv"), algo = "sha256"))
    writeLines(jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE), file.path(dir, "meta.json"))
    cat("recorded", nrow(run$data), "games to", dir, "\n")
  } else if (mode == "compare") {
    golden <- utils::read.csv(file.path(dir, "final_numeric.csv"), stringsAsFactors = FALSE)
    d <- gm_diff(golden, run$data)
    if (nrow(d)) print(d, row.names = FALSE) else cat("golden master: no differences\n")
  } else stop("mode must be record or compare")
}

if (sys.nframe() == 0L) gm_main(commandArgs(trailingOnly = TRUE))
```

- [ ] **Step 4: Run the test and confirm it PASSES.**

- [ ] **Step 5: Record the golden master and prove it's deterministic.**
  1. Run `Rscript scripts/golden_master.R record 15 2024 reports/<date>/golden-master/2024-w15` in the background and log the runtime.
  2. Run `compare` against it immediately. Expected: `golden master: no differences`.
  3. If they differ, the pipeline isn't deterministic. Stop and report which columns differ. Don't proceed with an unstable baseline.

- [ ] **Step 6: Run the gates, then commit** `test: golden master for 2024 week 15 (game model)`. Commit the CSV and meta.json.

---

### Task 3: M12 — Distinct, reproducible random streams per game

**Files:**
- Create: `tests/testthat/helper-extract.R`, `tests/testthat/test-simulate-game-nb.R`
- Modify: `NFLsimulation.R`, inside `simulate_game_nb` (the `randtoolbox::sobol(... scrambling = 0 ...)` line, ~:5316)

**Interfaces:**
- Produces: `load_script_functions(path, names)` → an environment holding the named top-level function definitions. Tasks 4 and 5 use it.

- [ ] **Step 1: Write the helper and the failing test.**

`tests/testthat/helper-extract.R`:
```r
#' Evaluate selected top-level function definitions from a script (without running it).
#' Safety: only `name <- function(...)`-style assignments from this repository's own
#' tracked scripts are evaluated; nothing else in the script runs.
load_script_functions <- function(path, names, envir = new.env(parent = globalenv())) {
  exprs <- parse(path, keep.source = FALSE)
  found <- character()
  for (e in exprs) {
    if (is.call(e) && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
        is.name(e[[2]]) && as.character(e[[2]]) %in% names) {
      eval(e, envir)
      found <- c(found, as.character(e[[2]]))
    }
  }
  missing <- setdiff(names, found)
  if (length(missing)) stop("load_script_functions: not found in ", basename(path), ": ", paste(missing, collapse = ", "))
  envir
}
```

`tests/testthat/test-simulate-game-nb.R`:
```r
sim_env <- load_script_functions(file.path(PROJECT_ROOT, "NFLsimulation.R"),
                                 c("simulate_game_nb", "nb_size_from_musd"))
sim_env$NB_SIZE_MIN <- 5; sim_env$NB_SIZE_MAX <- 50; sim_env$SEED <- 471

run_sim <- function(seed, n = 4000) {
  set.seed(seed)
  sim_env$simulate_game_nb(24, 10, 21, 10, n_trials = n, rho = 0.1, cap = 70)
}

test_that("different RNG states give different score streams (audit M12)", {
  expect_false(identical(run_sim(1)$margin, run_sim(2)$margin))
})

test_that("the same RNG state reproduces draws exactly", {
  expect_identical(run_sim(7), run_sim(7))
})

test_that("score means stay within Monte Carlo tolerance of the targets", {
  s <- run_sim(11, n = 40000)
  expect_lt(abs(mean(s$home) - 24), 0.3)
  expect_lt(abs(mean(s$away) - 21), 0.3)
  expect_true(all(s$home >= 0 & s$home <= 70))
})
```

- [ ] **Step 2: Run it and confirm it FAILS.** Only the "different RNG states" test should fail, because `scrambling = 0` ignores every RNG state.

- [ ] **Step 3: Implement.** In `simulate_game_nb`, replace the single line
`U <- randtoolbox::sobol(n = n_half, dim = 2, scrambling = 0, seed = seed, normal = FALSE)` with:
```r
  U <- randtoolbox::sobol(n = n_half, dim = 2, scrambling = 0, seed = seed, normal = FALSE)
  # Randomized QMC (Cranley-Patterson rotation, audit M12): with scrambling = 0 the
  # `seed` is ignored, so every game reused one uniform stream. A uniform shift drawn
  # from the caller-seeded RNG gives each game a distinct, reproducible stream while
  # keeping Sobol low discrepancy.
  shift <- stats::runif(2)
  U <- (U + matrix(shift, nrow = nrow(U), ncol = 2, byrow = TRUE)) %% 1
  U <- pmin(pmax(U, 1e-12), 1 - 1e-12)
```

- [ ] **Step 4: Run it and confirm it PASSES.**

- [ ] **Step 5: Golden-master compare.** Run `Rscript scripts/golden_master.R compare 15 2024 reports/<date>/golden-master/2024-w15`. Paste the diff table into the report. Every probability column may change by Monte Carlo noise only: at N = 100,000, expect |Δp| well under 0.01. A larger change is a finding. Stop and report it.

- [ ] **Step 6: Run the gates, then commit** `fix(M12): per-game randomized Sobol streams`.

---

### Task 4: M10 — One spread → probability convention (nflreadr: positive spread_line = home favored)

**Files:**
- Create: `tests/testthat/fixtures/schedules_2024_lines.csv`, `tests/testthat/test-spread-convention.R`
- Modify:
  - `R/utils.R`: add `spread_line_to_home_prob()`
  - `config.R`: add `SPREAD_MARGIN_SD <- 13.86`
  - `NFLsimulation.R`:
    - `map_spread_prob` (~:6568): replace its body.
    - `map_spread_total_prob` (~:7226): replace its `pnorm(-sp/13.86)` fallback.
  - `NFLbrier_logloss.R`: in `compare_to_market`, replace the spread fallback `pnorm(-home_spread / SD_MARGIN)` (~:637).
- Unchanged: `NFLmarket.R::spread_to_win_probability`. It operates on `market_home_spread` after `harmonize_home_spread()` aligns the sign with the market probability. Leave it as it is, and record that in the report.

- [ ] **Step 1: Create the fixture.** It comes from real data, fetched once. Write `<scratchpad>/make_lines_fixture.R`:
```r
setwd("C:/Users/jviol/Downloads/nfl")
s <- nflreadr::load_schedules(2024)
s <- s[s$game_type == "REG" & is.finite(s$spread_line) & is.finite(s$home_moneyline), 
       c("game_id", "spread_line", "home_moneyline", "away_moneyline", "home_score", "away_score")]
utils::write.csv(s, "tests/testthat/fixtures/schedules_2024_lines.csv", row.names = FALSE)
cat(nrow(s), "rows\n")
```
Expect about 272 rows.

- [ ] **Step 2: Write the failing test:**
```r
lines <- utils::read.csv(testthat::test_path("fixtures", "schedules_2024_lines.csv"))

test_that("positive spread_line means the home team is favoured (nflreadr convention)", {
  ml_home <- american_to_probability(lines$home_moneyline)
  ml_away <- american_to_probability(lines$away_moneyline)
  p_ml <- ml_home / (ml_home + ml_away)
  clear <- abs(lines$spread_line) >= 2.5
  p_sp <- spread_line_to_home_prob(lines$spread_line, SPREAD_MARGIN_SD)
  agree <- mean(sign(p_sp[clear] - 0.5) == sign(p_ml[clear] - 0.5))
  expect_gt(agree, 0.97)
})

test_that("spread_line_to_home_prob is monotone, symmetric and NA-safe", {
  expect_gt(spread_line_to_home_prob(7, 13.86), 0.5)
  expect_equal(spread_line_to_home_prob(3, 13.86) + spread_line_to_home_prob(-3, 13.86), 1)
  expect_true(is.na(spread_line_to_home_prob(NA_real_, 13.86)))
  p <- spread_line_to_home_prob(c(-30, 0, 30), 13.86)
  expect_true(all(p > 0 & p < 1)); expect_equal(p[2], 0.5)
})

test_that("NFLsimulation's spread fallback map agrees with the convention", {
  env <- load_script_functions(file.path(PROJECT_ROOT, "NFLsimulation.R"), "map_spread_prob")
  expect_gt(env$map_spread_prob(7), 0.5)
  expect_lt(env$map_spread_prob(-7), 0.5)
})
```

- [ ] **Step 3: Run it and confirm it FAILS.** `spread_line_to_home_prob` doesn't exist yet, and `map_spread_prob(7)` currently returns ≈0.12.

- [ ] **Step 4: Implement.** In `R/utils.R`, add next to `shrink_probability_toward_market`:
```r
#' Home win probability from an nflverse spread_line (positive = home favoured)
#' @param spread_line nflreadr `spread_line` (home favoured by this many points)
#' @param sigma NFL final-margin SD (config SPREAD_MARGIN_SD)
spread_line_to_home_prob <- function(spread_line, sigma) {
  p <- stats::pnorm(suppressWarnings(as.numeric(spread_line)) / sigma)
  ifelse(is.na(p), NA_real_, clamp_probability(p))
}
```
In `config.R`, after the market parameters, add:
```r
#' @description NFL final-margin SD used to convert spread_line to win probability
#' @default 13.86
SPREAD_MARGIN_SD <- 13.86
```
Add `SPREAD_MARGIN_SD = SPREAD_MARGIN_SD,` to `list2env`.

In `NFLsimulation.R`, replace the body of `map_spread_prob` with:
```r
map_spread_prob <- function(sp) {
  # sp = nflreadr spread_line (positive = home favoured); audit M10
  spread_line_to_home_prob(sp, SPREAD_MARGIN_SD)
}
```
In `map_spread_total_prob`, replace `pnorm(-sp/13.86)` with `spread_line_to_home_prob(sp, SPREAD_MARGIN_SD)`. In `NFLbrier_logloss.R`, replace `.clamp01(pnorm(-home_spread / SD_MARGIN))` with `spread_line_to_home_prob(home_spread, SD_MARGIN)`.

- [ ] **Step 5: Run it and confirm it PASSES.**

- [ ] **Step 6: Golden-master compare.** 2024 week 15 has moneylines for every game, so the fallback shouldn't fire. Expected: no differences beyond Task 3's baseline. If anything changes, report it; it means the fallback fired.

- [ ] **Step 7: Run the gates, then commit** `fix(M10): single nflreadr spread convention for probability fallbacks`.

---

### Task 5: M11 — Missing market lines are flagged, logged and tracked, not silently filled

**Files:**
- Create: `tests/testthat/test-attach-market.R`
- Modify: `NFLsimulation.R`. Replace the inline "Join market data and calculate away market probability" block (~:6673-6682) with a function `attach_market_probs()` defined just above it, and a call to it.

- [ ] **Step 1: Write the failing test:**
```r
env <- load_script_functions(file.path(PROJECT_ROOT, "NFLsimulation.R"), c("attach_market_probs", ".clp"))

test_that("games without a market line are flagged, warned about and tracked", {
  final <- data.frame(game_id = c("g1", "g2"), home_p_2w_cal = c(0.6, 0.4), away_p_2w_cal = c(0.4, 0.6))
  mkt <- data.frame(game_id = "g1", home_p_2w_mkt = 0.55)
  expect_warning(out <- env$attach_market_probs(final, mkt), "g2")
  expect_equal(out$market_available, c(TRUE, FALSE))
  expect_equal(out$home_p_2w_mkt[1], 0.55)
  # blend input keeps working (internal fill from home_p_2w_cal) but is explicitly marked
  expect_equal(out$home_p_2w_mkt[2], 0.4)
  q <- get_data_quality()
  expect_equal(q$market$status, "partial")
  expect_true("g2" %in% q$market$missing_games)
})

test_that("all games with lines report full market quality and no warning", {
  final <- data.frame(game_id = "g1", home_p_2w_cal = 0.6, away_p_2w_cal = 0.4)
  expect_silent(out <- env$attach_market_probs(final, data.frame(game_id = "g1", home_p_2w_mkt = 0.52)))
  expect_true(out$market_available)
  expect_equal(get_data_quality()$market$status, "full")
})
```
`get_data_quality()$market` exposes `status` and `missing_games` (`R/data_validation.R:378-415`). `.clp` needs `PROB_EPSILON`, which comes from `R/utils.R` (loaded by `setup.R`).

- [ ] **Step 2: Run it and confirm it FAILS** (`attach_market_probs` not found).

- [ ] **Step 3: Implement.** Define the function directly above the market-join block:
```r
#' Join market probabilities; flag, log and track games without a line (audit M11).
#' Games without a line keep the model probability as the blend *input* only, marked
#' market_available = FALSE; betting governance already passes on missing odds.
attach_market_probs <- function(final, mkt_now) {
  out <- dplyr::left_join(final, mkt_now, by = "game_id")
  out$market_available <- is.finite(out$home_p_2w_mkt)
  missing <- out$game_id[!out$market_available]
  out$home_p_2w_mkt <- ifelse(out$market_available, .clp(out$home_p_2w_mkt), out$home_p_2w_cal)
  out$away_p_2w_mkt <- 1 - out$home_p_2w_mkt
  if (length(missing)) {
    warning(sprintf("No market line for %d game(s): %s. Model probability used as blend input only; no market comparison or bet.",
                    length(missing), paste(missing, collapse = ", ")), call. = FALSE)
    update_market_quality(if (length(missing) == nrow(out)) "unavailable" else "partial", missing_games = missing)
  } else {
    update_market_quality("full")
  }
  out
}
```
Replace the inline `final <- final %>% dplyr::left_join(mkt_now, ...) %>% dplyr::mutate(...)` block with `final <- attach_market_probs(final, mkt_now)`.

The `tryCatch` that builds `mkt_now` swallows errors into an empty tibble. Make it log: `error = function(e) { warning("market_probs_from_sched failed: ", conditionMessage(e), call. = FALSE); tibble::tibble(game_id = character(), home_p_2w_mkt = numeric()) }`.

- [ ] **Step 4: Run it and confirm it PASSES.**

- [ ] **Step 5: Golden-master compare.** Expected: no differences in numeric outputs. `market_available` is a new logical column, and the golden-master diff only compares numeric columns.

- [ ] **Step 6: Run the gates, then commit** `fix(M11): flag and log games without market lines`.

---

### Task 6: M2/M3 — One market-weight stage

**Files:**
- Create: `tests/testthat/test-market-weight.R`
- Modify:
  - `NFLsimulation.R`: delete the whole `# 3) Apply shrinkage BEFORE calibration` section (the playoff branch and the dynamic-shrinkage branch, ~:8055-8142). Also neutralize all four calibration console messages that print withdrawn or outcome-leaked numbers. This is Phase 0 final review I5, per Ruling R16; the M4 logic stays in Phase 1b.
    - `~:5644` "Ensemble test Brier: …" (prints the M4-leaked 0.1049): replace with `"Ensemble calibrator loaded (invalid: fit on outcome-leaked data, audit M4)"`.
    - `~:5672` "Using SPLINE calibration (-6.9% Brier improvement)": replace with `"Using SPLINE calibration (unvalidated, see docs/EVIDENCE_LEDGER.md)"`.
    - `~:5694` "Test Brier (out-of-sample)": replace with `"Calibrator test Brier (not out-of-sample, audit M4/M5)"`.
    - `~:5713` "(2.1% Brier improvement)": remove the parenthetical.
    - Do not print any of these numbers.
  - `NFLmarket.R` (~:2220-2224): `.game_shrinkage = SHRINKAGE` for every game type, and its comment block. The source-note subtitle mentioning "Playoff shrinkage 70-75%" (~:3599) is reworded to the single weight.
  - `config.R`: remove `USE_DYNAMIC_SHRINKAGE`, `SHRINKAGE_BASE`, `SHRINKAGE_EARLY_SEASON_ADJ`, `SHRINKAGE_HIGH_SPREAD_ADJ`, `SHRINKAGE_CLOSE_GAME_ADJ`, `SHRINKAGE_HIGH_SPREAD_THRESHOLD`, `SHRINKAGE_CLOSE_GAME_THRESHOLD`, `PLAYOFF_SHRINKAGE`, `SUPER_BOWL_SHRINKAGE`. Also remove their `list2env` entries and the summary print that references them (~:1036). `SHRINKAGE` stays at 0.70.
  - `R/playoffs.R`: delete `get_playoff_shrinkage`.
  - `tests/testthat/test-playoffs.R`: delete the `get_playoff_shrinkage returns correct values` test.
  - `docs/EVIDENCE_LEDGER.md`: row `C-SHRINK` reason becomes "Single 70% market weight since Phase 1a; value unvalidated until Phase 3".

- [ ] **Step 1: Write the failing test:**
```r
test_that("final probability never moves away from the market (single-stage invariant)", {
  set.seed(5)
  p_model <- runif(500, 0.05, 0.95); p_mkt <- runif(500, 0.05, 0.95)
  p_final <- shrink_probability_toward_market(p_model, p_mkt, shrinkage = SHRINKAGE)
  expect_true(all(abs(p_final - p_mkt) <= abs(p_model - p_mkt) + 1e-12))
  expect_equal(p_final, (1 - SHRINKAGE) * p_model + SHRINKAGE * p_mkt)   # inputs are inside (0.05, 0.95), so clamping is a no-op
})

# Source guards (static): the removed stages must not return (audit M2, M3)
test_that("no dynamic or playoff-specific shrinkage remains", {
  sim <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  mkt <- readLines(file.path(PROJECT_ROOT, "NFLmarket.R"), warn = FALSE)
  cfg <- readLines(file.path(PROJECT_ROOT, "config.R"), warn = FALSE)
  expect_false(any(grepl("dynamic_shrinkage|get_playoff_shrinkage\\(", sim)))
  expect_false(any(grepl("PLAYOFF_SHRINKAGE|SUPER_BOWL_SHRINKAGE", c(mkt, cfg))))
  expect_false(any(grepl("^(USE_DYNAMIC_SHRINKAGE|SHRINKAGE_BASE|SHRINKAGE_[A-Z_]+_(ADJ|THRESHOLD))\\s*<-", cfg)))
  expect_false(any(grepl("6\\.9% Brier|2\\.1% Brier improvement|Ensemble test Brier:", sim)))
})
```
- [ ] **Step 2: Run it and confirm the guard test FAILS.** The invariant test passes already; it pins the kept function.

- [ ] **Step 3: Implement the deletions and edits listed under Files.** In NFLsimulation.R, `p_raw` flows straight from the blend step into `# 4) NOW apply isotonic calibration`. Keep that section header and change its comment to "calibration of the blend (no pre-calibration shrinkage; audit M2)".

- [ ] **Step 4: Run it and confirm it PASSES.** Then run `grep -rn "SHRINKAGE_BASE\|USE_DYNAMIC_SHRINKAGE\|PLAYOFF_SHRINKAGE\|SUPER_BOWL_SHRINKAGE\|get_playoff_shrinkage" --include=*.R . | grep -v archive/`. Only `scripts/parameter_grid_search.R` may still mention them (audit: broken tuning script, retired in Phase 3). List those lines in the report.

- [ ] **Step 5: Golden-master compare.** Expected: the calibrated/blend probability columns change for every game. Regular-season week 15 previously got the anti-shrink −0.15 adjustment, and the displayed shrunk probabilities now use one stage. Report the per-column diff and the direction: each `|p − market|` for the final probability should shrink or stay the same. Compute this from the two CSVs in the report.

- [ ] **Step 6: Run the gates, then commit** `fix(M2,M3): single 70% market-weight stage; remove anti-shrink and playoff variants`.

---

### Task 7: M14 — Date resolver parses nflreadr HH:MM kickoffs

**Files:**
- Modify: `R/date_resolver.R`. In `parse_datetime`, add a `ymd_hm` attempt between `ymd_hms` and `ymd` (~:162-168).
- Modify: `tests/testthat/test-date-resolver.R`. Remove the six `skip("KNOWN-DEFECT M14: ...")` lines, and fix any assertion that only passed because every date resolved to the offseason (Phase 0 ledger minor).

- [ ] **Step 1: Write the failing test** in `test-date-resolver.R`:
```r
test_that("parse_datetime accepts nflreadr 'YYYY-MM-DD HH:MM' kickoffs (audit M14)", {
  x <- parse_datetime("2024-09-05 20:20", tz = "America/New_York")
  expect_false(is.na(x))
  expect_equal(format(x, "%H:%M"), "20:20")
})
```

- [ ] **Step 2: Run it and confirm it FAILS** (returns NA).

- [ ] **Step 3: Implement.** After the `ymd_hms` attempt:
```r
  if (is.na(parsed)) {
    parsed <- tryCatch({
      lubridate::ymd_hm(datetime_str, tz = tz, quiet = TRUE)
    }, warning = function(w) lubridate::NA_POSIXct_,
    error = function(e) lubridate::NA_POSIXct_)
  }
```

- [ ] **Step 4: Remove the M14 skips and run the date-resolver tests.** They now exercise real resolution. Fix any assertion that encoded the offseason-only behavior, and state what each test now checks. If a test fails for a new reason, add it to the addendum as a new ID and skip it with that ID.

- [ ] **Step 5: Run the gates, then commit** `fix(M14): parse nflreadr HH:MM gametimes in the date resolver`.

---

### Task 8: M15 — Snap percentages from play-level participation data

**Files:**
- Modify: `injury_scalp.R`. In `load_player_snap_percentages`, move the play-level branch before the snap-column detection (~:1384-1394).
- Modify: `tests/testthat/test-snap-weighting.R`. Remove the `skip("KNOWN-DEFECT M15: ...")` line.

- [ ] **Step 1: Confirm the test fails with the skip removed.** Run the M15 test without its skip; it should fail with `nrow(snap_data) > 0` (this is the Phase 0 test). Also make the test pass explicit weeks (`weeks = 1:4`) instead of reading `WEEK_TO_SIM` from config (Phase 0 ledger minor), so it doesn't depend on config.

- [ ] **Step 2: Implement.** Immediately after the `if (nrow(filtered) == 0) return(default_result)` check, insert:
```r
    # nflreadr participation is play-level (offense_players strings, n_offense counts);
    # route it to the play-level calculator before looking for per-player snap columns
    # (audit M15: n_offense was mistaken for a per-player snap count)
    if ("offense_players" %in% names(filtered)) {
      return(calculate_snap_pct_from_plays(filtered, team))
    }
```
Then delete the now-unreachable `offense_players` branch inside the `if (is.null(snap_col))` block.

- [ ] **Step 3: Run the test and confirm it PASSES** with more than 0 rows.

- [ ] **Step 4: Run the gates, then commit** `fix(M15): compute snap percentages from play-level participation`.

---

### Task 8b: M16 — Offensive injury penalty clamp and scope

**Files:**
- Create: `tests/testthat/test-injury-penalty-clamp.R`
- Modify: `NFLsimulation.R`, in the injury summarise/mutate block (~:3445 offensive sum, ~:3457 clamp)

**Interfaces:** Extract the summarise+mutate into a top-level function `summarise_injury_points(inj, group_vars)` directly above its current use, and call it in place. It is then testable with `load_script_functions()`. Behavior is otherwise unchanged except for the two fixes below.

- [ ] **Step 1: Write the failing test.** Give it a fixture `inj` data frame with columns `position`, `pos_group`, `pen`, `severity`, `snap_weight`, plus a `team` group column. Cover:
  - one questionable WR (`pen = -0.20 * 1.05`, severity 0.4) → `inj_off_pts` in (−1.5, 0), not ≤ −1.5;
  - many OUT offensive starters → `inj_off_pts` ≥ −4.0 (the floor holds);
  - one OUT CB → `inj_off_pts == 0` (defensive injuries don't lower offensive points) and `inj_def_pts` in (0, 1.5];
  - a team with no rows → absent, so the caller's `coalesce(…, 0)` applies.
- [ ] **Step 2: Run it and confirm it FAILS.** The questionable-WR case returns −1.5, and the CB case lowers `inj_off_pts`.
- [ ] **Step 3: Implement.**
  - Offensive sum only over offensive non-QB positions: `pos_group %in% c("trenches", "skill")`.
  - Clamp `inj_off_pts = pmin(pmax(inj_off_pts_raw * w, -4.0), 0)`, i.e. bounds [−4.0, 0]. This mirrors the defensive clamp's shape. The −4.0 floor is the existing value; keep it and don't tune it here.
  - Add `INJURY_OFF_PTS_FLOOR <- -4.0` and `INJURY_DEF_PTS_CAP <- 1.5` to `config.R` (no hardcoded values), and use them.
- [ ] **Step 4: Run it and confirm it PASSES.**
- [ ] **Step 5: Golden-master compare.** Expect totals and margins to shift for every game with injury rows. The mean total should rise by about 2–3 points. Report the per-column diff and the change in mean predicted total vs actual 2024 week 15 totals.
- [ ] **Step 6: Run the gates, then commit** `fix(M16): offensive injury penalty clamp and offensive-only scope`.

---

### Task 9: Phase 1a close-out

- [ ] **Step 0a: Add an offline pipeline artifact to `run_matrix.R`** (Phase 0 Ruling R14, spec Phase 0 item). Add an artifact `golden-master` that runs `Rscript scripts/golden_master.R compare 15 2024 reports/<date>/golden-master/2024-w15`. Its timeout is the golden master's recorded runtime × 2.
  - It passes only when there are no differences from the recorded golden master.
  - After an intentional, attributed change, re-record the golden master in the same PR and cite the ATTRIBUTION table.
  - "Offline" here means it uses the nflreadr cache. If the cache is cold it needs network, and a network miss skips as `LIVE:` rather than failing.
- [ ] **Step 0b: Validate KNOWN-DEFECT IDs** (Phase 0 ledger minor). In `R/test_policy.R`, add `known_defect_ids(paths)`, which parses the `| ID |` first column of `reports/2026-09-28/AUDIT.md` and `reports/2026-09-29/AUDIT-ADDENDUM.md`. In `scripts/run_tests.R`, treat a `KNOWN-DEFECT <ID>:` skip as unapproved when that ID isn't listed. Add tests: `KNOWN-DEFECT M999` → unapproved, `KNOWN-DEFECT M15` → approved. This requires #191 merged, so `AUDIT.md` is on `main`.
- [ ] **Step 1: Run the gates.** `Rscript scripts/run_tests.R`, `Rscript scripts/verify_repo_integrity.R` and `Rscript scripts/run_matrix.R`. Quote the output of each.
- [ ] **Step 2: Build the golden-master attribution table.** For each of Tasks 3–6, list the columns changed, the max |Δ| and the cause. Save it as `reports/<date>/golden-master/2024-w15/ATTRIBUTION.md`.
- [ ] **Step 3: Update the docs.** CHANGELOG entries for each fix. In HANDOFF, record the next target, Phase 1b (point-in-time features, `predict_week()` extraction, disabling the invalid calibrator). Also note that `standardize_join_keys` still has duplicates outside `R/`.
- [ ] **Step 4: Push, open a PR, confirm CI is green, and ask the owner to approve the merge.**
