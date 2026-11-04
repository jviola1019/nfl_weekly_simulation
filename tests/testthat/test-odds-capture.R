# =============================================================================
# Tests: forward capture through the provider layer (R/odds/capture.R,
# scripts/capture_odds_raw.R, .github/workflows/odds-capture.yml). No network.
# =============================================================================

WEEK4 <- list(year = 2026L, type = 2L, week = 4L)    # the fixture scoreboard is week 3

capture_routes <- function() {
  r <- list()
  r[[espn_scoreboard_url()]] <- file.path("..", "capture", "espn_scoreboard.json")
  r[[espn_scoreboard_url(WEEK4)]] <- list(text = '{"season": {"year": 2026, "type": 2}, "week": {"number": 4}, "events": []}')
  r[[espn_game_odds_url("401872963")]] <- "espn_game_odds_2026_01_NE_SEA.json"
  r[[espn_prop_bets_url("401872963", 100, 1)]] <- file.path("..", "capture", "espn_propbets_page1.json")
  r[[espn_prop_bets_url("401872963", 100, 2)]] <- list(text = '{"pageCount": 2, "items": []}')
  r[[kalshi_series_url()]] <- list(text = '{"series": [{"ticker": "KXNFLTD"}, {"ticker": "KXNFLGAME"}, {"ticker": "KXNFLWINS-NO"}]}')
  r[[kalshi_open_markets_url("KXNFLGAME")]] <- "kalshi_markets_game_live.json"
  r[[kalshi_open_markets_url("KXNFLTD")]] <- "kalshi_markets_td_live.json"
  r
}
capture_cfg <- list(user_agent = "nfl-weekly-simulation/test (research)", timeout_sec = 20, max_tries = 3,
                    min_interval_sec = 0.5, horizon_hours = 36, game_horizon_hours = 216, espn_prop_providers = 100L)
NOW <- as.POSIXct("2026-09-28 20:53:00", tz = "UTC")

# run a pass on a fake network and clock; returns list(summary, fake, clock, root)
capture_run <- function(routes = capture_routes(), cfg = capture_cfg, sources = c("espn", "kalshi"), providers = NULL,
                        now = NOW) {
  odds_http_reset()
  root <- withr::local_tempdir(.local_envir = parent.frame())
  clock <- odds_fake_clock()
  fake <- odds_fake_fetch(routes)
  summary <- run_capture(root, cfg, now = now, sources = sources, fetch_fn = fake$fn, providers = providers,
                         now_fn = clock$now, sleep_fn = clock$sleep)
  list(summary = summary, fake = fake, clock = clock, root = root)
}

test_that("a capture pass stores every raw body with its sha256 and keeps the on-disk layout", {
  odds_http_reset()
  root <- withr::local_tempdir()
  clock <- odds_fake_clock()
  fake <- odds_fake_fetch(capture_routes())
  summary <- run_capture(root, capture_cfg, now = NOW, fetch_fn = fake$fn, now_fn = clock$now, sleep_fn = clock$sleep)

  expect_equal(summary$source, c("espn_scoreboard", "espn_scoreboard", "espn_game_odds", "espn_propbets", "espn_propbets",
                                 "kalshi_series", "kalshi_markets", "kalshi_markets"))
  expect_true(all(summary$status == 200L))
  manifest <- jsonlite::stream_in(file(file.path(root, "manifest.ndjson")), verbose = FALSE)
  expect_equal(nrow(manifest), nrow(summary))
  expect_true(all(file.exists(manifest$path)))
  expect_true(all(grepl("/espn_scoreboard/|/espn_game_odds/|/espn_propbets/|/kalshi_series/|/kalshi_markets/", manifest$path)))
  sb <- manifest[manifest$source == "espn_scoreboard" & manifest$key == "scoreboard", ]
  expect_equal(sb$sha256, digest::digest(readBin(testthat::test_path("fixtures", "capture", "espn_scoreboard.json"), "raw", 1e6),
                                         algo = "sha256", serialize = FALSE))
  expect_equal(fake$state$urls[1], espn_scoreboard_url())
  expect_equal(fake$state$urls[2], espn_scoreboard_url(WEEK4))
  expect_equal(sum(clock$state$sleeps >= 1), length(fake$state$urls) - 2)    # one request per second per domain; 2 domains, so 2 first requests
})

test_that("the configured 0.5 s interval is raised to the 1 request/second floor", {
  r <- capture_run(sources = "espn")
  expect_true(all(r$clock$state$sleeps >= 1))
  expect_false(any(r$clock$state$sleeps == 0.5))
})

test_that("a failed request is recorded in the summary and the manifest; nothing is dropped", {
  routes <- capture_routes()
  routes[[espn_game_odds_url("401872963")]] <- list(status = 404L)
  r <- capture_run(routes, sources = "espn")
  bad <- r$summary[r$summary$source == "espn_game_odds", ]
  expect_equal(bad$status, 404L)
  expect_equal(bad$error, "HTTP 404")
  manifest <- jsonlite::stream_in(file(file.path(r$root, "manifest.ndjson")), verbose = FALSE)
  expect_equal(manifest$http_status[manifest$source == "espn_game_odds"], 404L)
  expect_true(is.na(manifest$sha256[manifest$source == "espn_game_odds"]))
})

test_that("a 403 stops further requests to that domain", {
  routes <- capture_routes()
  routes[[espn_scoreboard_url()]] <- list(status = 403L)
  r <- capture_run(routes, sources = "espn")
  expect_equal(nrow(r$summary), 1)
  expect_equal(length(r$fake$state$urls), 1)
})

test_that("the legacy capture_http_get now runs through the same layer", {
  expect_error(capture_http_get("https://example.test/", "ua", 20, 1, 0.1), "forbidden")
})

# ---- Controller amendments (Task 7) ----

test_that("an empty 200 body is skipped and logged; the pass is not aborted", {
  routes <- capture_routes()
  routes[[espn_scoreboard_url()]] <- list(text = "")           # an empty 200 from the default scoreboard
  routes[[kalshi_open_markets_url("KXNFLTD")]] <- list(text = "")   # and from a market page
  r <- capture_run(routes)
  expect_equal(r$summary$error[r$summary$source == "espn_scoreboard"][1], "empty body")
  td <- r$summary[r$summary$source == "kalshi_markets", ]
  expect_equal(td$error[grepl("KXNFLTD", td$key)], "empty body")
  expect_true(any(r$summary$source == "kalshi_markets" & grepl("KXNFLGAME", r$summary$key) & is.na(r$summary$error)))   # the pass went on
  expect_true(all(r$summary$status == 200L))
})

test_that("discovery reads the default scoreboard AND the next week by number (R4)", {
  routes <- capture_routes()
  routes[[espn_scoreboard_url()]] <- list(text = '{"season": {"year": 2026, "type": 2}, "week": {"number": 3}, "events": [{"id": "1", "name": "A at B", "date": "2026-09-27T00:15Z", "status": {"type": {"name": "STATUS_FINAL"}}}]}')
  routes[[espn_scoreboard_url(WEEK4)]] <- list(text = '{"season": {"year": 2026, "type": 2}, "week": {"number": 4}, "events": [{"id": "701", "name": "C at D", "date": "2026-09-30T00:15Z", "status": {"type": {"name": "STATUS_SCHEDULED"}}}]}')
  routes[[espn_game_odds_url("701")]] <- "espn_game_odds_2026_01_NE_SEA.json"
  # 701 kicks off 27 h after NOW, inside the 36 h prop horizon, so its props are asked for too
  routes[[espn_prop_bets_url("701", 100, 1)]] <- list(text = '{"pageCount": 1, "items": []}')
  r <- capture_run(routes, sources = "espn")
  expect_equal(r$fake$state$urls[1:2], c(espn_scoreboard_url(), espn_scoreboard_url(WEEK4)))
  expect_true(espn_game_odds_url("701") %in% r$fake$state$urls)
  expect_false(espn_game_odds_url("1") %in% r$fake$state$urls)      # a final game is never fetched
})

test_that("a provider whose capture is NULL is skipped and logged (R5)", {
  odds_http_reset()
  nocap <- new_odds_provider("nocap", "kalshi", capture = NULL)
  expect_message(
    r <- capture_run(sources = c("nocap", "kalshi"), providers = list(nocap = nocap, kalshi = provider_kalshi())),
    "nocap.*no capture"
  )
  expect_true(all(r$summary$source %in% c("kalshi_series", "kalshi_markets")))
})

test_that("a 2xx body that is not JSON declares a block: the stop holds for every later request to that domain", {
  routes <- capture_routes()
  routes[[espn_scoreboard_url(WEEK4)]] <- list(text = "<html>Access denied</html>")
  r <- capture_run(routes)
  html <- r$summary[r$summary$source == "espn_scoreboard" & r$summary$key != "scoreboard", ]
  expect_match(html$error, "^blocked: HTTP 200 body is not JSON")
  expect_false(any(grepl("401872963", r$fake$state$urls)))          # no game odds or props after the block
  expect_true(any(r$summary$source == "kalshi_series"))             # a different domain is unaffected
  # a later call in the same session, through odds_fetch, is refused without a request
  later <- odds_fetch(espn_game_odds_url("401872963"), fetch_fn = r$fake$fn)
  expect_true(later$blocked)
  expect_false(espn_game_odds_url("401872963") %in% r$fake$state$urls)
})

test_that("a JSON null body is valid JSON, not a block", {
  routes <- capture_routes()
  routes[[espn_scoreboard_url(WEEK4)]] <- list(text = "null")
  r <- capture_run(routes, sources = "espn")
  expect_true(espn_game_odds_url("401872963") %in% r$fake$state$urls)
})

test_that("odds_declare_blocked stops later fetches to that realm and reports them blocked", {
  odds_http_reset()
  fake <- odds_fake_fetch(capture_routes())
  odds_declare_blocked(espn_scoreboard_url(), 200L)
  rec <- odds_fetch(espn_game_odds_url("401872963"), fetch_fn = fake$fn)
  expect_true(rec$blocked)
  expect_null(rec$body)
  expect_length(fake$state$urls, 0)
})

test_that("the ESPN prop-page loop is capped at 20 pages", {
  routes <- capture_routes()
  routes[[espn_prop_bets_url("401872963", 100, 1)]] <- list(text = '{"pageCount": 50, "items": []}')
  for (p in 2:50) routes[[espn_prop_bets_url("401872963", 100, p)]] <- list(text = '{"pageCount": 50, "items": []}')
  r <- capture_run(routes, sources = "espn")
  expect_equal(sum(r$summary$source == "espn_propbets"), 20)
})

test_that("a season-2025 scoreboard is never turned into game requests (the 2025 holdout is sealed)", {
  routes <- capture_routes()
  sealed <- '{"season": {"year": 2025, "type": 2}, "week": {"number": 3}, "events": [{"id": "250", "name": "A at B", "date": "2026-09-29T00:15Z", "status": {"type": {"name": "STATUS_SCHEDULED"}}}]}'
  routes[[espn_scoreboard_url()]] <- list(text = sealed)
  r <- capture_run(routes, sources = "espn")
  expect_false(any(grepl("/events/", r$fake$state$urls, fixed = TRUE)))
  expect_equal(r$summary$source, "espn_scoreboard")
})

test_that("run_capture stops before any request when a horizon setting is missing", {
  cfg <- capture_cfg
  cfg$game_horizon_hours <- NULL
  odds_http_reset()
  fake <- odds_fake_fetch(capture_routes())
  expect_error(run_capture(withr::local_tempdir(), cfg, now = NOW, sources = "espn", fetch_fn = fake$fn),
               "game_horizon_hours")
  expect_length(fake$state$urls, 0)
})

test_that("scripts/capture_odds_raw.R is a thin caller and the workflow still runs it", {
  script <- readLines(file.path(PROJECT_ROOT, "scripts", "capture_odds_raw.R"), warn = FALSE)
  expect_silent(parse(file.path(PROJECT_ROOT, "scripts", "capture_odds_raw.R")))
  expect_true(any(grepl("run_capture(", script, fixed = TRUE)))
  expect_false(any(grepl("httr2|capture_http_get|req_perform", script)))
  expect_lt(length(script), 80)
  wf <- yaml::read_yaml(file.path(PROJECT_ROOT, ".github", "workflows", "odds-capture.yml"))
  runs <- vapply(wf$jobs$capture$steps, function(s) if (is.null(s$run)) "" else s$run, "")
  expect_true(any(runs == "Rscript scripts/capture_odds_raw.R"))
  installs <- paste(runs, collapse = " ")
  expect_match(installs, "httr2")
  expect_match(installs, "jsonlite")
  expect_match(installs, "digest")
  expect_identical(wf$permissions, list(contents = "read"))
  # everything the script sources exists (the runner has no renv: base R plus the installed packages)
  src <- regmatches(script, gregexpr('"[^"]+\\.R"', script))
  files <- gsub('"', "", unlist(src))
  files <- files[!grepl("^scripts/", files)]
  expect_true(all(file.exists(file.path(PROJECT_ROOT, files))))
})
