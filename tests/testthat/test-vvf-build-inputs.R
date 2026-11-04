# VVF input builder (backtest/vvf/build_inputs.R, ported from PR #205): the seal
# is checked before any request, loader results are guarded, the injury rows obey
# the kickoff - 6 h rule, and geocoding follows the network rules. Offline: every
# loader is a fake.

vb <- vvf_test_env(c("common.R", "build_inputs.R"))

test_that("the builder refuses to overwrite inputs that already have a SOURCES.json, before any request (review I8)", {
  withr::local_dir(PROJECT_ROOT)
  tmp <- withr::local_tempdir()
  writeLines("{}", file.path(tmp, "SOURCES.json"))
  never <- function(...) stop("a request was made")
  expect_error(vb$vvf_build_inputs(out_dir = tmp, seasons = 2024L, load_schedules = never, load_injuries = never,
                                   http_get = never), "would overwrite")
  expect_identical(list.files(tmp), "SOURCES.json")
})

mini_games <- function() {
  data.table::data.table(
    game_id = c("2020_01_AAA_BBB", "2020_02_BBB_AAA"), season = 2020L, week = 1:2,
    home_franchise = c("AAA", "BBB"), away_franchise = c("BBB", "AAA"),
    kickoff = as.POSIXct(c("2020-09-13 17:00:00", "2020-09-20 17:00:00"), tz = "UTC"))
}

test_that("a sealed season is refused before any request is made", {
  withr::local_dir(PROJECT_ROOT)
  tmp <- withr::local_tempdir()
  never <- function(...) stop("a request was made")
  expect_error(vb$vvf_build_inputs(out_dir = tmp, seasons = 2024:2025, load_schedules = never,
                                   load_injuries = never, http_get = never), "sealed-season guard")
  expect_length(list.files(tmp), 0L)
})

test_that("a loader that returns a 2025 row stops the build before anything is written", {
  withr::local_dir(PROJECT_ROOT)
  tmp <- withr::local_tempdir()
  sched <- function(seasons) data.frame(season = c(2024L, 2025L), game_id = c("x", "y"))
  never <- function(...) stop("a request was made")
  expect_error(vb$vvf_build_inputs(out_dir = tmp, seasons = 2024L, load_schedules = sched,
                                   load_injuries = never, http_get = never), "sealed-season guard")
  expect_length(list.files(tmp), 0L)
})

test_that("injury rows count only when modified more than 6 h before the team's kickoff", {
  withr::local_dir(PROJECT_ROOT)
  inj <- data.table::data.table(
    season = 2020L, week = 1L, team = c("AAA", "AAA", "BBB", "CCC"), gsis_id = c("Q1", "W1", "L1", "Z9"),
    position = c("QB", "WR", "LB", "QB"), report_status = c("Out", "Questionable", "Doubtful", "Out"),
    date_modified = as.POSIXct(c("2020-09-11 20:00:00", "2020-09-13 12:00:00", "2020-09-12 09:00:00",
                                 "2020-09-11 20:00:00"), tz = "UTC"))
  out <- vb$vvf_build_injuries(inj, mini_games())
  expect_equal(out$meta$rows_unmatched_team_week, 1L)      # CCC plays no week-1 game
  expect_equal(out$meta$rows_dropped_not_before_kickoff, 1L) # W1 modified 5 h before kickoff
  expect_equal(out$meta$rows_kept, 2L)
  a <- out$team[team == "AAA"]
  expect_equal(c(a$qb_out, a$skill_questionable), c(1L, 0L))
  expect_equal(out$team[team == "BBB", lb_doubtful], 1L)
  expect_equal(out$qb$gsis_id, "Q1")
})

test_that("position groups follow the engine's injury groups", {
  expect_equal(vb$vvf_position_group(c("qb", "LT", "TE", "EDGE", "OLB", "SAF", "K")),
               c("qb", "ol", "skill", "dl", "lb", "db", "other"))
})

test_that("geocoding sends the project user agent and timeout, one request a second, one try", {
  withr::local_dir(PROJECT_ROOT)
  calls <- list(); sleeps <- numeric()
  fake_get <- function(url, user_agent, timeout_sec) {
    calls[[length(calls) + 1L]] <<- list(url = url, ua = user_agent, timeout = timeout_sec)
    '{"results":[{"name":"X","admin1":"Georgia","country_code":"US","latitude":33.7,"longitude":-84.4,"elevation":300,"timezone":"America/New_York"}]}'
  }
  v <- vb$vvf_build_venues(c("ATL00", "ATL97"), http_get = fake_get, sleep = function(s) sleeps <<- c(sleeps, s))
  expect_equal(nrow(v$venues), 2L)
  expect_length(calls, 2L)
  expect_identical(calls[[1]]$ua, vb$vvf_config_value("CAPTURE_USER_AGENT"))
  expect_equal(calls[[1]]$timeout, vb$vvf_config_value("CAPTURE_TIMEOUT_SEC"))
  expect_equal(sleeps, vb$vvf_config_value("CAPTURE_MIN_INTERVAL_SEC"))
  expect_match(calls[[2]]$url, "countryCode=US")
  failing <- function(...) stop("HTTP status was '429 Too Many Requests'")
  expect_error(vb$vvf_build_venues("ATL00", http_get = failing, sleep = function(s) NULL), "429")
})

test_that("an unmapped stadium stops the venue build", {
  expect_error(vb$vvf_build_venues("ZZZ00", http_get = function(...) stop("no"), sleep = function(s) NULL),
               "unmapped stadium_id")
})
