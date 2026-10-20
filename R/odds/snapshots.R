# =============================================================================
# The odds_snapshots shape, and the market / venue vocabulary (roadmap D1)
# =============================================================================
# Every provider returns rows in this shape. It is the Drizzle `odds_snapshots`
# table (web/src/db/schema.ts) with three differences, all resolved at ingest:
#   - `fetch_id` is replaced by `source` + `raw_sha256` (the fetch lineage; the
#     ingest maps them to a source_fetches row)
#   - `player_id` is carried as `player_key`, an unresolved external key such as
#     "kalshi:<uuid>" or "espn:<athleteId>" (alias tables are P1/P3 work)
#   - `snapshot_kind` says how to read `captured_at`:
#       open     the venue's labelled opening line; its time is unknown, so captured_at is NA
#       close    the venue's labelled closing line; captured_at is NA
#       observed a line seen at captured_at (forward capture)
#       candle   the end of a Kalshi candle
#     Only observed and candle rows have a time, so only they can be tested for
#     "before kickoff" (R/odds/closing.R).
# `side` is one of ODDS_SIDES, and each market takes only the sides in
# ODDS_MARKET_SIDES: home/away (moneyline, spread), over/under (total), and yes or
# line (player markets: a yes/no contract, or a line-only observation). For the
# spread, `line` is the side's own handicap (home -6.5, away +6.5).
# Kalshi bid, ask and last are dollars in [0, 1]; American prices are whole numbers.
# raw_sha256 (the fetch lineage) is required on every row.
# =============================================================================

ODDS_SNAPSHOT_COLUMNS <- c(
  "game_id", "market_id", "venue_id", "player_key", "side", "line", "price_american",
  "bid", "ask", "last", "volume", "captured_at", "snapshot_kind", "source", "raw_sha256"
)
ODDS_SIDES <- c("home", "away", "over", "under", "yes", "no", "line")
ODDS_SNAPSHOT_KINDS <- c("open", "close", "observed", "candle")
ODDS_TIMED_KINDS <- c("observed", "candle")
# The sides each market takes. Moneyline and spread: home or away. Total: over or under.
# Player markets: yes (a yes/no contract) or line (a line-only observation). This table is
# the one place these sets live, and a test holds its markets equal to odds_markets_catalog().
# They cannot be a column of the catalog: contracts/schema/markets.schema.json forbids extra columns.
ODDS_MARKET_SIDES <- list(
  moneyline = c("home", "away"),
  spread = c("home", "away"),
  total = c("over", "under"),
  anytime_td = c("yes", "line"),
  first_td = c("yes", "line"),
  td_2plus = c("yes", "line"),
  passing_yards = c("yes", "line"),
  rushing_yards = c("yes", "line"),
  receiving_yards = c("yes", "line"),
  receptions = c("yes", "line")
)
# The string forms captured_at accepts, tried in this order. strptime ignores text that follows
# a matched format, so "...Zjunk" still parses; a value that matches none of the formats is an error.
ODDS_TIME_FORMATS <- c("%Y-%m-%dT%H:%M:%OSZ", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%OS", "%Y-%m-%d %H:%M:%S")

#' The markets D1 knows, in the shape of contracts/schema/markets.schema.json
odds_markets_catalog <- function() {
  data.frame(
    market_id = c("moneyline", "spread", "total", "anytime_td", "first_td", "td_2plus",
                  "passing_yards", "rushing_yards", "receiving_yards", "receptions"),
    scope = c(rep("game", 3), rep("player", 7)),
    outcome_kind = c("yes_no", "line", "line", "yes_no", "yes_no", "yes_no", "line", "line", "line", "line"),
    grading_rule = c(
      "team scores more points than its opponent, overtime included; a tie voids",
      "side score plus handicap beats the opponent score; a push voids",
      "total points over or under the line; a push voids",
      "player scores at least 1 rushing or receiving touchdown",
      "player scores the first touchdown of the game",
      "player scores at least 2 rushing or receiving touchdowns",
      "player passing yards over or under the line, overtime included",
      "player rushing yards over or under the line, overtime included",
      "player receiving yards over or under the line, overtime included",
      "player receptions over or under the line, overtime included"
    ),
    stringsAsFactors = FALSE
  )
}

#' The venues D1 knows, in the shape of contracts/schema/venues.schema.json
odds_venues_catalog <- function() {
  data.frame(
    venue_id = c("nflverse_consensus", "espn_bet", "draftkings", "kalshi"),
    display_name = c("nflverse consensus close", "ESPN BET", "DraftKings", "Kalshi"),
    kind = c("consensus", "sportsbook", "sportsbook", "exchange"),
    stringsAsFactors = FALSE
  )
}

#' Parse American prices ("+225", "-275", "EVEN", 150) to integers. Anything that
#' is not a price (empty, OFF, Inf, between -100 and +100, fractional, beyond the
#' integer range) is NA. It never errors and never warns.
american_to_int <- function(x) {
  txt <- toupper(trimws(as.character(x)))
  txt[!is.na(txt) & txt %in% c("EVEN", "EV", "PK")] <- "100"
  num <- suppressWarnings(as.numeric(sub("^\\+", "", txt)))
  ok <- !is.na(num) & is.finite(num) & abs(num) >= 100 & abs(num) <= .Machine$integer.max &
    abs(num - round(num)) < 1e-9
  out <- rep(NA_integer_, length(num))
  out[ok] <- as.integer(round(num[ok]))
  out
}

odds_snapshots_empty <- function() {
  data.frame(
    game_id = character(), market_id = character(), venue_id = character(), player_key = character(),
    side = character(), line = numeric(), price_american = integer(), bid = numeric(), ask = numeric(),
    last = numeric(), volume = numeric(), captured_at = as.POSIXct(character(), tz = "UTC"),
    snapshot_kind = character(), source = character(), raw_sha256 = character(),
    stringsAsFactors = FALSE
  )
}

#' Problems with a snapshot table, as character strings; empty means valid
validate_odds_snapshots <- function(df) {
  fails <- character()
  missing_cols <- setdiff(ODDS_SNAPSHOT_COLUMNS, names(df))
  if (length(missing_cols)) {
    return(sprintf("odds_snapshots: missing column(s) %s", paste(missing_cols, collapse = ", ")))
  }
  flag <- function(what, bad) {
    if (any(bad, na.rm = TRUE)) {
      fails <<- c(fails, sprintf("%s (rows %s)", what, paste(utils::head(which(bad), 10), collapse = ", ")))
    }
  }
  markets <- odds_markets_catalog()
  venues <- odds_venues_catalog()
  for (col in c("game_id", "market_id", "venue_id", "side", "snapshot_kind", "source", "raw_sha256")) {
    flag(sprintf("%s: required, found NA or empty", col), is.na(df[[col]]) | !nzchar(df[[col]]))
  }
  flag("market_id: not in odds_markets_catalog()", !is.na(df$market_id) & !df$market_id %in% markets$market_id)
  flag("venue_id: not in odds_venues_catalog()", !is.na(df$venue_id) & !df$venue_id %in% venues$venue_id)
  flag("side: not one of home/away/over/under/yes/no/line", !is.na(df$side) & !df$side %in% ODDS_SIDES)
  # a side must fit its market (ODDS_MARKET_SIDES); a row whose market or side is unknown is reported above
  side_fits <- vapply(seq_len(nrow(df)), function(i) {
    m <- df$market_id[i]
    s <- df$side[i]
    if (is.na(m) || is.na(s) || !m %in% names(ODDS_MARKET_SIDES) || !s %in% ODDS_SIDES) return(TRUE)
    s %in% ODDS_MARKET_SIDES[[m]]
  }, logical(1))
  flag("side: not allowed for this market_id (moneyline and spread home/away, total over/under, player markets yes/line)",
       !side_fits)
  flag("snapshot_kind: not one of open/close/observed/candle", !is.na(df$snapshot_kind) & !df$snapshot_kind %in% ODDS_SNAPSHOT_KINDS)
  flag("captured_at: timed kinds (observed, candle) need a time",
       df$snapshot_kind %in% ODDS_TIMED_KINDS & is.na(df$captured_at))
  flag("price_american: must be a whole number in integer range with |price| >= 100",
       !is.na(df$price_american) & (abs(df$price_american) < 100 | df$price_american != round(df$price_american) |
                                    abs(df$price_american) > .Machine$integer.max))
  flag("bid > ask", !is.na(df$bid) & !is.na(df$ask) & df$bid > df$ask)
  exchange <- df$venue_id %in% venues$venue_id[venues$kind == "exchange"]
  flag("bid/ask/last: exchange quotes are dollars in [0, 1]",
       exchange & (((!is.na(df$bid)) & (df$bid < 0 | df$bid > 1)) | ((!is.na(df$ask)) & (df$ask < 0 | df$ask > 1)) |
                     ((!is.na(df$last)) & (df$last < 0 | df$last > 1))))
  scope <- markets$scope[match(df$market_id, markets$market_id)]
  flag("player_key: player markets need one", scope %in% "player" & (is.na(df$player_key) | !nzchar(df$player_key)))
  flag("player_key: game markets must not carry one", scope %in% "game" & !is.na(df$player_key))
  fails
}

#' The stop for a value that completion cannot keep exactly; names the rows (first ten)
odds_row_stop <- function(what, bad) {
  stop(sprintf("complete_odds_snapshots: %s (rows %s)", what, paste(utils::head(which(bad), 10), collapse = ", ")),
       call. = FALSE)
}

#' captured_at as POSIXct in UTC. A POSIXct keeps its instant, numbers are epoch seconds,
#' and strings are read with ODDS_TIME_FORMATS. A non-NA value that cannot be read stops.
odds_utc_time <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  if (inherits(x, "POSIXct")) return(.POSIXct(as.numeric(x), tz = "UTC"))
  if (is.logical(x) && all(is.na(x))) return(.POSIXct(rep(NA_real_, length(x)), tz = "UTC"))
  if (is.numeric(x)) {
    secs <- as.numeric(x)
    secs[!is.finite(secs)] <- NA_real_
  } else if (is.character(x)) {
    secs <- rep(NA_real_, length(x))
    todo <- !is.na(x)
    for (fmt in ODDS_TIME_FORMATS) {
      idx <- which(todo)
      if (!length(idx)) break
      hit <- as.numeric(as.POSIXct(strptime(x[idx], format = fmt, tz = "UTC"), tz = "UTC"))
      done <- !is.na(hit)
      secs[idx[done]] <- hit[done]
      todo[idx[done]] <- FALSE
    }
  } else {
    stop("complete_odds_snapshots: captured_at has unsupported type ", class(x)[1], call. = FALSE)
  }
  bad <- !is.na(x) & is.na(secs)
  if (any(bad)) {
    odds_row_stop("captured_at must be a UTC time: ISO-8601 with Z, 'YYYY-mm-dd HH:MM:SS', or epoch seconds", bad)
  }
  .POSIXct(secs, tz = "UTC")
}

#' price_american as integers. A non-NA value that is not a whole number in integer range stops,
#' naming its rows, so a price is never truncated. Prices under 100 pass here; validation flags them.
odds_price_integer <- function(x) {
  num <- if (is.character(x) || is.factor(x)) {
    suppressWarnings(as.numeric(trimws(as.character(x))))
  } else {
    suppressWarnings(as.numeric(x))
  }
  whole <- is.finite(num) & num == round(num) & abs(num) <= .Machine$integer.max
  bad <- !is.na(x) & !whole
  if (any(bad)) odds_row_stop("price_american must be a whole number in integer range", bad)
  out <- rep(NA_integer_, length(num))
  out[whole] <- as.integer(num[whole])
  out
}

#' Complete a snapshot table without validating it: missing columns become typed
#' NAs, the types are coerced and the column order is fixed. Unknown columns stop.
#' A time or price that the coercion could not keep exactly stops, naming its rows.
complete_odds_snapshots <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  extra <- setdiff(names(df), ODDS_SNAPSHOT_COLUMNS)
  if (length(extra)) stop("new_odds_snapshots: unknown column(s) ", paste(extra, collapse = ", "), call. = FALSE)
  template <- odds_snapshots_empty()
  n <- nrow(df)
  out <- template[rep(NA_integer_, n), , drop = FALSE]
  rownames(out) <- NULL
  for (col in ODDS_SNAPSHOT_COLUMNS) {
    if (col %in% names(df)) {
      out[[col]] <- switch(
        col,
        price_american = odds_price_integer(df[[col]]),
        captured_at = odds_utc_time(df[[col]]),
        line = , bid = , ask = , last = , volume = as.numeric(df[[col]]),
        as.character(df[[col]])
      )
    }
  }
  attr(out$captured_at, "tzone") <- "UTC"
  out
}

#' Build a validated snapshot table from the columns a provider has; an invalid
#' table stops, it is never repaired.
new_odds_snapshots <- function(df) {
  out <- complete_odds_snapshots(df)
  problems <- validate_odds_snapshots(out)
  if (length(problems)) {
    stop("new_odds_snapshots: invalid odds_snapshots:\n  ", paste(problems, collapse = "\n  "), call. = FALSE)
  }
  out
}

#' Stack snapshot tables; NULL and zero-row entries are skipped
bind_odds_snapshots <- function(parts) {
  parts <- Filter(function(p) !is.null(p) && nrow(p) > 0, parts)
  if (length(parts) == 0) return(odds_snapshots_empty())
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}
