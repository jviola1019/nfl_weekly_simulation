# Each settled contract's price at kickoff, from Kalshi's hourly candles (GET /markets/candlesticks, keyless, up to 100
# tickers a request) over the 48 hours before its game's scheduled kickoff. The capture archive cannot give it: GitHub
# starts the scheduled captures 2-4 hours late, so a game-day run can land after the 1 p.m. kickoffs (17:03Z on
# 2026-10-25) and those games' last capture is the day before. A candle covers the hour that ends at end_period_ts; an
# hour with no change has none, so the price at a time is the close of the last candle ending at or before it.
# Requests go through the capture layer's GET (R/capture_raw.R: truthful user agent, 20 s timeout, at most one request
# a second, a 403 stops the run). Only the contracts in kalshi_settled.csv.gz (2026 weeks 6-7) are requested.
# Run from the repository root:
#   Rscript reports/2026-10-28/feasibility/kalshi_candles.R <out_dir> <kalshi_settled.csv.gz>
# Writes <out_dir>/raw/ (the responses, gzipped) and <out_dir>/kalshi_candles.csv.gz (one row per contract).
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE); out <- args[1]; settled_csv <- args[2]
raw <- file.path(out, "raw"); dir.create(raw, recursive = TRUE, showWarnings = FALSE)
cfg <- new.env(); sys.source("config.R", envir = cfg); source("R/capture_raw.R")
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
WINDOW_H <- 48L; BATCH <- 100L   # 48 hourly candles x 100 tickers stays under the endpoint's 10,000-candle cap
st <- as.data.table(utils::read.csv(gzfile(settled_csv), stringsAsFactors = FALSE))
sched <- props_schedule()
st <- merge(st[, .(ticker, event_ticker)], props_event_games(st$event_ticker, sched), by = "event_ticker")
stopifnot(!any(format(st$kick, "%Y") == "2025"))   # the seal: 2026 only
st <- st[kick < Sys.time()]
num <- function(v) suppressWarnings(as.numeric(v))
at <- function(ts, v, t) { i <- which(ts <= t); if (length(i)) v[max(i)] else NA_real_ }
iso <- function(t) format(as.POSIXct(t, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
rows <- list(); log <- list(); k <- 0L
for (gid in unique(st$game_id)) {
  s <- st[game_id == gid]; kick <- as.integer(s$kick[1])
  for (b in split(s$ticker, ceiling(seq_along(s$ticker) / BATCH))) {
    k <- k + 1L
    url <- sprintf("%s/markets/candlesticks?market_tickers=%s&start_ts=%d&end_ts=%d&period_interval=60", KALSHI_BASE,
                   utils::URLencode(paste(b, collapse = ","), reserved = TRUE), kick - WINDOW_H * 3600L, kick)
    r <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC, cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
    log[[k]] <- data.table(game_id = gid, request = k, tickers = length(b), status = r$status, error = r$error, bytes = length(r$body))
    if (identical(r$status, 403L)) stop("kalshi_candles: HTTP 403, so the venue is dropped for this run, never retried", call. = FALSE)
    if (is.null(r$body)) next
    con <- gzfile(file.path(raw, sprintf("candles_%04d.json.gz", k)), "wb"); writeBin(r$body, con); close(con)
    j <- jsonlite::fromJSON(rawToChar(r$body), simplifyVector = TRUE)$markets
    for (i in seq_len(NROW(j))) {
      cs <- j$candlesticks[[i]]
      ts <- if (NROW(cs)) cs$end_period_ts else numeric(0)
      bid <- if (NROW(cs)) num(cs$yes_bid$close_dollars) else numeric(0); ask <- if (NROW(cs)) num(cs$yes_ask$close_dollars) else numeric(0)
      te <- ts[ts <= kick]
      rows[[length(rows) + 1L]] <- data.table(ticker = j$market_ticker[i], game_id = gid, kick = iso(kick), candles = length(te),
        close_end = if (length(te)) iso(max(te)) else NA_character_, bid_close = at(ts, bid, kick), ask_close = at(ts, ask, kick),
        bid_1h = at(ts, bid, kick - 3600L), ask_1h = at(ts, ask, kick - 3600L), bid_3h = at(ts, bid, kick - 3L * 3600L),
        ask_3h = at(ts, ask, kick - 3L * 3600L), bid_24h = at(ts, bid, kick - 24L * 3600L), ask_24h = at(ts, ask, kick - 24L * 3600L))
    }
  }
}
log <- rbindlist(log); cn <- rbindlist(rows, fill = TRUE)
fwrite(cn, file.path(out, "kalshi_candles.csv.gz"))
fwrite(log, file.path(out, "kalshi_candles_log.csv"))
cat(sprintf("games %d; requests %d (failed %d); contracts requested %d, returned %d, with a close at kickoff %d\n", uniqueN(st$game_id), nrow(log),
            sum(is.na(log$status) | log$status >= 400), nrow(st), nrow(cn), sum(is.finite(cn$bid_close) & is.finite(cn$ask_close))))
