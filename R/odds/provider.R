# =============================================================================
# The odds provider interface (roadmap D1; spec Phase 2)
# =============================================================================
# One interface for every source. A provider is built by a constructor
# (provider_nflverse(), provider_espn_core(), provider_kalshi()) that takes its
# network seam (`fetch_fn`) as an argument, and is a list with:
#   id               short source id
#   venue_ids        the odds_venues_catalog() venues it can emit
#   game_snapshots   function(games, ...) -> odds_result, or NULL
#   prop_snapshots   function(games, ...) -> odds_result, or NULL
#   capture          function(fetch, now, cfg), the forward-capture pass that stores
#                    raw responses (the games it needs come from the source itself), or NULL
# `games` is the table odds_games_from_schedule() builds. Every method returns an
# odds_result: normalized snapshots, a source_status row (the contract in
# contracts/schema/source_status.schema.json) and the fetch lineage. A source that
# fails says so in source_status; it never returns made-up rows.
# =============================================================================

ODDS_RESULT_STATUSES <- c("ok", "complete", "stale", "failed", "unavailable")

# Seasons whose games D1 never fetches, stores or reads: the 2025 game holdout stays sealed until
# its protocol is signed (roadmap D1 global constraints). Capture skips them at the source.
ODDS_SEALED_SEASONS <- 2025L

#' The NFL season a date falls in: January and February belong to the season before
odds_nfl_season <- function(now) {
  d <- as.POSIXlt(now, tz = "UTC")
  as.integer(d$year + 1900L - (d$mon + 1L <= 2L))
}

#' Build and check a provider
new_odds_provider <- function(id, venue_ids, game_snapshots = NULL, prop_snapshots = NULL, capture = NULL) {
  p <- structure(
    list(id = id, venue_ids = venue_ids, game_snapshots = game_snapshots,
         prop_snapshots = prop_snapshots, capture = capture),
    class = "odds_provider"
  )
  problems <- validate_odds_provider(p)
  if (length(problems)) stop("new_odds_provider: ", paste(problems, collapse = "; "), call. = FALSE)
  p
}

validate_odds_provider <- function(p) {
  fails <- character()
  if (!is.character(p$id) || length(p$id) != 1L || is.na(p$id) || !nzchar(p$id)) fails <- c(fails, "id must be a non-empty string")
  if (!is.character(p$venue_ids) || length(p$venue_ids) == 0 || !all(p$venue_ids %in% odds_venues_catalog()$venue_id)) {
    fails <- c(fails, "every venue id must be in odds_venues_catalog()")
  }
  for (m in c("game_snapshots", "prop_snapshots", "capture")) {
    if (!is.null(p[[m]]) && !is.function(p[[m]])) fails <- c(fails, sprintf("%s must be a function or NULL", m))
  }
  fails
}

# ---- helpers shared by the providers' error and block handling ----
# An error message on one line, for a detail string
odds_one_line <- function(text) trimws(gsub("[[:space:]]+", " ", text))

# What a body that odds_json() could not turn into a value holds: "empty" (no bytes, or white
# space only), "null" (the JSON literal null) or "not_json" (anything else, a binary body included)
odds_body_kind <- function(rec) {
  body <- rec$body
  if (is.null(body) || length(body) == 0L) return("empty")
  if (any(body == as.raw(0L))) return("not_json")
  txt <- tryCatch(trimws(rawToChar(body)), error = function(e) NA_character_)
  if (is.na(txt)) "not_json" else if (!nzchar(txt)) "empty" else if (identical(txt, "null")) "null" else "not_json"
}

# TRUE for a 2xx response whose body has text that is not JSON (the caller has found odds_json(rec)
# NULL): a captcha, challenge or geo-fence page served as 200. It is a block, not a missing game.
# An empty body or JSON null is no page at all: the caller counts it as a gap (review I-1).
odds_is_html_block <- function(rec) {
  !is.na(rec$status) && rec$status >= 200L && rec$status < 300L && identical(odds_body_kind(rec), "not_json")
}

# What went wrong with a response that has no JSON: odds_fetch's own error text, or for a body that
# arrived (rec$error is NA on success) the status and what the body held
odds_fetch_problem <- function(rec) {
  if (!is.na(rec$error)) return(rec$error)
  sprintf("HTTP %d, %s", rec$status,
          switch(odds_body_kind(rec), empty = "empty body", null = "JSON null", "body is not JSON"))
}

# The reason a provider gives odds_declare_blocked() for a 2xx page that is not JSON
ODDS_PAGE_BLOCK_REASON <- "served a page that is not JSON (a challenge or geo-fence page)"

odds_html_block_note <- function(rec, where) {
  sprintf("blocked: HTTP %d body is not JSON (a challenge or geo-fence page) at %s; run stopped", rec$status, where)
}

#' One row of fetch lineage from an odds_fetch() record
odds_fetch_row <- function(rec, key) {
  data.frame(
    source = rec$source %||% NA_character_, key = key, url = odds_redact_url(rec$url), http_status = rec$status,
    raw_sha256 = rec$sha256, bytes = rec$bytes, tries = rec$tries, blocked = rec$blocked,
    fetched_at = rec$fetched_at, stringsAsFactors = FALSE
  )
}

odds_fetches_empty <- function() {
  data.frame(
    source = character(), key = character(), url = character(), http_status = integer(),
    raw_sha256 = character(), bytes = integer(), tries = integer(), blocked = logical(),
    fetched_at = as.POSIXct(character(), tz = "UTC"), stringsAsFactors = FALSE
  )
}

#' What a provider method returns
odds_result <- function(snapshots = odds_snapshots_empty(), source, status = "ok", detail = NA_character_,
                        fetches = odds_fetches_empty(), now = Sys.time()) {
  if (!status %in% ODDS_RESULT_STATUSES) {
    stop("odds_result: status must be one of ", paste(ODDS_RESULT_STATUSES, collapse = ", "), call. = FALSE)
  }
  list(
    snapshots = snapshots,
    source_status = data.frame(
      source = source, status = status,
      last_success_utc = if (status %in% c("ok", "complete", "stale")) odds_iso(now) else NA_character_,
      detail = detail, stringsAsFactors = FALSE
    ),
    fetches = fetches
  )
}

bind_odds_results <- function(results) {
  results <- Filter(Negate(is.null), results)
  list(
    snapshots = bind_odds_snapshots(lapply(results, `[[`, "snapshots")),
    source_status = do.call(rbind, c(list(odds_result(source = "none")$source_status[0, ]),
                                     lapply(results, `[[`, "source_status"))),
    fetches = do.call(rbind, c(list(odds_fetches_empty()), lapply(results, `[[`, "fetches")))
  )
}

#' The `games` table the providers take, from an nflreadr::load_schedules() frame.
#' A game whose time is unknown keeps a NA kickoff; it is never given a default.
odds_games_from_schedule <- function(schedule) {
  sched <- as.data.frame(schedule, stringsAsFactors = FALSE)
  kick <- as.POSIXct(paste(sched$gameday, sched$gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")
  attr(kick, "tzone") <- "UTC"
  data.frame(
    game_id = sched$game_id, season = as.integer(sched$season), week = as.integer(sched$week),
    game_type = sched$game_type, gameday = sched$gameday, kickoff_utc = kick,
    home_team = sched$home_team, away_team = sched$away_team, espn = as.character(sched$espn),
    stringsAsFactors = FALSE
  )
}
