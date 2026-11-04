# Audit M1: CLI week/season must survive every source("config.R")

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
  expect_equal(env$.playoff_context$phase, "regular_season")   # derived while sourcing
  # a second load (as NFLsimulation.R does) keeps the override
  withr::with_dir(PROJECT_ROOT, sys.source("config.R", envir = env))
  expect_equal(env$WEEK_TO_SIM, 15L)
  expect_equal(env$SEASON, 2024L)
})

test_that("config.R without options falls back to the calendar week, never 2025 week 22, and says so", {
  withr::local_options(nfl.week = NULL, nfl.season = NULL)
  env <- new.env()
  expect_message(withr::with_dir(PROJECT_ROOT, sys.source("config.R", envir = env)), "calendar estimate")
  cal <- nfl_calendar_week(Sys.time())
  expect_equal(env$WEEK_TO_SIM, cal$week)
  expect_equal(env$SEASON, cal$season)
})

test_that("set_run_options publishes only supplied values", {
  withr::local_options(nfl.week = NULL, nfl.season = NULL)
  set_run_options(list(week = 9L, season = NA_integer_))
  expect_equal(getOption("nfl.week"), 9L)
  expect_null(getOption("nfl.season"))
})

# --- C1 (2026-10-20): the week comes from the schedule, never from a 2025 week 22 default ---

et <- function(x) as.POSIXct(x, tz = "America/New_York")

sched_fixture <- function() {
  data.frame(
    season = 2026L,
    game_type = c(rep("REG", 9), "WC"),
    week = c(6L, 6L, 6L, 7L, 7L, 7L, 7L, 8L, 8L, 19L),
    gameday = c("2026-10-15", "2026-10-18", "2026-10-19", "2026-10-22", "2026-10-25", "2026-10-25",
                "2026-10-26", "2026-10-29", NA, "2027-01-16"),
    gametime = c("20:15", "13:00", "20:15", "20:15", "13:00", "16:25", "20:15", "20:15", NA, "16:30"),
    stringsAsFactors = FALSE
  )
}

test_that("nfl_season_of puts January and February in the previous season", {
  expect_equal(nfl_season_of(et("2027-01-17 13:00")), 2026L)
  expect_equal(nfl_season_of(et("2027-02-14 18:30")), 2026L)
  expect_equal(nfl_season_of(et("2026-03-01 12:00")), 2026L)
  expect_equal(nfl_season_of(et("2026-10-20 12:00")), 2026L)
})

test_that("nfl_calendar_week counts Tuesday-to-Monday weeks from the Thursday after Labor Day", {
  cases <- list(
    list("2026-08-15 12:00", 2026L, 1L),   # before the season: week 1
    list("2026-09-08 09:00", 2026L, 1L),   # the Tuesday before the opener (Thursday 2026-09-10)
    list("2026-09-14 23:00", 2026L, 1L),   # Monday night of week 1
    list("2026-09-15 09:00", 2026L, 2L),
    list("2026-10-19 21:00", 2026L, 6L),   # Monday night of week 6
    list("2026-10-20 12:00", 2026L, 7L),   # the Tuesday after: the next week
    list("2027-01-05 12:00", 2026L, 18L),
    list("2027-01-12 12:00", 2026L, 19L),  # wild card
    list("2027-02-03 12:00", 2026L, 22L),  # the bye week before the Super Bowl
    list("2027-02-20 12:00", 2026L, 22L),  # after the Super Bowl it stays at 22 until March
    list("2024-12-17 12:00", 2024L, 16L)   # 2024: Labor Day was 2 September, the opener 5 September
  )
  for (cs in cases) {
    expect_equal(nfl_calendar_week(et(cs[[1]])), list(season = cs[[2]], week = cs[[3]]), info = cs[[1]])
  }
})

test_that("resolve_target_week picks the earliest week with a game still to kick off", {
  s <- sched_fixture()
  tue <- resolve_target_week(s, et("2026-10-20 12:00"))
  expect_equal(tue$season, 2026L)
  expect_equal(tue$week, 7L)
  expect_equal(tue$n_games, 4L)
  expect_equal(format(tue$first_kickoff, "%Y-%m-%d %H:%M", tz = "America/New_York"), "2026-10-22 20:15")
  expect_equal(resolve_target_week(s, et("2026-10-19 19:00"))$week, 6L)   # before Monday night's kickoff
  expect_equal(resolve_target_week(s, et("2026-10-25 14:00"))$week, 7L)   # between Sunday's kickoffs
  expect_equal(resolve_target_week(s, et("2026-10-26 21:00"))$week, 8L)   # after Monday night's kickoff
  expect_equal(resolve_target_week(s, et("2026-12-01 12:00"))$week, 19L)  # playoff weeks count
})

test_that("resolve_target_week stops when nothing is left to kick off, and ignores undated games", {
  s <- sched_fixture()
  expect_error(resolve_target_week(s, et("2027-02-01 12:00")), "pass a week and season")
  expect_error(resolve_target_week(s[0, ], et("2026-10-20 12:00")), "pass a week and season")
  # the undated week-8 game is not a game still to come
  expect_error(resolve_target_week(s[s$week != 19L, ], et("2026-10-30 12:00")), "pass a week and season")
})

test_that("resolve_run_target keeps explicit arguments and never loads the schedule for them", {
  boom <- function(season) stop("the schedule must not be loaded")
  now <- et("2026-10-20 12:00")
  expect_equal(resolve_run_target(list(week = 15L, season = 2024L), now, boom), list(week = 15L, season = 2024L))
  # a week alone means the season in progress
  expect_equal(resolve_run_target(list(week = 9L, season = NA_integer_), now, boom), list(week = 9L, season = 2026L))
})

test_that("resolve_run_target resolves the upcoming week from the schedule and says so", {
  loaded <- NULL
  load <- function(season) { loaded <<- season; sched_fixture() }
  expect_message(
    got <- resolve_run_target(list(week = NA_integer_, season = NA_integer_), et("2026-10-20 12:00"), load),
    "Auto-resolved 2026 week 7 (4 games, first kickoff Thu 2026-10-22 20:15 ET)", fixed = TRUE
  )
  expect_equal(got, list(week = 7L, season = 2026L))
  expect_equal(loaded, 2026L)
})

test_that("resolve_run_target stops, naming the command to use, when the schedule cannot load", {
  fail <- function(season) stop("HTTP 503")
  expect_error(
    resolve_run_target(list(week = NA_integer_, season = NA_integer_), et("2026-10-20 12:00"), fail),
    "Rscript run_week.R <week> <season>", fixed = TRUE
  )
})

test_that("run_week.R resolves the week before config.R is sourced", {
  src <- readLines(file.path(PROJECT_ROOT, "run_week.R"), warn = FALSE)
  resolve_at <- grep("resolve_run_target(parse_run_args(", src, fixed = TRUE)
  config_at <- which(src == 'source("config.R")')
  expect_length(resolve_at, 1)
  expect_lt(resolve_at, config_at[1])
})

test_that("scripts/resolve_week.R prints the week and season for the workflow", {
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- withr::with_dir(PROJECT_ROOT, system2(rscript, c("--vanilla", "scripts/resolve_week.R", "15", "2024"),
                                               stdout = TRUE, stderr = FALSE))
  expect_equal(out, c("week=15", "season=2024"))
})
