# Team-code tables outside the engine use the schedule's codes (data/reference/teams.csv): the Rams are LA, not
# LAR. The engine's team_tz had LAR until 2026-11-03 (test-team-tz.R); the props module's dome list and the odds
# name table had it too, so a Rams home game was never a dome to the props module.
ref <- utils::read.csv(file.path(PROJECT_ROOT, "data", "reference", "teams.csv"), stringsAsFactors = FALSE)$team_id

test_that("the props module's dome list uses schedule team codes", {
  src <- paste(readLines(file.path(PROJECT_ROOT, "sports", "nfl", "props", "data_sources.R"), warn = FALSE), collapse = "\n")
  m <- regmatches(src, regexpr("dome_teams <- c\\([^)]*\\)", src))
  expect_length(m, 1L)
  codes <- gsub('"', "", regmatches(m, gregexpr('"[A-Z]+"', m))[[1]], fixed = TRUE)   # the quoted codes
  expect_true(all(codes %in% ref), info = paste(setdiff(codes, ref), collapse = ", "))
  expect_true("LA" %in% codes)
})

test_that("the odds name table is keyed by schedule team codes", {
  env <- load_script_functions(file.path(PROJECT_ROOT, "R", "prop_odds_api.R"), "TEAM_ABBR_TO_NAME")
  expect_setequal(names(env$TEAM_ABBR_TO_NAME), ref)
})
