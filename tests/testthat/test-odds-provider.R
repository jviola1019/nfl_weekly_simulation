# =============================================================================
# Tests: the provider interface (R/odds/provider.R) and the nflverse provider
# (R/odds/provider_nflverse.R). No network: the schedule comes from a fixture.
# =============================================================================

sched_fixture <- function() utils::read.csv(testthat::test_path("fixtures", "schedules_2024_lines.csv"), stringsAsFactors = FALSE)

test_that("a provider declares its id, venues and capabilities, and the interface rejects a bad one", {
  p <- new_odds_provider("demo", "kalshi", game_snapshots = function(games, ...) odds_result(source = "demo"))
  expect_s3_class(p, "odds_provider")
  expect_equal(validate_odds_provider(p), character())
  expect_true(is.null(p$prop_snapshots))
  expect_error(new_odds_provider("demo", "nowhere"), "venue")
  expect_error(new_odds_provider("", "kalshi"), "id")
  expect_error(new_odds_provider("demo", "kalshi", game_snapshots = "not a function"), "function")
})

test_that("odds_result carries snapshots, a source_status row and the fetch lineage", {
  r <- odds_result(source = "demo", status = "ok", detail = "fine")
  expect_equal(names(r$source_status), c("source", "status", "last_success_utc", "detail"))
  expect_equal(nrow(r$snapshots), 0)
  contracts <- file.path(PROJECT_ROOT, "contracts", "schema")
  expect_equal(bw_validate_rows(r$source_status, bw_read_schema("source_status", contracts), "source_status"), character())
  expect_error(odds_result(source = "demo", status = "fine"), "status")
  both <- bind_odds_results(list(r, odds_result(source = "other", status = "failed", detail = "HTTP 500")))
  expect_equal(both$source_status$source, c("demo", "other"))
})

test_that("odds_games_from_schedule converts the Eastern kickoff to UTC and never guesses a missing time", {
  sched <- data.frame(
    game_id = c("a", "b"), season = 2024L, week = 1L, game_type = "REG",
    gameday = c("2024-09-08", "2024-09-08"), gametime = c("13:00", NA),
    home_team = "KC", away_team = "BAL", espn = c("1", "2"), stringsAsFactors = FALSE
  )
  g <- odds_games_from_schedule(sched)
  expect_equal(format(g$kickoff_utc[1], "%Y-%m-%d %H:%M", tz = "UTC"), "2024-09-08 17:00")   # EDT is UTC-4
  expect_true(is.na(g$kickoff_utc[2]))
})

test_that("the nflverse provider turns the consensus close into snapshots", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_fixture())
  expect_equal(validate_odds_provider(p), character())
  games <- data.frame(game_id = c("2024_01_BAL_KC", "2024_01_GB_PHI"), season = 2024L, stringsAsFactors = FALSE)
  res <- p$game_snapshots(games)
  s <- res$snapshots
  expect_equal(unique(s$venue_id), "nflverse_consensus")
  expect_equal(unique(s$snapshot_kind), "close")
  expect_true(all(is.na(s$captured_at)))
  expect_equal(nrow(s), 8)                                   # 2 games x (2 moneyline + 2 spread); no total_line column
  ml <- s[s$game_id == "2024_01_BAL_KC" & s$market_id == "moneyline", ]
  expect_equal(ml$price_american[ml$side == "home"], -148L)
  expect_equal(ml$price_american[ml$side == "away"], 124L)
  sp <- s[s$game_id == "2024_01_BAL_KC" & s$market_id == "spread", ]
  expect_equal(sp$line[sp$side == "home"], -3)               # spread_line > 0 means the home team is favoured
  expect_equal(sp$line[sp$side == "away"], 3)
  expect_equal(res$source_status$status, "ok")
  expect_match(res$source_status$detail, "total_line")       # the missing column is reported, not hidden
  expect_equal(length(unique(s$raw_sha256)), 1)
  expect_match(s$raw_sha256[1], "^[0-9a-f]{64}$")
})

test_that("games the schedule does not have are reported as a failure, never filled", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_fixture())
  games <- data.frame(game_id = c("2024_01_BAL_KC", "2024_99_AAA_BBB"), season = 2024L, stringsAsFactors = FALSE)
  res <- p$game_snapshots(games)
  expect_equal(res$source_status$status, "failed")
  expect_match(res$source_status$detail, "2024_99_AAA_BBB")
  expect_false("2024_99_AAA_BBB" %in% res$snapshots$game_id)
  none <- p$game_snapshots(data.frame(game_id = "2024_99_AAA_BBB", season = 2024L, stringsAsFactors = FALSE))
  expect_equal(none$source_status$status, "unavailable")
})

test_that("a game with no moneyline gets no moneyline rows (M11: a missing market stays missing)", {
  s <- sched_fixture()
  s$home_moneyline[1] <- NA
  s$away_moneyline[1] <- NA
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(data.frame(game_id = s$game_id[1], season = 2024L, stringsAsFactors = FALSE))
  expect_false("moneyline" %in% res$snapshots$market_id)
  expect_true("spread" %in% res$snapshots$market_id)
  expect_match(res$source_status$detail, "1 without a moneyline")
})
