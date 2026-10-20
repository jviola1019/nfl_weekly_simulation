# =============================================================================
# Tests: the closing rule (R/odds/closing.R)
# The close is the last snapshot at or before kickoff at the SAME line. A gap of
# more than 60 minutes is flagged stale and kept out of headline CLV. Nothing
# after kickoff is ever a close, and a missing close is never filled in.
# =============================================================================

KICK <- as.POSIXct("2026-10-12 20:15:00", tz = "UTC")
kickoffs <- data.frame(game_id = c("g1", "g2"), kickoff_utc = rep(KICK, 2))

candle <- function(minutes_before_kickoff, bid, ask, line = NA_real_, game_id = "g1", side = "home",
                   market_id = "moneyline", venue_id = "kalshi", kind = "candle") {
  data.frame(
    game_id = game_id, market_id = market_id, venue_id = venue_id, player_key = NA_character_, side = side,
    line = line, price_american = NA_integer_, bid = bid, ask = ask, last = NA_real_, volume = NA_real_,
    captured_at = KICK - minutes_before_kickoff * 60, snapshot_kind = kind, source = "kalshi_live",
    raw_sha256 = "x", stringsAsFactors = FALSE
  )
}
rows <- function(...) new_odds_snapshots(do.call(rbind, list(...)))

test_that("the close is the last snapshot at or before kickoff", {
  s <- rows(candle(180, .40, .42), candle(120, .44, .46), candle(50, .48, .50), candle(0, .49, .51), candle(-30, .90, .92))
  close <- select_closing_snapshots(s, kickoffs)
  expect_equal(nrow(close), 1)
  expect_equal(close$bid, .49)              # the candle ending exactly at kickoff counts
  expect_equal(close$close_gap_min, 0)
  expect_false(close$stale)
  expect_true(close$headline_eligible)
  expect_equal(close$rule_version, ODDS_CLOSE_RULE_VERSION)
  expect_equal(attr(close, "audit")$n_post_kickoff_dropped, 1)
})

test_that("a post-kickoff snapshot is never a close, even when it is the only one", {
  s <- rows(candle(-5, .90, .92))
  close <- select_closing_snapshots(s, kickoffs)
  expect_equal(nrow(close), 0)
  expect_equal(attr(close, "audit")$n_post_kickoff_dropped, 1)
})

test_that("a gap over 60 minutes is stale and not headline eligible; exactly 60 is not stale", {
  at_61 <- select_closing_snapshots(rows(candle(61, .40, .42)), kickoffs)
  expect_equal(at_61$close_gap_min, 61)
  expect_true(at_61$stale)
  expect_false(at_61$headline_eligible)
  at_60 <- select_closing_snapshots(rows(candle(60, .40, .42)), kickoffs)
  expect_false(at_60$stale)
  expect_true(at_60$headline_eligible)
  expect_equal(attr(at_61, "audit")$n_stale, 1)
})

test_that("the close is taken per line: a later snapshot at another line never replaces it", {
  s <- rows(
    candle(90, .50, .52, line = -3, market_id = "spread", venue_id = "kalshi", side = "home"),
    candle(10, .55, .57, line = -3.5, market_id = "spread", venue_id = "kalshi", side = "home")
  )
  close <- select_closing_snapshots(s, kickoffs)
  expect_equal(sort(close$line), c(-3.5, -3))
  hit <- match_close_at_line(close, "g1", "spread", "kalshi", "home", line = -3)
  expect_equal(hit$reason, "ok")
  expect_equal(hit$bid, .50)
  expect_equal(hit$close_gap_min, 90)
  expect_true(hit$stale)                                   # found, but too old for the headline
  miss <- match_close_at_line(close, "g1", "spread", "kalshi", "home", line = -2.5)
  expect_equal(miss$reason, "no_close_at_line")            # no nearest-line substitute
  expect_true(is.na(miss$bid))
  none <- match_close_at_line(close, "g1", "total", "kalshi", "over", line = 45.5)
  expect_equal(none$reason, "no_close")
})

test_that("venues, sides and games close independently", {
  s <- rows(
    candle(30, .40, .42, side = "home"), candle(20, .58, .60, side = "away"),
    candle(45, .10, .12, venue_id = "kalshi", game_id = "g2")
  )
  close <- select_closing_snapshots(s, kickoffs)
  expect_equal(nrow(close), 3)
})

test_that("a labelled close is used only when no timed snapshot exists, and has no gap", {
  labelled <- rows(candle(0, NA, NA, kind = "close", venue_id = "espn_bet"))
  labelled$captured_at <- as.POSIXct(NA, tz = "UTC")
  labelled$price_american <- -150L
  close <- select_closing_snapshots(labelled, kickoffs)
  expect_equal(nrow(close), 1)
  expect_equal(close$timing, "labelled")
  expect_true(is.na(close$close_gap_min))
  expect_false(close$stale)
  expect_true(close$headline_eligible)

  both <- rbind(labelled, rows(candle(25, .40, .42, venue_id = "espn_bet")))
  expect_equal(select_closing_snapshots(both, kickoffs)$timing, "timed")
})

test_that("opening lines are ignored, and games without a kickoff are counted, not guessed", {
  open_row <- rows(candle(0, NA, NA, kind = "open", venue_id = "espn_bet"))
  open_row$captured_at <- as.POSIXct(NA, tz = "UTC")
  open_row$price_american <- -110L
  expect_equal(nrow(select_closing_snapshots(open_row, kickoffs)), 0)
  orphan <- rows(candle(30, .40, .42, game_id = "unknown_game"))
  close <- select_closing_snapshots(orphan, kickoffs)
  expect_equal(nrow(close), 0)
  expect_equal(attr(close, "audit")$n_no_kickoff, 1)
})
