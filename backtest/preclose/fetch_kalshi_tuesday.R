#!/usr/bin/env Rscript
# =============================================================================
# nfl_preclose_v1's Tuesday track (PROTOCOL.md): each 2026 game's Kalshi KXNFLGAME price
# at the decision point and at the close, from hourly candles (GET /markets/candlesticks,
# keyless, through R/capture_raw.R's GET: truthful user agent, at most one request a
# second; a 403 stops the run). The decision point is 18:00 UTC on the Tuesday on or
# before the week's first kickoff (US Eastern date), as prospective_dispatch.R schedules
# its runs.
#   tue: the first candle ending at or after 18:00 UTC (the protocol's rule)
#   tue_state: the last candle ending at or before 18:00 UTC (the state then; a sensitivity)
#   close: the last candle ending at or before the scheduled kickoff
# A candle covers the hour ending at end_period_ts; an hour with no change has none.
#   Rscript backtest/preclose/fetch_kalshi_tuesday.R <raw_dir> <out_csv> <settled.csv.gz>,...
# Only KXNFLGAME contracts of 2026 games that have kicked off are requested.
# =============================================================================
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 3L)
raw <- args[1]; out_csv <- args[2]; settled <- strsplit(args[3], ",", fixed = TRUE)[[1]]
dir.create(raw, recursive = TRUE, showWarnings = FALSE)
cfg <- new.env(); sys.source("config.R", envir = cfg); source("R/capture_raw.R")
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
st <- unique(rbindlist(lapply(settled, function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))), fill = TRUE), by = "ticker")
st <- st[series == "KXNFLGAME"]
stopifnot(nrow(st) > 0, !any(substr(st$close_time, 1, 4) == "2025"))
sched <- props_schedule()
st <- merge(st[, .(ticker, event_ticker, label)], props_event_games(st$event_ticker, sched), by = "event_ticker")
st <- merge(st, sched[, .(game_id, home_team, away_team)], by = "game_id")
st <- st[kick < Sys.time()]
# each week's decision point: 18:00 UTC on the Tuesday on or before its first kickoff (US Eastern date)
first <- sched[, .(k1 = min(kick)), by = week]
first[, d1 := as.Date(format(k1, "%Y-%m-%d", tz = "America/New_York"))]
first[, tue := as.POSIXct(paste(d1 - ((as.POSIXlt(d1)$wday - 2L) %% 7L), "18:00:00"), tz = "UTC")]
st <- merge(st, first[, .(week, tue)], by = "week")
iso <- function(t) format(as.POSIXct(t, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
num <- function(v) suppressWarnings(as.numeric(v))
rows <- list(); k <- 0L
for (w in sort(unique(st$week))) {
  s <- st[week == w]; t0 <- as.integer(s$tue[1]); kmax <- as.integer(max(s$kick))
  for (b in split(seq_len(nrow(s)), ceiling(seq_len(nrow(s)) / 50L))) {
    k <- k + 1L
    url <- sprintf("%s/markets/candlesticks?market_tickers=%s&start_ts=%d&end_ts=%d&period_interval=60", KALSHI_BASE,
                   utils::URLencode(paste(s$ticker[b], collapse = ","), reserved = TRUE), t0 - 24L * 3600L, kmax)
    r <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC, cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
    if (identical(r$status, 403L)) stop("fetch_kalshi_tuesday: HTTP 403, the venue is dropped for this run, never retried", call. = FALSE)
    if (is.null(r$body)) { message(sprintf("week %d batch %d: no body (%s)", w, k, r$status)); next }
    con <- gzfile(file.path(raw, sprintf("tuesday_w%02d_%02d.json.gz", w, k)), "wb"); writeBin(r$body, con); close(con)
    j <- jsonlite::parse_json(rawToChar(r$body))$markets
    for (m in j) {
      tk <- m$market_ticker; kick <- as.integer(s[ticker == tk, kick][1]); cs <- m$candlesticks
      ts <- vapply(cs, function(c) as.numeric(c$end_period_ts), 0)
      bid <- vapply(cs, function(c) num(c$yes_bid$close_dollars %||% NA), 0); ask <- vapply(cs, function(c) num(c$yes_ask$close_dollars %||% NA), 0)
      i_tue <- which(ts >= t0 & ts <= kick); i_state <- which(ts <= t0); i_close <- which(ts <= kick)
      i_tue <- if (length(i_tue)) min(i_tue) else NA_integer_; i_state <- if (length(i_state)) max(i_state) else NA_integer_
      i_close <- if (length(i_close)) max(i_close) else NA_integer_
      rows[[length(rows) + 1L]] <- data.table(ticker = tk, week = w, tue = iso(t0), kick = iso(kick), tue_end = if (is.na(i_tue)) NA_character_ else iso(ts[i_tue]),
        bid_tue = bid[i_tue], ask_tue = ask[i_tue], bid_tue_state = bid[i_state], ask_tue_state = ask[i_state], bid_close = bid[i_close], ask_close = ask[i_close])
    }
  }
}
cn <- merge(rbindlist(rows), st[, .(ticker, game_id, label, home_team, away_team)], by = "ticker")
fwrite(cn, out_csv, eol = "\n")
cat(sprintf("%d KXNFLGAME contracts in %d games, weeks %s; with a Tuesday price %d, with a close %d\n", nrow(cn), uniqueN(cn$game_id),
            paste(range(cn$week), collapse = "-"), sum(is.finite(cn$bid_tue) & is.finite(cn$ask_tue)), sum(is.finite(cn$bid_close) & is.finite(cn$ask_close))))
