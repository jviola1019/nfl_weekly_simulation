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

test_that("config.R defaults are unchanged without options", {
  withr::local_options(nfl.week = NULL, nfl.season = NULL)
  env <- new.env()
  withr::with_dir(PROJECT_ROOT, sys.source("config.R", envir = env))
  expect_equal(env$WEEK_TO_SIM, 22L)
  expect_equal(env$SEASON, 2025L)
})

test_that("set_run_options publishes only supplied values", {
  withr::local_options(nfl.week = NULL, nfl.season = NULL)
  set_run_options(list(week = 9L, season = NA_integer_))
  expect_equal(getOption("nfl.week"), 9L)
  expect_null(getOption("nfl.season"))
})
