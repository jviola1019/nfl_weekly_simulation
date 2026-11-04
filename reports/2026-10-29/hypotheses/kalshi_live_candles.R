# Kalshi's in-game moneyline prices (Family D of PLAN.md): one-minute candles for every settled 2026 week 1-7
# KXNFLGAME contract from its game's scheduled kickoff to 4.5 hours after it. Games that share a kickoff share a
# request (GET /markets/candlesticks, keyless; at most 37 tickers x 270 one-minute candles stays under the endpoint's
# 10,000-candle cap), through the capture layer's GET (R/capture_raw.R; a 403 stops the run). Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/kalshi_live_candles.R <out_dir> <settled.csv.gz>[,<settled.csv.gz>]
# Writes <out_dir>/raw/ and <out_dir>/kalshi_live_candles.csv.gz (ticker, minute, yes bid and ask closes).
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE); out <- args[1]; settled <- strsplit(args[2], ",", fixed = TRUE)[[1]]
raw <- file.path(out, "raw"); dir.create(raw, recursive = TRUE, showWarnings = FALSE)
cfg <- new.env(); sys.source("config.R", envir = cfg); source("R/capture_raw.R")
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
WINDOW_MIN <- 270L; BATCH <- 37L
st <- unique(rbindlist(lapply(settled, function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE)))), by = "ticker")
st <- st[series == "KXNFLGAME"]
sched <- props_schedule()
st <- merge(st, props_event_games(st$event_ticker, sched), by = "event_ticker")
stopifnot(!any(format(st$kick, "%Y") == "2025"))
st <- st[kick < Sys.time() - WINDOW_MIN * 60]
num <- function(v) suppressWarnings(as.numeric(v))
rows <- list(); log <- list(); k <- 0L
for (kt in sort(unique(as.integer(st$kick)))) {
  tks <- st[as.integer(kick) == kt, ticker]
  for (b in split(tks, ceiling(seq_along(tks) / BATCH))) {
    k <- k + 1L
    url <- sprintf("%s/markets/candlesticks?market_tickers=%s&start_ts=%d&end_ts=%d&period_interval=1", KALSHI_BASE,
                   utils::URLencode(paste(b, collapse = ","), reserved = TRUE), kt, kt + WINDOW_MIN * 60L)
    r <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC, cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
    log[[k]] <- data.table(kick = kt, request = k, tickers = length(b), status = r$status, error = r$error, bytes = length(r$body))
    if (identical(r$status, 403L)) stop("kalshi_live_candles: HTTP 403, so the venue is dropped for this run, never retried", call. = FALSE)
    if (is.null(r$body)) next
    con <- gzfile(file.path(raw, sprintf("live_%04d.json.gz", k)), "wb"); writeBin(r$body, con); close(con)
    j <- jsonlite::fromJSON(rawToChar(r$body), simplifyVector = TRUE)$markets
    for (i in seq_len(NROW(j))) {
      cs <- j$candlesticks[[i]]
      if (!NROW(cs)) next
      rows[[length(rows) + 1L]] <- data.table(ticker = j$market_ticker[i], end_ts = cs$end_period_ts, bid = num(cs$yes_bid$close_dollars),
                                              ask = num(cs$yes_ask$close_dollars), volume = num(cs$volume_fp))
    }
  }
}
log <- rbindlist(log); cn <- rbindlist(rows)
fwrite(cn, file.path(out, "kalshi_live_candles.csv.gz"))
fwrite(log, file.path(out, "kalshi_live_candles_log.csv"))
cat(sprintf("kickoffs %d; requests %d (failed %d); contracts %d of %d; minute candles %d\n", uniqueN(as.integer(st$kick)), nrow(log),
            sum(is.na(log$status) | log$status >= 400), uniqueN(cn$ticker), nrow(st), nrow(cn)))
