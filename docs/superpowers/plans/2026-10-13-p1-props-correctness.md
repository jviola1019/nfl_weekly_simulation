# P1: Props Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every player-prop number the model writes trustworthy: lines are point-in-time and keyed by game and player id, opponent-defense adjustments apply, each row gets one consistent decision (side, tier, stake), EV is taken at the best fresh price after fees, and a prop with no market price stays unpriced with a reason. The keyed Odds API path is retired.

**Architecture:** Three new pure R files (`R/prop_keys.R` team and player keys, `R/prop_pricing.R` devig, Kalshi fee and best-EV quote, and the call-graph script) plus targeted edits to `R/prop_odds_api.R`, `R/correlated_props.R` and `sports/nfl/props/props_config.R`. The quote cache becomes a table with `game_id`, `captured_at` and `player_id`; `get_market_prop_quotes()` is the only way a quote reaches a prop, and every refusal carries a reason that ends up in `artifacts/baseline_props.csv`. `govern_prop_rows()` makes side, tier and stake one decision. `NFLsimulation.R`, `NFLmarket.R` and `R/utils.R` are not edited.

**Tech Stack:** R 4.5.1 with renv (testthat 3, dplyr, tibble, nflreadr; no new package), Node only to apply the plan mechanically in the dry run.

**Spec:** roadmap `docs/superpowers/plans/2026-10-12-modeling-roadmap.md` section 4 "P1: props correctness" (items P14, P13, P1, P2/P3, P9, P12, P4/P5, P10) and section 2 (global constraints); audit rows P1-P14 in `reports/2026-09-28/AUDIT.md` and `reports/2026-09-29/AUDIT-ADDENDUM.md`; research notes `.superpowers/research/d1-p1-notes.md`.

**Tasks:** 8. Order: P13 first (Task 1), then the keys (Task 2, pure helpers the lookup needs) and P14 (Task 3), the two corruptions of every historical props output. Models: sonnet for Tasks 1-5 (judgment, new modules), haiku for Tasks 6-8 (complete code or text).

**Reading the code steps.** Each code step is preceded by an HTML comment `<!-- apply: Tn.k create|replace|append|delete-range <path> -->` followed by one or two fenced blocks. `create` writes the block as the whole file. `replace` has two blocks: the exact current text (it must occur exactly once) and the new text. `delete-range` has two blocks: the first and the last line of a range to delete, both inclusive. `append` adds the block to the end of the file. An implementer applies them by hand; the dry run applied them with a script (`.superpowers/research/p1-apply-plan.js`), so the plan text and the dry-run tree agree byte for byte.

## Global Constraints

- **Keyless data only:** no API keys and no free trials. At most 1 request per second, a truthful user agent, and a 20 s timeout. Never work around an HTTP 403 or 429. (Roadmap section 2.)
- **The 2025 game Holdout stays sealed.** Props may read 2025 Kalshi data only under a signed `nfl_props_v1` protocol (owner, 2026-10-13); that is P3's job, not P1's. Nothing in this plan reads 2025 data.
- **Stop and ask the owner before:** changing config.R defaults; editing `NFLsimulation.R`, `NFLmarket.R` or `injury_scalp.R` beyond an approved item; adding a dependency (`renv.lock` or `web/package.json`); changing `R/data_validation.R` signatures; editing `backtest/eval_windows/*.json` or any frozen `PROTOCOL.md`; deleting any file; merging any PR. (Roadmap section 2.)
- **Numbers in docs.** A number goes in a doc only if a script or CI produced it, and claims carry ledger statuses. No silent fallbacks: every data problem is logged and flagged. (Roadmap section 2.)
- **Golden master.** Every PR's prediction changes are attributed by CI (Linux). Run local R gates with a fresh `HOME` (an empty scratch directory) so no stale `~/.cache` entry leaks in. CI's Linux determinism noise is about 4e-9; differences above the 1e-6 gate are real.
- **Linux.** R `system2` runs `sh -c` on Linux: quote shell arguments (`shQuote`). Nothing here may rely on Windows-only behaviour; CI is Linux.
- **Branches and commits.** One branch per defect or phase, in a git worktree; fix and feat are never mixed within a commit. Every commit message ends with a blank line, then exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. The PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **The M11 rule for props:** a prop without a market stays NA and unpriced, with a pass reason, never a substituted number.
- **Outputs:** `artifacts/baseline_props.csv` is what `run_week.R` writes for props (A8). The web does not show props yet; P3 decides publication. Nothing in this plan adds props to a bundle or a page.
- **Unchanged:** `tests/skip_allowlist.txt` (the `KNOWN-DEFECT` regex stays; only the P13 skip call goes), `renv.lock`, `DESCRIPTION`, `NFLsimulation.R`, `NFLmarket.R`, `R/utils.R`, `R/data_validation.R`, `backtest/`, `contracts/`, `web/`, and every frozen protocol.
- **Windows and Git Bash:** write and edit files with the file tools (heredocs collapse backslashes); pass `C:/` paths to R and node; list a directory before deleting anything.
- **Kalshi fee coefficient:** `KALSHI_TAKER_FEE_COEF = 0.07` is an owner-verification-required config default, not a verified fact. Source and status are in Task 4; do not describe it as validated anywhere.

## Review Focus

The five failure modes most likely to bite, each pinned by a test in the task that owns it:

1. **A historical props run is priced with a line captured after its kickoff** (roadmap Review Focus 2, audit P14). The audit's case: 2024 week 16 NE @ BUF priced with the 2026 week 4 line for the same teams. Pinned by Task 3's "a 2024 week 16 run never sees a line captured after its kickoff" (a 2026 quote labelled with the 2024 game id, plus a 200-quote property test), and end to end through `run_game_props` ("prices 2024 w16 from a pre-kickoff quote and leaves the rest unpriced").
2. **A prop without a market gets a substituted number** (roadmap Review Focus 4, rule M11). Pinned by Task 3 (every refusal returns a reason and NULL, never a number), Task 4 ("nothing priceable gives NULL") and Task 5 ("a prop without a market price is unpriced, with its reason, and cannot be a bet", and the 10,000-row property that unpriced rows have no EV and no side).
3. **Stake and label disagree, or the Under is staked as the Over** (audit P2, P3). Pinned by Task 5: over 10,000 random rows `final_stake_pct > 0` if and only if `tier == "bet"`, an Under the model likes is staked on the Under's probability and price, and a positive-EV row below the minimum stake is a PASS, never an OVER with stake 0.
4. **Which `load_defense_rankings()` runs depends on source order** (audit P13's duplicate). Pinned by Task 1: the function is defined once across `R/` and `sports/nfl/props/`, and loading `R/correlated_props.R` and `data_sources.R` in either order gives an identical function; a second test fails if any function is defined in both directories again.
5. **A name or team collision joins the wrong player or the wrong game** (audit P9). Pinned by Task 2: `"KC"` never becomes `""`, `LA` and `LAR` are one team, A.St. Brown does not resolve to A.J. Brown, and the same name on two teams is resolved by team and left unresolved without one.

## Setup (once, before Task 1)

- [ ] **S1: Worktree and R library.** Create the branch worktree from `origin/main`, copy `.Rprofile` (`source("renv/activate.R")`; it is gitignored), then `Rscript -e "library(testthat); cat('ok\n')"`. If it fails with "there is no package called", run `Rscript -e "renv::restore(prompt = FALSE)"` (packages link from the renv cache; `git diff --exit-code renv.lock` must stay clean).
- [ ] **S2: Baseline.** With `HOME=<empty scratch dir>`: `Rscript scripts/run_tests.R` gives `tests=450 passed=1722 failed=0 errors=0 skipped=1 unapproved_skips=0` (the one skip is `KNOWN-DEFECT P13`), exit 0; `Rscript scripts/verify_repo_integrity.R` gives `Total: 63 passed, 0 failed`, exit 0 (both measured at `210f791` on 2026-10-13).
- [ ] **S3: Test command.** Every "Run" step below runs from the repository root as `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = '<name>')"`. `tests/testthat/setup.R` sources every `R/*.R`, so a new `R/` file is loaded in tests automatically; production loads them from `R/correlated_props.R`.

## Owner checkpoints (STOP items)

| Where | What the owner decides |
|---|---|
| Task 3, Step 1 | New `config.R` default `PROP_QUOTE_MAX_AGE_MIN = 120` (minutes). Policy value, not measured. |
| Task 4, Step 1 | New `config.R` default `KALSHI_TAKER_FEE_COEF = 0.07`. **Owner verification required** against `https://kalshi.com/docs/kalshi-fee-schedule.pdf` (HTTP 429 on 2026-10-13, not retried); help page `https://help.kalshi.com/trading/fees` (dated 2026-04-19) points to it; the formula is quoted by `https://sailgp.com/prediction-markets/kalshi/fees` and `https://pm.wiki/ru/learn/prediction-market-arbitrage-after-fees` (read 2026-10-13). |
| Task 1 (no stop, flagged) | Removes three functions (not a file) from `sports/nfl/props/data_sources.R`: `load_defense_rankings`, `scale_defense_rank`, `get_default_defense_rankings`. The roadmap lists "the duplicate function if it means removing a file"; no file is removed, so this is flagged here rather than a STOP. The controller tells the owner before dispatching Task 1. |
| Task 7, Step 1 | Deleting `load_prop_odds()` (the keyed Odds API client), `ODDS_API_KEY`, and changing the default `PROP_ODDS_SOURCE_ORDER` from `c("odds_api","csv","model")` to `c("csv","model")`. Evidence: Task 6's call-graph output. |
| Merge | The owner merges. No dependency is added; `renv.lock` is untouched. |

## File map

| File | Task | Responsibility |
|---|---|---|
| `R/correlated_props.R` | 1, 3, 4, 5, 7 | defense multipliers; point-in-time plumbing; best-quote pricing columns; `govern_prop_rows`; fallback removal |
| `sports/nfl/props/data_sources.R` | 1 | the duplicate defense functions are deleted |
| `sports/nfl/props/props_config.R` | 5, 7 | vectorized `classify_prop_edge_quality`; fallback source order |
| `R/prop_keys.R` | 2 | `normalize_team_abbr`, `normalize_person_name`, `build_player_xwalk`, `resolve_player_ids` |
| `R/prop_odds_api.R` | 3, 4, 7 | `get_market_prop_quotes`, `get_market_prop_line`, `attach_player_ids`, `prop_kickoff_utc`; keyed client deleted |
| `R/prop_pricing.R` | 4 | `devig_two_way`, Kalshi fee, `quote_sides`, `select_best_quote` |
| `config.R` | 3, 4, 7 | `PROP_QUOTE_MAX_AGE_MIN`, `KALSHI_TAKER_FEE_COEF`; `ODDS_API_KEY` removed; source order |
| `scripts/check_odds_api_callgraph.R` | 6 | references to the keyed Odds API symbols |
| `scripts/audit_verify.R`, `docs/modeling.md` | 7 | follow the deletion |
| `tests/testthat/test-props-defense.R` | 1 | P13 |
| `tests/testthat/test-prop-keys.R` | 2 | P9 |
| `tests/testthat/test-prop-quotes.R` | 3 | P14, M11 |
| `tests/testthat/test-prop-pricing.R` | 4 | P12 worked examples |
| `tests/testthat/test-prop-governance.R` | 5 | P1, P2, P3 |
| `tests/testthat/test-odds-api-callgraph.R` | 6, 7 | P4, P5 |
| `tests/testthat/test-correlated-props.R`, `test-prop-odds-scoresandodds.R`, `test-repo-hygiene.R` | 1, 3, 7 | P13 skip removed; new signature; mock removed |
| `CHANGELOG.md`, `docs/EVIDENCE_LEDGER.md`, `README.md`, `HANDOFF.md` | 8 | close-out |

## P10 is already done

`sports/nfl/props/props_pipeline.R` does not exist. Evidence (run on 2026-10-13 at `210f791`): `ls sports/nfl/props/` lists `data_sources.R passing_yards.R props_config.R receiving_yards.R receptions.R rushing_yards.R touchdowns.R`; `git log --diff-filter=D -- sports/nfl/props/props_pipeline.R` shows `3b942ff Retire dead code and scrapers, untrack run logs, harden .gitignore (A0)`; `tests/testthat/test-repo-hygiene.R:5` lists the path among files that must not exist; a search of `*.R`, `*.md` and `*.yml` outside `reports/`, `docs/` and `CHANGELOG.md` finds no other reference. Nothing to do; `run_matrix` is run in Task 8.

## Golden master

**Prediction: no differences** (Task 8, Step 5 gives the reasons and the check). `final` and the golden-master columns contain no props-derived value: `scripts/golden_master.R` runs `NFLsimulation.R` only (its header says props run from `run_week.R` and are not part of the run), the props block of `run_week.R` consumes `last_simulation_results` after `final` is written, and none of `NFLsimulation.R`, `NFLmarket.R` or `R/utils.R` changes.

---

### Task 1: P13, one `load_defense_rankings()` that applies opponent-defense multipliers (sonnet)

**Why first.** Since dplyr 1.2.0 the `R/correlated_props.R` copy errors on every call (`if_else` with a scalar condition and 32-row branches), is caught, and `apply_defense_adjustments()` silently uses 1.0 for every team. A second copy lives in `sports/nfl/props/data_sources.R` with different columns (`pass_def_mult`, rank-scaled) and a different signature. `scripts/audit_verify.R` sources both in the order `R/correlated_props.R`, then `data_sources.R`, so there the second copy wins and `apply_defense_adjustments()` reads a column (`pass_def_multiplier`) that does not exist. `load_game_players()` also `source()`s `data_sources.R` with `local = TRUE`, so a third source order exists. The fix keeps the `R/` copy (it feeds `apply_defense_adjustments()`), widens it to the union signature `(season, weeks = NULL, pbp = NULL)`, makes the arithmetic a pure function over a play-by-play table (so the test needs no network), and deletes the other copy and its two helpers.

**Files:**
- Modify: `R/correlated_props.R` (the `load_defense_rankings` function and the head of `apply_defense_adjustments`)
- Modify: `sports/nfl/props/data_sources.R` (delete `load_defense_rankings`, `scale_defense_rank`, `get_default_defense_rankings`: 3 functions with their roxygen, no file is removed)
- Modify: `tests/testthat/test-correlated-props.R` (delete the `KNOWN-DEFECT P13` skip call; `tests/skip_allowlist.txt` is NOT edited, its regex stays)
- Create: `tests/testthat/test-props-defense.R`

**Interfaces:**
- Produces: `compute_defense_multipliers(pbp, weeks = NULL)` returns a tibble `team, pass_def_multiplier, rush_def_multiplier, recv_def_multiplier`, or `NULL` when `pbp` is empty.
- Produces: `load_defense_rankings(season, weeks = NULL, pbp = NULL)` (same columns; `NULL` plus a message when no data).
- Produces: `apply_defense_adjustments(players, home_team, away_team, season, weeks = NULL, defense_ranks = NULL)`.

- [ ] **Step 1: Write the failing tests**

<!-- apply: T1.1 create tests/testthat/test-props-defense.R -->
```r
# =============================================================================
# FILE: tests/testthat/test-props-defense.R
# PURPOSE: P13 (opponent-defense multipliers apply) and its duplicate definition.
# No network: the arithmetic is tested on a synthetic 32-team play-by-play table.
# =============================================================================

library(testthat)

suppressMessages(source(file.path(.test_project_root, "config.R"), local = FALSE))
source(file.path(.test_project_root, "sports", "nfl", "props", "props_config.R"), local = FALSE)
source(file.path(.test_project_root, "R", "correlated_props.R"), local = FALSE)

DEF_TEAMS <- c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", "DET",
               "GB", "HOU", "IND", "JAX", "KC", "LA", "LAC", "LV", "MIA", "MIN", "NE", "NO",
               "NYG", "NYJ", "PHI", "PIT", "SEA", "SF", "TB", "TEN", "WAS")

# Team i allows 200 + 10 * i passing yards and 80 + 4 * i rushing yards in week 1.
synthetic_pbp <- function() {
  i <- seq_along(DEF_TEAMS)
  rbind(
    data.frame(game_id = paste0("w1_", i), week = 1L, defteam = DEF_TEAMS, play_type = "pass",
               passing_yards = 200 + 10 * i, rushing_yards = NA_real_, stringsAsFactors = FALSE),
    data.frame(game_id = paste0("w1_", i), week = 1L, defteam = DEF_TEAMS, play_type = "run",
               passing_yards = NA_real_, rushing_yards = 80 + 4 * i, stringsAsFactors = FALSE),
    # a later week in which the first team (ARI) allows a huge number of yards
    data.frame(game_id = "w9_1", week = 9L, defteam = "ARI", play_type = "pass",
               passing_yards = 5000, rushing_yards = NA_real_, stringsAsFactors = FALSE)
  )
}

test_that("compute_defense_multipliers returns 32 distinct, bounded multipliers (P13)", {
  m <- compute_defense_multipliers(synthetic_pbp(), weeks = 1L)
  expect_s3_class(m, "data.frame")
  expect_equal(nrow(m), 32)
  expect_setequal(m$team, DEF_TEAMS)
  expect_true(all(c("team", "pass_def_multiplier", "rush_def_multiplier",
                    "recv_def_multiplier") %in% names(m)))
  expect_false(all(m$pass_def_multiplier == 1))
  expect_gt(length(unique(round(m$pass_def_multiplier, 6))), 10)
  expect_true(all(m$pass_def_multiplier >= 0.80 & m$pass_def_multiplier <= 1.20))
  expect_true(all(m$rush_def_multiplier >= 0.75 & m$rush_def_multiplier <= 1.25))
  expect_equal(m$recv_def_multiplier, m$pass_def_multiplier)
  # the team allowing the most yards has the largest multiplier, the fewest the smallest (ties at the clamp are allowed)
  expect_equal(m$pass_def_multiplier[m$team == "WAS"], max(m$pass_def_multiplier))
  expect_equal(m$pass_def_multiplier[m$team == "ARI"], min(m$pass_def_multiplier))
})

test_that("the weeks argument leaves out games played later (no future leak)", {
  early <- compute_defense_multipliers(synthetic_pbp(), weeks = 1:8)
  all_weeks <- compute_defense_multipliers(synthetic_pbp())
  ari_early <- early$pass_def_multiplier[early$team == "ARI"]
  ari_all <- all_weeks$pass_def_multiplier[all_weeks$team == "ARI"]
  expect_lt(ari_early, ari_all)
  expect_null(compute_defense_multipliers(synthetic_pbp(), weeks = 15L))
  expect_null(compute_defense_multipliers(NULL))
})

test_that("load_defense_rankings takes an injected table and apply_defense_adjustments uses it", {
  ranks <- load_defense_rankings(2024, weeks = 1L, pbp = synthetic_pbp())
  expect_equal(nrow(ranks), 32)

  players <- tibble::tibble(
    player_id = c("p1", "p2"), player_name = c("Home QB", "Away QB"), position = "QB",
    recent_team = c("KC", "SF"),
    avg_passing_yards = c(250, 250), avg_rushing_yards = c(10, 10), avg_receiving_yards = c(0, 0)
  )
  adj <- apply_defense_adjustments(players, home_team = "KC", away_team = "SF", season = 2024,
                                   defense_ranks = ranks)
  sf_mult <- ranks$pass_def_multiplier[ranks$team == "SF"]
  kc_mult <- ranks$pass_def_multiplier[ranks$team == "KC"]
  expect_false(isTRUE(all.equal(sf_mult, kc_mult)))
  # KC's QB faces SF's defense; SF's QB faces KC's defense
  expect_equal(adj$avg_passing_yards, c(250 * sf_mult, 250 * kc_mult))
  expect_true(any(adj$avg_passing_yards != 250))
})

test_that("with no rankings, adjustments are neutral and say so", {
  players <- tibble::tibble(
    player_id = "p1", player_name = "Home QB", position = "QB", recent_team = "KC",
    avg_passing_yards = 250, avg_rushing_yards = 10, avg_receiving_yards = 0
  )
  empty <- tibble::tibble(team = character(), pass_def_multiplier = numeric(),
                          rush_def_multiplier = numeric(), recv_def_multiplier = numeric())
  expect_message(
    adj <- apply_defense_adjustments(players, "KC", "SF", 2024, defense_ranks = empty),
    "NEUTRAL"
  )
  expect_equal(adj$avg_passing_yards, 250)
})

# --- the duplicate definition (audit P13): one definition, so source order cannot matter ---

top_level_functions <- function(path) {
  out <- character()
  for (e in parse(path, keep.source = FALSE)) {
    if (is.call(e) && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
        is.name(e[[2]]) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))) {
      out <- c(out, as.character(e[[2]]))
    }
  }
  out
}

test_that("load_defense_rankings is defined exactly once in R/ and sports/nfl/props/", {
  files <- c(list.files(file.path(.test_project_root, "R"), pattern = "[.]R$", full.names = TRUE),
             list.files(file.path(.test_project_root, "sports", "nfl", "props"),
                        pattern = "[.]R$", full.names = TRUE))
  defs <- unlist(lapply(files, function(f) {
    fn <- top_level_functions(f)
    if (length(fn)) paste0(basename(f), "::", fn)
  }))
  hits <- defs[grepl("::load_defense_rankings$", defs)]
  expect_equal(hits, "correlated_props.R::load_defense_rankings")
})

test_that("no function is defined in both R/ and sports/nfl/props/ (allowlist may only shrink)", {
  r_fns <- unlist(lapply(list.files(file.path(.test_project_root, "R"), pattern = "[.]R$",
                                    full.names = TRUE), top_level_functions))
  p_fns <- unlist(lapply(list.files(file.path(.test_project_root, "sports", "nfl", "props"),
                                    pattern = "[.]R$", full.names = TRUE), top_level_functions))
  known <- c("load_red_zone_efficiency")   # R/red_zone_data.R and data_sources.R; not a P1 item
  expect_equal(setdiff(intersect(r_fns, p_fns), known), character())
  expect_equal(setdiff(known, intersect(r_fns, p_fns)), character())
})

test_that("source order cannot change which load_defense_rankings runs", {
  paths <- c(file.path(.test_project_root, "R", "correlated_props.R"),
             file.path(.test_project_root, "sports", "nfl", "props", "data_sources.R"))
  load_in <- function(order) {
    env <- new.env(parent = globalenv())
    for (p in paths[order]) suppressMessages(sys.source(p, envir = env))
    env$load_defense_rankings
  }
  a <- load_in(1:2)
  b <- load_in(2:1)
  expect_identical(deparse(a), deparse(b))
  expect_equal(names(formals(a)), c("season", "weeks", "pbp"))
  expect_equal(nrow(a(2024, weeks = 1L, pbp = synthetic_pbp())), 32)
  expect_equal(nrow(b(2024, weeks = 1L, pbp = synthetic_pbp())), 32)
})
```

- [ ] **Step 2: Run the new tests and see RED**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_file('tests/testthat/test-props-defense.R')"` from the repo root (after `source` of `tests/testthat/setup.R` is done by `test_file`'s helper loading; if `.test_project_root` is not found, run `Rscript -e "testthat::test_dir('tests/testthat', filter = 'props-defense')"` instead).
Expected: FAIL. The first four tests error with `could not find function "compute_defense_multipliers"`; the duplicate-definition test fails with `actual` listing both `correlated_props.R::load_defense_rankings` and `data_sources.R::load_defense_rankings`; the source-order test fails on the `formals` names (`"season"` only vs `"season", "weeks", "pbp"`) or on `deparse` inequality.

- [ ] **Step 3: Implement**

Replace the `R/` copy (old function removed, pure helper and the widened loader added):

<!-- apply: T1.3 delete-range R/correlated_props.R -->
```r
#' Load defense rankings for a season
```
```r
}
```

<!-- apply: T1.3 replace R/correlated_props.R -->
```r
# DEFENSE AND GAME CONTEXT ADJUSTMENTS
# =============================================================================


```
```r
# DEFENSE AND GAME CONTEXT ADJUSTMENTS
# =============================================================================

#' Defense multipliers from a play-by-play table (pure: no network)
#'
#' League average = 1.0. A defense that allows more yards than average gives the
#' offence facing it a multiplier above 1. The multipliers are built elementwise,
#' one per team (audit P13: the old `if_else(avg > 0, <32 values>, 1)` could not
#' recycle and always errored).
#'
#' @param pbp Play-by-play with defteam, play_type, week, passing_yards, rushing_yards
#' @param weeks Optional weeks to include (the caller passes only weeks played before the game)
#' @return Tibble team, pass_def_multiplier, rush_def_multiplier, recv_def_multiplier; NULL if no rows
#' @keywords internal
compute_defense_multipliers <- function(pbp, weeks = NULL) {
  if (is.null(pbp) || nrow(pbp) == 0) return(NULL)
  if (!is.null(weeks)) pbp <- pbp[pbp$week %in% weeks, , drop = FALSE]
  if (nrow(pbp) == 0) return(NULL)

  defense_stats <- pbp %>%
    dplyr::filter(!is.na(defteam), !is.na(play_type)) %>%
    dplyr::group_by(defteam) %>%
    dplyr::summarize(
      pass_yards_allowed = sum(passing_yards, na.rm = TRUE),
      rush_yards_allowed = sum(rushing_yards, na.rm = TRUE),
      .groups = "drop"
    )
  if (nrow(defense_stats) == 0) return(NULL)

  scale_to_multiplier <- function(allowed, lo, hi) {
    avg <- mean(allowed, na.rm = TRUE)
    if (!is.finite(avg) || avg <= 0) return(rep(1, length(allowed)))
    pmin(pmax(allowed / avg, lo), hi)
  }
  pass_mult <- scale_to_multiplier(defense_stats$pass_yards_allowed, 0.80, 1.20)

  tibble::tibble(
    team = defense_stats$defteam,
    # Higher yards allowed = easier defense = higher multiplier for the opponent
    pass_def_multiplier = pass_mult,
    rush_def_multiplier = scale_to_multiplier(defense_stats$rush_yards_allowed, 0.75, 1.25),
    recv_def_multiplier = pass_mult   # same as pass for receiving
  )
}

#' Load defense rankings for a season (the only definition: audit P13)
#'
#' @param season Season year
#' @param weeks Optional weeks to include (default all: a historical run should pass the
#'   weeks played before its game so later games do not leak in)
#' @param pbp Optional play-by-play table (a test seam; default loads the season)
#' @return Tibble with team defense multipliers; NULL (and a message) when no data
#' @keywords internal
load_defense_rankings <- function(season, weeks = NULL, pbp = NULL) {
  if (is.null(pbp)) {
    pbp <- tryCatch(nflreadr::load_pbp(seasons = season), error = function(e) {
      message(sprintf("  Defense rankings unavailable: %s", e$message))
      NULL
    })
  }
  ranks <- compute_defense_multipliers(pbp, weeks)
  if (is.null(ranks)) message("  Defense rankings unavailable: no play-by-play rows")
  ranks
}

```

<!-- apply: T1.3 replace R/correlated_props.R -->
```r
apply_defense_adjustments <- function(players, home_team, away_team, season) {
  # Load defense rankings (with fallback to neutral)
  defense_ranks <- tryCatch({
    load_defense_rankings(season)
  }, error = function(e) NULL)

  if (is.null(defense_ranks) || nrow(defense_ranks) == 0) {
    # Use neutral defense rankings
    defense_ranks <- tibble::tibble(
```
```r
apply_defense_adjustments <- function(players, home_team, away_team, season,
                                      weeks = NULL, defense_ranks = NULL) {
  if (is.null(defense_ranks)) {
    defense_ranks <- tryCatch({
      load_defense_rankings(season, weeks)
    }, error = function(e) {
      message(sprintf("  Defense rankings failed: %s", e$message))
      NULL
    })
  }

  if (is.null(defense_ranks) || nrow(defense_ranks) == 0) {
    message("  Defense adjustments NEUTRAL: no rankings, every multiplier is 1.0")
    defense_ranks <- tibble::tibble(
```

Delete the duplicate and its helpers from `data_sources.R` (three functions with their roxygen; the file stays):

<!-- apply: T1.3 delete-range sports/nfl/props/data_sources.R -->
```r
#' Load Defense Rankings for Adjustments
```
```r
}
```

<!-- apply: T1.3 delete-range sports/nfl/props/data_sources.R -->
```r
#' Scale Defense Rank to Multiplier
```
```r
}
```

<!-- apply: T1.3 delete-range sports/nfl/props/data_sources.R -->
```r
#' Get Default Defense Rankings
```
```r
}
```

Remove the P13 skip call (the allowlist regex `^KNOWN-DEFECT (M|P|S|U|T|H|D|SEC)[0-9]+:` stays untouched):

<!-- apply: T1.3 replace tests/testthat/test-correlated-props.R -->
```r
test_that("load_defense_rankings returns per-team multipliers", {
  skip("KNOWN-DEFECT P13: load_defense_rankings() always errors (dplyr::if_else with a scalar condition and 32-row branches), so defense adjustments are always neutral")
  skip_if_not(exists("load_defense_rankings"), "load_defense_rankings not loaded")
```
```r
test_that("load_defense_rankings returns per-team multipliers", {
  skip_if_not(exists("load_defense_rankings"), "load_defense_rankings not loaded")
```

- [ ] **Step 4: Run the tests and see GREEN**

Run the same command as Step 2, then `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'correlated-props')"`.
Expected: `test-props-defense.R` all pass (about 30 expectations); `test-correlated-props.R` passes, with the live `load_defense_rankings returns per-team multipliers` test now running when `github.com` is reachable (it asserts 32 rows in 0.80-1.20) and no `KNOWN-DEFECT P13` skip.

- [ ] **Step 5: Commit**

```bash
git add R/correlated_props.R sports/nfl/props/data_sources.R tests/testthat/test-correlated-props.R tests/testthat/test-props-defense.R
git commit -m "fix(props): one load_defense_rankings that applies the multipliers (P13)

The R/ copy built its multipliers with an if_else that could not recycle and
errored on every call, so every adjustment was silently neutral; a second copy in
data_sources.R had other columns and which one ran depended on source order. Keep
one (pure compute_defense_multipliers plus a loader that accepts weeks), delete the
other and its helpers, and remove the KNOWN-DEFECT P13 skip.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: P9, one team normalizer and ID-only player resolution (sonnet)

**Why.** `get_market_prop_line()` normalizes teams with `tolower(gsub("[^a-z]", "", x))` after mapping through `TEAM_ABBR_TO_NAME`. An abbreviation that is not in the map ("KC" is, but "LA" is not; the schedule uses `LA`, the map `LAR`) is lower-cased and stripped of every upper-case letter, so it becomes `""`; any two unmapped teams then compare equal. Players are matched by fuzzy name: first initial plus last name, so "A.St. Brown" (Amon-Ra St. Brown, DET) matches "A.J. Brown" (PHI). This task adds the two pure building blocks; Task 3 uses them.

Measured on 2026-10-13 with `nflreadr` (a script run in the dry run): `nflreadr::load_ff_playerids()` has columns `gsis_id, name, merge_name, position, team, ...` and its `team` values include ffverse spellings that no other table uses: `GBP JAC KCC LAR LVR NEP NOS OAK RAM SDC SFO STL TBB` and the non-teams `FA` and `FA*`. `load_schedules(2024)` and `load_player_stats(2024)` use `GB JAX KC LA LV NE NO SF TB`. The canonical spelling in this repo is the schedule's (`LA` for the Rams).

**Files:**
- Create: `R/prop_keys.R`
- Create: `tests/testthat/test-prop-keys.R`

**Interfaces:**
- Produces: `normalize_team_abbr(x)` returns canonical schedule abbreviations (`"KC"`, `"LA"`, ...); `NA_character_` (never `""`) for blanks, `FA`, and unknown text. Accepts abbreviations in any case, ffverse/legacy aliases and full team names.
- Produces: `normalize_person_name(x)` returns a lower-case ASCII key: periods and apostrophes removed, other punctuation to a space, suffixes `jr sr ii iii iv v` dropped.
- Produces: `build_player_xwalk(ff = nflreadr::load_ff_playerids())` returns tibble `player_id` (gsis), `name`, `team` (canonical), `position`.
- Produces: `resolve_player_ids(names, teams, xwalk)` returns tibble `player_id`, `id_status` in `matched | no_match | ambiguous | bad_team`, same length as `names`. Exact key match on (normalized name, canonical team); no fuzzy step. A missing team allows a name-only match only when it is unique.

- [ ] **Step 1: Write the failing tests**

<!-- apply: T2.1 create tests/testthat/test-prop-keys.R -->
```r
# =============================================================================
# FILE: tests/testthat/test-prop-keys.R
# PURPOSE: P9, team and player keys. No network except the one LIVE test.
# =============================================================================

library(testthat)

source(file.path(.test_project_root, "R", "prop_keys.R"), local = FALSE)

test_that("normalize_team_abbr never turns a team into an empty string (P9: KC -> '')", {
  x <- c("KC", "kc", " KC ", "LAR", "LA", "Los Angeles Rams", "Kansas City Chiefs",
         "KCC", "NEP", "GBP", "SFO", "FA", "FA*", "", NA, "XYZ")
  expect_identical(
    normalize_team_abbr(x),
    c("KC", "KC", "KC", "LA", "LA", "LA", "KC", "KC", "NE", "GB", "SF",
      NA, NA, NA, NA, NA)
  )
  expect_false(any(normalize_team_abbr(c("KC", "LA", "SEA", "BUF")) == ""))
})

test_that("LA and LAR are the same team in a join (P9: 2025_21_LA_SEA lost its time zone)", {
  schedule <- data.frame(game_id = "2025_21_LA_SEA", away_team = "LA", home_team = "SEA")
  odds <- data.frame(event = "x", away_team = "LAR", home_team = "Seattle Seahawks")
  schedule$key <- paste(normalize_team_abbr(schedule$away_team), normalize_team_abbr(schedule$home_team))
  odds$key <- paste(normalize_team_abbr(odds$away_team), normalize_team_abbr(odds$home_team))
  joined <- merge(schedule, odds, by = "key")
  expect_equal(nrow(joined), 1)
  expect_equal(joined$game_id, "2025_21_LA_SEA")
})

test_that("every canonical team survives normalization unchanged", {
  expect_equal(length(CANONICAL_TEAMS), 32)
  expect_identical(normalize_team_abbr(CANONICAL_TEAMS), CANONICAL_TEAMS)
})

test_that("normalize_person_name makes comparable keys", {
  expect_identical(normalize_person_name("A.J. Brown"), "aj brown")
  expect_identical(normalize_person_name("Amon-Ra St. Brown"), "amon ra st brown")
  expect_identical(normalize_person_name("Marvin Harrison Jr."), "marvin harrison")
  expect_identical(normalize_person_name("A.St. Brown"), "ast brown")
  expect_identical(normalize_person_name("D'Andre Swift"), "dandre swift")
  expect_identical(normalize_person_name(c("", NA)), c(NA_character_, NA_character_))
})

xwalk_fixture <- function() {
  tibble::tibble(
    player_id = c("00-AJB", "00-ARSB", "00-JAQB", "00-JALB", "00-MHJ"),
    name = c("A.J. Brown", "Amon-Ra St. Brown", "Josh Allen", "Josh Allen", "Marvin Harrison Jr."),
    team = c("PHI", "DET", "BUF", "JAX", "ARI"),
    position = c("WR", "WR", "QB", "LB", "WR")
  )
}

test_that("A.St. Brown is not A.J. Brown (P9)", {
  r <- suppressMessages(resolve_player_ids(
    names = c("A.J. Brown", "A.St. Brown", "A.J. Brown", "Amon-Ra St. Brown"),
    teams = c("PHI", "DET", "DET", "DET"),
    xwalk = xwalk_fixture()
  ))
  expect_identical(r$player_id, c("00-AJB", NA, NA, "00-ARSB"))
  expect_identical(r$id_status, c("matched", "no_match", "no_match", "matched"))
})

test_that("same name on two teams resolves by team and is ambiguous without one", {
  r <- suppressMessages(resolve_player_ids(
    names = c("Josh Allen", "Josh Allen", "Josh Allen", "Josh Allen"),
    teams = c("BUF", "JAC", "KCC", NA),
    xwalk = xwalk_fixture()
  ))
  expect_identical(r$player_id, c("00-JAQB", "00-JALB", NA, NA))
  expect_identical(r$id_status, c("matched", "matched", "no_match", "ambiguous"))
})

test_that("suffixes, a missing team and an unmappable team", {
  r <- suppressMessages(resolve_player_ids(
    names = c("Marvin Harrison", "Amon-Ra St. Brown", "Amon-Ra St. Brown", NA),
    teams = c("ARI", NA, "Nowhere", "DET"),
    xwalk = xwalk_fixture()
  ))
  expect_identical(r$player_id, c("00-MHJ", "00-ARSB", NA, NA))
  expect_identical(r$id_status, c("matched", "matched", "bad_team", "no_match"))
})

test_that("unresolved players are reported, not hidden", {
  expect_message(
    resolve_player_ids("Nobody Real", "DET", xwalk_fixture()),
    "1 unresolved"
  )
  expect_equal(nrow(resolve_player_ids(character(), character(), xwalk_fixture())), 0)
})

test_that("build_player_xwalk canonicalizes ffverse teams and drops rows with no id or team", {
  ff <- data.frame(
    gsis_id = c("00-1", "00-2", NA, "00-4"),
    name = c("A", "B", "C", "D"),
    team = c("KCC", "FA", "DET", "LAR"),
    position = c("QB", "WR", "WR", "RB"),
    stringsAsFactors = FALSE
  )
  x <- build_player_xwalk(ff)
  expect_identical(x$player_id, c("00-1", "00-4"))
  expect_identical(x$team, c("KC", "LA"))
  expect_true(all(c("player_id", "name", "team", "position") %in% names(x)))
})

test_that("the live ffverse table maps to canonical teams", {
  skip_live("github.com")
  x <- with_live("github.com", build_player_xwalk())
  expect_gt(nrow(x), 1000)
  expect_true(all(x$team %in% CANONICAL_TEAMS))
})
```

- [ ] **Step 2: Run and see RED**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'prop-keys')"`
Expected: FAIL at load: `Error in `file(filename, "r", encoding = encoding)`: cannot open the connection` from the `source()` on line 8 (`R/prop_keys.R` does not exist yet, so the whole file errors).

- [ ] **Step 3: Implement**

<!-- apply: T2.3 create R/prop_keys.R -->
```r
# =============================================================================
# FILE: R/prop_keys.R
# PURPOSE: Keys for joining prop quotes to games and players (audit P9).
#   Teams: one canonical spelling (the nflverse schedule's: LA for the Rams).
#   Players: gsis ids resolved once, exactly, through a crosswalk. No fuzzy matching.
# =============================================================================

# The schedule's spelling (nflreadr::load_schedules): 32 teams
CANONICAL_TEAMS <- c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", "DET",
                     "GB", "HOU", "IND", "JAX", "KC", "LA", "LAC", "LV", "MIA", "MIN", "NE", "NO",
                     "NYG", "NYJ", "PHI", "PIT", "SEA", "SF", "TB", "TEN", "WAS")

# ffverse (load_ff_playerids), legacy and provider spellings -> canonical
TEAM_ALIAS_TO_CANONICAL <- c(
  LAR = "LA", RAM = "LA", STL = "LA", OAK = "LV", LVR = "LV", SD = "LAC", SDC = "LAC",
  WSH = "WAS", JAC = "JAX", ARZ = "ARI", GBP = "GB", KCC = "KC", NEP = "NE", NOS = "NO",
  SFO = "SF", TBB = "TB"
)

TEAM_NAME_TO_CANONICAL <- c(
  "Arizona Cardinals" = "ARI", "Atlanta Falcons" = "ATL", "Baltimore Ravens" = "BAL",
  "Buffalo Bills" = "BUF", "Carolina Panthers" = "CAR", "Chicago Bears" = "CHI",
  "Cincinnati Bengals" = "CIN", "Cleveland Browns" = "CLE", "Dallas Cowboys" = "DAL",
  "Denver Broncos" = "DEN", "Detroit Lions" = "DET", "Green Bay Packers" = "GB",
  "Houston Texans" = "HOU", "Indianapolis Colts" = "IND", "Jacksonville Jaguars" = "JAX",
  "Kansas City Chiefs" = "KC", "Los Angeles Chargers" = "LAC", "Los Angeles Rams" = "LA",
  "Las Vegas Raiders" = "LV", "Miami Dolphins" = "MIA", "Minnesota Vikings" = "MIN",
  "New England Patriots" = "NE", "New Orleans Saints" = "NO", "New York Giants" = "NYG",
  "New York Jets" = "NYJ", "Philadelphia Eagles" = "PHI", "Pittsburgh Steelers" = "PIT",
  "Seattle Seahawks" = "SEA", "San Francisco 49ers" = "SF", "Tampa Bay Buccaneers" = "TB",
  "Tennessee Titans" = "TEN", "Washington Commanders" = "WAS"
)

#' Canonical team abbreviation
#'
#' @param x Character: abbreviation in any case, alias, or full team name
#' @return Character of the same length: canonical abbreviation, or NA for blanks,
#'   free agents ("FA") and anything unknown. Never "".
normalize_team_abbr <- function(x) {
  out <- toupper(trimws(as.character(x)))
  out[!nzchar(out)] <- NA_character_
  by_name <- match(out, toupper(names(TEAM_NAME_TO_CANONICAL)))
  out[!is.na(by_name)] <- unname(TEAM_NAME_TO_CANONICAL)[by_name[!is.na(by_name)]]
  by_alias <- match(out, names(TEAM_ALIAS_TO_CANONICAL))
  out[!is.na(by_alias)] <- unname(TEAM_ALIAS_TO_CANONICAL)[by_alias[!is.na(by_alias)]]
  out[!(out %in% CANONICAL_TEAMS)] <- NA_character_
  out
}

#' Comparable key for a person's name
#'
#' Lower-case ASCII; periods and apostrophes removed; other punctuation becomes a space;
#' a trailing generational suffix (jr, sr, ii, iii, iv, v) is dropped.
normalize_person_name <- function(x) {
  out <- iconv(as.character(x), to = "ASCII//TRANSLIT")
  out <- tolower(out)
  out <- gsub("[.']", "", out)
  out <- gsub("[^a-z ]", " ", out)
  out <- trimws(gsub("[[:space:]]+", " ", out))
  out <- sub(" (jr|sr|ii|iii|iv|v)$", "", out)
  out[is.na(out) | !nzchar(out)] <- NA_character_
  out
}

#' Player crosswalk from the ffverse id table
#'
#' @param ff Table with gsis_id, name, team, position (default: nflreadr::load_ff_playerids())
#' @return Tibble player_id (gsis), name, team (canonical), position
build_player_xwalk <- function(ff = nflreadr::load_ff_playerids()) {
  need <- c("gsis_id", "name", "team", "position")
  if (!all(need %in% names(ff))) {
    stop(sprintf("build_player_xwalk: missing columns: %s", paste(setdiff(need, names(ff)), collapse = ", ")),
         call. = FALSE)
  }
  out <- tibble::tibble(
    player_id = as.character(ff$gsis_id),
    name = as.character(ff$name),
    team = normalize_team_abbr(ff$team),
    position = as.character(ff$position)
  )
  out <- out[!is.na(out$player_id) & !is.na(out$name) & !is.na(out$team), , drop = FALSE]
  unique(out)
}

#' Resolve provider player names to gsis ids, exactly
#'
#' A (normalized name, canonical team) pair must match exactly one player in the crosswalk.
#' With no team given, the name alone must match exactly one player. Anything else stays
#' unresolved (NA id) with a status, and the count is logged.
#'
#' @param names Provider player names
#' @param teams Provider team (abbreviation or name) per name; NA allowed
#' @param xwalk Output of build_player_xwalk()
#' @return Tibble player_id, id_status (matched | no_match | ambiguous | bad_team)
resolve_player_ids <- function(names, teams, xwalk) {
  n <- length(names)
  out <- tibble::tibble(player_id = rep(NA_character_, n), id_status = rep("no_match", n))
  if (n == 0) return(out)
  if (length(teams) != n) stop("resolve_player_ids: names and teams must have the same length", call. = FALSE)

  key_name <- normalize_person_name(names)
  raw_team_present <- !is.na(teams) & nzchar(trimws(as.character(teams)))
  key_team <- normalize_team_abbr(teams)
  xw_name <- normalize_person_name(xwalk$name)
  xw_team <- normalize_team_abbr(xwalk$team)

  pair <- paste(key_name, key_team, raw_team_present, sep = "|")
  for (p in unique(pair[!duplicated(pair)])) {
    i <- which(pair == p)
    first <- i[1]
    if (is.na(key_name[first])) next
    if (raw_team_present[first] && is.na(key_team[first])) {
      out$id_status[i] <- "bad_team"
      next
    }
    hit <- !is.na(xw_name) & xw_name == key_name[first]
    if (!is.na(key_team[first])) hit <- hit & !is.na(xw_team) & xw_team == key_team[first]
    ids <- unique(xwalk$player_id[hit])
    if (length(ids) == 1) {
      out$player_id[i] <- ids
      out$id_status[i] <- "matched"
    } else if (length(ids) > 1) {
      out$id_status[i] <- "ambiguous"
    }
  }

  bad <- out$id_status != "matched"
  if (any(bad)) {
    counts <- table(out$id_status[bad])
    message(sprintf("  Player ids: %d matched, %d unresolved (%s)", sum(!bad), sum(bad),
                    paste(sprintf("%s=%d", names(counts), as.integer(counts)), collapse = ", ")))
  }
  out
}
```

- [ ] **Step 4: Run and see GREEN**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'prop-keys')"`
Expected: all pass; the live test runs when `github.com` is reachable (it downloads the ffverse id table once).

- [ ] **Step 5: Commit**

```bash
git add R/prop_keys.R tests/testthat/test-prop-keys.R
git commit -m "feat(props): one team normalizer and exact player-id resolution (P9)

normalize_team_abbr never returns an empty string and treats LA and LAR as one team;
resolve_player_ids matches (name, team) exactly against the ffverse crosswalk, so
A.St. Brown can no longer resolve to A.J. Brown. Task 3 uses both.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: P14 and P9, point-in-time quotes keyed by game and player id (sonnet; OWNER STOP at Step 1)

**Why.** `get_market_prop_line(player_name, prop_type, ...)` matches a cached line by player name and prop type, so a historical run is priced with whatever is in the cache today (audit P14: 2024 week 16 NE @ BUF was priced with a 2026 week 4 line for the same teams). It also matches names fuzzily (P9). This task makes the quote cache a table with a game key, a capture time and a player id; a quote is used for a game only if it was captured at or before that game's kickoff (and before now) and is fresh; everything else leaves the prop unpriced with a reason that reaches `artifacts/baseline_props.csv`. The M11 rule: no matching quote means NA odds and a pass reason, never a substituted number.

**Cache schema (the contract D1's providers write to).** One row per (player, market, book, capture):

| Column | Type | Note |
|---|---|---|
| `player_id` | chr | gsis id; filled by `attach_player_ids()` at load (Task 2 resolver); NA rows never match |
| `prop_type` | chr | `passing_yards`, `rushing_yards`, `receiving_yards`, `receptions`, `anytime_td` |
| `game_id` | chr | nflverse id, e.g. `2024_16_NE_BUF` |
| `captured_at` | POSIXct (UTC) | when the quote was seen |
| `book` | chr | `draftkings`, `fanduel`, `kalshi`, ... |
| `line`, `line_over`, `line_under`, `over_odds`, `under_odds` | num | American odds; `over_odds` is "Yes" for `anytime_td` |
| `venue` | chr | optional, default `book`; `kalshi` rows are handled in Task 4 |
| `player`, `team` | chr | optional; used only to resolve `player_id` |

A cache without `captured_at` or `game_id` (the legacy `artifacts/prop_odds.csv`, the keyed API rows) is unusable by design: every prop stays unpriced and says why.

**Files:**
- Modify: `config.R` (one new default; OWNER STOP)
- Modify: `R/prop_odds_api.R` (`get_market_prop_line` rewritten; new `prop_kickoff_utc`, `get_market_prop_quotes`, `attach_player_ids`; `load_prop_odds_csv` and `resolve_prop_odds_cache` edits)
- Modify: `R/correlated_props.R` (source `prop_keys.R`; `run_game_props` and `run_correlated_props` pass game id, kickoff, week; an `unpriced_reason` column)
- Modify: `tests/testthat/test-prop-odds-scoresandodds.R` (the preferred-books test uses the new signature)
- Create: `tests/testthat/test-prop-quotes.R`

**Interfaces:**
- Consumes: `normalize_team_abbr`, `resolve_player_ids`, `build_player_xwalk` (Task 2); `apply_defense_adjustments(..., weeks, defense_ranks)` (Task 1).
- Produces: `prop_kickoff_utc(gameday, gametime)` returns POSIXct UTC, NA when either input is missing (no default kickoff time is invented).
- Produces: `get_market_prop_quotes(prop_odds_data, player_id, prop_type, game_id, kickoff, now = Sys.time(), max_age_min = PROP_QUOTE_MAX_AGE_MIN)` returns `list(quotes = <tibble or NULL>, reason = <chr>)`; the quotes are the latest per (venue, book) captured at or before `min(kickoff, now)` and not older than `max_age_min` minutes before that instant.
- Produces: `get_market_prop_line(player_id, prop_type, prop_odds_data, game_id, kickoff, now = Sys.time(), preferred_books = NULL, on_unpriced = NULL)` returns the list it always returned (`player, prop_type, line, line_over, line_under, over_odds, under_odds, book, books, n_books`) plus `captured_at` and `venue`; `NULL` after calling `on_unpriced(reason)` when unpriced. The old `player_name`, `fuzzy_match`, `home_team`, `away_team`, `event_id` arguments are gone.
- Produces: `attach_player_ids(cache, xwalk)`; `resolve_prop_odds_cache(..., xwalk = NULL)`.
- Produces: `run_game_props(..., game_id = NULL, kickoff = NULL, week = NULL, players = NULL, defense_ranks = NULL, now = Sys.time())` (the last three are test seams); result gains `unpriced_reason` (chr, `""` when priced).
- Produces: `run_correlated_props(..., prop_odds_cache = NULL, players = NULL, now = Sys.time())`.

- [ ] **Step 1: OWNER STOP, approve the new `config.R` default**

`config.R` defaults are an owner checkpoint (CLAUDE.md section 4). The controller shows the owner this block and waits for a yes before dispatching the task. It is a policy value, not a measurement: "fresh" means the newest quote is at most 120 minutes before the decision time (a live run: now; a historical run: kickoff), matching the 60-minute stale-close rule D1 uses for closing lines but looser because props are posted days ahead and move less. Nothing reads it before this task.

<!-- apply: T3.1 replace config.R -->
```r
#' @description Quantile used to derive fallback prop lines from simulation
#' @default 0.50 (median)
PROP_FALLBACK_LINE_QUANTILE <- 0.50
```
```r
#' @description Quantile used to derive fallback prop lines from simulation
#' @default 0.50 (median)
PROP_FALLBACK_LINE_QUANTILE <- 0.50

#' @description A prop quote older than this many minutes before the decision time is stale
#'   (a live run decides at now; a historical run at the game's kickoff). The prop then
#'   stays unpriced with a pass reason.
#' @default 120
#' @note Policy value, not measured. Owner-visible default (P1 plan, Task 3).
PROP_QUOTE_MAX_AGE_MIN <- 120
```

- [ ] **Step 2: Write the failing tests**

<!-- apply: T3.2 create tests/testthat/test-prop-quotes.R -->
```r
# =============================================================================
# FILE: tests/testthat/test-prop-quotes.R
# PURPOSE: P14 (a historical run never sees a quote captured after its kickoff),
#          P9 (id-only joins) and the M11 rule (no quote -> unpriced, never a number).
# No network. The cache is a table with a game key and a capture time.
# =============================================================================

library(testthat)

source(file.path(.test_project_root, "R", "prop_keys.R"), local = FALSE)
source(file.path(.test_project_root, "R", "prop_odds_api.R"), local = FALSE)
source(file.path(.test_project_root, "R", "correlated_props.R"), local = FALSE)

utc <- function(x) as.POSIXct(x, tz = "UTC")

# 2024 week 16: NE @ BUF, Sunday 2024-12-22 1:00 PM Eastern = 18:00 UTC
KICK_2024_W16 <- prop_kickoff_utc("2024-12-22", "13:00")
NOW_2026 <- utc("2026-10-13 12:00:00")

mk_quote <- function(captured_at, game_id = "2024_16_NE_BUF", player_id = "00-JA", line = 242.5,
                     over = -110, under = -110, book = "draftkings", prop_type = "passing_yards") {
  tibble::tibble(
    player_id = player_id, prop_type = prop_type, game_id = game_id, captured_at = utc(captured_at),
    book = book, line = line, line_over = line, line_under = line,
    over_odds = over, under_odds = under, venue = "book"
  )
}

# lines for the current slate: NE @ BUF is also a 2026 week 4 game (audit P14)
current_slate <- function() {
  rbind(
    mk_quote("2026-10-01 12:00:00", game_id = "2026_04_NE_BUF", line = 240.5, over = -111, under = -113),
    # a quote labelled with the 2024 game but captured two years after its kickoff
    mk_quote("2026-10-01 12:00:00", game_id = "2024_16_NE_BUF", line = 240.5, over = -111, under = -113)
  )
}

quotes_for <- function(cache, kickoff = KICK_2024_W16, now = NOW_2026, game_id = "2024_16_NE_BUF",
                       player_id = "00-JA", prop_type = "passing_yards") {
  get_market_prop_quotes(cache, player_id, prop_type, game_id, kickoff, now)
}

test_that("prop_kickoff_utc converts US Eastern kickoff to UTC and invents nothing", {
  expect_equal(format(KICK_2024_W16, "%Y-%m-%d %H:%M:%S", tz = "UTC"), "2024-12-22 18:00:00")
  expect_equal(format(prop_kickoff_utc("2024-09-08", "13:00"), "%H:%M", tz = "UTC"), "17:00")  # EDT
  expect_true(is.na(prop_kickoff_utc("2024-12-22", NA)))
  expect_true(is.na(prop_kickoff_utc("2024-12-22", "")))
  expect_true(is.na(prop_kickoff_utc(NA, "13:00")))
})

test_that("a 2024 week 16 run never sees a line captured after its kickoff (P14)", {
  r <- quotes_for(current_slate())
  expect_null(r$quotes)
  expect_identical(r$reason, "No line captured before kickoff")

  logged <- character()
  expect_null(get_market_prop_line("00-JA", "passing_yards", current_slate(),
                                   game_id = "2024_16_NE_BUF", kickoff = KICK_2024_W16, now = NOW_2026,
                                   on_unpriced = function(r) logged <<- c(logged, r)))
  expect_identical(logged, "No line captured before kickoff")

  # with one genuine pre-kickoff quote the 2026 lines are still ignored
  cache <- rbind(current_slate(), mk_quote("2024-12-22 17:10:00", line = 242.5, over = -108, under = -112))
  line <- get_market_prop_line("00-JA", "passing_yards", cache, game_id = "2024_16_NE_BUF",
                               kickoff = KICK_2024_W16, now = NOW_2026)
  expect_equal(line$line, 242.5)
  expect_equal(line$over_odds, -108)
  expect_lte(line$captured_at, KICK_2024_W16)
})

test_that("property: every quote returned was captured at or before the kickoff", {
  set.seed(14)
  n <- 200
  # 150 captures between 10:00 and 22:00 UTC on game day (kickoff 18:00) and 50 captured in 2026
  captured <- c(utc("2024-12-22 10:00:00") + runif(150, 0, 43200), utc("2026-01-01 00:00:00") + runif(50, 0, 1e7))
  cache <- do.call(rbind, lapply(seq_len(n), function(i) {
    mk_quote(format(captured[i], "%Y-%m-%d %H:%M:%S"), book = paste0("book", i))
  }))
  r <- quotes_for(cache, now = NOW_2026)
  expect_true(!is.null(r$quotes))
  expect_true(all(r$quotes$captured_at <= KICK_2024_W16))
  expect_true(nrow(r$quotes) > 0 && nrow(r$quotes) < n)
})

test_that("the kickoff instant is included, one second later is not", {
  expect_equal(nrow(quotes_for(mk_quote("2024-12-22 18:00:00"), kickoff = utc("2024-12-22 18:00:00"))$quotes), 1)
  expect_identical(quotes_for(mk_quote("2024-12-22 18:00:01"), kickoff = utc("2024-12-22 18:00:00"))$reason,
                   "No line captured before kickoff")
})

test_that("a stale quote leaves the prop unpriced, the limit is inclusive", {
  at_limit <- mk_quote("2024-12-22 16:00:00")      # exactly 120 minutes before kickoff
  expect_equal(nrow(quotes_for(at_limit)$quotes), 1)
  stale <- mk_quote("2024-12-22 15:59:59")
  r <- quotes_for(stale)
  expect_null(r$quotes)
  expect_match(r$reason, "^Newest line is stale")
  expect_equal(nrow(quotes_for(stale, now = utc("2024-12-22 16:00:30"))$quotes), 1)   # a live run at 16:00:30: 0.02 min old
})

test_that("a live run decides at now, not at kickoff", {
  cache <- mk_quote("2024-12-22 12:30:00")
  r <- quotes_for(cache, now = utc("2024-12-22 12:40:00"))
  expect_equal(nrow(r$quotes), 1)
  expect_null(quotes_for(cache, now = utc("2024-12-22 12:00:00"))$quotes)   # captured after "now"
})

test_that("the latest capture per book wins", {
  cache <- rbind(mk_quote("2024-12-22 16:30:00", line = 241.5),
                 mk_quote("2024-12-22 17:30:00", line = 242.5),
                 mk_quote("2024-12-22 17:00:00", line = 243.5, book = "fanduel"))
  q <- quotes_for(cache)$quotes
  expect_equal(nrow(q), 2)
  expect_equal(q$line[q$book == "draftkings"], 242.5)
})

test_that("unusable inputs give a reason, never a number (M11)", {
  good <- mk_quote("2024-12-22 17:00:00")
  expect_identical(quotes_for(NULL)$reason, "No prop lines loaded")
  expect_identical(quotes_for(good[0, ])$reason, "No prop lines loaded")
  expect_identical(quotes_for(good, kickoff = as.POSIXct(NA))$reason, "Kickoff unknown")
  expect_identical(quotes_for(good, player_id = NA_character_)$reason, "Player id unresolved")
  expect_identical(quotes_for(good, player_id = "")$reason, "Player id unresolved")
  expect_identical(quotes_for(good, game_id = NA_character_)$reason, "Game id missing")
  expect_identical(quotes_for(good, player_id = "00-OTHER")$reason, "No line for this player and game")
  expect_identical(quotes_for(good, prop_type = "rushing_yards")$reason, "No line for this player and game")
  expect_match(quotes_for(good[, setdiff(names(good), "captured_at")])$reason, "captured_at")
  expect_match(quotes_for(good[, setdiff(names(good), "game_id")])$reason, "game_id")
  legacy <- good
  legacy$captured_at <- format(legacy$captured_at)
  expect_identical(quotes_for(legacy)$reason, "captured_at is not a timestamp")
  na_id <- good
  na_id$player_id <- NA_character_
  expect_identical(quotes_for(na_id)$reason, "No line for this player and game")
})

test_that("preferred books narrow the choice; quotes of one player never leak to another", {
  props <- rbind(
    mk_quote("2024-12-22 17:00:00", line = 230.5, over = -113, under = -111, book = "draftkings"),
    mk_quote("2024-12-22 17:00:00", line = 229.5, over = -110, under = -110, book = "fanduel"),
    mk_quote("2024-12-22 17:00:00", line = 99.5, player_id = "00-OTHER", book = "draftkings")
  )
  dk <- get_market_prop_line("00-JA", "passing_yards", props, game_id = "2024_16_NE_BUF",
                             kickoff = KICK_2024_W16, now = NOW_2026, preferred_books = "draftkings")
  expect_equal(dk$book, "draftkings")
  expect_equal(dk$line, 230.5)
  all_books <- get_market_prop_line("00-JA", "passing_yards", props, game_id = "2024_16_NE_BUF",
                                    kickoff = KICK_2024_W16, now = NOW_2026)
  expect_equal(all_books$n_books, 2)
})

test_that("rows without prices are unpriced with a reason", {
  props <- mk_quote("2024-12-22 17:00:00", over = NA_real_, under = NA_real_)
  logged <- character()
  expect_null(get_market_prop_line("00-JA", "passing_yards", props, game_id = "2024_16_NE_BUF",
                                   kickoff = KICK_2024_W16, now = NOW_2026,
                                   on_unpriced = function(r) logged <<- r))
  expect_identical(logged, "Market odds missing")
})

# --- ids are attached once at load, exactly ---

xwalk_fixture <- function() {
  tibble::tibble(player_id = c("00-JA", "00-DM"), name = c("Josh Allen", "Drake Maye"),
                 team = c("BUF", "NEP"), position = "QB")
}

test_that("attach_player_ids fills missing ids exactly and leaves the rest NA", {
  cache <- tibble::tibble(player = c("Josh Allen", "Drake Maye", "J. Allen", "Josh Allen"),
                          team = c("Buffalo Bills", "NE", "BUF", "NE"), prop_type = "passing_yards")
  out <- suppressMessages(attach_player_ids(cache, xwalk_fixture()))
  expect_identical(out$player_id, c("00-JA", "00-DM", NA, NA))
  keep <- tibble::tibble(player = "Josh Allen", team = "BUF", player_id = "PROVIDER-ID")
  expect_identical(suppressMessages(attach_player_ids(keep, xwalk_fixture()))$player_id, "PROVIDER-ID")
})

test_that("a CSV cache keeps its capture times and gets ids", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  utils::write.csv(data.frame(
    player = "Josh Allen", team = "BUF", prop_type = "passing_yards", line = 242.5,
    over_odds = -108, under_odds = -112, book = "draftkings", game_id = "2024_16_NE_BUF",
    captured_at = "2024-12-22T17:10:00Z", stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  cache <- suppressMessages(resolve_prop_odds_cache(source = "csv", csv_path = tmp, xwalk = xwalk_fixture()))
  expect_s3_class(cache$captured_at, "POSIXct")
  expect_equal(format(cache$captured_at, "%H:%M", tz = "UTC"), "17:10")
  expect_identical(cache$player_id, "00-JA")
  expect_identical(attr(cache, "source"), "csv")
  line <- get_market_prop_line(cache$player_id, "passing_yards", cache, game_id = "2024_16_NE_BUF",
                               kickoff = KICK_2024_W16, now = NOW_2026)
  expect_equal(line$line, 242.5)
})

# --- through run_game_props: the audit's observed case, end to end ---

test_that("run_game_props prices 2024 w16 from a pre-kickoff quote and leaves the rest unpriced (P14, M11)", {
  set.seed(16)
  game_sim <- list(home = rpois(2000, 24), away = rpois(2000, 21))
  players <- tibble::tibble(
    player_id = c("00-JA", "00-DM"), player_name = c("Josh Allen", "Drake Maye"), position = "QB",
    recent_team = c("BUF", "NE"), avg_passing_yards = c(300, 220), avg_rushing_yards = c(40, 20),
    avg_receiving_yards = 0, avg_touchdowns = c(0.5, 0.3), is_projection = FALSE, is_baseline = FALSE
  )
  neutral <- tibble::tibble(team = c("BUF", "NE"), pass_def_multiplier = 1, rush_def_multiplier = 1,
                            recv_def_multiplier = 1)
  run <- function(cache) {
    suppressMessages(run_game_props(
      game_sim, home_team = "BUF", away_team = "NE", season = 2024, prop_types = "passing",
      prop_odds_cache = cache, game_id = "2024_16_NE_BUF", kickoff = KICK_2024_W16, week = 16L,
      players = players, defense_ranks = neutral, now = NOW_2026
    ))
  }

  late_only <- run(current_slate())
  allen <- late_only[late_only$player == "Josh Allen", ]
  expect_equal(nrow(allen), 1)
  expect_identical(allen$unpriced_reason, "No line captured before kickoff")
  expect_identical(allen$odds_source, "missing")
  expect_true(is.na(allen$over_odds) && is.na(allen$under_odds))
  expect_true(is.na(allen$ev_over) && is.na(allen$ev_under))
  expect_identical(allen$recommendation, "PASS")
  expect_false(isTRUE(allen$line == 240.5))     # the 2026 line was not used

  priced <- run(rbind(current_slate(), mk_quote("2024-12-22 17:10:00", line = 242.5, over = -108, under = -112)))
  allen <- priced[priced$player == "Josh Allen", ]
  maye <- priced[priced$player == "Drake Maye", ]
  expect_identical(allen$odds_source, "market")
  expect_equal(allen$line, 242.5)
  expect_equal(allen$over_odds, -108)
  expect_identical(allen$unpriced_reason, "")
  expect_identical(maye$odds_source, "missing")
  expect_identical(maye$unpriced_reason, "No line for this player and game")
  expect_true(is.na(maye$ev_over))
})

test_that("run_game_props with no cache says why every prop is unpriced", {
  set.seed(17)
  players <- tibble::tibble(
    player_id = "00-JA", player_name = "Josh Allen", position = "QB", recent_team = "BUF",
    avg_passing_yards = 300, avg_rushing_yards = 40, avg_receiving_yards = 0, avg_touchdowns = 0.5,
    is_projection = FALSE, is_baseline = FALSE
  )
  neutral <- tibble::tibble(team = c("BUF", "NE"), pass_def_multiplier = 1, rush_def_multiplier = 1,
                            recv_def_multiplier = 1)
  old <- get0("USE_REAL_PROP_ODDS", envir = globalenv(), inherits = FALSE)
  assign("USE_REAL_PROP_ODDS", FALSE, envir = globalenv())
  on.exit(assign("USE_REAL_PROP_ODDS", old, envir = globalenv()), add = TRUE)
  res <- suppressMessages(run_game_props(
    list(home = rpois(500, 24), away = rpois(500, 21)), "BUF", "NE", 2024, prop_types = "passing",
    players = players, defense_ranks = neutral
  ))
  expect_identical(res$unpriced_reason, "No prop lines loaded")
  expect_true(is.na(res$ev_over))
})
```

Update the existing preferred-books test to the new signature (it called the function by name with no game or time):

<!-- apply: T3.2 replace tests/testthat/test-prop-odds-scoresandodds.R -->
```r
  props <- tibble::tibble(
    player = c("Sam Darnold", "Sam Darnold"),
    prop_type = c("passing_yards", "passing_yards"),
    line = c(230.5, 229.5),
    line_over = c(230.5, 229.5),
    line_under = c(230.5, 229.5),
    over_odds = c(-113, -110),
    under_odds = c(-111, -110),
    book = c("draftkings", "fanduel")
  )

  dk_line <- get_market_prop_line("Sam Darnold", "passing_yards", props, preferred_books = "draftkings")
  expect_equal(dk_line$book, "draftkings")
  expect_equal(dk_line$line, 230.5)
```
```r
  props <- tibble::tibble(
    player_id = c("00-SD", "00-SD"),
    prop_type = c("passing_yards", "passing_yards"),
    game_id = "2025_22_SEA_NE",
    captured_at = as.POSIXct("2026-02-08 22:00:00", tz = "UTC"),
    line = c(230.5, 229.5),
    line_over = c(230.5, 229.5),
    line_under = c(230.5, 229.5),
    over_odds = c(-113, -110),
    under_odds = c(-111, -110),
    book = c("draftkings", "fanduel")
  )

  dk_line <- get_market_prop_line("00-SD", "passing_yards", props, game_id = "2025_22_SEA_NE",
                                  kickoff = as.POSIXct("2026-02-08 23:30:00", tz = "UTC"),
                                  now = as.POSIXct("2026-02-09 12:00:00", tz = "UTC"),
                                  preferred_books = "draftkings")
  expect_equal(dk_line$book, "draftkings")
  expect_equal(dk_line$line, 230.5)
```

- [ ] **Step 3: Run and see RED**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'prop-quotes|prop-odds-scoresandodds')"`
Expected: FAIL. `test-prop-quotes.R` errors while loading, at its line 17, with `could not find function "prop_kickoff_utc"` (so none of its tests run); `test-prop-odds-scoresandodds.R` fails `get_market_prop_line honors preferred books` with `unused arguments (game_id = ..., kickoff = ..., now = ...)` because the old function has no such arguments.

- [ ] **Step 4: Implement**

4a. `R/prop_odds_api.R`: replace the old lookup with the point-in-time quote functions.

<!-- apply: T3.4 delete-range R/prop_odds_api.R -->
```r
#' Get consensus prop line for a player (median across books)
```
```r
}
```

<!-- apply: T3.4 replace R/prop_odds_api.R -->
```r
# =============================================================================
# PROP ODDS FALLBACK UTILITIES
```
```r
# =============================================================================
# POINT-IN-TIME PROP QUOTES (audit P14 and P9)
# =============================================================================
# The quote cache has one row per (player, market, book, capture); see the table in the
# P1 plan, Task 3. A quote is used for a game only when it was captured at or before that
# game's kickoff and before now, and only when it is fresh. Players are matched by id,
# never by name. Anything else leaves the prop unpriced with a reason (rule M11).

PROP_CACHE_REQUIRED <- c("player_id", "prop_type", "game_id", "captured_at", "book")

#' Kickoff instant (UTC) from nflverse gameday and gametime (US Eastern)
#'
#' NA when either input is missing or blank: no default kickoff time is invented.
prop_kickoff_utc <- function(gameday, gametime) {
  gameday <- as.character(gameday)
  gametime <- as.character(gametime)
  ok <- !is.na(gameday) & nzchar(gameday) & !is.na(gametime) & nzchar(gametime)
  secs <- rep(NA_real_, length(gameday))
  if (any(ok)) {
    secs[ok] <- as.numeric(as.POSIXct(paste(gameday[ok], gametime[ok]),
                                      format = "%Y-%m-%d %H:%M", tz = "America/New_York"))
  }
  as.POSIXct(secs, origin = "1970-01-01", tz = "UTC")
}

#' Quotes usable for one player's prop in one game at the decision time
#'
#' @param prop_odds_data Quote cache (see PROP_CACHE_REQUIRED)
#' @param player_id gsis id
#' @param prop_type Market, e.g. "passing_yards"
#' @param game_id nflverse game id
#' @param kickoff POSIXct kickoff of that game
#' @param now POSIXct of the run; the decision time is min(kickoff, now)
#' @param max_age_min A quote older than this many minutes at the decision time is stale
#' @return list(quotes = tibble or NULL, reason = chr). quotes holds the latest capture per
#'   (venue, book) captured at or before the decision time; reason is "" when quotes is set.
get_market_prop_quotes <- function(prop_odds_data, player_id, prop_type, game_id, kickoff,
                                   now = Sys.time(),
                                   max_age_min = get0("PROP_QUOTE_MAX_AGE_MIN", ifnotfound = NULL)) {
  if (is.null(max_age_min) || length(max_age_min) != 1 || !is.finite(max_age_min)) {
    stop("get_market_prop_quotes: PROP_QUOTE_MAX_AGE_MIN is not set (config.R)", call. = FALSE)
  }
  none <- function(reason) list(quotes = NULL, reason = reason)

  if (is.null(prop_odds_data) || nrow(prop_odds_data) == 0) return(none("No prop lines loaded"))
  absent <- setdiff(PROP_CACHE_REQUIRED, names(prop_odds_data))
  if (length(absent)) {
    return(none(sprintf("Prop lines lack %s (cannot be placed in time)", paste(absent, collapse = ", "))))
  }
  if (!inherits(prop_odds_data$captured_at, "POSIXct")) return(none("captured_at is not a timestamp"))
  player_id <- as.character(player_id)
  if (length(player_id) != 1 || is.na(player_id) || !nzchar(player_id)) return(none("Player id unresolved"))
  game_id <- as.character(game_id)
  if (length(game_id) != 1 || is.na(game_id) || !nzchar(game_id)) return(none("Game id missing"))
  if (length(kickoff) != 1 || is.na(kickoff)) return(none("Kickoff unknown"))

  q <- prop_odds_data[prop_odds_data$prop_type %in% prop_type &
                        prop_odds_data$game_id %in% game_id &
                        prop_odds_data$player_id %in% player_id, , drop = FALSE]
  if (nrow(q) == 0) return(none("No line for this player and game"))

  asof <- min(kickoff, as.POSIXct(now))
  q <- q[!is.na(q$captured_at) & q$captured_at <= asof, , drop = FALSE]
  if (nrow(q) == 0) return(none("No line captured before kickoff"))

  q$venue <- if ("venue" %in% names(q)) ifelse(is.na(q$venue), "book", q$venue) else "book"
  q <- q[order(q$captured_at, decreasing = TRUE), , drop = FALSE]
  q <- q[!duplicated(paste(q$venue, q$book)), , drop = FALSE]

  age_min <- as.numeric(difftime(asof, q$captured_at, units = "mins"))
  fresh <- age_min <= max_age_min
  if (!any(fresh)) {
    return(none(sprintf("Newest line is stale (%.0f min before the decision time, limit %.0f)",
                        min(age_min), max_age_min)))
  }
  list(quotes = q[fresh, , drop = FALSE], reason = "")
}

#' Best sportsbook quote for a player's prop in a game at the decision time
#'
#' Replaces the name-keyed lookup (audit P14, P9). Returns NULL, after calling
#' `on_unpriced(reason)`, when nothing usable exists.
#'
#' @param player_id gsis id
#' @param prop_type Market, e.g. "passing_yards"
#' @param prop_odds_data Quote cache
#' @param game_id nflverse game id
#' @param kickoff POSIXct kickoff
#' @param now POSIXct of the run
#' @param preferred_books Optional books to prefer (used only if any of them has a quote)
#' @param on_unpriced Optional function(reason) called when the prop stays unpriced
#' @return list(player, prop_type, line, line_over, line_under, over_odds, under_odds, book,
#'   books, n_books, captured_at, venue) or NULL
#' @export
get_market_prop_line <- function(player_id, prop_type, prop_odds_data, game_id, kickoff,
                                 now = Sys.time(), preferred_books = NULL, on_unpriced = NULL) {
  unpriced <- function(reason) {
    if (is.function(on_unpriced)) on_unpriced(reason)
    NULL
  }

  res <- get_market_prop_quotes(prop_odds_data, player_id, prop_type, game_id, kickoff, now)
  if (is.null(res$quotes)) return(unpriced(res$reason))
  matches <- res$quotes

  # Apply preferred book filter if available
  if (!is.null(preferred_books)) {
    preferred_books <- tolower(preferred_books)
    matches$book <- tolower(matches$book)
    preferred_matches <- matches[matches$book %in% preferred_books, , drop = FALSE]
    if (nrow(preferred_matches) > 0) matches <- preferred_matches
  }

  priced <- matches[is.finite(suppressWarnings(as.numeric(matches$over_odds))), , drop = FALSE]
  if (nrow(priced) == 0) return(unpriced("Market odds missing"))
  matches <- priced

  # Choose best book row (min vig for two-way, max price for one-way)
  is_one_way <- all(is.na(matches$under_odds) | !is.finite(matches$under_odds))

  score_row <- function(df) {
    if (nrow(df) == 1) return(df)
    if (is_one_way) {
      dec <- american_to_decimal_odds(df$over_odds)
      df[which.max(dec), , drop = FALSE]
    } else {
      over_p <- american_odds_to_implied_prob(df$over_odds)
      under_p <- american_odds_to_implied_prob(df$under_odds)
      vig <- over_p + under_p
      df[which.min(vig), , drop = FALSE]
    }
  }

  best_row <- score_row(matches)

  as_scalar_num <- function(x) {
    if (is.null(x)) return(NA_real_)
    if (is.list(x)) x <- unlist(x, recursive = TRUE, use.names = FALSE)
    x <- suppressWarnings(as.numeric(x))
    if (!length(x)) return(NA_real_)
    x[1]
  }

  line_over <- if ("line_over" %in% names(best_row)) best_row$line_over else best_row$line
  line_under <- if ("line_under" %in% names(best_row)) best_row$line_under else best_row$line
  line_over <- as_scalar_num(line_over)
  line_under <- as_scalar_num(line_under)

  # Use average line when over/under lines are very close
  line_value <- if (is.finite(line_over) && is.finite(line_under) &&
                    abs(line_over - line_under) <= 0.25) {
    mean(c(line_over, line_under), na.rm = TRUE)
  } else if (is.finite(line_over)) {
    line_over
  } else {
    line_under
  }

  list(
    player = player_id,
    prop_type = prop_type,
    line = as_scalar_num(line_value),
    line_over = line_over,
    line_under = line_under,
    over_odds = as_scalar_num(best_row$over_odds),
    under_odds = as_scalar_num(best_row$under_odds),
    book = best_row$book[1],
    books = unique(matches$book),
    n_books = length(unique(matches$book)),
    captured_at = best_row$captured_at[1],
    venue = best_row$venue[1]
  )
}

#' Fill missing player ids in a quote cache, exactly (Task 2 resolver)
#'
#' Rows that already carry a player_id keep it. Others are resolved from `player` and `team`;
#' what cannot be resolved stays NA and can never match a player (the count is logged).
attach_player_ids <- function(cache, xwalk) {
  if (is.null(cache) || nrow(cache) == 0) return(cache)
  if (!"player_id" %in% names(cache)) cache$player_id <- NA_character_
  cache$player_id <- as.character(cache$player_id)
  need <- is.na(cache$player_id) | !nzchar(cache$player_id)
  if (any(need)) {
    nm <- if ("player" %in% names(cache)) cache$player else rep(NA_character_, nrow(cache))
    tm <- if ("team" %in% names(cache)) cache$team else rep(NA_character_, nrow(cache))
    resolved <- resolve_player_ids(nm[need], tm[need], xwalk)
    cache$player_id[need] <- resolved$player_id
  }
  cache
}

# =============================================================================
# PROP ODDS FALLBACK UTILITIES
```

4b. `load_prop_odds_csv` keeps `captured_at` as a timestamp:

<!-- apply: T3.4 replace R/prop_odds_api.R -->
```r
  if (!"source" %in% names(raw)) raw$source <- "csv"
  raw
}
```
```r
  if (!"source" %in% names(raw)) raw$source <- "csv"
  if ("captured_at" %in% names(raw) && !inherits(raw$captured_at, "POSIXct")) {
    raw$captured_at <- as.POSIXct(sub("Z$", "", sub("T", " ", as.character(raw$captured_at))), tz = "UTC")
  }
  raw
}
```

4c. `resolve_prop_odds_cache` attaches player ids (a test seam `xwalk`; the live crosswalk is built only when ids are missing):

<!-- apply: T3.4 replace R/prop_odds_api.R -->
```r
resolve_prop_odds_cache <- function(source = NULL,
                                    csv_path = NULL,
                                    api_key = Sys.getenv("ODDS_API_KEY"),
                                    source_order = NULL) {
```
```r
resolve_prop_odds_cache <- function(source = NULL,
                                    csv_path = NULL,
                                    api_key = Sys.getenv("ODDS_API_KEY"),
                                    source_order = NULL,
                                    xwalk = NULL) {
```

<!-- apply: T3.4 replace R/prop_odds_api.R -->
```r
  if (!is.null(cache)) {
    attr(cache, "source") <- cache_source
  }
  cache
}
```
```r
  if (!is.null(cache)) {
    needs_ids <- !"player_id" %in% names(cache) || anyNA(cache$player_id) || any(!nzchar(cache$player_id))
    if (needs_ids) {
      if (is.null(xwalk)) {
        xwalk <- tryCatch(build_player_xwalk(), error = function(e) {
          message(sprintf("  Player id crosswalk unavailable (%s): no quote can be matched to a player", e$message))
          NULL
        })
      }
      cache <- if (is.null(xwalk)) {
        if (!"player_id" %in% names(cache)) cache$player_id <- NA_character_
        cache
      } else {
        attach_player_ids(cache, xwalk)
      }
    }
    attr(cache, "source") <- cache_source
  }
  cache
}
```

4d. `R/correlated_props.R`: load `prop_keys.R` with the other modules.

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
# Source prop odds API if available
local({
```
```r
# Source the team and player key helpers (the quote cache is joined by id, audit P9)
local({
  keys_path <- file.path(getwd(), "R", "prop_keys.R")
  if (file.exists(keys_path)) source(keys_path, local = FALSE)
})

# Source prop odds API if available
local({
```

4e. `run_game_props`: signature, test seams, per-prop reasons, game-keyed lookup.

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
                           prop_types = c("passing", "rushing", "receiving", "receptions", "td"),
                           prop_odds_cache = NULL) {
```
```r
                           prop_types = c("passing", "rushing", "receiving", "receptions", "td"),
                           prop_odds_cache = NULL,
                           game_id = NULL, kickoff = NULL, week = NULL,
                           players = NULL, defense_ranks = NULL, now = Sys.time()) {
```

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
  # Load player data
  players <- load_game_players(home_team, away_team, season)
```
```r
  # Load player data (`players` is a test seam)
  if (is.null(players)) players <- load_game_players(home_team, away_team, season)
```

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
    adjusted <- apply_defense_adjustments(players, home_team, away_team, season)
```
```r
    # only games played before this one count (week 1: none, so the adjustment is neutral and says so)
    adjusted <- apply_defense_adjustments(
      players, home_team, away_team, season,
      weeks = if (!is.null(week)) seq_len(week - 1L) else NULL,
      defense_ranks = defense_ranks
    )
```

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
  get_market_line_for_books <- function(player_name, prop_type, books = NULL) {
    if (is.null(prop_odds_cache) || !exists("get_market_prop_line", mode = "function")) return(NULL)
    get_market_prop_line(
      player_name,
      prop_type,
      prop_odds_cache,
      home_team = home_team,
      away_team = away_team,
      preferred_books = books
    )
  }
```
```r
  # Why a prop has no market price, by "player|market" (audit P14, rule M11)
  unpriced_log <- list()

  get_market_line_for_books <- function(player_name, prop_type, books = NULL) {
    note <- function(reason) unpriced_log[[paste(player_name, prop_type, sep = "|")]] <<- reason
    if (is.null(prop_odds_cache)) {
      note("No prop lines loaded")
      return(NULL)
    }
    ids <- unique(players$player_id[players$player_name == player_name])
    if (length(ids) != 1) {
      note("Player id unresolved")
      return(NULL)
    }
    get_market_prop_line(
      ids,
      prop_type,
      prop_odds_cache,
      game_id = game_id,
      kickoff = kickoff,
      now = now,
      preferred_books = books,
      on_unpriced = note
    )
  }
```

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
  if (length(results_list) > 0) {
    dplyr::bind_rows(results_list)
  } else {
    tibble::tibble()
  }
}
```
```r
  if (length(results_list) > 0) {
    res <- dplyr::bind_rows(results_list)
    reason <- vapply(paste(res$player, res$prop_type, sep = "|"), function(k) {
      if (is.null(unpriced_log[[k]])) "" else unpriced_log[[k]]
    }, character(1), USE.NAMES = FALSE)
    reason[res$odds_source == "market"] <- ""
    reason[res$odds_source != "market" & !nzchar(reason)] <- "Market odds missing"
    res$unpriced_reason <- reason
    res
  } else {
    tibble::tibble()
  }
}
```

4f. `run_correlated_props`: carry the game's date, time and week; accept an injected cache and players.

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
run_correlated_props <- function(game_sim_results, schedule_data = NULL,
                                  prop_types = c("passing", "rushing", "receiving", "receptions", "td"),
                                  season = NULL) {
```
```r
run_correlated_props <- function(game_sim_results, schedule_data = NULL,
                                  prop_types = c("passing", "rushing", "receiving", "receptions", "td"),
                                  season = NULL, prop_odds_cache = NULL, players = NULL,
                                  now = Sys.time()) {
```

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
        away_team = dplyr::any_of(c("away_team", "awayTeam"))
      ) %>%
      dplyr::distinct()
```
```r
        away_team = dplyr::any_of(c("away_team", "awayTeam")),
        week = dplyr::any_of("week"),
        gameday = dplyr::any_of("gameday"),
        gametime = dplyr::any_of("gametime")
      ) %>%
      dplyr::distinct()
```

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
  # Load prop odds once (if enabled)
  prop_odds_cache <- NULL
  use_prop_odds <- TRUE
  if (exists("USE_REAL_PROP_ODDS") && !isTRUE(USE_REAL_PROP_ODDS)) {
    use_prop_odds <- FALSE
  }
  if (use_prop_odds) {
```
```r
  # Load prop odds once (if enabled and not supplied)
  use_prop_odds <- is.null(prop_odds_cache)
  if (exists("USE_REAL_PROP_ODDS") && !isTRUE(USE_REAL_PROP_ODDS)) {
    use_prop_odds <- FALSE
  }
  if (use_prop_odds) {
```

<!-- apply: T3.4 replace R/correlated_props.R -->
```r
    game_props <- tryCatch({
      run_game_props(
        game_sim = game_sim,
        home_team = game$home_team,
        away_team = game$away_team,
        season = season,
        prop_types = prop_types,
        prop_odds_cache = prop_odds_cache
      )
```
```r
    game_week <- if ("week" %in% names(game)) game$week else if (!is.null(game_sim$week)) game_sim$week else NA
    game_props <- tryCatch({
      run_game_props(
        game_sim = game_sim,
        home_team = game$home_team,
        away_team = game$away_team,
        season = season,
        prop_types = prop_types,
        prop_odds_cache = prop_odds_cache,
        game_id = game$game_id,
        kickoff = prop_kickoff_utc(
          if ("gameday" %in% names(game)) game$gameday else NA,
          if ("gametime" %in% names(game)) game$gametime else NA
        ),
        week = if (is.na(game_week)) NULL else as.integer(game_week),
        players = if (is.null(players)) NULL else players[players$recent_team %in% c(game$home_team, game$away_team), , drop = FALSE],
        now = now
      )
```

- [ ] **Step 5: Run and see GREEN**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'prop-quotes|prop-odds|prop-keys|correlated-props|props-defense|player-props')"`
Expected: all pass, no failures.

- [ ] **Step 6: Commit**

```bash
git add config.R R/prop_odds_api.R R/correlated_props.R tests/testthat/test-prop-quotes.R tests/testthat/test-prop-odds-scoresandodds.R
git commit -m "fix(props): prop lines are keyed by game and player id, point in time (P14, P9)

A quote is used for a game only when captured at or before its kickoff (and before
now) and fresh; players join by gsis id, never by name. A prop with no usable quote
stays unpriced with a reason in artifacts/baseline_props.csv (rule M11). New default
PROP_QUOTE_MAX_AGE_MIN (owner-approved).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: P12, devig per venue, EV at the best fresh price including Kalshi's taker fee (sonnet; OWNER STOP at Step 1)

**Why.** Today EV uses one quoted book price (the lowest-vig book, whichever side the model likes) and nothing devigs it. This task adds the pricing arithmetic in one new file and uses it to pick, among the point-in-time quotes of Task 3, the quote and side with the highest model EV after fees.

**Definitions (all pinned by worked-example tests).**
- **Devig per venue.** A sportsbook row with both prices is devigged proportionally: `p_over = q_over / (q_over + q_under)`, `q` the implied probability of each American price. A Kalshi row has no vig to remove; its fair probability is the mid of the best bid and ask, `(yes_bid + yes_ask) / 2`. Each (venue, book) is devigged on its own; the consensus `fair_over` is the mean over the quotes in play. It is reported (column `mkt_fair_over`) and never used as a price.
- **Kalshi price of a side.** Over/Yes is bought at `yes_ask`; Under/No at `1 - yes_bid`. Both are taker prices.
- **Kalshi taker fee per contract** at price `P` (dollars): `KALSHI_TAKER_FEE_COEF * P * (1 - P)`. A contract that pays 1 then has effective decimal odds `1 / (P + fee)`. Kalshi rounds the fee of a whole order up to the next cent; per contract that is under `0.01 / contracts` and is ignored.
- **EV at the best fresh price.** For every fresh quote and each side, `ev = p * (dec - 1) - (1 - p - p_push)` with `dec` the effective decimal odds (Kalshi: net of the fee). The chosen quote is the one holding the largest EV on either side, and that side is the one the model likes. Its effective American prices replace `over_odds` and `under_odds`, so every downstream EV already includes the fee.
- **Kalshi quote rows** use the Task 3 schema with `venue = "kalshi"`, `book = "kalshi"`, `yes_bid` and `yes_ask` (dollars in (0,1)), and `line_over = line_under =` the threshold such that Yes means the stat is above it (for example "250+ yards" is `249.5`). Their `over_odds` and `under_odds` may be NA. D1's Kalshi provider writes this shape.

**Source of the fee formula (owner-visible; read before Step 1).** On 2026-10-13 the primary source, `https://kalshi.com/docs/kalshi-fee-schedule.pdf`, answered HTTP 429; it was not retried or worked around. The help page `https://help.kalshi.com/trading/fees` (dated 2026-04-19) says Kalshi charges "a transaction fee on the expected earnings on the contract", points to that PDF for the math, and says some markets (elections, awards, major sports championships) carry different fees. The formula `round up(0.07 x C x P x (1 - P))` and the sample figures 1.75 cents per contract at 50 cents and 0.63 cents at 10 cents appear only on third-party pages (`https://sailgp.com/prediction-markets/kalshi/fees`; `https://pm.wiki/ru/learn/prediction-market-arbitrage-after-fees`; read 2026-10-13). The tests reproduce those two figures. **The coefficient 0.07 is therefore unverified against the primary source.** The controller confirms it (or corrects it) with the PDF open at Step 1. A different value is one config line and no code.

**Files:**
- Modify: `config.R` (one new default; OWNER STOP)
- Create: `R/prop_pricing.R`
- Modify: `R/prop_odds_api.R` (`get_market_prop_line` gains `sim_values`, `p_yes`)
- Modify: `R/correlated_props.R` (source `prop_pricing.R`; the priced lookup passes the simulation; three audit columns)
- Create: `tests/testthat/test-prop-pricing.R`

**Interfaces:**
- Consumes: `get_market_prop_quotes`, `american_to_decimal_odds`, `american_odds_to_implied_prob` (Task 3 and existing code).
- Produces: `devig_two_way(over_odds, under_odds)` returns `list(p_over, p_under, overround)`, vectorized, NA in gives NA out.
- Produces: `kalshi_fee_per_contract(price, coef)`, `kalshi_effective_decimal(price, coef)` (NA outside (0,1)), `decimal_to_american_exact(dec)` (unrounded; NA when `dec <= 1`).
- Produces: `quote_sides(quotes, coef)` returns tibble `venue, book, captured_at, line_over, line_under, over_dec, under_dec, fair_over`.
- Produces: `select_best_quote(quotes, sim_values = NULL, p_yes = NULL, coef = KALSHI_TAKER_FEE_COEF)`; exactly one of `sim_values` (two-way) or `p_yes` (one-way, Yes only) is given. Returns the `get_market_prop_line` list plus `fair_over`, `ev_over`, `ev_under`, `fee_included`; `NULL` when no quote can be priced.
- Produces: `get_market_prop_line(..., sim_values = NULL, p_yes = NULL)`; when either is given it returns the best-EV quote across books and Kalshi instead of the lowest-vig book.
- Produces: `run_game_props` result columns `mkt_fair_over`, `price_venue`, `quote_captured_at`.

- [ ] **Step 1: OWNER STOP, approve the fee default**

Show the owner the block below together with the source paragraph above, and confirm `0.07` against the PDF before dispatching. The default lives in `config.R`, so it is an owner checkpoint (CLAUDE.md section 4).

<!-- apply: T4.1 replace config.R -->
```r
#' @default 120
#' @note Policy value, not measured. Owner-visible default (P1 plan, Task 3).
PROP_QUOTE_MAX_AGE_MIN <- 120
```
```r
#' @default 120
#' @note Policy value, not measured. Owner-visible default (P1 plan, Task 3).
PROP_QUOTE_MAX_AGE_MIN <- 120

#' @description Kalshi taker fee per contract = KALSHI_TAKER_FEE_COEF * P * (1 - P), P the
#'   contract price in dollars. EV on a Kalshi quote is computed after this fee.
#' @default 0.07
#' @note UNVERIFIED against the primary source: kalshi.com/docs/kalshi-fee-schedule.pdf
#'   answered HTTP 429 on 2026-10-13; 0.07 is from third-party pages that quote the
#'   schedule (P1 plan, Task 4). Some Kalshi markets carry other fees. Owner-visible default.
KALSHI_TAKER_FEE_COEF <- 0.07
```

- [ ] **Step 2: Write the failing tests**

Every expected number in the comments below was also reproduced by running the formulas in R during the dry run (script output quoted in the dry-run section).

<!-- apply: T4.2 create tests/testthat/test-prop-pricing.R -->
```r
# =============================================================================
# FILE: tests/testthat/test-prop-pricing.R
# PURPOSE: P12, devig per venue, the Kalshi taker fee, EV at the best fresh price.
# =============================================================================

library(testthat)

source(file.path(.test_project_root, "R", "prop_keys.R"), local = FALSE)
source(file.path(.test_project_root, "R", "prop_odds_api.R"), local = FALSE)
source(file.path(.test_project_root, "R", "prop_pricing.R"), local = FALSE)
source(file.path(.test_project_root, "R", "correlated_props.R"), local = FALSE)

utc <- function(x) as.POSIXct(x, tz = "UTC")
COEF <- 0.07

test_that("devig_two_way: worked examples", {
  # -110/-110: each side implies 110/210 = 0.5238095, the overround is 1.047619, fair is 50/50
  d <- devig_two_way(-110, -110)
  expect_equal(d$p_over, 0.5)
  expect_equal(d$p_under, 0.5)
  expect_equal(d$overround, 2 * 110 / 210)
  # -120/+100: q_over = 120/220 = 0.5454545, q_under = 0.5; fair over = 0.5454545 / 1.0454545
  d <- devig_two_way(-120, 100)
  expect_equal(d$p_over, (120 / 220) / (120 / 220 + 0.5))
  expect_equal(d$p_over + d$p_under, 1)
  # vectorized; a missing side gives NA, not a made-up number
  d <- devig_two_way(c(-110, -120, NA), c(-110, 100, -110))
  expect_equal(d$p_over[1:2], c(0.5, (120 / 220) / (120 / 220 + 0.5)))
  expect_true(is.na(d$p_over[3]))
})

test_that("Kalshi taker fee: the schedule's figures at 50 and 10 cents", {
  expect_equal(kalshi_fee_per_contract(0.50, COEF), 0.0175)      # 1.75 cents
  expect_equal(kalshi_fee_per_contract(0.10, COEF), 0.0063)      # 0.63 cents
  expect_equal(kalshi_fee_per_contract(0.90, COEF), 0.0063)      # symmetric in P
  expect_equal(kalshi_fee_per_contract(0.50, 0), 0)
  expect_true(is.na(kalshi_fee_per_contract(1.2, COEF)))         # not a price
  expect_true(is.na(kalshi_fee_per_contract(0, COEF)))
})

test_that("Kalshi effective odds: worked example at 50 cents", {
  # pay 0.50 + 0.0175 = 0.5175 to collect 1: decimal 1 / 0.5175 = 1.932367
  expect_equal(kalshi_effective_decimal(0.50, COEF), 1 / 0.5175)
  expect_equal(kalshi_effective_decimal(0.50, 0), 2)
  # at p = 0.55 the contract is worth 0.55 * 1.932367 - 1 = +0.0628 per dollar after the fee
  expect_equal(round(0.55 * kalshi_effective_decimal(0.50, COEF) - 1, 4), 0.0628)
  expect_equal(decimal_to_american_exact(c(2, 3.5, 1.5, 1, NA)), c(100, 250, -200, NA, NA))
})

mk_book <- function(book, line, over, under, captured = "2024-12-22 17:00:00", prop_type = "passing_yards") {
  tibble::tibble(player_id = "00-JA", prop_type = prop_type, game_id = "2024_16_NE_BUF",
                 captured_at = utc(captured), book = book, line = line, line_over = line, line_under = line,
                 over_odds = over, under_odds = under, venue = "book")
}
mk_kalshi <- function(bid, ask, line = 242.5, captured = "2024-12-22 17:00:00", prop_type = "passing_yards") {
  tibble::tibble(player_id = "00-JA", prop_type = prop_type, game_id = "2024_16_NE_BUF",
                 captured_at = utc(captured), book = "kalshi", line = line, line_over = line, line_under = line,
                 over_odds = NA_real_, under_odds = NA_real_, yes_bid = bid, yes_ask = ask, venue = "kalshi")
}
bind <- function(...) dplyr::bind_rows(...)

# 100 simulated outcomes: 60 above 242.5 and 40 below, no pushes: p_over = 0.6, p_under = 0.4
SIM_OVER <- c(rep(300, 60), rep(200, 40))
# p_over = 0.2, p_under = 0.8
SIM_UNDER <- c(rep(300, 20), rep(200, 80))

test_that("quote_sides: books are devigged on their own, Kalshi uses the mid and the fee", {
  s <- quote_sides(bind(mk_book("draftkings", 242.5, -110, -110), mk_kalshi(0.50, 0.52)), COEF)
  expect_equal(s$fair_over, c(0.5, 0.51))                            # book: devig; Kalshi: (0.50 + 0.52) / 2
  expect_equal(s$over_dec[1], 1 + 100 / 110)
  expect_equal(s$over_dec[2], 1 / (0.52 + 0.07 * 0.52 * 0.48))       # Yes is bought at the ask
  expect_equal(s$under_dec[2], 1 / (0.50 + 0.07 * 0.50 * 0.50))      # No is bought at 1 - bid = 0.50
  bad <- quote_sides(bind(mk_kalshi(0.60, 0.50), mk_kalshi(NA, 0.5), mk_kalshi(0.5, 1)), COEF)
  expect_true(all(is.na(bad$over_dec)) && all(is.na(bad$under_dec)) && all(is.na(bad$fair_over)))
})

test_that("EV is taken at the best price for the side the model likes, after the Kalshi fee", {
  # book: over -130 (dec 1.769231), under +110; Kalshi: bid 0.50, ask 0.52; model p_over = 0.6
  #   book over EV   = 0.6 * 0.769231 - 0.4                           = 0.061538
  #   Kalshi over    = 0.6 / (0.52 + 0.07 * 0.52 * 0.48) - 1          = 0.116337 (fee 0.017472)
  cache <- bind(mk_book("draftkings", 242.5, -130, 110), mk_kalshi(0.50, 0.52))
  best <- select_best_quote(cache, sim_values = SIM_OVER, coef = COEF)
  expect_equal(best$venue, "kalshi")
  expect_true(best$fee_included)
  expect_equal(best$ev_over, 0.6 / (0.52 + 0.07 * 0.52 * 0.48) - 1)
  expect_equal(round(best$ev_over, 6), 0.116337)
  expect_equal(best$over_odds, -100 / (1 / (0.52 + 0.07 * 0.52 * 0.48) - 1))   # effective American (-116.2), unrounded
  # with no fee Kalshi is better still: 0.6 / 0.52 - 1
  free <- select_best_quote(cache, sim_values = SIM_OVER, coef = 0)
  expect_equal(free$ev_over, 0.6 / 0.52 - 1)
  expect_gt(free$ev_over, best$ev_over)
  # a large enough fee hands the quote back to the book: Kalshi EV falls to -0.032008 at coef 0.4
  costly <- select_best_quote(cache, sim_values = SIM_OVER, coef = 0.4)
  expect_equal(costly$venue, "book")
  expect_equal(round(costly$ev_over, 6), 0.061538)
})

test_that("the side the model likes can be the Under, bought as No at 1 - bid", {
  # model p_under = 0.8. Book: over +300, under -400 (dec 1.25): under EV = 0.8 * 0.25 - 0.2 = 0.
  # Kalshi bid 0.30, ask 0.32: No costs 0.70 (+ fee 0.0147): EV = 0.8 / 0.7147 - 1 = 0.119351
  cache <- bind(mk_book("draftkings", 242.5, 300, -400), mk_kalshi(0.30, 0.32))
  best <- select_best_quote(cache, sim_values = SIM_UNDER, coef = COEF)
  expect_equal(best$venue, "kalshi")
  expect_gt(best$ev_under, best$ev_over)
  expect_equal(best$ev_under, 0.8 / (0.70 + 0.07 * 0.70 * 0.30) - 1)
  expect_equal(round(best$ev_under, 6), 0.119351)
  # against a fair book under (-110) the book is the better price: 0.8 * 0.909091 - 0.2 = 0.527273
  cache2 <- bind(mk_book("draftkings", 242.5, -110, -110), mk_kalshi(0.30, 0.32))
  best2 <- select_best_quote(cache2, sim_values = SIM_UNDER, coef = COEF)
  expect_equal(best2$venue, "book")
  expect_equal(round(best2$ev_under, 6), 0.527273)
})

test_that("pushes are counted on each quote's own line", {
  sim <- c(rep(250, 10), rep(300, 50), rep(200, 40))      # 10 exactly on the line 250
  s <- select_best_quote(mk_book("draftkings", 250, -110, -110), sim_values = sim, coef = COEF)
  # p_over = 0.5, p_push = 0.1, p_under = 0.4: over EV = 0.5 * 0.909091 - (1 - 0.5 - 0.1) = 0.054545
  expect_equal(round(s$ev_over, 6), 0.054545)
})

test_that("one-way anytime TD: Yes only, fee included", {
  # model p = 0.30. Book Yes +250 (dec 3.5): EV 0.05. Kalshi ask 0.27 (+ fee 0.013797): EV 0.057094
  cache <- bind(mk_book("draftkings", NA_real_, 250, NA_real_, prop_type = "anytime_td"),
                mk_kalshi(0.25, 0.27, line = NA_real_, prop_type = "anytime_td"))
  best <- select_best_quote(cache, p_yes = 0.30, coef = COEF)
  expect_equal(best$venue, "kalshi")
  expect_equal(round(best$ev_over, 6), 0.057094)
  expect_true(is.na(best$ev_under))
  book_only <- select_best_quote(cache[1, ], p_yes = 0.30, coef = COEF)
  expect_equal(round(book_only$ev_over, 6), 0.05)
})

test_that("nothing priceable gives NULL, never a number (M11)", {
  expect_null(select_best_quote(mk_book("draftkings", 242.5, NA_real_, NA_real_), sim_values = SIM_OVER, coef = COEF))
  expect_null(select_best_quote(mk_kalshi(0.6, 0.5), sim_values = SIM_OVER, coef = COEF))
  expect_error(select_best_quote(mk_book("draftkings", 242.5, -110, -110), coef = COEF), "sim_values")
})

test_that("get_market_prop_line with the simulation honours freshness and the kickoff", {
  kick <- utc("2024-12-22 18:00:00")
  now <- utc("2026-10-13 12:00:00")
  cache <- bind(mk_book("draftkings", 242.5, -130, 110),
                mk_kalshi(0.50, 0.52, captured = "2024-12-22 17:00:00"),
                mk_kalshi(0.40, 0.42, captured = "2026-10-01 12:00:00"))     # a 2026 Kalshi quote
  logged <- character()
  best <- get_market_prop_line("00-JA", "passing_yards", cache, game_id = "2024_16_NE_BUF", kickoff = kick,
                               now = now, sim_values = SIM_OVER, on_unpriced = function(r) logged <<- r)
  expect_equal(best$venue, "kalshi")
  expect_equal(best$captured_at, utc("2024-12-22 17:00:00"))          # not the 2026 quote
  expect_equal(best$fair_over, mean(c((130 / 230) / (130 / 230 + 100 / 210), 0.51)))
  expect_identical(best$player, "00-JA")
  expect_identical(best$prop_type, "passing_yards")
  stale <- cache[2, ]
  stale$captured_at <- utc("2024-12-22 15:00:00")
  expect_null(get_market_prop_line("00-JA", "passing_yards", stale, game_id = "2024_16_NE_BUF", kickoff = kick,
                                   now = now, sim_values = SIM_OVER, on_unpriced = function(r) logged <<- r))
  expect_match(logged, "^Newest line is stale")
})

test_that("run_game_props reports the venue, the devigged market and the capture time", {
  set.seed(12)
  kick <- utc("2024-12-22 18:00:00")
  players <- tibble::tibble(
    player_id = "00-JA", player_name = "Josh Allen", position = "QB", recent_team = "BUF",
    avg_passing_yards = 300, avg_rushing_yards = 40, avg_receiving_yards = 0, avg_touchdowns = 0.5,
    is_projection = FALSE, is_baseline = FALSE
  )
  neutral <- tibble::tibble(team = c("BUF", "NE"), pass_def_multiplier = 1, rush_def_multiplier = 1,
                            recv_def_multiplier = 1)
  cache <- bind(mk_book("draftkings", 242.5, -130, 110), mk_kalshi(0.50, 0.52))
  res <- suppressMessages(run_game_props(
    list(home = rpois(2000, 24), away = rpois(2000, 21)), "BUF", "NE", 2024, prop_types = "passing",
    prop_odds_cache = cache, game_id = "2024_16_NE_BUF", kickoff = kick, week = 16L,
    players = players, defense_ranks = neutral, now = utc("2026-10-13 12:00:00")
  ))
  expect_equal(nrow(res), 1)
  expect_identical(res$price_venue, "kalshi")
  expect_identical(res$book, "kalshi")
  expect_equal(res$quote_captured_at, utc("2024-12-22 17:00:00"))
  expect_equal(res$mkt_fair_over, mean(c((130 / 230) / (130 / 230 + 100 / 210), 0.51)))
  # EV already includes the fee: recompute it from the row's own probability
  expect_lt(abs(res$ev_over - (res$p_over / (0.52 + 0.07 * 0.52 * 0.48) - 1)), 5e-4)
  expect_identical(res$unpriced_reason, "")
})
```

- [ ] **Step 3: Run and see RED**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'prop-pricing')"`
Expected: FAIL while loading, `cannot open the connection` from the `source()` of `R/prop_pricing.R` (line 10), so no test in the file runs.

- [ ] **Step 4: Implement**

4a. The pricing file:

<!-- apply: T4.4 create R/prop_pricing.R -->
```r
# =============================================================================
# FILE: R/prop_pricing.R
# PURPOSE: Prices a prop at the best fresh quote (audit P12).
#   Devig per venue; Kalshi uses the bid/ask mid and pays a taker fee; EV is taken at the
#   best price for the side the model likes. Pure functions, no network.
# =============================================================================

#' Proportional two-way devig
#'
#' @param over_odds,under_odds American prices of the two sides (vectors; NA allowed)
#' @return list(p_over, p_under, overround); NA where a price is missing
devig_two_way <- function(over_odds, under_odds) {
  q_over <- american_odds_to_implied_prob(over_odds)
  q_under <- american_odds_to_implied_prob(under_odds)
  total <- q_over + q_under
  list(p_over = q_over / total, p_under = q_under / total, overround = total)
}

#' Kalshi taker fee per contract: coef * P * (1 - P), P in dollars, NA outside (0, 1)
kalshi_fee_per_contract <- function(price, coef = get0("KALSHI_TAKER_FEE_COEF", ifnotfound = NULL)) {
  if (is.null(coef) || length(coef) != 1 || !is.finite(coef) || coef < 0) {
    stop("kalshi_fee_per_contract: KALSHI_TAKER_FEE_COEF is not set (config.R)", call. = FALSE)
  }
  price <- suppressWarnings(as.numeric(price))
  out <- rep(NA_real_, length(price))
  ok <- is.finite(price) & price > 0 & price < 1
  out[ok] <- coef * price[ok] * (1 - price[ok])
  out
}

#' Decimal odds of a Kalshi contract that pays 1, after the taker fee: 1 / (P + fee)
kalshi_effective_decimal <- function(price, coef = get0("KALSHI_TAKER_FEE_COEF", ifnotfound = NULL)) {
  1 / (suppressWarnings(as.numeric(price)) + kalshi_fee_per_contract(price, coef))
}

#' Decimal to American odds without rounding; NA when dec <= 1
decimal_to_american_exact <- function(dec) {
  dec <- suppressWarnings(as.numeric(dec))
  out <- rep(NA_real_, length(dec))
  ok <- is.finite(dec) & dec > 1
  big <- ok & dec >= 2
  small <- ok & dec < 2
  out[big] <- (dec[big] - 1) * 100
  out[small] <- -100 / (dec[small] - 1)
  out
}

#' Decimal odds and fair probability of each side of every quote
#'
#' @param quotes Quotes of one player's prop in one game (from get_market_prop_quotes)
#' @param coef Kalshi taker fee coefficient
#' @return Tibble venue, book, captured_at, line_over, line_under, over_dec, under_dec, fair_over.
#'   Sportsbook rows: decimal odds of the quoted prices, fair_over by proportional devig (NA for a
#'   one-way market). Kalshi rows: Yes at yes_ask and No at 1 - yes_bid, both after the fee; fair_over
#'   is the bid/ask mid. A Kalshi row with a crossed or out-of-range book has NA everywhere.
quote_sides <- function(quotes, coef = get0("KALSHI_TAKER_FEE_COEF", ifnotfound = NULL)) {
  n <- nrow(quotes)
  num <- function(nm) if (nm %in% names(quotes)) suppressWarnings(as.numeric(quotes[[nm]])) else rep(NA_real_, n)
  venue <- if ("venue" %in% names(quotes)) ifelse(is.na(quotes$venue), "book", quotes$venue) else rep("book", n)
  line <- num("line")
  line_over <- if ("line_over" %in% names(quotes)) num("line_over") else line
  line_under <- if ("line_under" %in% names(quotes)) num("line_under") else line

  over_odds <- num("over_odds")
  under_odds <- num("under_odds")
  over_dec <- american_to_decimal_odds(over_odds)
  under_dec <- american_to_decimal_odds(under_odds)
  fair_over <- devig_two_way(over_odds, under_odds)$p_over

  is_kalshi <- venue == "kalshi"
  bid <- num("yes_bid")
  ask <- num("yes_ask")
  valid <- is_kalshi & is.finite(bid) & is.finite(ask) & bid > 0 & ask < 1 & bid <= ask
  over_dec[is_kalshi] <- NA_real_
  under_dec[is_kalshi] <- NA_real_
  fair_over[is_kalshi] <- NA_real_
  if (any(valid)) {
    over_dec[valid] <- kalshi_effective_decimal(ask[valid], coef)
    under_dec[valid] <- kalshi_effective_decimal(1 - bid[valid], coef)
    fair_over[valid] <- (bid[valid] + ask[valid]) / 2
  }

  tibble::tibble(
    venue = venue,
    book = as.character(quotes$book),
    captured_at = quotes$captured_at,
    line_over = line_over,
    line_under = line_under,
    over_dec = over_dec,
    under_dec = under_dec,
    fair_over = fair_over
  )
}

#' The quote and side with the highest model EV, after fees
#'
#' @param quotes Fresh quotes (from get_market_prop_quotes)
#' @param sim_values Simulated stat values (two-way market: over and under)
#' @param p_yes Model probability of Yes (one-way market, e.g. anytime TD)
#' @param coef Kalshi taker fee coefficient
#' @return list shaped like get_market_prop_line() plus fair_over (mean over quotes), ev_over, ev_under,
#'   fee_included; over_odds and under_odds are the effective American prices (Kalshi: net of fee).
#'   NULL when no quote can be priced.
select_best_quote <- function(quotes, sim_values = NULL, p_yes = NULL,
                              coef = get0("KALSHI_TAKER_FEE_COEF", ifnotfound = NULL)) {
  if (is.null(sim_values) && is.null(p_yes)) {
    stop("select_best_quote: give sim_values (two-way) or p_yes (one-way)", call. = FALSE)
  }
  sides <- quote_sides(quotes, coef)
  n <- nrow(sides)
  ev_over <- rep(NA_real_, n)
  ev_under <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (!is.null(sim_values)) {
      if (is.finite(sides$over_dec[i]) && is.finite(sides$line_over[i])) {
        p <- mean(sim_values > sides$line_over[i])
        p_push <- mean(sim_values == sides$line_over[i])
        ev_over[i] <- p * (sides$over_dec[i] - 1) - (1 - p - p_push)
      }
      if (is.finite(sides$under_dec[i]) && is.finite(sides$line_under[i])) {
        p <- mean(sim_values < sides$line_under[i])
        p_push <- mean(sim_values == sides$line_under[i])
        ev_under[i] <- p * (sides$under_dec[i] - 1) - (1 - p - p_push)
      }
    } else if (is.finite(sides$over_dec[i])) {
      ev_over[i] <- p_yes * (sides$over_dec[i] - 1) - (1 - p_yes)
    }
  }

  best_ev <- pmax(ev_over, ev_under, na.rm = TRUE)
  if (all(is.na(best_ev))) return(NULL)
  i <- which.max(best_ev)
  r <- sides[i, ]

  line_value <- if (is.finite(r$line_over) && is.finite(r$line_under) &&
                    abs(r$line_over - r$line_under) <= 0.25) {
    mean(c(r$line_over, r$line_under))
  } else if (is.finite(r$line_over)) {
    r$line_over
  } else {
    r$line_under
  }

  list(
    player = NA_character_,
    prop_type = NA_character_,
    line = line_value,
    line_over = r$line_over,
    line_under = r$line_under,
    over_odds = decimal_to_american_exact(r$over_dec),
    under_odds = decimal_to_american_exact(r$under_dec),
    book = r$book,
    books = unique(sides$book),
    n_books = length(unique(sides$book)),
    captured_at = r$captured_at,
    venue = r$venue,
    fair_over = if (all(is.na(sides$fair_over))) NA_real_ else mean(sides$fair_over, na.rm = TRUE),
    ev_over = ev_over[i],
    ev_under = ev_under[i],
    fee_included = identical(r$venue, "kalshi")
  )
}
```

4b. `get_market_prop_line` uses it when given the simulation:

<!-- apply: T4.4 replace R/prop_odds_api.R -->
```r
#' @param on_unpriced Optional function(reason) called when the prop stays unpriced
```
```r
#' @param sim_values Simulated stat values: pick the best-EV quote across books and Kalshi
#'   (see select_best_quote) instead of the lowest-vig book
#' @param p_yes Model probability of Yes for a one-way market (anytime TD); same selection
#' @param on_unpriced Optional function(reason) called when the prop stays unpriced
```

<!-- apply: T4.4 replace R/prop_odds_api.R -->
```r
get_market_prop_line <- function(player_id, prop_type, prop_odds_data, game_id, kickoff,
                                 now = Sys.time(), preferred_books = NULL, on_unpriced = NULL) {
```
```r
get_market_prop_line <- function(player_id, prop_type, prop_odds_data, game_id, kickoff,
                                 now = Sys.time(), preferred_books = NULL, on_unpriced = NULL,
                                 sim_values = NULL, p_yes = NULL) {
```

<!-- apply: T4.4 replace R/prop_odds_api.R -->
```r
  matches <- res$quotes

  # Apply preferred book filter if available
```
```r
  matches <- res$quotes

  # With the model's distribution: EV at the best fresh price for the side the model likes (P12)
  if (!is.null(sim_values) || !is.null(p_yes)) {
    best <- select_best_quote(matches, sim_values = sim_values, p_yes = p_yes)
    if (is.null(best)) return(unpriced("Market odds missing"))
    best$player <- player_id
    best$prop_type <- prop_type
    return(best)
  }

  # Apply preferred book filter if available
```

4c. `run_game_props` prices at the best quote and records what it used:

<!-- apply: T4.4 replace R/correlated_props.R -->
```r
# Source prop odds API if available
local({
```
```r
# Source the pricing arithmetic (devig, Kalshi fee, best-EV quote; audit P12)
local({
  pricing_path <- file.path(getwd(), "R", "prop_pricing.R")
  if (file.exists(pricing_path)) source(pricing_path, local = FALSE)
})

# Source prop odds API if available
local({
```

<!-- apply: T4.4 replace R/correlated_props.R -->
```r
  unpriced_log <- list()

  get_market_line_for_books <- function(player_name, prop_type, books = NULL) {
    note <- function(reason) unpriced_log[[paste(player_name, prop_type, sep = "|")]] <<- reason
    if (is.null(prop_odds_cache)) {
      note("No prop lines loaded")
      return(NULL)
    }
    ids <- unique(players$player_id[players$player_name == player_name])
    if (length(ids) != 1) {
      note("Player id unresolved")
      return(NULL)
    }
    get_market_prop_line(
      ids,
      prop_type,
      prop_odds_cache,
      game_id = game_id,
      kickoff = kickoff,
      now = now,
      preferred_books = books,
      on_unpriced = note
    )
  }
```
```r
  unpriced_log <- list()
  quote_log <- list()   # what the price came from, by "player|market"

  # `sim_values` or `p_yes` given: the best-EV quote across books and Kalshi, fee included (P12).
  # Neither: the display lookups for one named book.
  get_market_line_for_books <- function(player_name, prop_type, books = NULL,
                                        sim_values = NULL, p_yes = NULL) {
    key <- paste(player_name, prop_type, sep = "|")
    note <- function(reason) unpriced_log[[key]] <<- reason
    if (is.null(prop_odds_cache)) {
      note("No prop lines loaded")
      return(NULL)
    }
    ids <- unique(players$player_id[players$player_name == player_name])
    if (length(ids) != 1) {
      note("Player id unresolved")
      return(NULL)
    }
    found <- get_market_prop_line(
      ids,
      prop_type,
      prop_odds_cache,
      game_id = game_id,
      kickoff = kickoff,
      now = now,
      preferred_books = books,
      on_unpriced = note,
      sim_values = sim_values,
      p_yes = p_yes
    )
    if (!is.null(found) && (!is.null(sim_values) || !is.null(p_yes))) {
      quote_log[[key]] <<- list(venue = found$venue, fair_over = found$fair_over,
                                captured_at = found$captured_at)
    }
    found
  }
```

<!-- apply: T4.4 replace R/correlated_props.R -->
```r
            market_line <- get_market_line_for_books(qb_name, "passing_yards", books = book_priority)
```
```r
            market_line <- get_market_line_for_books(qb_name, "passing_yards", sim_values = sim_values)
```

<!-- apply: T4.4 replace R/correlated_props.R -->
```r
            market_line <- get_market_line_for_books(pl_name, "rushing_yards", books = book_priority)
```
```r
            market_line <- get_market_line_for_books(pl_name, "rushing_yards", sim_values = sim_values)
```

<!-- apply: T4.4 replace R/correlated_props.R -->
```r
            market_line <- get_market_line_for_books(pl_name, "receiving_yards", books = book_priority)
```
```r
            market_line <- get_market_line_for_books(pl_name, "receiving_yards", sim_values = sim_values)
```

<!-- apply: T4.4 replace R/correlated_props.R -->
```r
            market_line <- get_market_line_for_books(pl_name, "receptions", books = book_priority)
```
```r
            market_line <- get_market_line_for_books(pl_name, "receptions", sim_values = sim_values)
```

<!-- apply: T4.4 replace R/correlated_props.R -->
```r
            market_td <- get_market_line_for_books(pl_name, "anytime_td", books = book_priority)
```
```r
            market_td <- get_market_line_for_books(pl_name, "anytime_td", p_yes = p_anytime)
```

<!-- apply: T4.4 replace R/correlated_props.R -->
```r
    res$unpriced_reason <- reason
    res
```
```r
    res$unpriced_reason <- reason
    from_quote <- function(field, empty) {
      vapply(paste(res$player, res$prop_type, sep = "|"), function(k) {
        v <- quote_log[[k]][[field]]
        if (is.null(v) || length(v) != 1 || is.na(v)) empty else v
      }, empty, USE.NAMES = FALSE)
    }
    res$mkt_fair_over <- from_quote("fair_over", NA_real_)
    res$price_venue <- from_quote("venue", NA_character_)
    res$quote_captured_at <- as.POSIXct(from_quote("captured_at", NA_real_), origin = "1970-01-01", tz = "UTC")
    res
```

- [ ] **Step 5: Run and see GREEN**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'prop-pricing|prop-quotes|prop-odds|correlated-props|player-props')"`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add config.R R/prop_pricing.R R/prop_odds_api.R R/correlated_props.R tests/testthat/test-prop-pricing.R
git commit -m "feat(props): EV at the best fresh price after fees; devig per venue (P12)

select_best_quote picks, across sportsbook rows and Kalshi, the quote and side with the
highest model EV; Kalshi pays the taker fee (KALSHI_TAKER_FEE_COEF, owner-approved, not yet
checked against Kalshi's PDF) and is read at bid/ask. Each venue is devigged on its own; the
consensus is reported as mkt_fair_over, never used as a price.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: P1, P2 and P3, one decision per row: side, tier and stake together (sonnet)

**Why.** Three defects share one block in `run_correlated_props()`:
- **P1.** `classify_prop_edge_quality()` is scalar but is called on whole columns inside `case_when`. It takes the maximum over all rows and labels every row with one value (the unit test used `mapply`, so it never saw this).
- **P2.** `recommendation` (OVER/UNDER) is decided by EV alone while the stake comes from a second pass with a minimum stake, so rows show OVER or UNDER with `Final Stake (%)` 0 ("Stake below minimum") and the table highlights them as bets.
- **P3.** For REVIEW and PASS rows the stake inputs default to the over side, so an Under at +16.8% EV gets "Negative EV".

The fix is one vectorized function, `govern_prop_rows()`, that picks the side the model likes (the larger EV among sides that have a market price), takes that side's probability and price, runs `apply_bet_governance()` on those, and derives the tier and the recommendation from the stake. A row is a bet exactly when its stake is above zero. The rule from the roadmap's Review Focus 4 also lives here: a row whose `odds_source` is not `market` has its EV set to NA and cannot be a bet, whatever `PROP_ALLOW_MODEL_ODDS` says; its pass reason is the one Task 3 recorded.

**Files:**
- Modify: `sports/nfl/props/props_config.R` (`classify_prop_edge_quality` vectorized, scalar callers unchanged)
- Modify: `R/correlated_props.R` (new `govern_prop_rows()`; `run_correlated_props()` uses it)
- Create: `tests/testthat/test-prop-governance.R`

**Interfaces:**
- Consumes: `apply_bet_governance(ev, prob, odds, min_stake, kelly_fraction, max_stake, max_edge, is_placeholder_odds)` in `R/utils.R` (vectorized in practice; not edited), `unpriced_reason` and `odds_source` (Tasks 3 and 4).
- Produces: `classify_prop_edge_quality(ev_over, ev_under, recommendation)` returns a character vector the length of its longest input.
- Produces: `govern_prop_rows(ev_over, ev_under, p_over, p_under, over_odds, under_odds, priced = TRUE, unpriced_reason = "", one_sided = FALSE, model_error = FALSE, min_stake = 0.01, kelly_fraction = 0.125, max_stake = 0.02, max_edge = 0.10)` returns a tibble with one row per input row: `side` (OVER, UNDER, YES, NONE), `tier` (bet, review, pass, model_error), `recommendation` (OVER, UNDER, BET, REVIEW, PASS, MODEL ERROR), `edge_quality`, `ev_over`, `ev_under` (NA when unpriced), `raw_kelly_pct`, `capped_stake_pct`, `final_stake_pct`, `pass_reason`. `min_stake` must be positive.
- Produces: `run_correlated_props()` output gains `side` and `tier`; `recommendation`, `edge_quality`, the three stake columns and `Pass Reason` now come from `govern_prop_rows()`.

- [ ] **Step 1: Write the failing tests**

<!-- apply: T5.1 create tests/testthat/test-prop-governance.R -->
```r
# =============================================================================
# FILE: tests/testthat/test-prop-governance.R
# PURPOSE: P1 (distinct tiers per row), P2/P3 (side, tier and stake agree), M11 (no price, no bet).
# =============================================================================

library(testthat)

source(file.path(.test_project_root, "sports", "nfl", "props", "props_config.R"), local = FALSE)
source(file.path(.test_project_root, "R", "correlated_props.R"), local = FALSE)

test_that("classify_prop_edge_quality gives each row its own tier (P1)", {
  tiers <- classify_prop_edge_quality(
    ev_over = c(0.04, 0.07, 0.12, -0.20),
    ev_under = c(0.01, 0.02, -0.01, 0.03),
    recommendation = c("OVER", "OVER", "OVER", "UNDER")
  )
  expect_identical(tiers, c("OK", "High", "Review", "OK"))
  expect_length(unique(tiers), 3)
  # scalar calls still work
  expect_identical(classify_prop_edge_quality(0.04, 0.01, "OVER"), "OK")
  expect_identical(classify_prop_edge_quality(NA_real_, NA_real_, "MODEL ERROR"), "MODEL ERROR")
  expect_identical(classify_prop_edge_quality(c(NA, 0.03), c(NA, NA), c("OVER", "OVER")), c("MODEL ERROR", "OK"))
  expect_length(classify_prop_edge_quality(numeric(), numeric(), character()), 0)
})

gov <- function(...) {
  args <- list(...)
  defaults <- list(ev_over = 0, ev_under = 0, p_over = 0.5, p_under = 0.5, over_odds = -110, under_odds = -110)
  do.call(govern_prop_rows, utils::modifyList(defaults, args))
}

test_that("an Under the model likes is governed on the Under side (P3)", {
  # Under: p 0.5683 at -110 is +8.5% EV, Kelly 0.0935, 1/8 Kelly = 0.0117 (above the 1% minimum)
  g <- gov(ev_over = -0.176, ev_under = 0.085, p_over = 0.4317, p_under = 0.5683)
  expect_identical(g$side, "UNDER")
  expect_identical(g$tier, "bet")
  expect_identical(g$recommendation, "UNDER")
  expect_identical(g$pass_reason, "")
  expect_gt(g$final_stake_pct, 0.01)
  expect_equal(g$final_stake_pct, g$capped_stake_pct)
  expect_identical(g$edge_quality, "High")
})

test_that("a positive-EV row below the minimum stake is a pass, never an OVER with stake 0 (P2)", {
  g <- gov(ev_over = 0.04, ev_under = -0.1, p_over = 0.5445, p_under = 0.4555)
  expect_identical(g$tier, "pass")
  expect_identical(g$recommendation, "PASS")
  expect_identical(g$pass_reason, "Stake below minimum")
  expect_equal(g$final_stake_pct, 0)
  expect_identical(g$edge_quality, "Pass")
})

test_that("an edge above the believable maximum is a review with no stake", {
  g <- gov(ev_over = 0.168, ev_under = -0.2, p_over = 0.61, p_under = 0.39)
  expect_identical(g$tier, "review")
  expect_identical(g$recommendation, "REVIEW")
  expect_match(g$pass_reason, "^Edge too large")
  expect_equal(g$final_stake_pct, 0)
})

test_that("one-sided markets (anytime TD) bet the Yes side", {
  # +250 at p 0.30 is +5% EV but Kelly 0.02 gives 1/8 Kelly = 0.0025, below the 1% minimum: a pass
  g <- gov(ev_over = 0.05, ev_under = NA_real_, p_over = 0.30, p_under = 0.70, over_odds = 250,
           under_odds = NA_real_, one_sided = TRUE)
  expect_identical(g$side, "YES")
  expect_identical(g$tier, "pass")
  expect_identical(g$pass_reason, "Stake below minimum")
  # -110 at p 0.5683 is +8.5% EV, Kelly 0.0935, stake 0.0117: a bet, labelled BET
  g2 <- gov(ev_over = 0.085, ev_under = 0.5, p_over = 0.5683, p_under = 0.4317, over_odds = -110,
            under_odds = -110, one_sided = TRUE)
  expect_identical(g2$side, "YES")        # the Under is never taken, whatever its EV
  expect_identical(g2$tier, "bet")
  expect_identical(g2$recommendation, "BET")
  expect_gt(g2$final_stake_pct, 0.01)
})

test_that("a prop without a market price is unpriced, with its reason, and cannot be a bet (M11)", {
  g <- gov(ev_over = c(0.09, 0.09), ev_under = c(0.2, 0.2), over_odds = c(-110, NA), under_odds = c(-110, NA),
           priced = c(FALSE, FALSE), unpriced_reason = c("No line captured before kickoff", ""))
  expect_true(all(is.na(g$ev_over)) && all(is.na(g$ev_under)))
  expect_identical(g$tier, c("pass", "pass"))
  expect_identical(g$recommendation, c("PASS", "PASS"))
  expect_identical(g$side, c("NONE", "NONE"))
  expect_equal(g$final_stake_pct, c(0, 0))
  expect_identical(g$pass_reason, c("No line captured before kickoff", "Market odds missing/placeholder"))
})

test_that("a model error never stakes", {
  g <- gov(ev_over = 0.085, ev_under = -0.1, p_over = 0.5683, p_under = 0.4317, model_error = TRUE)
  expect_identical(g$tier, "model_error")
  expect_identical(g$recommendation, "MODEL ERROR")
  expect_equal(g$final_stake_pct, 0)
})

test_that("zero rows and a non-positive minimum stake", {
  g <- govern_prop_rows(numeric(), numeric(), numeric(), numeric(), numeric(), numeric())
  expect_equal(nrow(g), 0)
  expect_true(all(c("side", "tier", "recommendation", "final_stake_pct", "pass_reason") %in% names(g)))
  expect_error(gov(min_stake = 0), "min_stake")
})

test_that("over 10,000 random rows: stake > 0 if and only if tier is bet (P2, P3)", {
  set.seed(2026)
  n <- 10000
  p_over <- runif(n, 0.05, 0.95)
  p_under <- pmin(pmax(1 - p_over - runif(n, 0, 0.03), 0), 1)
  odds_pool <- c(-250, -180, -150, -130, -120, -110, -105, 100, 110, 130, 180, 250, 400, NA)
  over_odds <- sample(odds_pool, n, replace = TRUE)
  under_odds <- sample(odds_pool, n, replace = TRUE)
  dec <- function(o) ifelse(is.na(o), NA_real_, ifelse(o > 0, 1 + o / 100, 1 + 100 / abs(o)))
  ev_over <- p_over * dec(over_odds) - 1
  ev_under <- p_under * dec(under_odds) - 1
  priced <- runif(n) > 0.15
  one_sided <- runif(n) > 0.8
  model_error <- runif(n) > 0.97

  g <- govern_prop_rows(ev_over, ev_under, p_over, p_under, over_odds, under_odds, priced = priced,
                        unpriced_reason = ifelse(priced, "", "No line for this player and game"),
                        one_sided = one_sided, model_error = model_error)

  expect_equal(nrow(g), n)
  expect_identical(g$final_stake_pct > 0, g$tier == "bet")
  expect_true(all(g$final_stake_pct >= 0 & g$final_stake_pct <= 0.02))
  expect_true(all(g$final_stake_pct[g$tier == "bet"] >= 0.01))
  expect_true(all(g$pass_reason[g$tier == "bet"] == ""))
  expect_true(all(nzchar(g$pass_reason[g$tier != "bet"])))
  expect_identical(g$recommendation == "PASS", g$tier == "pass")
  expect_identical(g$recommendation %in% c("OVER", "UNDER", "BET"), g$tier == "bet")
  # unpriced rows: no EV, no bet, no side
  expect_true(all(is.na(g$ev_over[!priced])) && all(is.na(g$ev_under[!priced])))
  expect_true(all(g$tier[!priced & !model_error] == "pass"))
  expect_true(all(g$side[!priced] == "NONE"))
  # the side taken is the larger-EV priced side; a one-sided market never takes the Under
  both <- priced & !one_sided & is.finite(ev_over) & is.finite(ev_under)
  expect_true(all(g$side[both & ev_under > ev_over] == "UNDER"))
  expect_true(all(g$side[both & ev_over >= ev_under] == "OVER"))
  expect_false(any(g$side[one_sided] == "UNDER"))
  # distinct tiers exist (P1)
  expect_gt(length(unique(g$edge_quality)), 3)
})

# --- through run_correlated_props ---

test_that("run_correlated_props applies the governance: tiers agree with stakes, unpriced rows say why", {
  set.seed(5)
  utc <- function(x) as.POSIXct(x, tz = "UTC")
  players <- tibble::tibble(
    player_id = c("00-JA", "00-DM"), player_name = c("Josh Allen", "Drake Maye"), position = "QB",
    recent_team = c("BUF", "NE"), avg_passing_yards = c(300, 220), avg_rushing_yards = c(40, 20),
    avg_receiving_yards = 0, avg_touchdowns = c(0.5, 0.3), is_projection = FALSE, is_baseline = FALSE
  )
  cache <- tibble::tibble(
    player_id = "00-JA", prop_type = "passing_yards", game_id = "2024_16_NE_BUF",
    captured_at = utc("2024-12-22 17:10:00"), book = "draftkings", line = 242.5, line_over = 242.5,
    line_under = 242.5, over_odds = -108, under_odds = -112, venue = "book"
  )
  schedule <- tibble::tibble(game_id = "2024_16_NE_BUF", home_team = "BUF", away_team = "NE", week = 16L,
                             gameday = "2024-12-22", gametime = "13:00")
  sims <- list("2024_16_NE_BUF" = list(game_id = "2024_16_NE_BUF", home_team = "BUF", away_team = "NE",
                                       week = 16L, home = rpois(2000, 24), away = rpois(2000, 21)))
  old_req <- get0("PROP_REQUIRE_MARKET_ODDS", envir = globalenv(), inherits = FALSE)
  assign("PROP_REQUIRE_MARKET_ODDS", FALSE, envir = globalenv())
  on.exit(assign("PROP_REQUIRE_MARKET_ODDS", old_req, envir = globalenv()), add = TRUE)

  res <- suppressMessages(suppressWarnings(run_correlated_props(
    sims, schedule_data = schedule, prop_types = "passing", season = 2024,
    prop_odds_cache = cache, players = players, now = utc("2026-10-13 12:00:00")
  )))
  expect_equal(nrow(res), 2)
  expect_true(all(c("side", "tier", "recommendation", "Final Stake (%)", "Pass Reason", "edge_quality",
                    "unpriced_reason", "price_venue") %in% names(res)))
  expect_identical(res[["Final Stake (%)"]] > 0, res$tier == "bet")
  maye <- res[res$player == "Drake Maye", ]
  expect_identical(maye$tier, "pass")
  expect_identical(maye$`Pass Reason`, "No line for this player and game")
  expect_true(is.na(maye$ev_over))
  allen <- res[res$player == "Josh Allen", ]
  expect_identical(allen$odds_source, "market")
  expect_false(allen$recommendation %in% c("OVER", "UNDER") && allen$`Final Stake (%)` == 0)
})
```

- [ ] **Step 2: Run and see RED**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'prop-governance')"`
Expected: FAIL. The first test fails with `expect_identical(tiers, c("OK", "High", "Review", "OK"))` (the scalar function returns one label, `"Review"`); the others error with `could not find function "govern_prop_rows"`.

- [ ] **Step 3: Implement**

3a. The vectorized classifier (the same bins, applied per row):

<!-- apply: T5.3 replace sports/nfl/props/props_config.R -->
```r
classify_prop_edge_quality <- function(ev_over, ev_under = NA_real_, recommendation = NA_character_) {
  if (identical(recommendation, "MODEL ERROR")) return("MODEL ERROR")

  best_candidates <- c(ev_over, ev_under)
  best_candidates <- best_candidates[is.finite(best_candidates) & best_candidates > 0]
  best_ev <- if (length(best_candidates)) max(best_candidates, na.rm = TRUE) else NA_real_
  if (!is.finite(best_ev)) return("MODEL ERROR")

  if (best_ev <= PROP_EDGE_BIN_OK_MAX) return("OK")
  if (best_ev <= PROP_EDGE_BIN_HIGH_MAX) return("High")
  "Review"
}
```
```r
classify_prop_edge_quality <- function(ev_over, ev_under = NA_real_, recommendation = NA_character_) {
  # Vectorized (audit P1): every row gets its own tier from its own best positive EV
  n <- max(length(ev_over), length(ev_under), length(recommendation))
  if (n == 0) return(character())
  ev_over <- rep_len(suppressWarnings(as.numeric(ev_over)), n)
  ev_under <- rep_len(suppressWarnings(as.numeric(ev_under)), n)
  recommendation <- rep_len(as.character(recommendation), n)

  ev_over[!is.finite(ev_over) | ev_over <= 0] <- NA_real_
  ev_under[!is.finite(ev_under) | ev_under <= 0] <- NA_real_
  best_ev <- pmax(ev_over, ev_under, na.rm = TRUE)

  out <- rep("Review", n)
  out[!is.na(best_ev) & best_ev <= PROP_EDGE_BIN_HIGH_MAX] <- "High"
  out[!is.na(best_ev) & best_ev <= PROP_EDGE_BIN_OK_MAX] <- "OK"
  out[is.na(best_ev)] <- "MODEL ERROR"
  out[!is.na(recommendation) & recommendation == "MODEL ERROR"] <- "MODEL ERROR"
  out
}
```

3b. `govern_prop_rows()`, placed before the main pipeline function:

<!-- apply: T5.3 replace R/correlated_props.R -->
```r
# =============================================================================
# MAIN PIPELINE FUNCTION
# =============================================================================
```
```r
# =============================================================================
# GOVERNANCE: SIDE, TIER AND STAKE TOGETHER (audit P1, P2, P3; rule M11)
# =============================================================================

#' Decide every prop row once: side, tier and stake together
#'
#' The side is the one with the larger EV among sides that have a market price; its probability and
#' price feed apply_bet_governance(). A row is a bet exactly when its final stake is above zero. A row
#' that is not priced from the market (`priced = FALSE`) has no EV, no side and no bet; its pass reason
#' is `unpriced_reason`, or "Market odds missing/placeholder" when none was recorded.
#'
#' @param ev_over,ev_under Model EV per unit staked on each side (NA allowed)
#' @param p_over,p_under Model probability of each side
#' @param over_odds,under_odds American prices of each side (effective prices, net of fees)
#' @param priced TRUE where the prices come from the market
#' @param unpriced_reason Why a row is unpriced ("" otherwise)
#' @param one_sided TRUE for Yes-only markets (anytime TD); the Under is never taken
#' @param model_error TRUE where the row failed its validity checks
#' @param min_stake,kelly_fraction,max_stake,max_edge Passed to apply_bet_governance(); min_stake must be > 0
#' @return Tibble: side, tier, recommendation, edge_quality, ev_over, ev_under, raw_kelly_pct,
#'   capped_stake_pct, final_stake_pct, pass_reason
govern_prop_rows <- function(ev_over, ev_under, p_over, p_under, over_odds, under_odds,
                             priced = TRUE, unpriced_reason = "", one_sided = FALSE,
                             model_error = FALSE,
                             min_stake = 0.01, kelly_fraction = 0.125, max_stake = 0.02, max_edge = 0.10) {
  if (!is.finite(min_stake) || min_stake <= 0) {
    stop("govern_prop_rows: min_stake must be > 0 (a stake above zero is what makes a row a bet)", call. = FALSE)
  }
  n <- length(ev_over)
  num <- function(x) rep_len(suppressWarnings(as.numeric(x)), n)
  lgl <- function(x) {
    x <- rep_len(as.logical(x), n)
    x[is.na(x)] <- FALSE
    x
  }
  ev_o <- num(ev_over)
  ev_u <- num(ev_under)
  p_o <- num(p_over)
  p_u <- num(p_under)
  odds_o <- num(over_odds)
  odds_u <- num(under_odds)
  priced <- lgl(priced)
  one_sided <- lgl(one_sided)
  model_error <- lgl(model_error)
  reason_in <- rep_len(as.character(unpriced_reason), n)
  reason_in[is.na(reason_in)] <- ""

  # M11: no market price, no EV
  ev_o[!priced] <- NA_real_
  ev_u[!priced] <- NA_real_
  ev_u[one_sided] <- NA_real_

  has_o <- is.finite(ev_o) & is.finite(odds_o)
  has_u <- is.finite(ev_u) & is.finite(odds_u)
  take_u <- has_u & (!has_o | ev_u > ev_o)
  take_o <- has_o & !take_u
  side <- ifelse(take_u, "UNDER", ifelse(take_o, ifelse(one_sided, "YES", "OVER"), "NONE"))
  ev <- ifelse(take_u, ev_u, ifelse(take_o, ev_o, NA_real_))
  prob <- ifelse(take_u, p_u, ifelse(take_o, p_o, NA_real_))
  odds <- ifelse(take_u, odds_u, ifelse(take_o, odds_o, NA_real_))

  gov <- apply_bet_governance(
    ev = ev, prob = prob, odds = odds,
    min_stake = min_stake, kelly_fraction = kelly_fraction, max_stake = max_stake, max_edge = max_edge
  )

  pass_reason <- gov$pass_reason
  pass_reason[!priced] <- ifelse(nzchar(reason_in[!priced]), reason_in[!priced],
                                 "Market odds missing/placeholder")
  pass_reason[model_error] <- "Model error"

  final_stake <- ifelse(pass_reason == "", gov$capped_stake_pct, 0)
  tier <- ifelse(model_error, "model_error",
                 ifelse(pass_reason == "", "bet",
                        ifelse(grepl("^Edge too large", pass_reason), "review", "pass")))
  recommendation <- ifelse(tier == "bet", ifelse(side == "YES", "BET", side),
                           ifelse(tier == "review", "REVIEW",
                                  ifelse(tier == "model_error", "MODEL ERROR", "PASS")))
  edge_quality <- ifelse(
    recommendation == "PASS", "Pass",
    ifelse(recommendation == "REVIEW", "Review",
           ifelse(recommendation == "MODEL ERROR", "MODEL ERROR",
                  classify_prop_edge_quality(ev_o, ev_u, recommendation)))
  )

  tibble::tibble(
    side = side,
    tier = tier,
    recommendation = recommendation,
    edge_quality = edge_quality,
    ev_over = ev_o,
    ev_under = ev_u,
    raw_kelly_pct = gov$raw_kelly_pct,
    capped_stake_pct = gov$capped_stake_pct,
    final_stake_pct = final_stake,
    pass_reason = pass_reason
  )
}

# =============================================================================
# MAIN PIPELINE FUNCTION
# =============================================================================
```

3c. `run_correlated_props()` decides every row through it (the block that classified and staked row by row is replaced; 63 lines):

<!-- apply: T5.3 delete-range R/correlated_props.R -->
```r
    # Add edge quality classification
```
```r
      dplyr::select(-.ev_for_quality, -governance_ev, -governance_prob, -governance_odds, -governance)  # Remove helper columns
```

<!-- apply: T5.3 replace R/correlated_props.R -->
```r
    require_market_odds <- isTRUE(if (exists("PROP_REQUIRE_MARKET_ODDS")) PROP_REQUIRE_MARKET_ODDS else FALSE)
```
```r
    # One decision per row: side, tier and stake together (audit P1, P2, P3). A row without a market
    # price keeps NA EV and the reason Task 3 recorded (rule M11). TD props are Yes-only.
    gov <- govern_prop_rows(
      ev_over = results$ev_over, ev_under = results$ev_under,
      p_over = results$p_over, p_under = results$p_under,
      over_odds = results$over_odds, under_odds = results$under_odds,
      priced = results$odds_source == "market",
      unpriced_reason = if ("unpriced_reason" %in% names(results)) results$unpriced_reason else "",
      one_sided = results$prop_type == "anytime_td",
      model_error = results$recommendation == "MODEL ERROR",
      kelly_fraction = get0("KELLY_FRACTION", ifnotfound = 0.125, inherits = TRUE),
      max_stake = get0("MAX_STAKE", ifnotfound = 0.02, inherits = TRUE),
      max_edge = get0("MAX_EDGE", ifnotfound = 0.10, inherits = TRUE)
    )
    results <- results %>%
      dplyr::mutate(
        ev_over = gov$ev_over,
        ev_under = gov$ev_under,
        recommendation = gov$recommendation,
        side = gov$side,
        tier = gov$tier,
        `Raw Kelly (%)` = gov$raw_kelly_pct,
        `Capped Stake (%)` = gov$capped_stake_pct,
        `Final Stake (%)` = gov$final_stake_pct,
        `Pass Reason` = gov$pass_reason,
        edge_quality = gov$edge_quality,
        # Get the relevant EV for classification (ev_over for both yard props and TDs)
        .ev_for_quality = dplyr::coalesce(pmax(ev_over, ev_under, na.rm = TRUE), ev_over),
        # Document why positive EV can still show PASS (2% minimum edge threshold)
        edge_note = dplyr::case_when(
          recommendation == "PASS" & !is.na(.ev_for_quality) & .ev_for_quality > 0 & .ev_for_quality <= PROP_MIN_BET_EDGE ~ "Edge < 2%",
          recommendation == "PASS" & !is.na(.ev_for_quality) & .ev_for_quality > PROP_EDGE_BIN_HIGH_MAX ~ "Blocked (>10%)",
          recommendation == "REVIEW" & !is.na(.ev_for_quality) & .ev_for_quality > PROP_EDGE_BIN_HIGH_MAX ~ "Review (>10%)",
          recommendation == "PASS" & !is.na(.ev_for_quality) & .ev_for_quality <= 0 ~ "Negative EV",
          TRUE ~ ""
        )
      ) %>%
      dplyr::select(-.ev_for_quality)

    require_market_odds <- isTRUE(if (exists("PROP_REQUIRE_MARKET_ODDS")) PROP_REQUIRE_MARKET_ODDS else FALSE)
```

- [ ] **Step 4: Run and see GREEN**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'prop-governance|props-edge-policy|prop-pricing|prop-quotes|correlated-props|player-props|bet-governance')"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add sports/nfl/props/props_config.R R/correlated_props.R tests/testthat/test-prop-governance.R
git commit -m "fix(props): one decision per row, side, tier and stake together (P1, P2, P3)

classify_prop_edge_quality is vectorized, so rows get their own tiers. govern_prop_rows picks
the side the model likes, stakes on that side's probability and price, and makes tier = bet
exactly when the stake is above zero. A row with no market price has no EV and cannot be a bet.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: P4 and P5, a call-graph check for the keyed Odds API path (haiku)

**Why.** Keyless data only is the owner's rule. `load_prop_odds()` is the keyed The Odds API path (audit P4: it requests player markets from `/odds` where props need `/events/{id}/odds`, and iterates a `fromJSON` data frame as a list; audit P5: its anytime-TD "No" price is never attached). Task 7 retires it. Deleting code is an owner checkpoint, so this task adds only the evidence: a script that lists every reference to the path's symbols, and a test that pins the list so it can only shrink. The list below was produced by running the script on the dry-run tree after Task 5.

The P5 ScoresAndOdds half ("touchdowns" over price treated as Yes, unverified) is the S5 scraper, which is off by default (`PROP_ODDS_ALLOW_REMOTE_HTML = FALSE`) and whose rows carry no game id or capture time, so after Task 3 none of its rows can be priced. Its deletion is audit S5's decision, not this plan's.

**Files:**
- Create: `scripts/check_odds_api_callgraph.R`
- Create: `tests/testthat/test-odds-api-callgraph.R`

**Interfaces:**
- Produces: `ODDS_API_SYMBOLS`, `repo_r_files(root = ".")`, `refs_to_symbols(files, symbols = ODDS_API_SYMBOLS, root = ".")` returning `data.frame(file, line, symbol, kind)` with `kind` in `code | string | comment`.

- [ ] **Step 1: Write the failing test**

<!-- apply: T6.1 create tests/testthat/test-odds-api-callgraph.R -->
```r
# =============================================================================
# FILE: tests/testthat/test-odds-api-callgraph.R
# PURPOSE: P4/P5. The keyed Odds API path gets no new caller, and the list below only shrinks.
# =============================================================================

library(testthat)

source(file.path(.test_project_root, "scripts", "check_odds_api_callgraph.R"), local = FALSE)

test_that("refs_to_symbols finds code, strings and comments, and not the file name", {
  root <- withr::local_tempdir()
  writeLines(c(
    "# uses ODDS_API_KEY here",
    "x <- load_prop_odds(1)",
    "y <- Sys.getenv(\"ODDS_API_KEY\")",
    "z <- \"odds_api\"",
    "f <- \"R/prop_odds_api.R\"",
    "# see prop_odds_api.R and load_prop_odds_csv"
  ), file.path(root, "a.R"))
  r <- refs_to_symbols("a.R", root = root)
  expect_setequal(
    paste(r$symbol, r$kind, r$line),
    c("ODDS_API_KEY comment 1", "load_prop_odds code 2", "ODDS_API_KEY string 3", "odds_api string 4")
  )
  expect_equal(nrow(refs_to_symbols(character(), root = root)), 0)
})

# file::symbol pairs that still exist at the end of Task 5; Task 7 empties this list
KNOWN_ODDS_API_REFS <- c(
  "config.R::ODDS_API_KEY",
  "config.R::odds_api",
  "R/correlated_props.R::load_prop_odds",
  "R/prop_odds_api.R::ODDS_API_KEY",
  "R/prop_odds_api.R::load_prop_odds",
  "R/prop_odds_api.R::odds_api",
  "R/prop_odds_api.R::oddsapi",
  "scripts/audit_verify.R::ODDS_API_KEY",
  "scripts/audit_verify.R::load_prop_odds",
  "sports/nfl/props/props_config.R::ODDS_API_KEY",
  "sports/nfl/props/props_config.R::odds_api",
  "tests/testthat/test-repo-hygiene.R::load_prop_odds"
)

test_that("the keyed Odds API path has no new caller, and the allowlist only shrinks", {
  refs <- refs_to_symbols(repo_r_files(PROJECT_ROOT), root = PROJECT_ROOT)
  found <- if (nrow(refs)) unique(paste0(refs$file, "::", refs$symbol)) else character()
  expect_equal(setdiff(found, KNOWN_ODDS_API_REFS), character())   # a new reference: use a keyless source
  expect_equal(setdiff(KNOWN_ODDS_API_REFS, found), character())   # a removed reference: delete its entry
})
```

- [ ] **Step 2: Run and see RED**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'odds-api-callgraph')"`
Expected: FAIL while loading, `cannot open the connection` from the `source()` on line 8 (the script does not exist yet).

- [ ] **Step 3: Implement**

<!-- apply: T6.3 create scripts/check_odds_api_callgraph.R -->
```r
#!/usr/bin/env Rscript
# =============================================================================
# FILE: scripts/check_odds_api_callgraph.R
# PURPOSE: P4/P5, the keyed Odds API path. Lists every reference to its symbols in the
#   repository's R files, so a deletion can be shown to leave no caller behind.
#   Usage: Rscript scripts/check_odds_api_callgraph.R   (prints references; exit 0 when none)
# =============================================================================

ODDS_API_SYMBOLS <- c("load_prop_odds", "ODDS_API_KEY", "odds_api", "oddsapi")

#' R files of the repository worth scanning (no vendored or generated trees; this script and
#' its test name the symbols on purpose)
repo_r_files <- function(root = ".") {
  files <- list.files(root, pattern = "[.]R$", recursive = TRUE, full.names = FALSE)
  skip <- grepl("^(renv|web/node_modules|reports|run_logs|data|\\.git)/", files) |
    files %in% c("scripts/check_odds_api_callgraph.R", "tests/testthat/test-odds-api-callgraph.R")
  sort(files[!skip])
}

#' References to symbols in R files
#'
#' A reference is a code symbol or call (`load_prop_odds(...)`, `ODDS_API_KEY`), a string equal to the
#' name (`exists("load_prop_odds")`, `Sys.getenv("ODDS_API_KEY")`, `"odds_api"`), or a comment that
#' contains the name as a whole word. `prop_odds_api.R` (the file name) is not a reference.
#'
#' @param files Paths relative to `root`
#' @param symbols Names to look for
#' @param root Directory the paths are relative to
#' @return data.frame(file, line, symbol, kind), one row per reference
refs_to_symbols <- function(files, symbols = ODDS_API_SYMBOLS, root = ".") {
  rows <- list()
  for (f in files) {
    pd <- utils::getParseData(parse(file.path(root, f), keep.source = TRUE))
    if (is.null(pd)) next
    for (s in symbols) {
      code <- pd$token %in% c("SYMBOL", "SYMBOL_FUNCTION_CALL", "SYMBOL_SUB", "SYMBOL_FORMALS") & pd$text == s
      str_const <- pd$token == "STR_CONST" & gsub("^[\"']|[\"']$", "", pd$text) == s
      comment <- pd$token == "COMMENT" & grepl(sprintf("\\b%s\\b", s), pd$text)
      for (kind in c("code", "string", "comment")) {
        hit <- switch(kind, code = code, string = str_const, comment = comment)
        if (any(hit)) {
          rows[[length(rows) + 1]] <- data.frame(file = f, line = pd$line1[hit], symbol = s, kind = kind,
                                                 stringsAsFactors = FALSE)
        }
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(file = character(), line = integer(), symbol = character(), kind = character(),
                      stringsAsFactors = FALSE))
  }
  out <- do.call(rbind, rows)
  out[order(out$file, out$line, out$symbol), , drop = FALSE]
}

if (sys.nframe() == 0L) {
  if (!file.exists("DESCRIPTION")) stop("Run from the repository root")
  refs <- refs_to_symbols(repo_r_files("."))
  if (nrow(refs) == 0) {
    cat("No reference to the keyed Odds API path remains.\n")
    quit(status = 0)
  }
  print(refs, row.names = FALSE)
  cat(sprintf("\n%d reference(s) in %d file(s).\n", nrow(refs), length(unique(refs$file))))
  quit(status = 1)
}
```

- [ ] **Step 4: Run and see GREEN, then run the script**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'odds-api-callgraph')"`
Expected: pass.
Run: `HOME=<empty scratch dir> Rscript scripts/check_odds_api_callgraph.R; echo "exit $?"`
Expected: a table of 30 references in 6 files (counted by the dry run), then `30 reference(s) in 6 file(s).`, and exit status 1. After Task 7 it prints `No reference to the keyed Odds API path remains.` and exits 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/check_odds_api_callgraph.R tests/testthat/test-odds-api-callgraph.R
git commit -m "test(props): call-graph check for the keyed Odds API path (P4, P5)

Lists every reference to load_prop_odds, ODDS_API_KEY and the odds_api source, and pins the
list so it can only shrink. The deletion itself is Task 7, behind the owner's approval.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: P4 and P5, retire the keyed Odds API path (haiku; OWNER STOP at Step 1)

**Why.** The owner's rule is keyless data only, and nothing keyless feeds `load_prop_odds()`. After Tasks 3 and 4 the cache needs `game_id`, `captured_at` and ids, which this path's rows never had, so it can no longer price anything anyway. Task 6's script shows what refers to it.

**What is deleted (no file is removed).**
- `load_prop_odds()` and its roxygen block in `R/prop_odds_api.R` (about 190 lines, the Odds API client with the `/odds` request of audit P4 and the Yes/No parsing of audit P5), the `odds_api` branch and `api_key` argument of `resolve_prop_odds_cache()`, and the file header that describes the API.
- `ODDS_API_KEY` in `config.R`.
- The two `exists("load_prop_odds")` fallbacks in `R/correlated_props.R`.
- `"odds_api"` from the default source order in `config.R` and the `props_config.R` fallback. This changes a `config.R` default: `PROP_ODDS_SOURCE_ORDER` goes from `c("odds_api", "csv", "model")` to `c("csv", "model")`. With `ODDS_API_KEY` empty the old first entry always returned NULL, so behaviour does not change.
- The checks of `scripts/audit_verify.R` that assert the deleted function and variable exist, and one line of `docs/modeling.md`.

**Files:**
- Modify: `R/prop_odds_api.R`, `R/correlated_props.R`, `config.R`, `sports/nfl/props/props_config.R`, `scripts/audit_verify.R`, `docs/modeling.md`
- Modify: `tests/testthat/test-repo-hygiene.R` (its mock of the deleted function), `tests/testthat/test-odds-api-callgraph.R` (the allowlist becomes empty)

**Interfaces:**
- Consumes: `refs_to_symbols`, `repo_r_files` (Task 6).
- Produces: `resolve_prop_odds_cache(source = NULL, csv_path = NULL, source_order = NULL, xwalk = NULL)`; no `load_prop_odds`, no `ODDS_API_KEY`.

- [ ] **Step 1: OWNER STOP, approve the deletion and the source-order default**

CLAUDE.md section 4 lists deleting files, changing `config.R` defaults and modifying the engine as stops; this task deletes code and changes one default, so the controller shows the owner the "What is deleted" list above and the output of `Rscript scripts/check_odds_api_callgraph.R` (Task 6) and waits for a yes. Do not start Step 2 without it.

- [ ] **Step 2: Write the failing test (empty the allowlist)**

<!-- apply: T7.2 replace tests/testthat/test-odds-api-callgraph.R -->
```r
# file::symbol pairs that still exist at the end of Task 5; Task 7 empties this list
KNOWN_ODDS_API_REFS <- c(
  "config.R::ODDS_API_KEY",
  "config.R::odds_api",
  "R/correlated_props.R::load_prop_odds",
  "R/prop_odds_api.R::ODDS_API_KEY",
  "R/prop_odds_api.R::load_prop_odds",
  "R/prop_odds_api.R::odds_api",
  "R/prop_odds_api.R::oddsapi",
  "scripts/audit_verify.R::ODDS_API_KEY",
  "scripts/audit_verify.R::load_prop_odds",
  "sports/nfl/props/props_config.R::ODDS_API_KEY",
  "sports/nfl/props/props_config.R::odds_api",
  "tests/testthat/test-repo-hygiene.R::load_prop_odds"
)
```
```r
# The keyed Odds API path is retired (P4, P5): nothing may refer to it
KNOWN_ODDS_API_REFS <- character()
```

- [ ] **Step 3: Run and see RED**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'odds-api-callgraph')"`
Expected: FAIL, `setdiff(found, KNOWN_ODDS_API_REFS)` lists the 12 `file::symbol` pairs.

- [ ] **Step 4: Implement**

4a. `R/prop_odds_api.R`:

<!-- apply: T7.4 replace R/prop_odds_api.R -->
```r
# PROP ODDS API INTEGRATION
# =============================================================================
# File: R/prop_odds_api.R
# Purpose: Load real player prop odds from The Odds API or fallback to defaults
# Version: 2.9.2
#
# API Documentation: https://the-odds-api.com/liveapi/guides/v4/
# Free tier: 500 requests/month
# =============================================================================
```
```r
# PROP ODDS: point-in-time quote cache, CSV loader, ScoresAndOdds parser (off by default)
# =============================================================================
# File: R/prop_odds_api.R
# Purpose: Load prop quotes from keyless sources and look them up by game and player id.
# The keyed The Odds API client was retired (audit P4, P5; keyless data only).
# =============================================================================
```

<!-- apply: T7.4 delete-range R/prop_odds_api.R -->
```r
#' Load player prop odds from The Odds API
```
```r
}
```

<!-- apply: T7.4 replace R/prop_odds_api.R -->
```r
                                    csv_path = NULL,
                                    api_key = Sys.getenv("ODDS_API_KEY"),
                                    source_order = NULL,
```
```r
                                    csv_path = NULL,
                                    source_order = NULL,
```

<!-- apply: T7.4 replace R/prop_odds_api.R -->
```r
    source_order <- c("odds_api", "csv", "model")
```
```r
    source_order <- c("csv", "model")
```

<!-- apply: T7.4 replace R/prop_odds_api.R -->
```r
    if (src %in% c("odds_api", "oddsapi", "api")) {
      cache <- load_prop_odds(api_key = api_key)
      if (!is.null(cache) && nrow(cache) > 0) {
        cache_source <- "odds_api"
        break
      }
    }

```
```r
```

4b. `R/correlated_props.R`, the two fallbacks:

<!-- apply: T7.4 replace R/correlated_props.R -->
```r
  if (is.null(prop_odds_cache) && exists("USE_REAL_PROP_ODDS") && USE_REAL_PROP_ODDS) {
    prop_odds_cache <- tryCatch({
      if (exists("resolve_prop_odds_cache", mode = "function")) {
        resolve_prop_odds_cache()
      } else if (exists("load_prop_odds", mode = "function")) {
        load_prop_odds()
      } else {
```
```r
  if (is.null(prop_odds_cache) && exists("USE_REAL_PROP_ODDS") && USE_REAL_PROP_ODDS) {
    prop_odds_cache <- tryCatch({
      if (exists("resolve_prop_odds_cache", mode = "function")) {
        resolve_prop_odds_cache()
      } else {
```

<!-- apply: T7.4 replace R/correlated_props.R -->
```r
  if (use_prop_odds) {
    prop_odds_cache <- tryCatch({
      if (exists("resolve_prop_odds_cache", mode = "function")) {
        resolve_prop_odds_cache()
      } else if (exists("load_prop_odds", mode = "function")) {
        load_prop_odds()
      } else {
```
```r
  if (use_prop_odds) {
    prop_odds_cache <- tryCatch({
      if (exists("resolve_prop_odds_cache", mode = "function")) {
        resolve_prop_odds_cache()
      } else {
```

4c. `config.R` (variable removed, source order default changed; owner-approved in Step 1):

<!-- apply: T7.4 replace config.R -->
```r
#' @description API key for The Odds API (prop lines)
#' @default Empty string (uses position-based defaults)
#' @note Get free API key at https://the-odds-api.com/
#' @usage Set via environment variable: Sys.setenv(ODDS_API_KEY = "your_key")
ODDS_API_KEY <- Sys.getenv("ODDS_API_KEY", unset = "")

#' @description Enable real market prop odds loading
```
```r
#' @description Enable real market prop odds loading
```

<!-- apply: T7.4 replace config.R -->
```r
#' @description Prop odds source ("auto", "odds_api", "scoresandodds", "csv", or "model")
```
```r
#' @description Prop odds source ("auto", "scoresandodds", "csv", or "model"; keyless sources only)
```

<!-- apply: T7.4 replace config.R -->
```r
#' @default c("odds_api","csv","model")
PROP_ODDS_SOURCE_ORDER <- c("odds_api", "csv", "model")
```
```r
#' @default c("csv","model")
PROP_ODDS_SOURCE_ORDER <- c("csv", "model")
```

4d. `sports/nfl/props/props_config.R`:

<!-- apply: T7.4 replace sports/nfl/props/props_config.R -->
```r
#  - "auto": Prefer ScoresAndOdds scraping when available; otherwise Odds API
#  - "odds_api": The Odds API (requires ODDS_API_KEY)
#  - "scoresandodds": ScoresAndOdds market-comparison API
```
```r
#  - "auto": walk PROP_ODDS_SOURCE_ORDER (keyless sources only)
#  - "scoresandodds": ScoresAndOdds market-comparison API
```

<!-- apply: T7.4 replace sports/nfl/props/props_config.R -->
```r
  PROP_ODDS_SOURCE_ORDER <- c("odds_api", "csv", "model")
```
```r
  PROP_ODDS_SOURCE_ORDER <- c("csv", "model")
```

4e. `scripts/audit_verify.R` and the hygiene test:

<!-- apply: T7.4 replace scripts/audit_verify.R -->
```r
  log_check("P-CHECK-1: Config variables exist", {
    exists("ODDS_API_KEY") && exists("USE_REAL_PROP_ODDS")
  })
```
```r
  log_check("P-CHECK-1: Config variables exist", {
    exists("USE_REAL_PROP_ODDS")
  })
```

<!-- apply: T7.4 replace scripts/audit_verify.R -->
```r
log_check("P-CHECK-2: load_prop_odds() exists",
          exists("load_prop_odds", mode = "function"))

```
```r
log_check("P-CHECK-2: resolve_prop_odds_cache() exists",
          exists("resolve_prop_odds_cache", mode = "function"))

```

<!-- apply: T7.4 replace scripts/audit_verify.R -->
```r
          exists("ODDS_API_KEY") && exists("USE_REAL_PROP_ODDS") && exists("DEFAULT_TD_ODDS"))
```
```r
          exists("USE_REAL_PROP_ODDS") && exists("DEFAULT_TD_ODDS"))
```

<!-- apply: T7.4 replace tests/testthat/test-repo-hygiene.R -->
```r
  api$load_prop_odds <- function(...) NULL
  api$load_prop_odds_csv <- function(...) NULL
  expect_no_error(withr::with_options(list(), api$resolve_prop_odds_cache(source_order = NULL, api_key = "")))
```
```r
  api$load_prop_odds_csv <- function(...) NULL
  expect_no_error(withr::with_options(list(), api$resolve_prop_odds_cache(source_order = NULL)))
```

4f. `docs/modeling.md`:

<!-- apply: T7.4 replace docs/modeling.md -->
```r
- `PROP_ODDS_SOURCE = "auto"` iterates sources in `PROP_ODDS_SOURCE_ORDER` (default: ScoresAndOdds → OddsTrader → Covers → The Odds API → CSV → model).
- `PROP_ODDS_SOURCE = "odds_api"` uses The Odds API (requires `ODDS_API_KEY`).
```
```r
- `PROP_ODDS_SOURCE = "auto"` iterates sources in `PROP_ODDS_SOURCE_ORDER` (default: CSV → model). The keyed The Odds API client was retired (audit P4, P5; keyless data only).
- A prop quote needs `game_id`, `captured_at` and a player id to be used (`R/prop_odds_api.R`, `get_market_prop_quotes`); a quote captured after the game's kickoff is never used, and a prop with no usable quote stays unpriced with a pass reason (audit P14, rule M11).
```

- [ ] **Step 5: Run and see GREEN**

Run: `HOME=<empty scratch dir> Rscript -e "testthat::test_dir('tests/testthat', filter = 'odds-api-callgraph|repo-hygiene|prop-|props-|correlated-props|player-props')"` and `HOME=<empty scratch dir> Rscript scripts/check_odds_api_callgraph.R; echo "exit $?"`
Expected: the tests pass; the script prints `No reference to the keyed Odds API path remains.` and `exit 0`.

- [ ] **Step 6: Commit**

```bash
git add R/prop_odds_api.R R/correlated_props.R config.R sports/nfl/props/props_config.R scripts/audit_verify.R docs/modeling.md tests/testthat/test-repo-hygiene.R tests/testthat/test-odds-api-callgraph.R
git commit -m "chore(props): retire the keyed Odds API path (P4, P5; owner-approved)

Keyless data only. load_prop_odds, ODDS_API_KEY and the odds_api source are gone; the call-graph
check from Task 6 now finds no reference. PROP_ODDS_SOURCE_ORDER defaults to csv, model.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Docs, ledger, CHANGELOG, HANDOFF, and the close-out gates (haiku for Steps 1-2, controller for Steps 3-6)

**Files:**
- Modify: `CHANGELOG.md`, `docs/EVIDENCE_LEDGER.md`, `README.md`, `HANDOFF.md`

- [ ] **Step 1: Ledger rows for the two new defaults**

Both are policy or third-party values, not measurements, so both are `unvalidated`. The fee row names the source and what is still open.

<!-- apply: T8.1 append docs/EVIDENCE_LEDGER.md -->
```text
| P-FEE-COEF | Kalshi taker fee per contract = 0.07 x P x (1 - P) (`KALSHI_TAKER_FEE_COEF`) | – | unvalidated | Owner must verify before relying on it. The primary source kalshi.com/docs/kalshi-fee-schedule.pdf answered HTTP 429 on 2026-10-13 (not retried); help.kalshi.com/trading/fees (dated 2026-04-19) points to it and says some markets carry other fees; 0.07 and the 1.75 / 0.63 cent examples are from sailgp.com/prediction-markets/kalshi/fees and pm.wiki | config.R; tests/testthat/test-prop-pricing.R |
| P-QUOTE-AGE | A prop quote more than 120 minutes older than the decision time is stale (`PROP_QUOTE_MAX_AGE_MIN`) | – | unvalidated | Policy value, not measured; D1's closing rule uses 60 minutes for closes | config.R |
```

- [ ] **Step 2: CHANGELOG and README**

<!-- apply: T8.2 replace CHANGELOG.md -->
```text
## [Unreleased]
```
```text
## [Unreleased]

### P1: props correctness (audit P1-P5, P9, P12-P14; P10 was already done)

- **P14, prop lines are point-in-time.** The quote cache has a game key (`game_id`), a capture time (`captured_at`) and a player id. `get_market_prop_quotes()` uses a quote only if it was captured at or before the game's kickoff and before the run, and only if it is at most `PROP_QUOTE_MAX_AGE_MIN` (120, new default, owner-approved) minutes old at that moment. A 2024 week 16 run can no longer be priced with a 2026 line. A prop with no usable quote stays unpriced: NA odds and EV, recommendation PASS, and the reason in `artifacts/baseline_props.csv` (`unpriced_reason`, `Pass Reason`).
- **P13, defense multipliers apply.** One `load_defense_rankings(season, weeks, pbp)` (the `R/correlated_props.R` copy; the `data_sources.R` copy and its two helpers are deleted, no file removed). The arithmetic is elementwise (`compute_defense_multipliers`), a game uses only weeks played before it, and a neutral fallback says so. The `KNOWN-DEFECT P13` skip is gone; the allowlist regex is unchanged. A new test scans `R/` and `sports/nfl/props/` for functions defined in both (`load_red_zone_efficiency` is the one known duplicate left, not a P1 item).
- **P1, P2, P3, one decision per row.** `classify_prop_edge_quality` is vectorized. `govern_prop_rows()` picks the side the model likes among the priced sides, stakes on that side's probability and price, and returns side, tier (`bet`, `review`, `pass`, `model_error`) and stake together: stake above zero exactly when the tier is `bet` (10,000 random rows). `artifacts/baseline_props.csv` gains `side`, `tier`, `unpriced_reason`, `mkt_fair_over`, `price_venue`, `quote_captured_at`.
- **P9, ids only.** `R/prop_keys.R`: `normalize_team_abbr` (no more `"KC"` to `""`; `LA` and `LAR` are one team; ffverse spellings such as `KCC`, `NEP`, `GBP` map to the schedule's), `resolve_player_ids` (exact name plus team against the ffverse crosswalk; A.St. Brown is no longer A.J. Brown). The `team_tz` table in `NFLsimulation.R` still has `LAR` where schedules use `LA`; that is the game model's half of P9 and is left for an owner-approved engine change.
- **P12, price.** `R/prop_pricing.R`: proportional devig per venue, Kalshi at the bid/ask mid, EV at the best fresh quote for the side the model likes, including the Kalshi taker fee `KALSHI_TAKER_FEE_COEF` (0.07; **unverified against the primary PDF**, see the ledger row P-FEE-COEF). The consensus devigged probability is reported, never used as a price.
- **P4, P5, keyless only.** `scripts/check_odds_api_callgraph.R` shows no reference to the keyed The Odds API client remains; `load_prop_odds`, `ODDS_API_KEY` and the `odds_api` source are deleted (owner-approved). `PROP_ODDS_SOURCE_ORDER` defaults to `csv`, `model`. The ScoresAndOdds scraper (audit S5) is untouched and its rows cannot be priced (no game key, no capture time).
- **P10.** Already done: `sports/nfl/props/props_pipeline.R` was deleted in `3b942ff` (A0) and `test-repo-hygiene.R` keeps it from returning.
- **Golden master:** no differences predicted and measured; the golden master runs `NFLsimulation.R` only, and props run from `run_week.R` after `final` is written.
```

<!-- apply: T8.2 replace README.md -->
```text
| `R/sim_bundle.R` | The simulator's weekly bundle, written by `run_week.R` |
```
```text
| `R/sim_bundle.R` | The simulator's weekly bundle, written by `run_week.R` |
| `R/prop_keys.R` | Canonical team abbreviations and exact player-id resolution for prop quotes |
| `R/prop_pricing.R` | Devig per venue, Kalshi taker fee, EV at the best fresh quote |
```

- [ ] **Step 3: HANDOFF note**

<!-- apply: T8.3 append HANDOFF.md -->
```text

## P1 (props correctness) close-out note

- Done on the P1 branch (see CHANGELOG "P1"): P13, P14, P1, P2, P3, P9, P12, P4, P5; P10 was already done.
- Not done, owner decisions: the `KALSHI_TAKER_FEE_COEF` value must be checked against kalshi.com/docs/kalshi-fee-schedule.pdf (HTTP 429 on 2026-10-13); `PROP_REQUIRE_MARKET_ODDS` (default TRUE) drops unpriced rows from the output when any priced row exists, which hides their pass reasons; `team_tz` in `NFLsimulation.R` has `LAR` where schedules use `LA`; the ScoresAndOdds scraper (S5) and the duplicate `load_red_zone_efficiency` remain.
- Next: P2 (props model v2) needs G1's `predict_week()`; P3 needs the signed `nfl_props_v1` protocol; D1's Kalshi provider must write the quote schema in the P1 plan, Tasks 3 and 4.
```

- [ ] **Step 4: Run the gates (fresh HOME) and quote the final lines**

```bash
HOME=<empty scratch dir> Rscript scripts/run_tests.R              # exit 0, skipped=0
HOME=<empty scratch dir> Rscript scripts/verify_repo_integrity.R  # exit 0
HOME=<empty scratch dir> Rscript scripts/audit_verify.R           # CI also runs it
HOME=<empty scratch dir> Rscript scripts/check_odds_api_callgraph.R   # exit 0
```
Expected: `tests=<N> passed=<M> failed=0 errors=0 skipped=0 unapproved_skips=0`; `[VERIFICATION PASSED]`. The `KNOWN-DEFECT P13` skip no longer appears and `tests/skip_allowlist.txt` is byte-identical to main (`git diff --exit-code tests/skip_allowlist.txt`).

- [ ] **Step 5: Golden master (controller)**

Prediction: **no differences**. Reasons: `scripts/golden_master.R` runs `NFLsimulation.R` and states that player props run from `run_week.R` and are not part of the run; the props block of `run_week.R` reads `last_simulation_results` after `final` is written and sets no value that `final` or the golden-master columns read; this plan edits no line of `NFLsimulation.R`, `NFLmarket.R` or `R/utils.R`; the only shared file touched is `config.R` (two constants appended, `ODDS_API_KEY` removed, `PROP_ODDS_SOURCE_ORDER` default changed), and `NFLmarket.R` sources `props_config.R` for constants and a classifier it does not call. Check: record and compare, and CI's `attribute` per commit.

```bash
HOME=<empty scratch dir> Rscript scripts/golden_master.R record 15 2024 <base_dir>      # on origin/main
HOME=<empty scratch dir> Rscript scripts/golden_master.R compare 15 2024 <base_dir>     # on the P1 tree
```
Expected: the compare prints no differing columns.

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md docs/EVIDENCE_LEDGER.md README.md HANDOFF.md
git commit -m "docs: P1 props correctness close-out (CHANGELOG, ledger, README, HANDOFF)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

## Dry-run evidence (2026-10-13/14 by the P1 planner; final gates 2026-10-19 by the controller)

The dry-run tree is `C:/Users/jviol/Downloads/nfl-worktrees/p1dry`: detached at `210f791`, uncommitted. The plan was assembled from its parts (`.superpowers/research/p1-parts/`, `p1-assemble.sh`) and re-applied to the tree with `p1-apply-plan.js`, then:

| Gate (fresh HOME) | Result | Run by |
|---|---|---|
| `Rscript scripts/run_tests.R` | `tests=504 passed=1970 failed=0 errors=0 skipped=0`, exit 0. The `KNOWN-DEFECT P13` skip is gone | planner, 2026-10-14 |
| `Rscript scripts/golden_master.R compare 15 2024 <base>` (base recorded on `origin/main` in a throwaway worktree) | `golden master: no differences`, exit 0. Player props are not part of the golden-master run | planner, 2026-10-14 |
| `Rscript scripts/verify_repo_integrity.R` | `Total: 63 passed, 0 failed`, `[VERIFICATION PASSED]`, exit 0 | controller, 2026-10-19 |
| `Rscript scripts/run_matrix.R` | `Total: 11 artifacts`, `[RUN MATRIX: ALL PASSED]`, exit 0 (golden-master artifact 1012.4 s, under the 1800 s cap) | controller, 2026-10-19 |

**Open for the owner** (owner checkpoints in this plan):
- `KALSHI_TAKER_FEE_COEF` (0.07) is unverified. The primary fee PDF answered HTTP 429 on 2026-10-13 and was not retried.
- The deletions in Tasks 7 (the keyed Odds API path) and 1 (the duplicate `load_defense_rankings`).
- The `config.R` defaults that Tasks 3 and 4 add.

**Executing after A0 (PR #214):** `config.R` gains capture constants. P1 appends its own constants, so re-check the anchors of every `config.R` edit when this plan is executed.
