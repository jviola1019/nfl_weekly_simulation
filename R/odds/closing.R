# =============================================================================
# The closing rule (roadmap D1; spec Phase 2)
# =============================================================================
# The close of a (game, market, venue, player, side) at one line is the last
# snapshot at or before kickoff at that same line:
#   - a row is classed by whether it has a time, never by its kind: a row with a
#     captured_at is "timed", and a row without one is "labelled"
#   - a row with a time strictly after kickoff is never a close, whatever its
#     kind; it is dropped and counted in the audit (n_post_kickoff_dropped)
#   - the line is part of the key, so a later snapshot at another line does not
#     replace the close, and a pick with no close at its line gets none
#     (match_close_at_line says so; it never takes the nearest line)
#   - a line has one identity (odds_line_canon): rounded to 3 decimals, with -0
#     read as 0; the close key and the matcher both use it
#   - a gap of more than 60 minutes between a timed close and kickoff is `stale`
#     and is not eligible for headline CLV; every timed row has a gap
#   - a venue's labelled close (no timestamp) is used only when no timed snapshot
#     exists; it has no gap, so it is never stale, and its timing is "labelled"
# Opening lines are ignored here. The rule is price-agnostic: Kalshi's close is
# the mid of the returned bid and ask, a sportsbook's is price_american.
# Inputs are checked on entry: the snapshots must pass validate_odds_snapshots(),
# kickoff_utc must be POSIXct, and each game_id may appear once in kickoffs. A pick
# with an NA where its identity needs a value stops (match_close_at_line).
# =============================================================================

ODDS_CLOSE_RULE_VERSION <- "close-v1"
ODDS_CLOSE_STALE_MIN <- 60

#' The one identity of a line: rounded to 3 decimals, with -0 read as 0
odds_line_canon <- function(line) {
  x <- round(as.numeric(line), 3)
  x[!is.na(x) & x == 0] <- 0
  x
}

#' The text key of a line: "NA" for no line, otherwise the canonical line
odds_line_key <- function(line) {
  ifelse(is.na(line), "NA", formatC(odds_line_canon(line), format = "f", digits = 3))
}

odds_snapshot_key <- function(df) {
  paste(df$game_id, df$market_id, df$venue_id, ifelse(is.na(df$player_key), "", df$player_key),
        df$side, odds_line_key(df$line), sep = "|")
}

#' Stops unless the snapshots and the kickoffs can be used for the closing rule
odds_close_check_inputs <- function(snaps, kickoffs) {
  problems <- validate_odds_snapshots(snaps)
  if (length(problems)) {
    stop("select_closing_snapshots: invalid odds_snapshots:\n  ", paste(problems, collapse = "\n  "), call. = FALSE)
  }
  if (!all(c("game_id", "kickoff_utc") %in% names(kickoffs))) {
    stop("select_closing_snapshots: kickoffs needs game_id and kickoff_utc", call. = FALSE)
  }
  if (!inherits(kickoffs$kickoff_utc, "POSIXct")) {
    stop("select_closing_snapshots: kickoffs$kickoff_utc must be POSIXct (UTC)", call. = FALSE)
  }
  dup <- unique(kickoffs$game_id[duplicated(kickoffs$game_id)])
  if (length(dup)) {
    stop("select_closing_snapshots: duplicate kickoff game_id(s): ", paste(dup, collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

#' Select the close of every (game, market, venue, player, side, line).
#' @param snaps odds_snapshots table, checked by validate_odds_snapshots on entry
#' @param kickoffs data.frame(game_id, kickoff_utc [POSIXct UTC]), one row per game_id
#' @return data.frame, one row per close, with attr "audit": n_input, n_no_kickoff,
#'   n_post_kickoff_dropped and n_open_ignored (each input row is counted in exactly one
#'   of these, or is a candidate close), n_closes and n_stale
select_closing_snapshots <- function(snaps, kickoffs, stale_after_min = ODDS_CLOSE_STALE_MIN) {
  odds_close_check_inputs(snaps, kickoffs)
  n_input <- nrow(snaps)
  s <- snaps
  s$.idx <- seq_len(n_input)
  s$kickoff_utc <- kickoffs$kickoff_utc[match(s$game_id, kickoffs$game_id)]
  no_kickoff <- is.na(s$kickoff_utc)
  # a time after kickoff drops the row whatever its kind; a row with no time cannot be after kickoff
  post_kickoff <- !no_kickoff & !is.na(s$captured_at) & s$captured_at > s$kickoff_utc
  is_open <- s$snapshot_kind == "open"
  keep <- !no_kickoff & !post_kickoff & !is_open
  e <- s[keep, , drop = FALSE]

  if (nrow(e) > 0) {
    e$timing <- ifelse(is.na(e$captured_at), "labelled", "timed")
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
    n_open_ignored = sum(is_open & !no_kickoff & !post_kickoff), n_closes = nrow(e), n_stale = sum(e$stale)
  )
  e
}

#' The close for one pick, at exactly its line.
#' The pick's game_id, market_id, venue_id and side must be given. A player market also needs
#' its player_key, and a market with lines (outcome_kind "line": spread, total, and the yards and
#' receptions markets) needs its line; a moneyline or other yes/no query may give line NA. An NA
#' where the pick needs a value stops, so the matcher never reports "ok" for a query it cannot match.
#' @return one row of `closes` plus `reason`: "ok"; "no_close_at_line" when the key has
#'   closes only at other lines; "no_close" when it has none. Non-ok rows are NA-filled.
match_close_at_line <- function(closes, game_id, market_id, venue_id, side, line, player_key = NA_character_) {
  if (length(line) != 1) stop("match_close_at_line: line must be one value", call. = FALSE)
  ids <- list(game_id = game_id, market_id = market_id, venue_id = venue_id, side = side)
  bad <- names(ids)[vapply(ids, function(v) length(v) != 1 || is.na(v) || !nzchar(v), logical(1))]
  if (!length(bad)) {
    catalog <- odds_markets_catalog()
    m <- match(market_id, catalog$market_id)
    if (!is.na(m) && catalog$scope[m] == "player" &&
        (length(player_key) != 1 || is.na(player_key) || !nzchar(player_key))) {
      bad <- c(bad, "player_key")
    }
    if (!is.na(m) && catalog$outcome_kind[m] == "line" && is.na(line)) bad <- c(bad, "line")
  }
  if (length(bad)) {
    stop(sprintf("match_close_at_line: NA where the pick needs a value (%s)", paste(bad, collapse = ", ")),
         call. = FALSE)
  }
  same_key <- closes$game_id == game_id & closes$market_id == market_id & closes$venue_id == venue_id &
    closes$side == side &
    ifelse(is.na(closes$player_key), "", closes$player_key) == ifelse(is.na(player_key), "", player_key)
  same_line <- odds_line_key(closes$line) == odds_line_key(line)
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
