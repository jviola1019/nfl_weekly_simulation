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
