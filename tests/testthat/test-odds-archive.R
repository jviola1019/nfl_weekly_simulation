# =============================================================================
# Tests: the decision-time archive builder (R/odds/archive.R, backtest/build_odds_archive.R)
# The 2025 Holdout is sealed: the builder must refuse 2025 before it makes a request.
# The fixture is a trimmed REAL ESPN response; no test here touches the network.
# =============================================================================

schedule_rows <- function() {
  data.frame(
    game_id = c("2024_01_ARI_BUF", "2023_01_XXX_YYY", "2025_01_AAA_BBB"),
    season = c(2024L, 2023L, 2025L), week = 1L, game_type = "REG",
    gameday = c("2024-09-08", "2023-09-10", "2025-09-07"), gametime = "13:00",
    home_team = c("BUF", "YYY", "BBB"), away_team = c("ARI", "XXX", "AAA"),
    espn = c("401671617", "999", "888"), stringsAsFactors = FALSE
  )
}
# The archive is fetched after its games, so the fake clock starts after them: a close block
# fetched before kickoff is not a close (review I-7)
ARCHIVE_CLOCK_START <- as.numeric(as.POSIXct("2026-10-13 12:00:00", tz = "UTC"))
archive_provider <- function(routes, clock = odds_fake_clock(ARCHIVE_CLOCK_START)) {
  odds_http_reset()
  fake <- odds_fake_fetch(routes)
  list(provider = provider_espn_core(cfg = odds_http_config(), fetch_fn = fake$fn,
                                     now_fn = clock$now, sleep_fn = clock$sleep), fake = fake)
}
archive_routes <- function() {
  setNames(list("espn_game_odds_2024_01_ARI_BUF.json", list(status = 404L)),
           c(espn_game_odds_url("401671617"), espn_game_odds_url("999")))
}
file_sha <- function(path) digest::digest(file = path, algo = "sha256")

test_that("the archive window is 2023 to 2024, and 2025 is refused with the reason", {
  expect_equal(ODDS_ARCHIVE_MAX_SEASON, 2024L)
  expect_equal(odds_archive_assert_seasons(c(2024L, 2023L)), c(2023L, 2024L))
  expect_error(odds_archive_assert_seasons(2025L), "2025 Holdout is sealed")
  expect_error(odds_archive_assert_seasons(c(2023L, 2024L, 2025L)), "refusing season\\(s\\) 2025")
  expect_error(odds_archive_assert_seasons(2026L), "sealed")
  expect_error(odds_archive_assert_seasons(2022L), "before 2023")
  expect_error(odds_archive_assert_seasons(integer()), "integers")
})

test_that("the game list never carries a sealed season, even from a wider schedule", {
  games <- odds_archive_games(schedule_rows(), c(2023L, 2024L))
  expect_equal(games$game_id, c("2023_01_XXX_YYY", "2024_01_ARI_BUF"))      # kickoff order
  expect_false(2025L %in% games$season)
  expect_error(odds_archive_games(schedule_rows(), 2025L), "sealed")
  expect_equal(format(games$kickoff_utc[2], "%Y-%m-%d %H:%M", tz = "UTC"), "2024-09-08 17:00")
})

test_that("odds_archive_build refuses 2025 before any request or file", {
  a <- archive_provider(archive_routes())
  out <- file.path(withr::local_tempdir(), "archive")
  raw <- file.path(withr::local_tempdir(), "raw")
  games_2025 <- odds_games_from_schedule(schedule_rows()[3, ])
  expect_error(odds_archive_build(games_2025, a$provider, out, raw), "2025 Holdout is sealed")
  expect_length(a$fake$state$urls, 0)                                         # no request was made
  expect_false(dir.exists(out))
  mixed <- odds_games_from_schedule(schedule_rows()[c(1, 3), ])
  expect_error(odds_archive_build(mixed, a$provider, out, raw), "sealed")
  expect_length(a$fake$state$urls, 0)
})

test_that("the build script refuses 2025 on the command line without loading a schedule", {
  withr::local_dir(PROJECT_ROOT)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                  c(shQuote("backtest/build_odds_archive.R"), shQuote(withr::local_tempdir()), "--seasons=2023,2025"),
                                  stdout = TRUE, stderr = TRUE))
  expect_gt(attr(out, "status") %||% 0L, 0L)
  expect_match(paste(out, collapse = "\n"), "2025 Holdout is sealed")
})

test_that("coverage counts a market as covered only when both sides of the line are present", {
  s <- new_odds_snapshots(data.frame(
    game_id = c("g1", "g1", "g1", "g2", "g2"), market_id = "moneyline", venue_id = "espn_bet",
    side = c("home", "away", "home", "home", "away"), price_american = c(-110L, 100L, -120L, -110L, 100L),
    snapshot_kind = c("open", "open", "close", "open", "open"), source = "espn_core", raw_sha256 = "x",
    stringsAsFactors = FALSE))
  games <- data.frame(game_id = c("g1", "g2", "g3"), season = 2024L, stringsAsFactors = FALSE)
  cov <- odds_coverage(s, games)
  row <- cov[cov$venue_id == "espn_bet" & cov$market_id == "moneyline", ]
  expect_equal(c(row$games_expected, row$games_with_open, row$games_with_close, row$games_with_open_and_close), c(3, 2, 0, 0))
  expect_equal(cov$games_with_open[cov$venue_id == "any" & cov$market_id == "moneyline"], 2)
  expect_equal(nrow(cov[cov$market_id == "total", ]), 1)                       # the "any" row still reports 0 of 3
})

test_that("a build writes hash-recorded derived files, keeps the raw bodies, and verifies", {
  a <- archive_provider(archive_routes())
  out <- file.path(withr::local_tempdir(), "archive")
  raw <- file.path(withr::local_tempdir(), "raw")
  games <- odds_archive_games(schedule_rows(), c(2023L, 2024L))
  res <- odds_archive_build(games, a$provider, out, raw, built_utc = as.POSIXct("2026-10-13 12:00:00", tz = "UTC"))

  expect_setequal(list.files(out), c("COVERAGE.csv", "SOURCES.json", "event_map.csv", "espn_game_odds.csv"))
  arch <- utils::read.csv(file.path(out, "espn_game_odds.csv"), stringsAsFactors = FALSE)
  expect_equal(names(arch), ODDS_ARCHIVE_COLUMNS)
  expect_equal(nrow(arch), 12)
  expect_equal(unique(arch$season), 2024L)
  expect_false(2025L %in% arch$season)
  src <- jsonlite::read_json(file.path(out, "SOURCES.json"))
  expect_length(src$raw, 1)
  expect_equal(src$raw[[1]]$sha256, digest::digest(odds_fixture_raw("espn_game_odds_2024_01_ARI_BUF.json"), algo = "sha256", serialize = FALSE))
  expect_equal(src$raw[[1]]$file, "espn_game_odds__401671617.json.gz")
  expect_true(file.exists(file.path(raw, src$raw[[1]]$file)))
  expect_length(src$fetch_failures, 1)                                         # the 2023 game's 404 is recorded, not dropped
  expect_equal(src$fetch_failures[[1]]$http_status, 404L)
  expect_equal(src$max_season, 2024L)
  expect_equal(src$built_utc, "2026-10-13T12:00:00Z")
  for (d in src$derived) expect_equal(d$sha256, file_sha(file.path(out, d$file)))
  expect_false(any(grepl("\r", readLines(file.path(out, "espn_game_odds.csv"), warn = FALSE), fixed = TRUE)))
  expect_equal(odds_archive_verify(out, raw), character())
  expect_equal(odds_archive_verify(out, NULL), character())                    # derived files only, as in the committed data test

  cov <- utils::read.csv(file.path(out, "COVERAGE.csv"), stringsAsFactors = FALSE)
  expect_equal(cov$games_with_open_and_close[cov$season == 2024 & cov$venue_id == "espn_bet" & cov$market_id == "moneyline"], 1)
  expect_equal(cov$games_with_open_and_close[cov$season == 2023 & cov$venue_id == "any" & cov$market_id == "moneyline"], 0)

  # tampering is caught
  oa_write_gz(file.path(raw, "espn_game_odds__401671617.json.gz"), charToRaw("{}"))
  expect_match(odds_archive_verify(out, raw), "raw hash differs", all = FALSE)
})

test_that("the archive rebuilds byte for byte from its stored raw responses, offline", {
  a <- archive_provider(archive_routes())
  out1 <- file.path(withr::local_tempdir(), "a")
  out2 <- file.path(withr::local_tempdir(), "b")
  raw <- file.path(withr::local_tempdir(), "raw")
  games <- odds_archive_games(schedule_rows(), c(2023L, 2024L))
  odds_archive_build(games, a$provider, out1, raw)
  odds_http_reset()
  replay <- provider_espn_core(cfg = odds_http_config(), fetch_fn = odds_replay_fetch(raw),
                               now_fn = odds_fake_clock(ARCHIVE_CLOCK_START)$now, sleep_fn = function(s) NULL)
  odds_archive_build(games, replay, out2, raw)
  for (f in c("espn_game_odds.csv", "event_map.csv", "COVERAGE.csv")) {
    expect_identical(file_sha(file.path(out1, f)), file_sha(file.path(out2, f)), info = f)
  }
})

test_that("a replay of the stored raw responses adds nothing to the fetch log", {
  # the fetch log records requests that reached ESPN; a replay reads local files and makes none
  a <- archive_provider(archive_routes())
  out <- file.path(withr::local_tempdir(), "archive")
  raw <- file.path(withr::local_tempdir(), "raw")
  odds_archive_build(odds_archive_games(schedule_rows(), 2024L), a$provider, out, raw)
  log <- file.path(raw, "fetch_log.ndjson")
  writeLines('{"source":"espn_game_odds","http_status":200}', log)          # the live build's one line
  withr::local_dir(PROJECT_ROOT)
  st <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                 c(shQuote("backtest/build_odds_archive.R"), shQuote(raw), "--from-raw",
                                   "--seasons=2024", paste0("--out=", shQuote(out))),
                                 stdout = TRUE, stderr = TRUE))
  expect_equal(attr(st, "status") %||% 0L, 0L, info = paste(st, collapse = "\n"))
  expect_length(readLines(log), 1)
})

block_rows <- function() {
  data.frame(
    game_id = c("2024_01_ARI_BUF", "2024_01_XXA_YYA", "2024_01_XXB_YYB"), season = 2024L, week = 1L, game_type = "REG",
    gameday = c("2024-09-08", "2024-09-08", "2024-09-09"), gametime = c("13:00", "16:25", "20:15"),
    home_team = c("BUF", "YYA", "YYB"), away_team = c("ARI", "XXA", "XXB"),
    espn = c("401671617", "401671618", "401671619"), stringsAsFactors = FALSE
  )
}

test_that("a block mid-build counts every game it never fetched, lists only stored responses, and exits 1 (review I-2)", {
  for (block in list(list(status = 403L), list(status = 200L, text = "<html><body>challenge</body></html>"))) {
    a <- archive_provider(setNames(list("espn_game_odds_2024_01_ARI_BUF.json", block),
                                   c(espn_game_odds_url("401671617"), espn_game_odds_url("401671618"))))
    out <- file.path(withr::local_tempdir(), "archive")
    raw <- file.path(withr::local_tempdir(), "raw")
    res <- odds_archive_build(odds_archive_games(block_rows(), 2024L), a$provider, out, raw)
    src <- jsonlite::read_json(file.path(out, "SOURCES.json"))
    info <- paste("block status", block$status)
    expect_equal(vapply(src$raw, `[[`, "", "file"), "espn_game_odds__401671617.json.gz", info = info)
    expect_setequal(vapply(src$fetch_failures, `[[`, "", "key"), c("401671618", "401671619"))
    never <- Filter(function(x) identical(x$key, "401671619"), src$fetch_failures)[[1]]
    expect_match(never$reason, "never requested", info = info)
    expect_equal(odds_archive_exit_status(res$sources), 1L, info = info)
    expect_equal(odds_archive_verify(out, raw), character(), info = info)   # no "missing raw file" for the block
  }
})

test_that("the build fails only when a game could not be fetched, not for gaps in what ESPN serves", {
  # a stale source status from markets ESPN never posted is reported, not a failure (Task 9 ruling)
  expect_equal(odds_archive_exit_status(list(fetch_failures = list(), source_status = "stale")), 0L)
  expect_equal(odds_archive_exit_status(list(fetch_failures = list(list(key = "999", http_status = 404L)), source_status = "stale")), 1L)
})

test_that("the event map round-trips into the games table", {
  a <- archive_provider(archive_routes())
  out <- file.path(withr::local_tempdir(), "archive")
  games <- odds_archive_games(schedule_rows(), c(2023L, 2024L))
  odds_archive_build(games, a$provider, out, file.path(withr::local_tempdir(), "raw"))
  back <- odds_archive_read_event_map(file.path(out, "event_map.csv"))
  expect_equal(back$game_id, games$game_id)
  expect_equal(back$kickoff_utc, games$kickoff_utc)
  expect_equal(back$espn, games$espn)
})
