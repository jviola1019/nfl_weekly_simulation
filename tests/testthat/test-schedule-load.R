# A failed schedule download (2026-11-04 22:35Z, a dropped connection): nflreadr::load_schedules() returned an
# empty table with only a warning, and the engine stopped with "object 'home_score' not found" inside a mutate().
# load_schedules_checked() retries after clearing nflreadr's remembered failure, and stops with nflreadr's
# warning as the cause. The loader is a parameter, so these tests need no network; the good table is the
# committed nflverse results (backtest/data/games.csv).

real_schedule <- function() {
  g <- utils::read.csv(file.path(PROJECT_ROOT, "backtest", "data", "games.csv"), stringsAsFactors = FALSE)
  g[g$season == 2024, c("game_id", "season", "game_type", "week", "gameday", "home_team", "away_team",
                        "home_score", "away_score", "location")]
}
# a loader that fails `fails` times the way nflreadr does (an empty table and a warning), then succeeds
flaky_loader <- function(fails, warning_text = "HTTP status was '503 Service Unavailable'") {
  calls <- 0L
  function(seasons) {
    calls <<- calls + 1L
    if (calls <= fails) {
      warning(warning_text, call. = FALSE)
      return(data.frame())
    }
    s <- real_schedule()
    s[s$season %in% seasons, , drop = FALSE]
  }
}

test_that("a schedule that loads on a retry is returned, after nflreadr's cache is cleared", {
  cleared <- 0L
  s <- load_schedules_checked(2024, retries = 2L, wait = 0, loader = flaky_loader(2),
                              clear = function() cleared <<- cleared + 1L)
  expect_equal(nrow(s), nrow(real_schedule()))
  expect_equal(cleared, 2L)
})

test_that("a schedule that never loads stops with nflreadr's warning, not a missing column", {
  expect_error(load_schedules_checked(2024, retries = 2L, wait = 0, loader = flaky_loader(99), clear = function() NULL),
               "the nflverse schedule did not load after 3 attempt\\(s\\) \\(HTTP status was '503 Service Unavailable'\\)")
})

test_that("a table without the columns the engine reads counts as a failed load", {
  partial <- function(seasons) real_schedule()[, c("game_id", "season", "week")]
  expect_error(load_schedules_checked(2024, retries = 0L, wait = 0, loader = partial, clear = function() NULL),
               "after 1 attempt\\(s\\) \\(missing game_type, home_team, away_team, home_score, away_score, location\\)")
})

test_that("both of the engine's schedule loads go through load_schedules_checked()", {
  code <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_true(any(grepl("sched <- load_schedules_checked(seasons_hfa,", code, fixed = TRUE)))
  expect_true(any(grepl("hfa_games <- load_schedules_checked(1999:SEASON,", code, fixed = TRUE)))
  expect_false(any(grepl("<- load_schedules(seasons", code, fixed = TRUE)))
})
