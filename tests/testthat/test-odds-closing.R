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

# -----------------------------------------------------------------------------
# Fix round 1 (Task 3 review). These blocks were written and run RED before the
# fix in R/odds/closing.R. The seven blocks above are unchanged.
# -----------------------------------------------------------------------------

# A player-market row. The brief's candle() leaves player_key NA, which a player market must not be.
prow <- function(minutes_before_kickoff, market_id, side, player_key, bid, ask, line = NA_real_,
                 venue_id = "kalshi", kind = "candle") {
  data.frame(
    game_id = "g1", market_id = market_id, venue_id = venue_id, player_key = player_key, side = side,
    line = line, price_american = NA_integer_, bid = bid, ask = ask, last = NA_real_, volume = NA_real_,
    captured_at = KICK - minutes_before_kickoff * 60, snapshot_kind = kind, source = "kalshi_live",
    raw_sha256 = "x", stringsAsFactors = FALSE
  )
}

test_that("A0: a row exactly at kickoff is a close; one second after kickoff is dropped, whatever its kind", {
  at <- rows(candle(0, .49, .51, kind = "close"))
  expect_equal(nrow(select_closing_snapshots(at, kickoffs)), 1)
  after <- rows(candle(0, .49, .51, kind = "close"))
  after$captured_at <- KICK + 1
  res <- select_closing_snapshots(after, kickoffs)
  expect_equal(nrow(res), 0)
  expect_equal(attr(res, "audit")$n_post_kickoff_dropped, 1)
})

test_that("A1: a close-kind row stamped after kickoff is dropped and counted, and is never returned", {
  res <- select_closing_snapshots(rows(candle(-60, .30, .32, kind = "close")), kickoffs)
  expect_equal(nrow(res), 0)
  expect_equal(attr(res, "audit")$n_post_kickoff_dropped, 1)
})

test_that("A2: a close-kind row stamped before kickoff is timed, with a gap, and stale past 60 minutes", {
  res <- select_closing_snapshots(rows(candle(300, .30, .32, kind = "close")), kickoffs)
  expect_equal(nrow(res), 1)
  expect_equal(res$timing, "timed")
  expect_equal(res$close_gap_min, 300)
  expect_true(res$stale)
  expect_false(res$headline_eligible)
})

test_that("C: a timed-kind row with no time is rejected on entry, so it can never become a headline row", {
  bad <- candle(30, .40, .42, kind = "observed")
  bad$captured_at <- as.POSIXct(NA, tz = "UTC")
  expect_error(select_closing_snapshots(bad, kickoffs), "need a time")
})

test_that("kickoffs must be POSIXct, and each game_id may appear once", {
  s <- rows(candle(30, .40, .42))
  text_kickoffs <- data.frame(game_id = c("g1", "g2"),
                              kickoff_utc = c("2026-10-12 20:15:00", "2026-10-12 20:15:00"),
                              stringsAsFactors = FALSE)
  expect_error(select_closing_snapshots(s, text_kickoffs), "POSIXct")
  dup_kickoffs <- rbind(kickoffs, data.frame(game_id = "g1", kickoff_utc = KICK))
  expect_error(select_closing_snapshots(s, dup_kickoffs), "duplicate kickoff game_id.*g1")
})

test_that("one line identity: -0 and 0 are one line, and the freshest pre-kickoff close is the one kept", {
  s <- rows(
    candle(90, .50, .52, line = -0, market_id = "spread", side = "home"),
    candle(10, .55, .57, line = 0, market_id = "spread", side = "home")
  )
  close <- select_closing_snapshots(s, kickoffs)
  expect_equal(nrow(close), 1)
  expect_equal(close$bid, .55)
  expect_equal(close$close_gap_min, 10)
  expect_equal(match_close_at_line(close, "g1", "spread", "kalshi", "home", line = -0)$reason, "ok")
  expect_equal(match_close_at_line(close, "g1", "spread", "kalshi", "home", line = 0)$bid, .55)
})

test_that("the matcher never reports ok for an NA identity field; a moneyline query with line NA still matches", {
  closes <- select_closing_snapshots(rows(candle(30, .40, .42)), kickoffs)
  expect_error(match_close_at_line(closes, NA_character_, "moneyline", "kalshi", "home", NA_real_), "game_id")
  expect_error(match_close_at_line(closes, "g1", NA_character_, "kalshi", "home", NA_real_), "market_id")
  expect_error(match_close_at_line(closes, "g1", "moneyline", NA_character_, "home", NA_real_), "venue_id")
  expect_error(match_close_at_line(closes, "g1", "moneyline", "kalshi", NA_character_, NA_real_), "side")
  hit <- match_close_at_line(closes, "g1", "moneyline", "kalshi", "home", line = NA_real_)
  expect_equal(hit$reason, "ok")
  expect_equal(hit$bid, .40)
})

test_that("a player market with no player, and a line market with no line, stop", {
  closes <- select_closing_snapshots(rows(
    prow(20, "anytime_td", "yes", "kalshi:p1", .30, .32),
    candle(20, .10, .12, market_id = "spread", line = -3)
  ), kickoffs)
  expect_error(match_close_at_line(closes, "g1", "anytime_td", "kalshi", "yes", line = NA_real_,
                                   player_key = NA_character_), "player_key")
  expect_error(match_close_at_line(closes, "g1", "spread", "kalshi", "home", line = NA_real_), "line")
  expect_equal(match_close_at_line(closes, "g1", "anytime_td", "kalshi", "yes", line = NA_real_,
                                   player_key = "kalshi:p1")$reason, "ok")
})

test_that("a second venue for the same game, side and market closes independently of the first", {
  book <- candle(40, NA, NA, venue_id = "espn_bet", kind = "observed")
  book$price_american <- -150L
  close <- select_closing_snapshots(rows(candle(30, .40, .42), book), kickoffs)
  expect_equal(nrow(close), 2)
  expect_equal(sort(close$venue_id), c("espn_bet", "kalshi"))
  expect_equal(match_close_at_line(close, "g1", "moneyline", "espn_bet", "home", line = NA_real_)$price_american, -150L)
  expect_equal(match_close_at_line(close, "g1", "moneyline", "kalshi", "home", line = NA_real_)$bid, .40)
})

test_that("venue, side, player and market each separate the matches", {
  closes <- select_closing_snapshots(rows(
    candle(30, .40, .42, side = "home"),
    candle(30, .58, .60, side = "away"),
    candle(20, .10, .12, market_id = "spread", line = -3, side = "home"),
    prow(20, "anytime_td", "yes", "kalshi:p1", .30, .32),
    prow(25, "anytime_td", "yes", "kalshi:p2", .10, .12),
    prow(15, "passing_yards", "yes", "kalshi:p1", .50, .52, line = 250.5),
    prow(15, "passing_yards", "line", "kalshi:p1", NA_real_, NA_real_, line = 250.5)
  ), kickoffs)
  expect_equal(nrow(closes), 7)
  m <- function(market_id, venue_id, side, line = NA_real_, player_key = NA_character_) {
    match_close_at_line(closes, "g1", market_id, venue_id, side, line = line, player_key = player_key)
  }
  expect_equal(m("moneyline", "kalshi", "home")$bid, .40)
  expect_equal(m("moneyline", "kalshi", "away")$bid, .58)
  expect_equal(m("moneyline", "espn_bet", "home")$reason, "no_close")
  expect_equal(m("spread", "kalshi", "home", line = -3)$bid, .10)
  expect_equal(m("spread", "kalshi", "away", line = -3)$reason, "no_close")
  expect_equal(m("spread", "kalshi", "home", line = -3.5)$reason, "no_close_at_line")
  expect_equal(m("anytime_td", "kalshi", "yes", player_key = "kalshi:p1")$bid, .30)
  expect_equal(m("anytime_td", "kalshi", "yes", player_key = "kalshi:p2")$bid, .10)
  expect_equal(m("anytime_td", "kalshi", "yes", player_key = "kalshi:p3")$reason, "no_close")
  expect_equal(m("passing_yards", "kalshi", "yes", line = 250.5, player_key = "kalshi:p1")$bid, .50)
  expect_equal(m("passing_yards", "kalshi", "line", line = 250.5, player_key = "kalshi:p1")$reason, "ok")
  expect_equal(m("passing_yards", "kalshi", "line", line = 251.5, player_key = "kalshi:p1")$reason, "no_close_at_line")
  expect_equal(m("moneyline", "kalshi", "home", player_key = "kalshi:p1")$reason, "no_close")
})

test_that("for a deterministic mix of valid rows: no close is after kickoff, each key keeps its freshest pre-kickoff row, and the audit adds up", {
  i <- seq_len(480)
  combos <- list(
    list("moneyline", "home", NA_real_, NA_character_),
    list("moneyline", "away", NA_real_, NA_character_),
    list("spread", "home", -3, NA_character_),
    list("spread", "away", 3, NA_character_),
    list("anytime_td", "yes", NA_real_, "kalshi:p1"),
    list("passing_yards", "line", 250.5, "kalshi:p2")
  )
  # each pick meets every kind, both venues and both timed and untimed rows
  pick <- (i %% 6) + 1
  kind <- c("open", "close", "observed", "candle")[((i %/% 6) %% 4) + 1]
  venue <- ifelse((i %/% 24) %% 2 == 0, "kalshi", "espn_bet")
  timed <- kind %in% c("observed", "candle") | (i %% 5 < 3)
  mins <- ((i * 37) %% 480) - 120
  kalshi <- venue == "kalshi"
  bid <- round(0.05 + ((i * 13) %% 85) / 100, 2)
  snaps <- new_odds_snapshots(data.frame(
    game_id = "g1",
    market_id = vapply(pick, function(k) combos[[k]][[1]], ""),
    venue_id = venue,
    player_key = vapply(pick, function(k) combos[[k]][[4]], ""),
    side = vapply(pick, function(k) combos[[k]][[2]], ""),
    line = vapply(pick, function(k) combos[[k]][[3]], 0),
    price_american = ifelse(kalshi, NA_integer_, -110L),
    bid = ifelse(kalshi, bid, NA_real_),
    ask = ifelse(kalshi, pmin(bid + 0.02, 0.99), NA_real_),
    last = NA_real_, volume = NA_real_,
    captured_at = .POSIXct(ifelse(timed, as.numeric(KICK) - mins * 60, NA_real_), tz = "UTC"),
    snapshot_kind = kind, source = "kalshi_live", raw_sha256 = "x", stringsAsFactors = FALSE
  ))
  out <- select_closing_snapshots(snaps, kickoffs)
  audit <- attr(out, "audit")
  after <- !is.na(snaps$captured_at) & snaps$captured_at > KICK
  cand <- snaps[snaps$snapshot_kind != "open" & !after, , drop = FALSE]
  ckey <- odds_snapshot_key(cand)
  okey <- odds_snapshot_key(out)
  expect_false(any(out$timing == "timed" & out$captured_at > KICK, na.rm = TRUE))
  expect_equal(sort(okey), sort(unique(ckey)))
  has_time <- tapply(!is.na(cand$captured_at), ckey, any)
  latest <- tapply(as.numeric(cand$captured_at), ckey,
                   function(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE))
  expect_equal(out$timing == "timed", as.vector(has_time[okey]))
  expect_equal(as.numeric(out$captured_at), as.vector(latest[okey]))
  expect_equal(audit$n_post_kickoff_dropped, sum(after))
  expect_equal(audit$n_open_ignored, sum(snaps$snapshot_kind == "open" & !after))
  expect_equal(nrow(snaps), audit$n_post_kickoff_dropped + audit$n_open_ignored + nrow(cand))
})
