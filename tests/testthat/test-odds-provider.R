# =============================================================================
# Tests: the provider interface (R/odds/provider.R) and the nflverse provider
# (R/odds/provider_nflverse.R). No network: the schedule comes from a fixture.
# =============================================================================

sched_fixture <- function() utils::read.csv(testthat::test_path("fixtures", "schedules_2024_lines.csv"), stringsAsFactors = FALSE)

# The 2024 fixture has no spread-odds or total columns. The ok-path fixture adds those five
# columns with SYNTHETIC prices and a 46.5 total (not nflverse data), so the ok case is a true
# ok case. The shared CSV is left alone: test-spread-convention.R reads it.
sched_full_fixture <- function() {
  s <- sched_fixture()
  s$home_spread_odds <- -110L
  s$away_spread_odds <- -110L
  s$total_line <- 46.5
  s$over_odds <- -110L
  s$under_odds <- -110L
  s
}

games_of <- function(...) data.frame(game_id = c(...), season = 2024L, stringsAsFactors = FALSE)

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

test_that("a stale result carries the success timestamp, as ok does", {
  r <- odds_result(source = "demo", status = "stale", detail = "partial",
                   now = as.POSIXct(1e9, origin = "1970-01-01", tz = "UTC"))
  expect_equal(r$source_status$last_success_utc, "2001-09-09T01:46:40Z")
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

test_that("a winter (EST) kickoff converts at UTC-5, and an empty gametime is NA", {
  sched <- data.frame(
    game_id = c("a", "b"), season = 2024L, week = 1L, game_type = "REG",
    gameday = c("2024-12-08", "2024-12-08"), gametime = c("13:00", ""),
    home_team = "KC", away_team = "BAL", espn = c("1", "2"), stringsAsFactors = FALSE
  )
  g <- odds_games_from_schedule(sched)
  expect_equal(format(g$kickoff_utc[1], "%Y-%m-%d %H:%M", tz = "UTC"), "2024-12-08 18:00")   # EST is UTC-5
  expect_true(is.na(g$kickoff_utc[2]))
})

test_that("the nflverse provider turns the consensus close into snapshots", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_full_fixture())
  expect_equal(validate_odds_provider(p), character())
  res <- p$game_snapshots(games_of("2024_01_BAL_KC", "2024_01_GB_PHI"))
  s <- res$snapshots
  expect_equal(unique(s$venue_id), "nflverse_consensus")
  expect_equal(unique(s$snapshot_kind), "close")
  expect_true(all(is.na(s$captured_at)))
  expect_equal(nrow(s), 12)                                  # 2 games x (2 moneyline + 2 spread + 2 total)
  ml <- s[s$game_id == "2024_01_BAL_KC" & s$market_id == "moneyline", ]
  expect_equal(ml$price_american[ml$side == "home"], -148L)
  expect_equal(ml$price_american[ml$side == "away"], 124L)
  sp <- s[s$game_id == "2024_01_BAL_KC" & s$market_id == "spread", ]
  expect_equal(sp$line[sp$side == "home"], -3)               # spread_line > 0 means the home team is favoured
  expect_equal(sp$line[sp$side == "away"], 3)
  tot <- s[s$game_id == "2024_01_BAL_KC" & s$market_id == "total", ]
  expect_equal(sort(tot$side), c("over", "under"))
  expect_true(all(tot$line == 46.5))
  expect_equal(res$source_status$status, "ok")
  expect_false(grepl("absent", res$source_status$detail))
  expect_equal(length(unique(s$raw_sha256)), 1)
  expect_match(s$raw_sha256[1], "^[0-9a-f]{64}$")
})

test_that("games the schedule does not have make the result stale, and are never filled", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_full_fixture())
  res <- p$game_snapshots(games_of("2024_01_BAL_KC", "2024_99_AAA_BBB"))
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "2024_99_AAA_BBB")
  expect_true("2024_01_BAL_KC" %in% res$snapshots$game_id)
  expect_false("2024_99_AAA_BBB" %in% res$snapshots$game_id)
  none <- p$game_snapshots(games_of("2024_99_AAA_BBB"))
  expect_equal(none$source_status$status, "unavailable")
})

test_that("a game with no moneyline gets no moneyline rows (M11: a missing market stays missing)", {
  s <- sched_fixture()
  s$home_moneyline[1] <- NA
  s$away_moneyline[1] <- NA
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(games_of(s$game_id[1]))
  expect_false("moneyline" %in% res$snapshots$market_id)
  expect_true("spread" %in% res$snapshots$market_id)
  expect_match(res$source_status$detail, "1 without a moneyline")
})

test_that("a schedule load with no rows is unavailable, not a crash (the network-down shape)", {
  roof_only <- provider_nflverse(load_schedules_fn = function(seasons) data.frame(roof = character()))
  res <- roof_only$game_snapshots(games_of("2024_01_BAL_KC"))
  expect_equal(res$source_status$status, "unavailable")
  expect_equal(nrow(res$snapshots), 0)
  expect_match(res$source_status$detail, "no schedule rows", fixed = TRUE)
  empty <- provider_nflverse(load_schedules_fn = function(seasons) data.frame())
  expect_equal(empty$game_snapshots(games_of("2024_01_BAL_KC"))$source_status$status, "unavailable")
})

test_that("a loader that throws is a failed source, with its message in detail", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) stop("nflverse unreachable"))
  res <- p$game_snapshots(games_of("2024_01_BAL_KC"))
  expect_equal(res$source_status$status, "failed")
  expect_match(res$source_status$detail, "nflverse unreachable", fixed = TRUE)
  expect_equal(nrow(res$snapshots), 0)
})

test_that("nflreadr warnings are captured into detail, not lost", {
  warn_then_empty <- provider_nflverse(load_schedules_fn = function(seasons) {
    warning("download failed for schedules")
    data.frame(roof = character())
  })
  res <- warn_then_empty$game_snapshots(games_of("2024_01_BAL_KC"))
  expect_equal(res$source_status$status, "unavailable")
  expect_match(res$source_status$detail, "download failed for schedules", fixed = TRUE)
})

test_that("warning and error text is collapsed to one line in detail", {
  warn_multiline <- provider_nflverse(load_schedules_fn = function(seasons) {
    warning("download\nfailed   for\n schedules")
    data.frame(roof = character())
  })
  res <- warn_multiline$game_snapshots(games_of("2024_01_BAL_KC"))
  expect_false(grepl("\n", res$source_status$detail, fixed = TRUE))
  expect_match(res$source_status$detail, "download failed for schedules", fixed = TRUE)
  err_multiline <- provider_nflverse(load_schedules_fn = function(seasons) stop("unreachable\nhost   down"))
  res2 <- err_multiline$game_snapshots(games_of("2024_01_BAL_KC"))
  expect_false(grepl("\n", res2$source_status$detail, fixed = TRUE))
  expect_match(res2$source_status$detail, "unreachable host down", fixed = TRUE)
})

test_that("a spread with a price but no line is dropped and counted, never stored line-less", {
  s <- sched_full_fixture()
  s$spread_line[s$game_id == "2024_01_BAL_KC"] <- NA
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(games_of("2024_01_BAL_KC"))
  expect_false("spread" %in% res$snapshots$market_id)
  expect_false(any(is.na(res$snapshots$line[res$snapshots$market_id %in% c("spread", "total")])))
  expect_match(res$source_status$detail, "2 price-only spread/total row(s) dropped", fixed = TRUE)
  expect_equal(res$source_status$status, "stale")
})

test_that("an absent total_line drops its price-only rows and the detail names the count", {
  s <- sched_full_fixture()
  s$total_line <- NULL
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(games_of("2024_01_BAL_KC", "2024_01_GB_PHI"))
  expect_false("total" %in% res$snapshots$market_id)
  expect_false(any(is.na(res$snapshots$line[res$snapshots$market_id %in% c("spread", "total")])))
  expect_match(res$source_status$detail, "4 price-only spread/total row(s) dropped", fixed = TRUE)
  expect_match(res$source_status$detail, "column(s) absent: total_line", fixed = TRUE)
})

test_that("absent price and total columns make the result stale, with the columns named", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_fixture())
  res <- p$game_snapshots(games_of("2024_01_BAL_KC", "2024_01_GB_PHI"))
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "column(s) absent: home_spread_odds, away_spread_odds, total_line, over_odds, under_odds", fixed = TRUE)
  expect_true(nrow(res$snapshots) > 0)
})

test_that("a game with no prices or lines at all is unavailable, not ok", {
  s <- sched_full_fixture()
  bal <- s$game_id == "2024_01_BAL_KC"
  for (nm in c("home_moneyline", "away_moneyline", "spread_line", "home_spread_odds", "away_spread_odds",
               "total_line", "over_odds", "under_odds")) {
    s[[nm]][bal] <- NA
  }
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(games_of("2024_01_BAL_KC"))
  expect_equal(res$source_status$status, "unavailable")
  expect_equal(nrow(res$snapshots), 0)
})

test_that("a requested game with no market rows makes the result stale, and the game is counted", {
  s <- sched_full_fixture()
  bal <- s$game_id == "2024_01_BAL_KC"
  for (nm in c("home_moneyline", "away_moneyline", "spread_line", "home_spread_odds", "away_spread_odds",
               "total_line", "over_odds", "under_odds")) {
    s[[nm]][bal] <- NA
  }
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(games_of("2024_01_BAL_KC", "2024_01_GB_PHI"))
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "1 requested game(s) in the schedule with no market rows", fixed = TRUE)
  expect_false("2024_01_BAL_KC" %in% res$snapshots$game_id)
  expect_true("2024_01_GB_PHI" %in% res$snapshots$game_id)
})

test_that("a requested game with a moneyline and spread but no total is counted as missing a market", {
  s <- sched_full_fixture()
  bal <- s$game_id == "2024_01_BAL_KC"
  s$total_line[bal] <- NA
  s$over_odds[bal] <- NA
  s$under_odds[bal] <- NA
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(games_of("2024_01_BAL_KC", "2024_01_GB_PHI"))
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "1 requested game(s) missing a moneyline, spread or total", fixed = TRUE)
  bal_markets <- res$snapshots$market_id[res$snapshots$game_id == "2024_01_BAL_KC"]
  expect_true(all(c("moneyline", "spread") %in% bal_markets))
})

test_that("raw_sha256 is the same whether one game or two is requested", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_full_fixture())
  one <- p$game_snapshots(games_of("2024_01_BAL_KC"))
  two <- p$game_snapshots(games_of("2024_01_BAL_KC", "2024_01_GB_PHI"))
  expect_equal(one$fetches$raw_sha256, two$fetches$raw_sha256)
  expect_equal(unique(one$snapshots$raw_sha256), one$fetches$raw_sha256)
})

test_that("raw_sha256 does not depend on the locale's collation", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_full_fixture())
  games <- games_of("2024_01_BAL_KC", "2024_01_GB_PHI")
  default_sha <- p$game_snapshots(games)$fetches$raw_sha256
  withr::local_collate("C")
  expect_equal(p$game_snapshots(games)$fetches$raw_sha256, default_sha)
})

test_that("raw_sha256 changes when a loaded price changes", {
  s <- sched_full_fixture()
  before <- provider_nflverse(load_schedules_fn = function(seasons) s)$game_snapshots(games_of("2024_01_BAL_KC"))
  s$home_moneyline[s$game_id == "2024_01_BAL_KC"] <- -150L
  after <- provider_nflverse(load_schedules_fn = function(seasons) s)$game_snapshots(games_of("2024_01_BAL_KC"))
  expect_false(identical(before$fetches$raw_sha256, after$fetches$raw_sha256))
})

test_that("the lineage holds: one fetch row, and every snapshot carries its hash", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_full_fixture())
  res <- p$game_snapshots(games_of("2024_01_BAL_KC", "2024_01_GB_PHI"))
  expect_equal(nrow(res$fetches), 1L)
  expect_equal(res$fetches$key, "nflverse_schedules_2024")
  expect_equal(res$fetches$url, "nflreadr::load_schedules(seasons = c(2024))")
  expect_true(is.na(res$fetches$http_status))
  expect_gt(res$fetches$bytes, 0)
  expect_true(all(res$snapshots$raw_sha256 %in% res$fetches$raw_sha256))
  expect_equal(res$fetches$raw_sha256, res$snapshots$raw_sha256[1])
})

test_that("an unreadable moneyline price drops the whole pair, counted in detail", {
  s <- sched_full_fixture()
  s$home_moneyline[s$game_id == "2024_01_BAL_KC"] <- 0L
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(games_of("2024_01_BAL_KC"))
  expect_false("moneyline" %in% res$snapshots$market_id)
  expect_match(res$source_status$detail, "1 unreadable price", fixed = TRUE)
  expect_equal(res$source_status$status, "stale")
})

test_that("both spread signs come out right: HOU at IND has -3, so the home side gets +3", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_full_fixture())
  res <- p$game_snapshots(games_of("2024_01_HOU_IND"))
  sp <- res$snapshots[res$snapshots$market_id == "spread", ]
  expect_equal(sp$line[sp$side == "home"], 3)     # IND (home) is the underdog by 3
  expect_equal(sp$line[sp$side == "away"], -3)    # HOU (away) gives 3
  ml <- res$snapshots[res$snapshots$market_id == "moneyline", ]
  expect_equal(ml$price_american[ml$side == "home"], 130L)
  expect_equal(ml$price_american[ml$side == "away"], -155L)
})

test_that("odds_fetch_row stores the redacted URL, never the key", {
  rec <- list(url = "https://api.example.com/feed?apiKey=SECRET123&week=1", source = "demo", status = 200L,
              sha256 = strrep("a", 64), bytes = 10L, tries = 1L, blocked = FALSE,
              fetched_at = as.POSIXct(1e9, origin = "1970-01-01", tz = "UTC"))
  row <- odds_fetch_row(rec, key = "k1")
  expect_false(grepl("SECRET123", row$url, fixed = TRUE))
  expect_equal(row$url, odds_redact_url(rec$url))
  expect_match(row$url, "apiKey=REDACTED", fixed = TRUE)
})

test_that("a spread or total line with no price is kept and counted, and makes the result stale (review I-6)", {
  s <- sched_full_fixture()
  s$home_spread_odds[s$game_id == "2024_01_BAL_KC"] <- NA
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(games_of("2024_01_BAL_KC"))
  kept <- res$snapshots[res$snapshots$market_id == "spread" & res$snapshots$side == "home", ]
  expect_equal(nrow(kept), 1)
  expect_true(is.na(kept$price_american))
  expect_match(res$source_status$detail, "1 spread/total line(s) kept without a price", fixed = TRUE)
  expect_equal(res$source_status$status, "stale")
})
