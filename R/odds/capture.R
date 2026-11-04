# =============================================================================
# Forward capture, as a caller of the provider layer (roadmap D1)
# =============================================================================
# One pass over the providers' capture() methods. Every request goes through
# odds_fetch() (truthful user agent, 20 s timeout, at most 1 request/second per
# domain, backoff on 429/5xx, no workaround for a 403), and every raw response is
# stored byte-for-byte (gzipped) with its sha256 in the append-only manifest
# (write_capture() in R/capture_raw.R). The on-disk layout is unchanged:
#   root/YYYY-MM-DD/<source>/<key>__<timestamp>.json.gz   and   root/manifest.ndjson
#
# What reaches a provider is the body's text, or NULL when there is none to read:
#   - an error or a block (401/403/429 stops the domain for the session);
#   - an empty 2xx body (logged as "empty body"; the pass goes on);
#   - a 2xx body that is not JSON: a challenge or geo-fence page served as 200. That is a
#     block too: it is declared to the HTTP layer, so no later request this session goes
#     to that domain. It is never retried or worked around.
# A season in ODDS_SEALED_SEASONS is never captured (the 2025 game holdout is sealed).
# =============================================================================

#' One capture pass over ESPN and Kalshi. Returns a summary data.frame
#' (source, key, status, bytes, error), one row per request.
#' @param cfg list(user_agent, timeout_sec, max_tries, min_interval_sec, horizon_hours,
#'   game_horizon_hours, espn_prop_providers)
#' @param fetch_fn the network seam (odds_http_get in production)
#' @param providers named list of providers; default ESPN core and Kalshi
run_capture <- function(root, cfg, now = Sys.time(), sources = c("espn", "kalshi"),
                        fetch_fn = odds_http_get, providers = NULL,
                        now_fn = Sys.time, sleep_fn = Sys.sleep) {
  now <- as.POSIXct(format(now, tz = "UTC"), tz = "UTC")
  season <- odds_nfl_season(now)
  if (season %in% ODDS_SEALED_SEASONS) {
    message(sprintf("run_capture: %s falls in the %d season, which is sealed; nothing is captured",
                    format(now, "%Y-%m-%d"), season))
    return(data.frame())
  }
  http_cfg <- odds_http_config(overrides = cfg[intersect(names(cfg), c("user_agent", "timeout_sec", "max_tries", "min_interval_sec"))])
  providers <- providers %||% list(espn = provider_espn_core(), kalshi = provider_kalshi())
  log <- list()

  fetch <- function(source, key, url) {
    rec <- odds_fetch(url, http_cfg, fetch_fn = fetch_fn, source = source, now_fn = now_fn, sleep_fn = sleep_fn)
    write_capture(root, source, key, rec$fetched_at, url, rec$status, body = rec$body, error = rec$error)
    error <- rec$error
    text <- NULL
    if (rec$blocked) {
      message(sprintf("  %s: %s", odds_redact_url(url), rec$error))
    } else if (!is.null(rec$body) && !length(rec$body)) {
      error <- "empty body"
      message(sprintf("  %s returned an empty body; skipped", odds_redact_url(url)))
    } else if (!is.null(rec$body)) {
      text <- rawToChar(rec$body)
      if (odds_is_html_block(rec) && !isTRUE(jsonlite::validate(text))) {
        odds_declare_blocked(url, rec$status)
        error <- odds_html_block_note(rec, odds_redact_url(url))
        message(sprintf("  %s; no further requests to that domain this session", error))
        text <- NULL
      }
    }
    log[[length(log) + 1]] <<- data.frame(
      source = source, key = key, status = rec$status, bytes = rec$bytes,
      error = error %||% NA_character_, stringsAsFactors = FALSE
    )
    text
  }

  unknown <- setdiff(sources, names(providers))
  if (length(unknown)) warning("run_capture: no provider for source(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  for (name in intersect(sources, names(providers))) {
    if (is.null(providers[[name]]$capture)) {
      message(sprintf("run_capture: provider %s has no capture method; skipped", name))
      next
    }
    providers[[name]]$capture(fetch, now, cfg)
  }

  if (length(log) == 0) return(data.frame())
  do.call(rbind, log)
}
