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
# Pure helpers (parse/select/URL/path) are unit-tested with fixtures; only
# capture_http_get() touches the network.
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
  sb <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)
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
  sb <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)
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
  parsed <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)
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

#' GET with a truthful user agent, timeout, polite throttle and bounded retry
#' @return list(status, body [raw or NULL], error)
capture_http_get <- function(url, user_agent, timeout_sec, max_tries, min_interval_sec) {
  req <- httr2::request(url) |>
    httr2::req_user_agent(user_agent) |>
    httr2::req_timeout(timeout_sec) |>
    httr2::req_throttle(capacity = 1, fill_time_s = min_interval_sec) |>
    httr2::req_retry(
      max_tries = max_tries,
      is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504)
    ) |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error")) {
    return(list(status = NA_integer_, body = NULL, error = conditionMessage(resp)))
  }
  status <- httr2::resp_status(resp)
  if (status >= 400) {
    return(list(status = status, body = NULL, error = sprintf("HTTP %d", status)))
  }
  list(status = status, body = httr2::resp_body_raw(resp), error = NA_character_)
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

#' One capture pass over ESPN and Kalshi. Returns a summary data.frame.
#' @param cfg list with user_agent, timeout_sec, max_tries, min_interval_sec,
#'   horizon_hours (props), game_horizon_hours (ESPN game odds), espn_prop_providers
#'   (integer vector)
run_capture <- function(root, cfg, now = Sys.time(), sources = c("espn", "kalshi")) {
  now <- as.POSIXct(format(now, tz = "UTC"), tz = "UTC")
  log <- list()
  fetch <- function(source, key, url) {
    res <- capture_http_get(url, cfg$user_agent, cfg$timeout_sec,
                            cfg$max_tries, cfg$min_interval_sec)
    rec <- write_capture(root, source, key, Sys.time(), url, res$status,
                         body = res$body, error = res$error)
    log[[length(log) + 1]] <<- data.frame(
      source = source, key = key, status = res$status %||% NA_integer_,
      bytes = rec$bytes, error = res$error %||% NA_character_, stringsAsFactors = FALSE
    )
    if (is.null(res$body)) NULL else rawToChar(res$body)
  }

  if ("espn" %in% sources) {
    sb_text <- fetch("espn_scoreboard", "scoreboard", espn_scoreboard_url())
    if (!is.null(sb_text)) {
      if (is.null(cfg$game_horizon_hours)) {
        stop("run_capture: cfg$game_horizon_hours is missing (config.R CAPTURE_ESPN_GAME_HORIZON_HOURS)", call. = FALSE)
      }
      # ESPN's current week can still be the week just played, so read the next week as well
      events <- parse_espn_scoreboard(sb_text)
      sb_week <- parse_espn_scoreboard_week(sb_text)
      next_week <- if (is.null(sb_week)) NULL else espn_next_week(sb_week)
      if (!is.null(next_week)) {
        next_text <- fetch("espn_scoreboard",
                           sprintf("scoreboard_%d_t%d_w%02d", next_week$year, next_week$type, next_week$week),
                           espn_scoreboard_url(next_week))
        if (!is.null(next_text)) {
          upcoming <- parse_espn_scoreboard(next_text)
          events <- rbind(events, upcoming[!upcoming$event_id %in% events$event_id, , drop = FALSE])
        }
      }
      targets <- capture_targets(events, now, cfg$game_horizon_hours, cfg$horizon_hours)
      message(sprintf("ESPN: %d game(s) within %sh (game odds), %d within %sh (props)",
                      length(targets$game), cfg$game_horizon_hours,
                      length(targets$props), cfg$horizon_hours))
      for (event_id in targets$game) {
        fetch("espn_game_odds", event_id, espn_game_odds_url(event_id))
        if (!event_id %in% targets$props) next
        for (provider_id in cfg$espn_prop_providers) {
          first <- fetch("espn_propbets", sprintf("%s_%s_p1", event_id, provider_id),
                         espn_prop_bets_url(event_id, provider_id, 1))
          if (is.null(first)) next
          n_pages <- espn_page_count(first)
          for (page in seq_len(n_pages)[-1]) {
            fetch("espn_propbets", sprintf("%s_%s_p%d", event_id, provider_id, page),
                  espn_prop_bets_url(event_id, provider_id, page))
          }
        }
      }
    }
  }

  if ("kalshi" %in% sources) {
    series_text <- fetch("kalshi_series", "sports", kalshi_series_url())
    if (!is.null(series_text)) {
      series <- jsonlite::fromJSON(series_text, simplifyVector = FALSE)$series %||% list()
      tickers <- vapply(series, function(s) s$ticker, character(1))
      tickers <- sort(tickers[is_nfl_game_series(tickers)])
      message(sprintf("Kalshi: %d per-game NFL series", length(tickers)))
      for (ticker in tickers) {
        cursor <- NULL
        page <- 1L
        repeat {
          text <- fetch("kalshi_markets", sprintf("%s_p%d", ticker, page),
                        kalshi_open_markets_url(ticker, cursor))
          if (is.null(text)) break
          cursor <- jsonlite::fromJSON(text, simplifyVector = FALSE)$cursor
          if (is.null(cursor) || !nzchar(cursor) || page >= 20L) break
          page <- page + 1L
        }
      }
    }
  }

  if (length(log) == 0) return(data.frame())
  do.call(rbind, log)
}
