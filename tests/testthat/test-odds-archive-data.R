# =============================================================================
# Guard on the COMMITTED decision-time archive (backtest/data/odds_archive/, built by
# backtest/build_odds_archive.R). The 2025 Holdout is sealed: no 2025 row may be in it.
# The raw ESPN responses are not committed, so only the derived files are re-hashed here.
# =============================================================================

arch_dir <- file.path(PROJECT_ROOT, "backtest", "data", "odds_archive")
arch_read <- function(name) utils::read.csv(file.path(arch_dir, name), stringsAsFactors = FALSE, na.strings = "")

test_that("the committed archive holds 2023 and 2024 only, with no 2025 row anywhere", {
  src <- jsonlite::read_json(file.path(arch_dir, "SOURCES.json"))
  expect_equal(src$max_season, 2024L)
  expect_setequal(unlist(src$seasons), c(2023L, 2024L))
  arch <- arch_read("espn_game_odds.csv")
  em <- arch_read("event_map.csv")
  expect_true(all(arch$season %in% c(2023L, 2024L)))
  expect_true(all(em$season %in% c(2023L, 2024L)))
  expect_false(any(grepl("^2025_", c(arch$game_id, em$game_id))))
})

test_that("every derived file matches its recorded sha256 and uses LF line endings", {
  expect_equal(odds_archive_verify(arch_dir, NULL), character())
  for (f in c("espn_game_odds.csv", "event_map.csv", "COVERAGE.csv", "SOURCES.json")) {
    bytes <- readBin(file.path(arch_dir, f), "raw", file.size(file.path(arch_dir, f)))
    expect_false(as.raw(13) %in% bytes, info = f)
  }
})

test_that("the archive covers the 570 games of 2023-2024 and every game is a known schedule game", {
  em <- arch_read("event_map.csv")
  expect_equal(nrow(em), 570L)
  expect_equal(as.vector(table(em$season)), c(285L, 285L))
  games <- utils::read.csv(file.path(PROJECT_ROOT, "backtest", "data", "games.csv"), stringsAsFactors = FALSE)
  expect_true(all(em$game_id %in% games$game_id))               # backtest/data/games.csv is hash-locked and stops at 2024
  arch <- arch_read("espn_game_odds.csv")
  expect_true(all(arch$game_id %in% em$game_id))
  expect_equal(sort(unique(arch$venue_id)), "espn_bet")
})

test_that("COVERAGE.csv is exactly what the archive rows imply, and its numbers are the measured ones", {
  arch <- arch_read("espn_game_odds.csv")
  em <- arch_read("event_map.csv")
  snaps <- new_odds_snapshots(data.frame(
    game_id = arch$game_id, market_id = arch$market_id, venue_id = arch$venue_id, side = arch$side,
    line = arch$line, price_american = arch$price_american, snapshot_kind = arch$snapshot_kind,
    source = "espn_core", raw_sha256 = arch$raw_sha256, stringsAsFactors = FALSE))
  games <- data.frame(game_id = em$game_id, season = em$season, stringsAsFactors = FALSE)
  recomputed <- odds_coverage(snaps, games)
  committed <- arch_read("COVERAGE.csv")
  expect_equal(recomputed, committed, ignore_attr = TRUE)
  any_ml <- committed[committed$venue_id == "any" & committed$market_id == "moneyline", ]
  # Measured 2026-10-13: ESPN BET has a close for almost every game but no opener for 2023 weeks 1-5
  expect_equal(any_ml$games_with_open_and_close[any_ml$season == 2023], 205L)
  expect_equal(any_ml$games_with_open_and_close[any_ml$season == 2024], 284L)
})

test_that("the frozen v1 protocol does not hash the archive, and its ESPN input is untouched", {
  win <- jsonlite::read_json(file.path(PROJECT_ROOT, "backtest", "eval_windows", "nfl_games_v1.json"), simplifyVector = TRUE)
  expect_false("odds_archive" %in% names(win$data_sha256))
  expect_identical(digest::digest(file = file.path(PROJECT_ROOT, "backtest", "data", "espn_open_close.csv"), algo = "sha256"),
                   win$data_sha256[["espn_open_close"]])
})
