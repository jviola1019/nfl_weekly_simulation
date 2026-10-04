# =============================================================================
# Report Audit Guardrails (governance labels)
# =============================================================================
# The display-label guards went with the HTML report (checkpoint A8); the governance
# pass reasons live in R/utils.R and still feed artifacts/baseline_games.csv.

context("Report Audit Guardrails")

test_that("pass reasons include required deterministic governance reasons", {
  market_file <- file.path(.test_project_root, "NFLmarket.R")
  utils_file <- file.path(.test_project_root, "R", "utils.R")

  txt <- paste(readLines(market_file, warn = FALSE), collapse = "\n")
  utils_txt <- paste(readLines(utils_file, warn = FALSE), collapse = "\n")
  combined <- paste(txt, utils_txt, collapse = "\n")

  expect_match(combined, "Market odds missing/placeholder")
  expect_match(combined, "Negative EV")
  expect_match(combined, "Stake below minimum")
})
