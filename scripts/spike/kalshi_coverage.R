# =============================================================================
# Spike: Kalshi keyless coverage for NFL series (measurement, not production)
# =============================================================================
# Usage (from the repo root):
#   Rscript scripts/spike/kalshi_coverage.R [--sample] [--out=DIR] [--max-minutes=55]
#
# Stages:
#   1. Page /events?series_ticker=S&status=settled for every series.
#   2. Sample 3 events per series per season-month: list the event's markets and
#      pull hourly candles for kickoff-48h..kickoff on the highest-volume market
#      (the brief's check) and on one seeded-random market (unbiased share).
#   3. List markets for every remaining player-prop event, to count settled
#      markets and settled player-games exactly. Game-level series (GAME, SPREAD,
#      TOTAL) are counted from the stage-2 sample only and extrapolated.
#
# Markets settled before Kalshi's historical cutoff (GET /historical/cutoff) are
# only under /historical; later ones are only under the live /markets and
# /series/.../candlesticks. Each event tries the side of the cutoff it falls on
# first and falls back to the other, recording which answered.
# Every failed request is written to kalshi_failures.csv. Nothing is dropped.
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

if (!file.exists("config.R")) stop("Run from the repo root (config.R not found)")
source("R/capture_raw.R")
source("scripts/spike/spike_helpers.R")
cfg <- new.env()
sys.source("config.R", envir = cfg)

args <- commandArgs(trailingOnly = TRUE)
arg_val <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[1]) else default
}
SAMPLE <- "--sample" %in% args
OUT_DIR <- arg_val("out", "reports/2026-09-29/spike")
MAX_MINUTES <- as.numeric(arg_val("max-minutes", "55"))
SEED <- 20260929L
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

SERIES <- c("KXNFLANYTD", "KXNFLTD", "KXNFL2TD", "KXNFLFIRSTTD", "KXNFLRECYDS",
            "KXNFLRSHYDS", "KXNFLPASSYDS", "KXNFLREC", "KXNFLGAME", "KXNFLSPREAD",
            "KXNFLTOTAL")
PLAYER_SERIES <- SERIES[1:8]
PER_MONTH <- 3L
if (SAMPLE) {
  SERIES <- c("KXNFLANYTD", "KXNFLTD")
  PER_MONTH <- 1L
}

started <- Sys.time()
deadline <- started + MAX_MINUTES * 60
time_left <- function() Sys.time() < deadline
log_msg <- function(...) message(format(Sys.time(), "%H:%M:%S "), sprintf(...))

# ---- HTTP with failure ledger -----------------------------------------------
ledger <- new.env()
ledger$fail <- list()
ledger$count <- list()
fetch_json <- function(url, stage, key) {
  res <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC,
                          cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
  ledger$count[[stage]] <- (ledger$count[[stage]] %||% 0L) + 1L
  err <- res$error
  parsed <- NULL
  if (!is.null(res$body)) {
    parsed <- tryCatch(
      jsonlite::fromJSON(rawToChar(res$body), simplifyVector = FALSE),
      error = function(e) {
        err <<- paste("JSON parse error:", conditionMessage(e))
        NULL
      }
    )
  }
  if (is.null(parsed)) {
    ledger$fail[[length(ledger$fail) + 1]] <- data.frame(
      stage = stage, key = key, url = url, status = res$status %||% NA_integer_,
      error = err %||% NA_character_, stringsAsFactors = FALSE
    )
  }
  parsed
}

num <- function(x) if (is.null(x)) NA_real_ else suppressWarnings(as.numeric(x))
close_of <- function(obj) num(obj$close_dollars %||% obj$close)
utc_ts <- function(x) as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")

# ---- Schedule for kickoffs ----------------------------------------------------
sched <- as.data.frame(nflreadr::load_schedules(2024:2026))
# Kalshi writes Jacksonville as JAC, and the Rams as LA (2025 tickers) or LAR
# (2026 tickers). Accept any of these spellings.
team_spellings <- function(x) {
  switch(x, JAX = c("JAX", "JAC"), LA = c("LA", "LAR"), x)
}
sched$kalshi_suffixes <- lapply(seq_len(nrow(sched)), function(i) {
  as.vector(outer(team_spellings(sched$away_team[i]), team_spellings(sched$home_team[i]), paste0))
})
sched$kickoff_utc <- as.POSIXct(paste(sched$gameday, sched$gametime),
                                format = "%Y-%m-%d %H:%M", tz = "America/New_York")
attr(sched$kickoff_utc, "tzone") <- "UTC"
sched$gameday_date <- as.Date(sched$gameday)

match_game <- function(event_ticker, event_date) {
  if (is.na(event_date)) return(NULL)
  suffix <- sub("^.*-[0-9]{2}[A-Z]{3}[0-9]{2}", "", event_ticker)
  near <- abs(as.numeric(sched$gameday_date - event_date)) <= 1
  spelled <- vapply(sched$kalshi_suffixes, function(s) suffix %in% s, logical(1))
  hit <- sched[near & spelled, , drop = FALSE]
  if (nrow(hit) == 1) hit else NULL
}

# ---- Stage 1: settled events per series -----------------------------------------
event_rows <- list()
for (s in SERIES) {
  cursor <- NULL
  page <- 0L
  repeat {
    page <- page + 1L
    url <- sprintf("%s/events?series_ticker=%s&status=settled&limit=200", KALSHI_BASE, s)
    if (!is.null(cursor)) url <- paste0(url, "&cursor=", utils::URLencode(cursor, reserved = TRUE))
    x <- fetch_json(url, "events", sprintf("%s_p%d", s, page))
    if (is.null(x)) break
    evs <- x$events %||% list()
    if (length(evs)) {
      event_rows[[length(event_rows) + 1]] <- data.frame(
        series = s,
        event_ticker = vapply(evs, function(e) e$event_ticker %||% NA_character_, character(1)),
        sub_title = vapply(evs, function(e) e$sub_title %||% NA_character_, character(1)),
        stringsAsFactors = FALSE
      )
    }
    cursor <- x$cursor
    if (is.null(cursor) || !nzchar(cursor) || length(evs) == 0 || page >= 50L) break
  }
  log_msg("events %s: %d page(s)", s, page)
}
events <- do.call(rbind, event_rows)
events <- events[!duplicated(events[c("series", "event_ticker")]), ]
events$event_date <- do.call(c, lapply(events$event_ticker, kalshi_event_date))
events$season_month <- format(events$event_date, "%Y-%m")
events$game_id <- NA_character_
events$game_type <- NA_character_
events$kickoff_utc <- as.POSIXct(NA, tz = "UTC")
for (i in seq_len(nrow(events))) {
  g <- match_game(events$event_ticker[i], events$event_date[i])
  if (!is.null(g)) {
    events$game_id[i] <- g$game_id
    events$game_type[i] <- g$game_type
    events$kickoff_utc[i] <- g$kickoff_utc
  }
}
log_msg("stage 1 done: %d events, %d matched to nflreadr schedule", nrow(events), sum(!is.na(events$game_id)))

# ---- Market listing (historical and live, cutoff decides which goes first) -------
cutoff_json <- fetch_json(sprintf("%s/historical/cutoff", KALSHI_BASE), "cutoff", "cutoff")
HIST_CUTOFF <- if (is.null(cutoff_json$market_settled_ts)) as.POSIXct(NA, tz = "UTC") else
  utc_ts(cutoff_json$market_settled_ts)
log_msg("historical cutoff (market_settled_ts): %s", format_utc_iso(HIST_CUTOFF))

list_markets <- function(event_ticker, event_date) {
  collect <- function(base_url, stage) {
    out <- list()
    cursor <- NULL
    ok <- TRUE
    for (page in 1:5) {
      url <- base_url
      if (!is.null(cursor)) url <- paste0(url, "&cursor=", utils::URLencode(cursor, reserved = TRUE))
      x <- fetch_json(url, stage, sprintf("%s_p%d", event_ticker, page))
      if (is.null(x)) { ok <- FALSE; break }
      out <- c(out, x$markets %||% list())
      cursor <- x$cursor
      if (is.null(cursor) || !nzchar(cursor) || length(x$markets %||% list()) < 200) break
    }
    list(markets = out, ok = ok)
  }
  urls <- c(
    historical = sprintf("%s/historical/markets?event_ticker=%s&limit=200", KALSHI_BASE, event_ticker),
    live = sprintf("%s/markets?event_ticker=%s&limit=200", KALSHI_BASE, event_ticker)
  )
  after_cutoff <- !is.na(HIST_CUTOFF) && !is.na(event_date) &&
    event_date >= as.Date(HIST_CUTOFF, tz = "UTC")
  order <- if (after_cutoff) c("live", "historical") else c("historical", "live")
  oks <- logical()
  for (src in order) {
    got <- collect(urls[[src]], paste0("markets_", src))
    oks[src] <- got$ok
    if (length(got$markets)) return(list(markets = got$markets, source = src))
  }
  list(markets = list(), source = if (!any(oks)) "failed" else "none")
}

summarise_markets <- function(ml, series) {
  mk <- ml$markets
  player_of <- function(m) m$custom_strike$football_player %||% NA_character_
  result <- vapply(mk, function(m) m$result %||% NA_character_, character(1))
  settled <- result %in% c("yes", "no")
  players <- vapply(mk, player_of, character(1))
  is_player <- series %in% PLAYER_SERIES
  data.frame(
    market_source = ml$source,
    n_markets = length(mk),
    n_settled_markets = sum(settled),
    n_other_result = sum(!settled),
    n_players = if (is_player) length(unique(players[!is.na(players)])) else NA_integer_,
    n_players_settled = if (is_player) length(unique(players[settled & !is.na(players)])) else NA_integer_,
    n_markets_volume_pos = sum(vapply(mk, function(m) num(m$volume_fp %||% m$volume), 0) > 0, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

candle_check <- function(series, ticker, source, kickoff) {
  ko <- as.integer(as.numeric(kickoff))
  path <- if (source == "historical") {
    sprintf("%s/historical/markets/%s/candlesticks", KALSHI_BASE, ticker)
  } else {
    sprintf("%s/series/%s/markets/%s/candlesticks", KALSHI_BASE, series, ticker)
  }
  url <- sprintf("%s?start_ts=%d&end_ts=%d&period_interval=60", path, ko - 48L * 3600L, ko)
  x <- fetch_json(url, "candles", ticker)
  empty <- data.frame(candle_request_ok = !is.null(x), n_candles = NA_integer_,
                      n_pre_kickoff = NA_integer_, has_pre_kickoff_candle = NA,
                      last_pre_trade_price = NA_real_, last_pre_yes_bid = NA_real_,
                      last_pre_yes_ask = NA_real_, pre_kickoff_priced = NA,
                      hours_before_kickoff_first = NA_real_, stringsAsFactors = FALSE)
  if (is.null(x)) return(empty)
  cs <- x$candlesticks %||% list()
  empty$n_candles <- length(cs)
  ends <- vapply(cs, function(c) num(c$end_period_ts), 0)
  pre <- which(ends <= ko)
  empty$n_pre_kickoff <- length(pre)
  empty$has_pre_kickoff_candle <- length(pre) > 0
  empty$pre_kickoff_priced <- FALSE
  if (length(pre)) {
    last <- cs[[pre[which.max(ends[pre])]]]
    trade <- close_of(last$price)
    bid <- close_of(last$yes_bid)
    ask <- close_of(last$yes_ask)
    empty$last_pre_trade_price <- trade
    empty$last_pre_yes_bid <- bid
    empty$last_pre_yes_ask <- ask
    empty$pre_kickoff_priced <- !is.na(trade) || (!is.na(bid) && !is.na(ask) && bid > 0 && ask < 1)
    empty$hours_before_kickoff_first <- (ko - min(ends[pre])) / 3600
  }
  empty
}

# ---- Stage 2: sampled events with candle checks ----------------------------------
set.seed(SEED)
matched <- events[!is.na(events$game_id), ]
sample_keys <- character()
for (s in SERIES) {
  e <- matched[matched$series == s, ]
  for (mo in sort(unique(e$season_month))) {
    pool <- e$event_ticker[e$season_month == mo]
    take <- if (length(pool) <= PER_MONTH) pool else sample(pool, PER_MONTH)
    sample_keys <- c(sample_keys, paste(s, take))
  }
}
events$sampled <- paste(events$series, events$event_ticker) %in% sample_keys
market_cols <- c("market_source", "n_markets", "n_settled_markets", "n_other_result",
                 "n_players", "n_players_settled", "n_markets_volume_pos")
for (col in market_cols) events[[col]] <- NA
candle_rows <- list()
stage2_complete <- TRUE
for (i in which(events$sampled)) {
  if (!time_left()) { stage2_complete <- FALSE; break }
  s <- events$series[i]
  et <- events$event_ticker[i]
  ml <- list_markets(et, events$event_date[i])
  events[i, market_cols] <- summarise_markets(ml, s)
  if (!length(ml$markets)) next
  vols <- vapply(ml$markets, function(m) num(m$volume_fp %||% m$volume), 0)
  vols[is.na(vols)] <- 0
  picks <- list(top_volume = which.max(vols), random = sample.int(length(ml$markets), 1))
  for (which_pick in names(picks)) {
    m <- ml$markets[[picks[[which_pick]]]]
    cc <- candle_check(s, m$ticker, ml$source, events$kickoff_utc[i])
    open_t <- utc_ts(m$open_time %||% NA_character_)
    candle_rows[[length(candle_rows) + 1]] <- cbind(data.frame(
      series = s, event_ticker = et, season_month = events$season_month[i],
      game_id = events$game_id[i], kickoff_utc = format_utc_iso(events$kickoff_utc[i]),
      pick = which_pick, ticker = m$ticker, market_source = ml$source,
      result = m$result %||% NA_character_, volume = vols[picks[[which_pick]]],
      market_open_hours_before_kickoff = as.numeric(difftime(events$kickoff_utc[i], open_t, units = "hours")),
      stringsAsFactors = FALSE
    ), cc)
  }
  log_msg("sample %s %s: %d markets (%s)", s, et, length(ml$markets), ml$source)
}
candles <- if (length(candle_rows)) do.call(rbind, candle_rows) else data.frame()
log_msg("stage 2 done: %d sampled events, %d candle checks", sum(events$sampled), nrow(candles))

# ---- Stage 3: market counts for every remaining event -----------------------------
stage3_complete <- TRUE
todo <- which(!events$sampled & events$series %in% PLAYER_SERIES)
if (SAMPLE) todo <- head(todo, 5)
for (k in seq_along(todo)) {
  if (!time_left()) { stage3_complete <- FALSE; break }
  i <- todo[k]
  events[i, market_cols] <- summarise_markets(list_markets(events$event_ticker[i], events$event_date[i]), events$series[i])
  if (k %% 100 == 0) log_msg("stage 3: %d/%d events", k, length(todo))
}
log_msg("stage 3 %s", if (stage3_complete) "complete" else "STOPPED at time cap (PARTIAL)")

# ---- Summaries -------------------------------------------------------------------
pct <- function(x) if (length(x) == 0 || all(is.na(x))) NA_real_ else round(100 * mean(x, na.rm = TRUE), 1)
series_summary <- do.call(rbind, lapply(SERIES, function(s) {
  e <- events[events$series == s, ]
  fetched <- e[!is.na(e$n_markets), ]
  reg_post <- fetched[!is.na(fetched$game_id), ]
  pick_rows <- function(p) if (!nrow(candles)) candles else candles[candles$series == s & candles$pick == p, ]
  c_top <- pick_rows("top_volume")
  c_rnd <- pick_rows("random")
  pg_settled <- sum(reg_post$n_players_settled, na.rm = TRUE)
  rnd_rate <- if (nrow(c_rnd)) mean(c_rnd$pre_kickoff_priced %in% TRUE) else NA_real_
  data.frame(
    series = s,
    events = nrow(e),
    first_event_date = if (nrow(e)) as.character(min(e$event_date, na.rm = TRUE)) else NA,
    last_event_date = if (nrow(e)) as.character(max(e$event_date, na.rm = TRUE)) else NA,
    events_matched_schedule = sum(!is.na(e$game_id)),
    events_markets_listed = nrow(fetched),
    events_markets_failed = sum(fetched$market_source == "failed"),
    events_historical = sum(fetched$market_source == "historical"),
    events_live = sum(fetched$market_source == "live"),
    markets_total = sum(fetched$n_markets),
    settled_markets = sum(fetched$n_settled_markets),
    other_result_markets = sum(fetched$n_other_result),
    markets_listed_scope = if (s %in% PLAYER_SERIES) "all events" else "sampled events only",
    est_settled_markets_all_events = if (s %in% PLAYER_SERIES || !nrow(fetched)) NA else
      round(nrow(e) * mean(fetched$n_settled_markets)),
    settled_player_games_sched = if (s %in% PLAYER_SERIES) pg_settled else NA,
    sample_events = nrow(c_top),
    pct_pre_kickoff_candle_top = pct(c_top$has_pre_kickoff_candle %in% TRUE),
    pct_pre_kickoff_priced_top = pct(c_top$pre_kickoff_priced %in% TRUE),
    pct_pre_kickoff_candle_random = pct(c_rnd$has_pre_kickoff_candle %in% TRUE),
    pct_pre_kickoff_priced_random = pct(c_rnd$pre_kickoff_priced %in% TRUE),
    est_player_games_pre_kickoff_priced = if (s %in% PLAYER_SERIES && !is.na(rnd_rate)) round(pg_settled * rnd_rate) else NA,
    stringsAsFactors = FALSE
  )
}))

failures <- if (length(ledger$fail)) do.call(rbind, ledger$fail) else
  data.frame(stage = character(), key = character(), url = character(),
             status = integer(), error = character())
finished <- Sys.time()
meta <- data.frame(
  script = "kalshi_coverage.R", sample_mode = SAMPLE,
  started_utc = format_utc_iso(started), finished_utc = format_utc_iso(finished),
  minutes = round(as.numeric(difftime(finished, started, units = "mins")), 1),
  stage2_complete = stage2_complete, stage3_complete = stage3_complete,
  status = if (stage2_complete && stage3_complete) "COMPLETE" else "PARTIAL",
  requests_total = sum(unlist(ledger$count)),
  requests_by_stage = paste(names(ledger$count), unlist(ledger$count), sep = "=", collapse = ";"),
  failed_requests = nrow(failures),
  historical_cutoff_utc = format_utc_iso(HIST_CUTOFF),
  stringsAsFactors = FALSE
)

events_out <- events
events_out$event_date <- as.character(events_out$event_date)
events_out$kickoff_utc <- format_utc_iso(events_out$kickoff_utc)
utils::write.csv(events_out, file.path(OUT_DIR, "kalshi_events.csv"), row.names = FALSE)
utils::write.csv(candles, file.path(OUT_DIR, "kalshi_candle_sample.csv"), row.names = FALSE)
utils::write.csv(series_summary, file.path(OUT_DIR, "kalshi_series_summary.csv"), row.names = FALSE)
utils::write.csv(failures, file.path(OUT_DIR, "kalshi_failures.csv"), row.names = FALSE)
utils::write.csv(meta, file.path(OUT_DIR, "kalshi_run_meta.csv"), row.names = FALSE)
log_msg("done: %s, %d requests, %d failed, %.1f min", meta$status, meta$requests_total,
        meta$failed_requests, meta$minutes)
