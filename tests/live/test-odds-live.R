# =============================================================================
# LIVE smoke tests for the keyless odds layer. NOT part of the default suite:
# scripts/run_tests.R runs tests/testthat only. Run with
#   Rscript scripts/odds_live_smoke.R
# (or the manual "Odds live smoke" workflow). Each test skips as LIVE only after a real
# connectivity check to its host fails (helper-live.R). They make a handful of requests at
# 1 request/second and compare the live responses with the recorded fixtures, so API drift
# shows up here and not in the default suite.
# =============================================================================

test_that("LIVE: ESPN core still returns the 2024 week 1 open and close lines we recorded", {
  skip_live("sports.core.api.espn.com")
  odds_http_reset()
  game <- data.frame(game_id = "2024_01_ARI_BUF", season = 2024L, espn = "401671617", stringsAsFactors = FALSE)
  res <- with_live("sports.core.api.espn.com", provider_espn_core()$game_snapshots(game))
  expect_equal(res$source_status$status, "ok")
  recorded <- parse_espn_game_odds(odds_fixture_json("espn_game_odds_2024_01_ARI_BUF.json"), "2024_01_ARI_BUF", "x")
  key <- function(d) d[order(d$venue_id, d$market_id, d$side, d$snapshot_kind), c("venue_id", "market_id", "side", "snapshot_kind", "line", "price_american")]
  expect_equal(key(res$snapshots), key(recorded), ignore_attr = TRUE)
})

test_that("LIVE: Kalshi still serves the historical cutoff and a game-market listing", {
  skip_live("api.elections.kalshi.com")
  odds_http_reset()
  rec <- with_live("api.elections.kalshi.com", odds_fetch(kalshi_cutoff_url(), odds_http_config(), source = "kalshi_cutoff"))
  expect_equal(rec$status, 200L)
  expect_false(is.null(odds_json(rec)$market_settled_ts))
  rec2 <- with_live("api.elections.kalshi.com",
                    odds_fetch(kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLAR", historical = FALSE), odds_http_config(), source = "kalshi_markets"))
  expect_equal(rec2$status, 200L)
  expect_gte(length(odds_json(rec2)$markets), 2L)
})
