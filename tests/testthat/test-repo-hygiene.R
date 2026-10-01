# Repo hygiene invariants from the 2026-09-28 audit (H1, H2, SEC2, S1)

test_that("dead and misleading files are gone", {
  removed <- c(
    "core/simulation_engine.R", "sports/nfl/config.R", "sports/nfl/props/props_pipeline.R",
    "professional_model_benchmarking.R", "simplified_baseline_comparison.R",
    "rolling_validation_system.R", "scripts/grid_search_results_copula.rds",
    "artifacts/oddstrader_playerprops.js", "artifacts/tmp_check.R",
    "AUDIT.md", "IMPROVEMENT_PLAN.md", "docs/AUDIT_REPORT.md",
    # deletion batch 2 (2026-09-29): superseded by backtest/ or never called
    "scripts/parameter_grid_search.R", "validation_pipeline.R", "validation_reports.R",
    "validation/validate_correlations.R", "validation/playoffs_validation.R",
    "R/coaching_adjustments.R", "R/simulation_helpers.R", "R/model_diagnostics.R",
    "core/calibration.R", "validation/calibration_harness.R"
  )
  still_there <- removed[file.exists(file.path(PROJECT_ROOT, removed))]
  expect_equal(still_there, character())
})

test_that("superseded audit documents are preserved under reports/history", {
  kept <- file.path(PROJECT_ROOT, "reports", "history",
                    c("AUDIT.md", "IMPROVEMENT_PLAN.md", "AUDIT_REPORT.md"))
  expect_true(all(file.exists(kept)))
})

test_that(".gitignore covers secrets, local settings and generated data", {
  gi <- trimws(readLines(file.path(PROJECT_ROOT, ".gitignore"), warn = FALSE))
  required <- c(".Renviron", ".env*", ".claude/settings*.json", ".playwright-mcp/",
                "data/raw_capture/", "run_logs/")
  expect_equal(setdiff(required, gi), character())
  expect_false("reports/" %in% gi)
})

test_that("OddsTrader and Covers scrapers are retired", {
  env <- new.env()
  sys.source(file.path(PROJECT_ROOT, "R", "prop_odds_api.R"), envir = env)
  retired <- c("load_prop_odds_oddstrader", "load_prop_odds_covers", "parse_oddstrader_html")
  expect_false(any(vapply(retired, exists, logical(1), envir = env, inherits = FALSE)))
  expect_false(any(c("oddstrader", "covers") %in% PROP_ODDS_SOURCE_ORDER))
})

test_that("ScoresAndOdds scraping is off by default (audit S5)", {
  # config.R and props_config.R defaults: no remote scraping, not in the source order
  expect_false(isTRUE(PROP_ODDS_ALLOW_REMOTE_HTML))
  expect_false("scoresandodds" %in% tolower(PROP_ODDS_SOURCE_ORDER))
  env <- new.env(parent = baseenv())   # props_config.R's own fallbacks, not the global config
  sys.source(file.path(PROJECT_ROOT, "sports", "nfl", "props", "props_config.R"), envir = env)
  expect_false(isTRUE(get("PROP_ODDS_ALLOW_REMOTE_HTML", envir = env)))
  expect_false("scoresandodds" %in% tolower(get("PROP_ODDS_SOURCE_ORDER", envir = env)))
  # the odds resolver never reaches the scraper unless someone opts in explicitly
  api <- new.env()
  sys.source(file.path(PROJECT_ROOT, "R", "prop_odds_api.R"), envir = api)
  expect_false(formals(api$load_prop_odds_scoresandodds)$allow_remote)
  api$load_prop_odds_scoresandodds <- function(...) stop("scraper called")
  api$load_prop_odds <- function(...) NULL
  api$load_prop_odds_csv <- function(...) NULL
  expect_no_error(withr::with_options(list(), api$resolve_prop_odds_cache(source_order = NULL, api_key = "")))
})
