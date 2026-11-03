# safe_load_injuries() (NFLsimulation.R). nflreadr reports a failed download (a timeout, or a
# release not yet published) as a warning and an empty table, and memoises that empty table. A
# season that comes back empty is retried after nflreadr's cache is cleared; one that stays empty
# is recorded as missing, with nflreadr's warning as the cause. Before, the warning was suppressed
# and the season dropped out unflagged: on 2026-11-03 a timed-out 2024 load ran the golden master
# with zero injury impact and no cause, and an empty season beside a loaded one still read "full".

# NFLsimulation.R runs the whole pipeline when sourced, so evaluate only this function's definition,
# with update_injury_quality() recording what it is told
load_safe_load_injuries <- function() {
  exprs <- parse(file.path(PROJECT_ROOT, "NFLsimulation.R"), keep.source = FALSE)
  defs <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                   identical(e[[2]], as.name("safe_load_injuries")), exprs)
  if (length(defs) != 1) stop("expected one safe_load_injuries definition in NFLsimulation.R")
  env <- new.env(parent = globalenv())
  env$quality <- NULL
  env$update_injury_quality <- function(status, missing_seasons = character()) {
    env$quality <- list(status = status, missing_seasons = missing_seasons)
  }
  eval(defs[[1]], env)
  env
}

injury_rows <- function(season) data.frame(season = season, team = "KC", full_name = "A Player", report_status = "Out")

# A stand-in for nflreadr: `script` gives each season's downloads in turn, NULL being a failed one
# (nflreadr's warning and an empty table). Like nflreadr's memoised loaders, a season's last result
# is returned again until clear_cache() is called.
fake_nflreadr <- function(script) {
  state <- new.env()
  state$downloads <- list()
  state$cache <- list()
  load_injuries <- function(seasons, ...) {
    key <- as.character(seasons)
    if (!is.null(state$cache[[key]])) return(state$cache[[key]])
    i <- (state$downloads[[key]] %||% 0L) + 1L
    state$downloads[[key]] <- i
    outcome <- script[[key]][[min(i, length(script[[key]]))]]
    if (is.null(outcome)) {
      warning(sprintf("Failed to readRDS from <https://github.com/nflverse/nflverse-data/releases/download/injuries/injuries_%s.rds>", key),
              call. = FALSE)
      outcome <- data.frame()
    }
    state$cache[[key]] <- outcome
    outcome
  }
  clear_cache <- function() {
    state$cache <- list()
    invisible(TRUE)
  }
  list(load_injuries = load_injuries, clear_cache = clear_cache, state = state)
}

# runs the loader, returning its result and every message it printed
run_quietly <- function(expr) {
  msgs <- character()
  out <- withCallingHandlers(expr, message = function(m) {
    msgs <<- c(msgs, conditionMessage(m))
    invokeRestart("muffleMessage")
  })
  list(out = out, messages = msgs)
}

test_that("an injury season that comes back empty is downloaded again, past nflreadr's cache", {
  env <- load_safe_load_injuries()
  fake <- fake_nflreadr(list(`2023` = list(injury_rows(2023)), `2024` = list(NULL, injury_rows(2024))))
  local_mocked_bindings(load_injuries = fake$load_injuries, clear_cache = fake$clear_cache, .package = "nflreadr")
  res <- run_quietly(env$safe_load_injuries(c(2023, 2024), prefer_fast = FALSE, retry_wait = 0))
  expect_equal(sort(unique(res$out$season)), c(2023, 2024))
  expect_equal(fake$state$downloads[["2024"]], 2L)
  expect_equal(env$quality$status, "full")
  expect_true(any(grepl("2024.*empty.*Failed to readRDS", res$messages)), info = paste(res$messages, collapse = "\n"))
})

test_that("a season that stays empty is missing, with nflreadr's warning as the cause", {
  env <- load_safe_load_injuries()
  fake <- fake_nflreadr(list(`2023` = list(injury_rows(2023)), `2024` = list(NULL)))
  local_mocked_bindings(load_injuries = fake$load_injuries, clear_cache = fake$clear_cache, .package = "nflreadr")
  res <- run_quietly(env$safe_load_injuries(c(2023, 2024), prefer_fast = FALSE, retries = 2L, retry_wait = 0))
  expect_equal(unique(res$out$season), 2023)
  expect_equal(fake$state$downloads[["2024"]], 3L)
  expect_equal(env$quality$status, "partial")
  expect_equal(env$quality$missing_seasons, "2024")
  expect_true(any(grepl("2024.*3 attempts.*Failed to readRDS", res$messages)), info = paste(res$messages, collapse = "\n"))
})

test_that("every season empty is unavailable, and the cause is printed", {
  env <- load_safe_load_injuries()
  fake <- fake_nflreadr(list(`2024` = list(NULL)))
  local_mocked_bindings(load_injuries = fake$load_injuries, clear_cache = fake$clear_cache, .package = "nflreadr")
  res <- run_quietly(env$safe_load_injuries(2024, prefer_fast = FALSE, retry_wait = 0))
  expect_equal(nrow(res$out), 0)
  expect_equal(env$quality$status, "unavailable")
  expect_true(any(grepl("Failed to readRDS", res$messages)), info = paste(res$messages, collapse = "\n"))
})

test_that("a season that loads the first time is downloaded once", {
  env <- load_safe_load_injuries()
  fake <- fake_nflreadr(list(`2024` = list(injury_rows(2024))))
  local_mocked_bindings(load_injuries = fake$load_injuries, clear_cache = fake$clear_cache, .package = "nflreadr")
  res <- run_quietly(env$safe_load_injuries(2024, prefer_fast = FALSE, retry_wait = 0))
  expect_equal(nrow(res$out), 1)
  expect_equal(fake$state$downloads[["2024"]], 1L)
  expect_equal(env$quality$status, "full")
})
