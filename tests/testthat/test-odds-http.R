# =============================================================================
# Tests: keyless odds HTTP layer (R/odds/http.R)
# No test here touches the network: every fetch goes through a fake fetch function.
# =============================================================================

local_odds_state <- function(env = parent.frame()) {
  odds_http_reset()
  withr::defer(odds_http_reset(), envir = env)
}

# A fetch function that returns the queued responses in order and counts calls
queued_fetch <- function(...) {
  queue <- list(...)
  state <- new.env()
  state$calls <- 0L
  fn <- function(url, cfg) {
    state$calls <- state$calls + 1L
    r <- queue[[min(state$calls, length(queue))]]
    list(status = r$status, body = r$body, error = r$error %||% NA_character_,
         retry_after = r$retry_after %||% NA_real_)
  }
  list(fn = fn, state = state)
}
ok_body <- function(txt = '{"ok":true}') list(status = 200L, body = charToRaw(txt))

test_that("the request settings enforce the owner rules", {
  cfg <- odds_http_config(overrides = list(min_interval_sec = 0.25))
  expect_equal(cfg$min_interval_sec, 1)                   # a faster config is raised to 1 request/second
  expect_equal(cfg$timeout_sec, 20)
  expect_match(cfg$user_agent, "nfl", ignore.case = TRUE)  # truthful: names this project
  expect_match(cfg$user_agent, "research")
  expect_gte(odds_http_config(overrides = list(max_tries = 0))$max_tries, 1L)
})

test_that("requests to one domain are spaced at least one second apart; other domains are independent", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(ok_body())
  cfg <- odds_http_config()
  for (u in c("https://sports.core.api.espn.com/a", "https://site.api.espn.com/b", "https://sports.core.api.espn.com/c")) {
    odds_fetch(u, cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  }
  expect_equal(clock$state$sleeps, c(1, 1))                # espn.com hosts share one budget
  odds_fetch("https://api.elections.kalshi.com/x", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(clock$state$sleeps, c(1, 1))                # kalshi.com has its own
})

test_that("a 429 is retried with backoff and then succeeds", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(list(status = 429L), list(status = 503L), ok_body())
  rec <- odds_fetch("https://example.test/x", odds_http_config(), fetch_fn = f$fn,
                    now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(rec$status, 200L)
  expect_equal(rec$tries, 3L)
  expect_equal(f$state$calls, 3L)
  expect_false(rec$blocked)
  expect_true(all(clock$state$sleeps >= 1))
  expect_true(2 %in% clock$state$sleeps && 4 %in% clock$state$sleeps)   # exponential backoff 2 s, 4 s
})

test_that("Retry-After is honoured and capped", {
  expect_equal(odds_backoff_sec(1, retry_after = 7), 7)
  expect_equal(odds_backoff_sec(1, retry_after = 9999), ODDS_BACKOFF_CAP_SEC)
  expect_equal(odds_backoff_sec(3), 8)
  expect_equal(odds_backoff_sec(20), ODDS_BACKOFF_CAP_SEC)
})

test_that("a network error (no status) is retried, then reported, never guessed", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(list(status = NA_integer_, error = "timeout"))
  rec <- odds_fetch("https://example.test/x", odds_http_config(), fetch_fn = f$fn,
                    now_fn = clock$now, sleep_fn = clock$sleep)
  expect_true(is.na(rec$status))
  expect_equal(f$state$calls, 3L)
  expect_equal(rec$error, "timeout")
  expect_null(rec$body)
})

test_that("a 403 is never retried and blocks the domain for the session", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(list(status = 403L))
  cfg <- odds_http_config()
  rec <- odds_fetch("https://sports.core.api.espn.com/a", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(rec$status, 403L)
  expect_true(rec$blocked)
  expect_equal(f$state$calls, 1L)                          # no retry, no workaround
  again <- odds_fetch("https://site.api.espn.com/b", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(f$state$calls, 1L)                          # the breaker: no second request to espn.com
  expect_true(again$blocked)
  expect_match(again$error, "blocked")
  expect_equal(again$tries, 0L)
})

test_that("a 429 that survives every retry blocks the domain", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(list(status = 429L, retry_after = 3))
  cfg <- odds_http_config()
  rec <- odds_fetch("https://example.test/x", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(f$state$calls, cfg$max_tries)
  expect_true(rec$blocked)
  expect_true(3 %in% clock$state$sleeps)                   # waited the server's Retry-After
  odds_fetch("https://example.test/y", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(f$state$calls, cfg$max_tries)               # nothing more was sent
})

test_that("the raw sha256 is returned and appended to the fetch log, with credentials redacted", {
  local_odds_state()
  clock <- odds_fake_clock()
  log_path <- file.path(withr::local_tempdir(), "logs", "fetch_log.ndjson")
  body <- charToRaw('{"hello":"world"}')
  f <- queued_fetch(list(status = 200L, body = body))
  rec <- odds_fetch("https://example.test/x?apikey=SECRET&page=2", odds_http_config(), fetch_fn = f$fn,
                    log_path = log_path, source = "unit", now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(rec$sha256, digest::digest(body, algo = "sha256", serialize = FALSE))
  expect_equal(rec$bytes, length(body))
  line <- jsonlite::fromJSON(readLines(log_path))
  expect_equal(line$raw_sha256, rec$sha256)
  expect_equal(line$http_status, 200L)
  expect_equal(line$source, "unit")
  expect_equal(line$endpoint_redacted, "https://example.test/x?apikey=REDACTED&page=2")
  expect_false(grepl("SECRET", readLines(log_path)))
  # a failed fetch is logged too, with a null hash
  f2 <- queued_fetch(list(status = 404L))
  odds_fetch("https://example.test/gone", odds_http_config(), fetch_fn = f2$fn, log_path = log_path,
             source = "unit", now_fn = clock$now, sleep_fn = clock$sleep)
  lines <- readLines(log_path)
  expect_length(lines, 2)
  expect_true(is.null(jsonlite::fromJSON(lines[[2]])$raw_sha256))
})

test_that("odds_json returns NULL for a missing or malformed body", {
  expect_null(odds_json(list(body = NULL)))
  expect_null(odds_json(list(body = charToRaw("<html>not json"))))
  expect_equal(odds_json(list(body = charToRaw('{"a":1}')))$a, 1)
})

test_that("the real network call refuses to run inside the default suite", {
  expect_identical(Sys.getenv("NFL_ODDS_FORBID_LIVE"), "1")
  expect_error(odds_http_get("https://example.test/", odds_http_config()), "forbidden")
})

test_that("the realm of a URL is its registrable domain", {
  expect_equal(odds_url_realm("https://sports.core.api.espn.com/v2/x?y=1"), "espn.com")
  expect_equal(odds_url_realm("https://api.elections.kalshi.com/trade-api/v2"), "kalshi.com")
  expect_equal(odds_url_realm("https://example.test/x"), "example.test")
})
