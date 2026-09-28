# =============================================================================
# Tests: raw odds forward capture (R/capture_raw.R)
# =============================================================================
# Fixtures in fixtures/capture/ are trimmed REAL responses captured 2026-09-28
# from the keyless ESPN core API. No test in this file makes a network call.
# =============================================================================

fixture_path <- function(name) {
  testthat::test_path("fixtures", "capture", name)
}

read_fixture_text <- function(name) {
  paste(readLines(fixture_path(name), warn = FALSE), collapse = "\n")
}

test_that("parse_espn_scoreboard returns one row per event with UTC kickoff", {
  events <- parse_espn_scoreboard(read_fixture_text("espn_scoreboard.json"))

  expect_s3_class(events, "data.frame")
  expect_equal(nrow(events), 2)
  expect_setequal(events$event_id, c("401872963", "401872948"))
  expect_s3_class(events$kickoff_utc, "POSIXct")
  expect_equal(attr(events$kickoff_utc, "tzone"), "UTC")

  mnf <- events[events$event_id == "401872963", ]
  expect_equal(format(mnf$kickoff_utc, "%Y-%m-%d %H:%M", tz = "UTC"), "2026-09-29 00:15")
  expect_equal(mnf$status, "STATUS_SCHEDULED")
})

test_that("select_capture_events keeps only unstarted games inside the horizon", {
  events <- parse_espn_scoreboard(read_fixture_text("espn_scoreboard.json"))
  now <- as.POSIXct("2026-09-28 20:53:00", tz = "UTC")

  picked <- select_capture_events(events, now = now, horizon_hours = 36)
  expect_equal(picked$event_id, "401872963")

  # A horizon that ends before kickoff selects nothing
  none <- select_capture_events(events, now = now, horizon_hours = 1)
  expect_equal(nrow(none), 0)

  # After kickoff the game is no longer capturable, even if still "scheduled"
  late <- select_capture_events(events, now = as.POSIXct("2026-09-29 00:16:00", tz = "UTC"),
                                horizon_hours = 36)
  expect_equal(nrow(late), 0)
})

test_that("ESPN URLs are built exactly", {
  expect_equal(
    espn_game_odds_url("401872963"),
    "https://sports.core.api.espn.com/v2/sports/football/leagues/nfl/events/401872963/competitions/401872963/odds"
  )
  expect_equal(
    espn_prop_bets_url("401872963", provider_id = 100, page = 2),
    paste0("https://sports.core.api.espn.com/v2/sports/football/leagues/nfl/events/401872963/",
           "competitions/401872963/odds/100/propBets?limit=1000&page=2")
  )
})

test_that("espn_page_count reads pageCount and defaults to 1", {
  expect_equal(espn_page_count(read_fixture_text("espn_propbets_page1.json")), 2L)
  expect_equal(espn_page_count('{"items": []}'), 1L)
})

test_that("is_nfl_game_series keeps per-game series and drops season-long futures", {
  keep <- c("KXNFLGAME", "KXNFLTD", "KXNFLRECYDS", "KXNFLFIRSTTD", "KXNFLSPREAD", "KXNFL1HTOTAL")
  drop <- c("KXNFLWINS-NO", "KXNFLDRAFT1", "KXNFLMVP", "KXNFLCAREERPASSYDS",
            "KXNFLEXACTWINSBUF", "KXNCAAFSPREAD", "KXNBAGAME", "KXCOACHOUTNFL")
  expect_true(all(is_nfl_game_series(keep)))
  expect_false(any(is_nfl_game_series(drop)))
})

test_that("kalshi_open_markets_url encodes series and cursor", {
  expect_equal(
    kalshi_open_markets_url("KXNFLTD"),
    "https://api.elections.kalshi.com/trade-api/v2/markets?series_ticker=KXNFLTD&status=open&limit=1000"
  )
  expect_equal(
    kalshi_open_markets_url("KXNFLTD", cursor = "a b/c"),
    paste0("https://api.elections.kalshi.com/trade-api/v2/markets?series_ticker=KXNFLTD",
           "&status=open&limit=1000&cursor=a%20b%2Fc")
  )
})

test_that("capture_path is deterministic and partitioned by UTC date and source", {
  at <- as.POSIXct("2026-09-28 20:53:02", tz = "UTC")
  expect_equal(
    capture_path("root", "espn_propbets", at, "401872963_p1"),
    file.path("root", "2026-09-28", "espn_propbets", "401872963_p1__20260928T205302Z.json.gz")
  )
})

test_that("write_capture gzips the body, returns its sha256, and appends a manifest line", {
  root <- withr::local_tempdir()
  body <- charToRaw('{"hello":"world"}')
  at <- as.POSIXct("2026-09-28 20:53:02", tz = "UTC")

  rec <- write_capture(
    root = root, source = "espn_scoreboard", key = "week", captured_at = at,
    url = "https://example.test/x", http_status = 200L, body = body
  )

  expect_true(file.exists(rec$path))
  con <- gzfile(rec$path, "rb")
  on.exit(close(con), add = TRUE)
  expect_identical(readBin(con, "raw", n = 1000), body)
  expect_equal(rec$sha256, digest::digest(body, algo = "sha256", serialize = FALSE))
  expect_equal(rec$bytes, length(body))

  manifest <- file.path(root, "manifest.ndjson")
  lines <- readLines(manifest)
  expect_length(lines, 1)
  entry <- jsonlite::fromJSON(lines[[1]])
  expect_equal(entry$source, "espn_scoreboard")
  expect_equal(entry$sha256, rec$sha256)
  expect_equal(entry$http_status, 200L)
  expect_equal(entry$captured_at, "2026-09-28T20:53:02Z")
})

test_that("write_capture records failed fetches in the manifest without a body file", {
  root <- withr::local_tempdir()
  at <- as.POSIXct("2026-09-28 20:53:02", tz = "UTC")

  rec <- write_capture(
    root = root, source = "kalshi_markets", key = "KXNFLTD_p1", captured_at = at,
    url = "https://example.test/y", http_status = 503L, body = NULL, error = "HTTP 503"
  )

  expect_true(is.na(rec$path))
  entry <- jsonlite::fromJSON(readLines(file.path(root, "manifest.ndjson"))[[1]])
  expect_equal(entry$http_status, 503L)
  expect_equal(entry$error, "HTTP 503")
})
