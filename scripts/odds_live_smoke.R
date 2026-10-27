#!/usr/bin/env Rscript
# Live smoke test of the keyless odds layer (tests/live/). Makes a handful of real requests
# at 1 request/second; never part of scripts/run_tests.R. Exit status 1 on any failure, and on
# any skip: a test skipped because its host is unreachable checked nothing.
#   Rscript scripts/odds_live_smoke.R
if (!file.exists("config.R") || !dir.exists("tests/live")) stop("Run from the repository root")
Sys.setenv(NFL_ODDS_FORBID_LIVE = "0")
# config.R in the global environment, where odds_http_config() reads the CAPTURE_* settings
sys.source("config.R", envir = globalenv())
env <- new.env(parent = globalenv())
sys.source("R/capture_raw.R", envir = env)
for (f in sort(list.files("R/odds", pattern = "\\.R$", full.names = TRUE))) sys.source(f, envir = env)
sys.source("tests/testthat/helper-live.R", envir = env)
sys.source("tests/testthat/helper-odds.R", envir = env)
fixture_dir <- normalizePath(file.path("tests", "testthat", "fixtures", "odds"))
env$odds_fixture_path <- function(...) file.path(fixture_dir, ...)   # test_path() would resolve inside tests/live
Sys.setenv(NFL_ODDS_FORBID_LIVE = "0")   # helper-odds.R sets the guard for the default suite; undo it here
res <- testthat::test_dir("tests/live", env = env, reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
status <- env$live_smoke_exit_status(df)
if (sum(df$skipped) > 0) message(sprintf("NOT RUN: %d live test(s) skipped (a host was unreachable)", sum(df$skipped)))
quit(status = status)
