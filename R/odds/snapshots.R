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
# `side` is home/away (moneyline, spread), over/under (total), yes/no (binary
# prop and exchange contracts), or `line` for a line-only observation with no
# price. For the spread, `line` is the side's own handicap (home -6.5, away +6.5).
# Kalshi bid, ask and last are dollars in [0, 1]; American prices are integers.
# =============================================================================

ODDS_SNAPSHOT_COLUMNS <- c(
  "game_id", "market_id", "venue_id", "player_key", "side", "line", "price_american",
  "bid", "ask", "last", "volume", "captured_at", "snapshot_kind", "source", "raw_sha256"
)
ODDS_SIDES <- c("home", "away", "over", "under", "yes", "no", "line")
ODDS_SNAPSHOT_KINDS <- c("open", "close", "observed", "candle")
ODDS_TIMED_KINDS <- c("observed", "candle")

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
#' is not a price (empty, OFF, between -100 and +100, fractional) is NA.
american_to_int <- function(x) {
  txt <- toupper(trimws(as.character(x)))
  txt[!is.na(txt) & txt %in% c("EVEN", "EV", "PK")] <- "100"
  num <- suppressWarnings(as.numeric(sub("^\\+", "", txt)))
  ok <- !is.na(num) & abs(num) >= 100 & abs(num - round(num)) < 1e-9
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
  for (col in c("game_id", "market_id", "venue_id", "side", "snapshot_kind", "source")) {
    flag(sprintf("%s: required, found NA or empty", col), is.na(df[[col]]) | !nzchar(df[[col]]))
  }
  flag("market_id: not in odds_markets_catalog()", !is.na(df$market_id) & !df$market_id %in% markets$market_id)
  flag("venue_id: not in odds_venues_catalog()", !is.na(df$venue_id) & !df$venue_id %in% venues$venue_id)
  flag("side: not one of home/away/over/under/yes/no/line", !is.na(df$side) & !df$side %in% ODDS_SIDES)
  flag("snapshot_kind: not one of open/close/observed/candle", !is.na(df$snapshot_kind) & !df$snapshot_kind %in% ODDS_SNAPSHOT_KINDS)
  flag("captured_at: timed kinds (observed, candle) need a time",
       df$snapshot_kind %in% ODDS_TIMED_KINDS & is.na(df$captured_at))
  flag("price_american: must be an integer with |price| >= 100",
       !is.na(df$price_american) & abs(df$price_american) < 100)
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

#' Complete a snapshot table without validating it: missing columns become typed
#' NAs, the types are coerced and the column order is fixed. Unknown columns stop.
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
        price_american = as.integer(df[[col]]),
        captured_at = as.POSIXct(df[[col]], tz = "UTC"),
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
