# =============================================================================
# Raw odds forward capture (Phase 0)
# =============================================================================
# Snapshots keyless public odds JSON to disk before kickoff, because prop
# markets disappear from these endpoints once a game starts. Bodies are stored
# byte-for-byte (gzipped) with a sha256 in an append-only manifest, so later
# provider code can re-parse them without re-fetching.
#
# Sources (no API keys, no trials):
#   - ESPN core API: scoreboard, per-game odds (open/close), DraftKings propBets
#   - Kalshi public market data: open markets for per-game NFL series
#
# Pure helpers (parse/select/URL/path) are unit-tested with fixtures. The network
# calls and the capture pass live in R/odds/ (http.R, provider_*.R, capture.R).
# =============================================================================

ESPN_CORE_BASE <- "https://sports.core.api.espn.com/v2/sports/football/leagues/nfl"
ESPN_SITE_BASE <- "https://site.api.espn.com/apis/site/v2/sports/football/nfl"
KALSHI_BASE <- "https://api.elections.kalshi.com/trade-api/v2"

# Season-long / futures / off-field series. Everything else prefixed KXNFL is
# treated as a per-game market and captured.
KALSHI_NON_GAME_PATTERN <- paste0(
  "WINS|DRAFT|COACH|MVP|ROY|POY|AFC|NFC|EXACT|SUPERBOWL|DIV|LEADER|RANK|RELOC|",
  "T100|PLAYOFF|ROUND|LASTTOLOSE|WEEK|CAREER|RECORD|COMBINE|CONTRACT|HIRE|",
  "ALLPRO|AWARD|CELEB|53MAN|DEBUT|DEPTH|VIEWERSHIP|SEED|SZN|ENDSTREAK|",
  "LOCATION|DELAY|FFH2HSEASON|COTY|EXEC"
)

format_utc_iso <- function(x) {
  format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

#' Parse an ESPN site scoreboard response into one row per event
#' @param json_text Scoreboard JSON as a string
#' @return data.frame(event_id, name, kickoff_utc [POSIXct UTC], status)
parse_espn_scoreboard <- function(json_text) {
  sb <- jsonlite::parse_json(json_text, simplifyVector = FALSE)
  events <- sb$events %||% list()
  if (length(events) == 0) {
    return(data.frame(
      event_id = character(), name = character(),
      kickoff_utc = as.POSIXct(character(), tz = "UTC"), status = character(),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    event_id = vapply(events, function(e) as.character(e$id), character(1)),
    name = vapply(events, function(e) e$name %||% NA_character_, character(1)),
    kickoff_utc = as.POSIXct(
      vapply(events, function(e) e$date, character(1)),
      format = "%Y-%m-%dT%H:%MZ", tz = "UTC"
    ),
    status = vapply(events, function(e) e$status$type$name %||% NA_character_, character(1)),
    stringsAsFactors = FALSE
  )
}

#' Keep games that have not kicked off and start within the horizon
select_capture_events <- function(events, now, horizon_hours) {
  keep <- events$status == "STATUS_SCHEDULED" &
    events$kickoff_utc > now &
    events$kickoff_utc <= now + horizon_hours * 3600
  events[which(keep), , drop = FALSE]
}

#' The season, season type (1 preseason, 2 regular season, 3 postseason) and week an ESPN
#' scoreboard response lists; NULL when the response names none
parse_espn_scoreboard_week <- function(json_text) {
  sb <- jsonlite::parse_json(json_text, simplifyVector = FALSE)
  year <- sb$season$year
  type <- sb$season$type
  week <- sb$week$number
  if (is.null(year) || is.null(type) || is.null(week)) return(NULL)
  list(year = as.integer(year), type = as.integer(type), week = as.integer(week))
}

#' The ESPN week after `wk`. ESPN numbers the regular season 1-18 (type 2) and the postseason
#' 1-5 (type 3: wild card to the Super Bowl, the Pro Bowl in week 4). NULL after the Super Bowl
#' and for any other season type (the preseason and the off-season are not captured).
espn_next_week <- function(wk) {
  last <- switch(as.character(wk$type), `2` = 18L, `3` = 5L, NULL)
  if (is.null(last)) return(NULL)
  if (wk$week < last) return(list(year = wk$year, type = wk$type, week = wk$week + 1L))
  if (wk$type == 2L) return(list(year = wk$year, type = 3L, week = 1L))
  NULL
}

#' ESPN's site scoreboard: ESPN's current week, or a named week. ESPN's current week stays on
#' the week just played until ESPN rolls it over (on Tuesday 2026-10-20 it still listed week 6,
#' every game final), and ESPN refuses a dates=YYYYMMDD-YYYYMMDD range (HTTP 400, probed
#' 2026-10-21), so the capture also asks for the next week by number.
espn_scoreboard_url <- function(week = NULL) {
  if (is.null(week)) return(paste0(ESPN_SITE_BASE, "/scoreboard"))
  sprintf("%s/scoreboard?seasontype=%d&week=%d&dates=%d", ESPN_SITE_BASE, week$type, week$week, week$year)
}

espn_game_odds_url <- function(event_id) {
  sprintf("%s/events/%s/competitions/%s/odds", ESPN_CORE_BASE, event_id, event_id)
}

espn_prop_bets_url <- function(event_id, provider_id, page = 1) {
  sprintf("%s/events/%s/competitions/%s/odds/%s/propBets?limit=1000&page=%d",
          ESPN_CORE_BASE, event_id, event_id, provider_id, as.integer(page))
}

#' Number of pages in an ESPN core collection response (1 when absent)
espn_page_count <- function(json_text) {
  parsed <- jsonlite::parse_json(json_text, simplifyVector = FALSE)
  n <- parsed$pageCount
  if (is.null(n) || !is.numeric(n) || n < 1) 1L else as.integer(n)
}

#' TRUE for Kalshi series tickers that are per-game NFL markets
is_nfl_game_series <- function(tickers) {
  startsWith(tickers, "KXNFL") & !grepl(KALSHI_NON_GAME_PATTERN, tickers)
}

kalshi_series_url <- function() {
  paste0(KALSHI_BASE, "/series?category=Sports")
}

kalshi_open_markets_url <- function(series_ticker, cursor = NULL) {
  url <- sprintf("%s/markets?series_ticker=%s&status=open&limit=1000",
                 KALSHI_BASE, utils::URLencode(series_ticker, reserved = TRUE))
  if (!is.null(cursor) && nzchar(cursor)) {
    url <- paste0(url, "&cursor=", utils::URLencode(cursor, reserved = TRUE))
  }
  url
}

#' Deterministic on-disk location: root/YYYY-MM-DD/source/key__YYYYMMDDTHHMMSSZ.json.gz
capture_path <- function(root, source, captured_at, key) {
  file.path(
    root,
    format(captured_at, "%Y-%m-%d", tz = "UTC"),
    source,
    sprintf("%s__%s.json.gz", key, format(captured_at, "%Y%m%dT%H%M%SZ", tz = "UTC"))
  )
}

#' Store one fetch: gzipped body (if any) plus an append-only manifest line
#' @return list(path, sha256, bytes); path is NA when there is no body
write_capture <- function(root, source, key, captured_at, url, http_status,
                          body = NULL, error = NA_character_) {
  path <- NA_character_
  sha <- NA_character_
  bytes <- 0L
  if (!is.null(body)) {
    path <- capture_path(root, source, captured_at, key)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    con <- gzfile(path, "wb")
    writeBin(body, con)
    close(con)
    sha <- digest::digest(body, algo = "sha256", serialize = FALSE)
    bytes <- length(body)
  }
  entry <- list(
    source = source, key = key, captured_at = format_utc_iso(captured_at),
    url = url, http_status = as.integer(http_status), sha256 = sha,
    bytes = bytes, path = path, error = error
  )
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  cat(jsonlite::toJSON(entry, auto_unbox = TRUE, na = "null"), "\n",
      file = file.path(root, "manifest.ndjson"), append = TRUE, sep = "")
  list(path = path, sha256 = sha, bytes = bytes)
}

#' GET through the odds HTTP layer (R/odds/http.R): truthful user agent, timeout, at most
#' 1 request per second per domain, bounded retry with backoff, no workaround for a 403.
#' Kept for the spike scripts; new code calls odds_fetch() directly.
#' @return list(status, body [raw or NULL], error)
capture_http_get <- function(url, user_agent, timeout_sec, max_tries, min_interval_sec) {
  if (!exists("odds_fetch", mode = "function")) source("R/odds/http.R")
  rec <- odds_fetch(url, list(user_agent = user_agent, timeout_sec = timeout_sec,
                              max_tries = max_tries, min_interval_sec = min_interval_sec))
  list(status = rec$status, body = rec$body, error = rec$error)
}

#' Which ESPN events to capture: game odds on the long horizon (every upcoming game's
#' line, so a Tuesday run sees Sunday's games), prop lists on the short one (they are
#' posted close to kickoff). Owner A0, 2026-10-19.
#' @return list(game = event ids, props = event ids); props is a subset of game
capture_targets <- function(events, now, game_horizon_hours, prop_horizon_hours) {
  if (prop_horizon_hours > game_horizon_hours) {
    stop(sprintf("capture_targets: the prop horizon (%sh) exceeds the game horizon (%sh)",
                 prop_horizon_hours, game_horizon_hours), call. = FALSE)
  }
  list(game = select_capture_events(events, now, game_horizon_hours)$event_id,
       props = select_capture_events(events, now, prop_horizon_hours)$event_id)
}
