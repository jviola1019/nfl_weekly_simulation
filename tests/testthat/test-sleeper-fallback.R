# Audit M20: Sleeper serves only today's injury report. Before Plan 1b-1 the engine used it
# for any week when nflverse injuries failed, stamped with the calendar year, so a re-run of
# 2024 week 15 could price 2026 injuries.
sim_path <- file.path(PROJECT_ROOT, "NFLsimulation.R")
inj_env <- load_script_functions(sim_path, "safe_load_injuries")
sleeper_rows <- data.frame(team = "KC", position = "WR", game_status = "Out",
                           injury_body_part = "Knee", player = "Test Player")

test_that("the live report is allowed only while the slate has games to play", {
  expect_true(sleeper_fallback_allowed(as.Date(c("2026-10-01", "2026-10-04")), today = as.Date("2026-10-02")))
  expect_true(sleeper_fallback_allowed(as.Date("2026-10-04"), today = as.Date("2026-10-04")))
  expect_false(sleeper_fallback_allowed(as.Date(c("2024-12-12", "2024-12-16")), today = as.Date("2026-10-01")))
  expect_false(sleeper_fallback_allowed(as.Date(NA), today = as.Date("2026-10-01")))
})

test_that("Sleeper rows carry the slate's season and week, not the calendar year", {
  r <- sleeper_as_injury_rows(sleeper_rows, season = 2026L, week = 5L)
  expect_equal(r$season, 2026L)
  expect_equal(r$week, 5L)
  expect_equal(r$status, "Out")
  expect_error(sleeper_as_injury_rows(sleeper_rows, season = NA, week = 5L), "season and week")
})

test_that("a completed slate never takes today's Sleeper report (audit M20)", {
  local_mocked_bindings(load_injuries = function(...) tibble::tibble(), .package = "nflreadr")
  called <- FALSE
  assign("load_injuries_sleeper", function(...) { called <<- TRUE; list(success = TRUE, data = sleeper_rows) },
         envir = inj_env)
  withr::defer(rm("load_injuries_sleeper", envir = inj_env))
  withr::defer(reset_data_quality())
  out <- inj_env$safe_load_injuries(2024, prefer_fast = FALSE, allow_live_fallback = FALSE,
                                    stamp_season = 2024L, stamp_week = 15L)
  expect_equal(nrow(out), 0L)
  expect_false(called)
  expect_equal(get_data_quality()$injury$status, "unavailable")
})

test_that("a live slate takes Sleeper rows stamped with its season and week", {
  local_mocked_bindings(load_injuries = function(...) tibble::tibble(), .package = "nflreadr")
  assign("load_injuries_sleeper", function(...) list(success = TRUE, data = sleeper_rows), envir = inj_env)
  withr::defer(rm("load_injuries_sleeper", envir = inj_env))
  withr::defer(reset_data_quality())
  out <- inj_env$safe_load_injuries(2026, prefer_fast = FALSE, allow_live_fallback = TRUE,
                                    stamp_season = 2026L, stamp_week = 5L)
  expect_equal(out$season, 2026L)
  expect_equal(out$week, 5L)
  expect_equal(get_data_quality()$injury$status, "partial")
})

test_that("both injury loads in NFLsimulation.R pass the slate check (audit M20)", {
  code <- readLines(sim_path, warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_equal(sum(grepl("allow_live_fallback = sleeper_fallback_allowed(week_slate$game_date)", code, fixed = TRUE)), 2L)
  expect_false(any(grepl('season = as.integer(format(Sys.Date(), "%Y"))', code, fixed = TRUE)))
  expect_true(any(grepl('source(file.path(base_path, "sleeper_api.R"))', code, fixed = TRUE)))
})
