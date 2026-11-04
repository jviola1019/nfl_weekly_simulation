# =============================================================================
# Odds-layer test helpers (roadmap D1)
# =============================================================================
# The default suite never touches the network for odds: this sets the guard that
# makes odds_http_get() refuse to run, and offers a fake fetch function that
# serves recorded JSON fixtures from tests/testthat/fixtures/odds/. Live checks
# live in tests/live/ and run only through scripts/odds_live_smoke.R.
# =============================================================================

Sys.setenv(NFL_ODDS_FORBID_LIVE = "1")

odds_fixture_path <- function(...) testthat::test_path("fixtures", "odds", ...)

odds_fixture_raw <- function(name) {
  path <- odds_fixture_path(name)
  readBin(path, "raw", n = file.size(path))
}

odds_fixture_json <- function(name) {
  jsonlite::fromJSON(rawToChar(odds_fixture_raw(name)), simplifyVector = FALSE)
}

#' A fetch function for odds_fetch()/the providers that serves fixtures by URL.
#' `routes` maps a full URL to a fixture file name, or to list(status =, file =,
#' text =, retry_after =); `text` serves an inline body. An unknown URL is an error,
#' so a test can never reach out by accident.
#' @return list(fn = fetch function, state = environment with `urls`, the URLs requested)
odds_fake_fetch <- function(routes) {
  state <- new.env()
  state$urls <- character()
  fn <- function(url, cfg) {
    state$urls <- c(state$urls, url)
    hit <- routes[[url]]
    if (is.null(hit)) stop("odds_fake_fetch: no fixture route for ", url, call. = FALSE)
    if (is.character(hit)) hit <- list(status = 200L, file = hit)
    body <- if (!is.null(hit$file)) odds_fixture_raw(hit$file) else if (!is.null(hit$text)) charToRaw(hit$text) else NULL
    list(status = as.integer(hit$status %||% 200L), body = body,
         error = if ((hit$status %||% 200L) >= 400) sprintf("HTTP %d", hit$status) else NA_character_,
         retry_after = hit$retry_after %||% NA_real_)
  }
  list(fn = fn, state = state)
}

#' A deterministic clock: now() and a sleep() that advances it and records each wait
odds_fake_clock <- function(start = 1e9) {
  state <- new.env()
  state$t <- start
  state$sleeps <- numeric()
  list(
    now = function() as.POSIXct(state$t, origin = "1970-01-01", tz = "UTC"),
    sleep = function(s) {
      state$sleeps <- c(state$sleeps, s)
      state$t <- state$t + s
    },
    state = state
  )
}
