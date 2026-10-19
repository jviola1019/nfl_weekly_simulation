# =============================================================================
# Keyless odds HTTP layer (roadmap D1)
# =============================================================================
# The one place the odds providers touch the network. Policy (owner rules):
#   - a truthful user agent, a 20 s timeout, at most 1 request per second per
#     registrable domain (a hard floor: a config value below 1 s is raised to 1 s)
#   - bounded retry with backoff on HTTP 429/5xx and on network errors
#   - a 401/403, or a 429 that survives the retries, is never worked around: the
#     result is flagged `blocked`, and later calls to that domain make no request
#   - every response's raw sha256 is returned, and appended to a fetch log when
#     `log_path` is given (the columns follow the source_fetches table)
#
# The network call itself is `fetch_fn(url, cfg)`, an injectable seam. Tests pass
# a fake that reads recorded JSON fixtures, so the default suite makes no request.
# `odds_http_get` is the only real implementation; it refuses to run when
# NFL_ODDS_FORBID_LIVE=1, which tests/testthat/helper-odds.R sets.
# =============================================================================

ODDS_MIN_INTERVAL_SEC <- 1       # hard floor between requests to one domain
ODDS_DEFAULT_TIMEOUT_SEC <- 20
ODDS_DEFAULT_MAX_TRIES <- 3L
ODDS_RETRY_STATUS <- c(429L, 500L, 502L, 503L, 504L)
ODDS_BLOCKED_STATUS <- c(401L, 403L, 429L)
ODDS_BACKOFF_CAP_SEC <- 60
ODDS_DEFAULT_USER_AGENT <- "nfl-weekly-simulation (research; https://github.com/jviola1019/nfl_weekly_simulation)"

# Per-process state: the last request time and the blocked flag, by domain
.odds_http_state <- new.env(parent = emptyenv())

#' Forget throttle times and blocked domains (tests, and long-lived sessions)
odds_http_reset <- function() {
  rm(list = ls(.odds_http_state, all.names = TRUE), envir = .odds_http_state)
  invisible(NULL)
}

#' Request settings. Reads the CAPTURE_* constants from `env` (config.R), applies
#' `overrides`, and enforces the 1 request/second floor.
odds_http_config <- function(env = globalenv(), overrides = list()) {
  pick <- function(name, default) {
    if (exists(name, envir = env, inherits = FALSE)) get(name, envir = env, inherits = FALSE) else default
  }
  cfg <- list(
    user_agent = pick("CAPTURE_USER_AGENT", ODDS_DEFAULT_USER_AGENT),
    timeout_sec = pick("CAPTURE_TIMEOUT_SEC", ODDS_DEFAULT_TIMEOUT_SEC),
    max_tries = pick("CAPTURE_MAX_TRIES", ODDS_DEFAULT_MAX_TRIES),
    min_interval_sec = pick("CAPTURE_MIN_INTERVAL_SEC", ODDS_MIN_INTERVAL_SEC)
  )
  cfg[names(overrides)] <- overrides
  cfg$min_interval_sec <- max(cfg$min_interval_sec, ODDS_MIN_INTERVAL_SEC)
  cfg$max_tries <- max(1L, as.integer(cfg$max_tries))
  cfg
}

#' Registrable domain of a URL ("sports.core.api.espn.com" -> "espn.com"), the
#' throttle key, so two ESPN hosts share one budget
odds_url_realm <- function(url) {
  host <- sub("^[a-z]+://([^/:?#]+).*$", "\\1", tolower(url))
  parts <- strsplit(host, ".", fixed = TRUE)[[1]]
  if (length(parts) <= 2) host else paste(utils::tail(parts, 2), collapse = ".")
}

#' Blank the value of any credential-looking query parameter before a URL is logged
odds_redact_url <- function(url) {
  gsub("([?&](?:key|apikey|api_key|token|auth|access_token)=)[^&]*", "\\1REDACTED", url,
       ignore.case = TRUE, perl = TRUE)
}

odds_iso <- function(x) format(as.POSIXct(x, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

#' Wait until `min_interval_sec` has passed since the last request to this domain
odds_throttle <- function(url, min_interval_sec, now_fn = Sys.time, sleep_fn = Sys.sleep) {
  realm <- odds_url_realm(url)
  key <- paste0("last:", realm)
  now <- as.numeric(now_fn())
  last <- if (exists(key, envir = .odds_http_state, inherits = FALSE)) get(key, envir = .odds_http_state) else NULL
  if (!is.null(last)) {
    wait <- last + min_interval_sec - now
    if (wait > 0) {
      sleep_fn(wait)
      now <- now + wait
    }
  }
  assign(key, now, envir = .odds_http_state)
  invisible(now)
}

#' Seconds to wait after attempt `attempt` failed: the server's Retry-After when
#' it sent one, otherwise 2, 4, 8 ... seconds, never more than ODDS_BACKOFF_CAP_SEC
odds_backoff_sec <- function(attempt, retry_after = NA_real_) {
  if (!is.null(retry_after) && !is.na(retry_after) && retry_after >= 0) {
    return(min(retry_after, ODDS_BACKOFF_CAP_SEC))
  }
  min(2^attempt, ODDS_BACKOFF_CAP_SEC)
}

#' The real network call: one GET, no retry, no throttle (odds_fetch adds both).
#' @return list(status, body [raw or NULL], error, retry_after)
odds_http_get <- function(url, cfg) {
  if (identical(Sys.getenv("NFL_ODDS_FORBID_LIVE"), "1")) {
    stop("odds_http_get: live HTTP is forbidden while NFL_ODDS_FORBID_LIVE=1 (url: ", url, ")", call. = FALSE)
  }
  req <- httr2::request(url) |>
    httr2::req_user_agent(cfg$user_agent) |>
    httr2::req_timeout(cfg$timeout_sec) |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error")) {
    return(list(status = NA_integer_, body = NULL, error = conditionMessage(resp), retry_after = NA_real_))
  }
  status <- httr2::resp_status(resp)
  retry_after <- suppressWarnings(as.numeric(httr2::resp_header(resp, "Retry-After", default = NA_character_)))
  list(
    status = status,
    body = if (status < 400) httr2::resp_body_raw(resp) else NULL,
    error = if (status >= 400) sprintf("HTTP %d", status) else NA_character_,
    retry_after = retry_after
  )
}

#' Append one fetch-log line (NDJSON; the columns follow the source_fetches table)
odds_log_fetch <- function(path, rec) {
  entry <- list(
    source = rec$source, endpoint_redacted = odds_redact_url(rec$url),
    http_status = rec$status, fetched_at = odds_iso(rec$fetched_at),
    raw_sha256 = rec$sha256, bytes = rec$bytes, tries = rec$tries,
    blocked = rec$blocked, error = rec$error
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  cat(jsonlite::toJSON(entry, auto_unbox = TRUE, na = "null"), "\n", file = path, append = TRUE, sep = "")
  invisible(path)
}

#' GET with throttle, bounded retry and backoff, a blocked-domain breaker, the raw
#' sha256 and an optional fetch log.
#' @param fetch_fn function(url, cfg) -> list(status, body, error, retry_after)
#' @return list(url, source, status, body, error, sha256, bytes, fetched_at, tries, blocked)
odds_fetch <- function(url, cfg = odds_http_config(), fetch_fn = odds_http_get, log_path = NULL,
                       source = NA_character_, now_fn = Sys.time, sleep_fn = Sys.sleep) {
  stopifnot(is.character(url), length(url) == 1L, !is.na(url))
  min_interval <- max(cfg$min_interval_sec %||% ODDS_MIN_INTERVAL_SEC, ODDS_MIN_INTERVAL_SEC)
  max_tries <- max(1L, as.integer(cfg$max_tries %||% ODDS_DEFAULT_MAX_TRIES))
  realm <- odds_url_realm(url)
  blocked_key <- paste0("blocked:", realm)

  if (exists(blocked_key, envir = .odds_http_state, inherits = FALSE)) {
    res <- list(status = get(blocked_key, envir = .odds_http_state), body = NULL,
                error = sprintf("blocked: %s refused an earlier request (HTTP %s); no further requests this session",
                                realm, get(blocked_key, envir = .odds_http_state)),
                retry_after = NA_real_)
    attempts <- 0L
  } else {
    res <- NULL
    attempts <- 0L
    for (attempt in seq_len(max_tries)) {
      attempts <- attempt
      odds_throttle(url, min_interval, now_fn, sleep_fn)
      res <- fetch_fn(url, cfg)
      status <- res$status %||% NA_integer_
      transient <- is.na(status) || status %in% ODDS_RETRY_STATUS
      if (!transient || attempt == max_tries) break
      sleep_fn(odds_backoff_sec(attempt, res$retry_after %||% NA_real_))
    }
    final <- res$status %||% NA_integer_
    if (!is.na(final) && final %in% ODDS_BLOCKED_STATUS) {
      assign(blocked_key, as.integer(final), envir = .odds_http_state)
    }
  }

  body <- res$body
  status <- res$status %||% NA_integer_
  rec <- list(
    url = url, source = source, status = as.integer(status), body = body,
    error = res$error %||% NA_character_,
    sha256 = if (is.null(body)) NA_character_ else digest::digest(body, algo = "sha256", serialize = FALSE),
    bytes = if (is.null(body)) 0L else length(body),
    fetched_at = as.POSIXct(now_fn(), tz = "UTC"), tries = attempts,
    blocked = !is.na(status) && status %in% ODDS_BLOCKED_STATUS
  )
  if (!is.null(log_path)) odds_log_fetch(log_path, rec)
  rec
}

#' Parse a fetch result's body as JSON. Returns NULL (and the caller records why)
#' when there is no body or it is not JSON; it never returns a guess.
odds_json <- function(rec) {
  if (is.null(rec$body)) return(NULL)
  tryCatch(jsonlite::fromJSON(rawToChar(rec$body), simplifyVector = FALSE), error = function(e) NULL)
}
