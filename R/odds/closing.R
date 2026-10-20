# =============================================================================
# The closing rule (roadmap D1; spec Phase 2)
# =============================================================================
# The close of a (game, market, venue, player, side) at one line is the last
# snapshot at or before kickoff at that same line:
#   - a snapshot after kickoff is never a close (it is counted in the audit)
#   - the line is part of the key, so a later snapshot at another line does not
#     replace the close, and a pick with no close at its line gets none
#     (match_close_at_line says so; it never takes the nearest line)
#   - a gap of more than 60 minutes between the close and kickoff is `stale` and
#     is not eligible for headline CLV
#   - a venue's labelled close (snapshot_kind "close", no timestamp) is used only
#     when no timed snapshot exists; it has no gap, so it is never stale, and its
#     timing is reported as "labelled"
# Opening lines are ignored here. The rule is price-agnostic: Kalshi's close is
# the mid of the returned bid and ask, a sportsbook's is price_american.
# =============================================================================

ODDS_CLOSE_RULE_VERSION <- "close-v1"
ODDS_CLOSE_STALE_MIN <- 60

odds_line_key <- function(line) ifelse(is.na(line), "NA", formatC(line, format = "f", digits = 3))

odds_snapshot_key <- function(df) {
  paste(df$game_id, df$market_id, df$venue_id, ifelse(is.na(df$player_key), "", df$player_key),
        df$side, odds_line_key(df$line), sep = "|")
}

#' Select the close of every (game, market, venue, player, side, line).
#' @param snaps odds_snapshots table
#' @param kickoffs data.frame(game_id, kickoff_utc [POSIXct UTC])
#' @return data.frame, one row per close, with attr "audit" (counts of what was set aside)
select_closing_snapshots <- function(snaps, kickoffs, stale_after_min = ODDS_CLOSE_STALE_MIN) {
  stopifnot(all(c("game_id", "kickoff_utc") %in% names(kickoffs)))
  n_input <- nrow(snaps)
  s <- snaps
  s$.idx <- seq_len(n_input)
  s$kickoff_utc <- kickoffs$kickoff_utc[match(s$game_id, kickoffs$game_id)]
  no_kickoff <- is.na(s$kickoff_utc)
  timed <- s$snapshot_kind %in% ODDS_TIMED_KINDS
  post_kickoff <- timed & !no_kickoff & s$captured_at > s$kickoff_utc
  is_open <- s$snapshot_kind == "open"
  keep <- !no_kickoff & !is_open & !post_kickoff
  e <- s[keep, , drop = FALSE]

  if (nrow(e) > 0) {
    e$timing <- ifelse(e$snapshot_kind %in% ODDS_TIMED_KINDS, "timed", "labelled")
    e$.key <- odds_snapshot_key(e)
    when <- ifelse(is.na(e$captured_at), -Inf, as.numeric(e$captured_at))
    ord <- order(e$.key, e$timing != "timed", -when, -e$.idx)
    e <- e[ord, , drop = FALSE]
    e <- e[!duplicated(e$.key), , drop = FALSE]
    e$close_gap_min <- ifelse(e$timing == "timed",
                              as.numeric(difftime(e$kickoff_utc, e$captured_at, units = "mins")), NA_real_)
    e$stale <- e$timing == "timed" & e$close_gap_min > stale_after_min
    e$headline_eligible <- !e$stale
    e$rule_version <- ODDS_CLOSE_RULE_VERSION
    cols <- c(setdiff(ODDS_SNAPSHOT_COLUMNS, c("source", "raw_sha256")), "timing", "close_gap_min", "stale",
              "headline_eligible", "rule_version", "source", "raw_sha256")
    e <- e[order(e$.key), cols, drop = FALSE]
  } else {
    e <- data.frame(
      odds_snapshots_empty()[, setdiff(ODDS_SNAPSHOT_COLUMNS, c("source", "raw_sha256"))],
      timing = character(), close_gap_min = numeric(), stale = logical(), headline_eligible = logical(),
      rule_version = character(), source = character(), raw_sha256 = character(), stringsAsFactors = FALSE
    )
  }
  rownames(e) <- NULL
  attr(e, "audit") <- data.frame(
    n_input = n_input, n_no_kickoff = sum(no_kickoff), n_post_kickoff_dropped = sum(post_kickoff),
    n_open_ignored = sum(is_open & !no_kickoff), n_closes = nrow(e), n_stale = sum(e$stale)
  )
  e
}

#' The close for one pick, at exactly its line.
#' @return one row of `closes` plus `reason`: "ok"; "no_close_at_line" when the key has
#'   closes only at other lines; "no_close" when it has none. Non-ok rows are NA-filled.
match_close_at_line <- function(closes, game_id, market_id, venue_id, side, line, player_key = NA_character_) {
  same_key <- closes$game_id == game_id & closes$market_id == market_id & closes$venue_id == venue_id &
    closes$side == side &
    ifelse(is.na(closes$player_key), "", closes$player_key) == ifelse(is.na(player_key), "", player_key)
  same_line <- if (is.na(line)) is.na(closes$line) else (!is.na(closes$line) & abs(closes$line - line) < 1e-9)
  hit <- closes[same_key & same_line, , drop = FALSE]
  if (nrow(hit) > 0) {
    hit <- hit[1, , drop = FALSE]
    hit$reason <- "ok"
    return(hit)
  }
  blank <- closes[NA_integer_, , drop = FALSE][1, , drop = FALSE]
  rownames(blank) <- NULL
  blank$game_id <- game_id
  blank$market_id <- market_id
  blank$venue_id <- venue_id
  blank$side <- side
  blank$line <- line
  blank$reason <- if (any(same_key)) "no_close_at_line" else "no_close"
  blank
}
