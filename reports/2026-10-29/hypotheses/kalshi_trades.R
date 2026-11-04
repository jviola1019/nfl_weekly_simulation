# Kalshi's trades before kickoff for a sample of settled 2026 week 1-7 contracts (Family C of PLAN.md): every
# KXNFLGAME contract and a seeded random sample of 2,000 other single-game contracts. One keyless pass over
# GET /markets/trades?ticker=&min_ts=&max_ts= (the 72 hours before the scheduled kickoff), up to 20 pages a contract,
# through the capture layer's GET (R/capture_raw.R: truthful user agent, 20 s timeout, at most one request a second; a
# 403 stops the run). Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/kalshi_trades.R <out_dir> <settled.csv.gz>[,<settled.csv.gz>]
# Writes <out_dir>/raw/ (the responses, gzipped) and <out_dir>/kalshi_trades.csv.gz (one row per trade).
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE); out <- args[1]; settled <- strsplit(args[2], ",", fixed = TRUE)[[1]]
raw <- file.path(out, "raw"); dir.create(raw, recursive = TRUE, showWarnings = FALSE)
cfg <- new.env(); sys.source("config.R", envir = cfg); source("R/capture_raw.R")
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
N_OTHER <- 2000L; MAX_PAGES <- 20L; WINDOW_H <- 72L
st <- unique(rbindlist(lapply(settled, function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE)))), by = "ticker")
stopifnot(!any(substr(st$close_time, 1, 4) == "2025"))
sched <- props_schedule()
st <- merge(st, props_event_games(st$event_ticker, sched), by = "event_ticker")
st[, outcome := props_outcome(series, game_id, result, settlement_value)]
st <- st[outcome %in% c("settled", "payout") & kick < Sys.time()]
set.seed(20261029)
pick <- rbind(st[series == "KXNFLGAME"], st[series != "KXNFLGAME"][sample.int(.N, min(N_OTHER, .N))])
num <- function(v) suppressWarnings(as.numeric(v))
rows <- list(); log <- list(); k <- 0L
for (i in seq_len(nrow(pick))) {
  tk <- pick$ticker[i]; kick <- as.integer(pick$kick[i]); cursor <- ""; page <- 0L
  repeat {
    page <- page + 1L; k <- k + 1L
    url <- sprintf("%s/markets/trades?ticker=%s&min_ts=%d&max_ts=%d&limit=1000%s", KALSHI_BASE, utils::URLencode(tk, reserved = TRUE),
                   kick - WINDOW_H * 3600L, kick, if (nzchar(cursor)) paste0("&cursor=", utils::URLencode(cursor, reserved = TRUE)) else "")
    r <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC, cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
    log[[k]] <- data.table(ticker = tk, page = page, status = r$status, error = r$error, bytes = length(r$body))
    if (identical(r$status, 403L)) stop("kalshi_trades: HTTP 403, so the venue is dropped for this run, never retried", call. = FALSE)
    if (is.null(r$body)) break
    con <- gzfile(file.path(raw, sprintf("trades_%05d.json.gz", k)), "wb"); writeBin(r$body, con); close(con)
    j <- jsonlite::fromJSON(rawToChar(r$body), simplifyVector = TRUE)
    tr <- j$trades
    if (NROW(tr)) rows[[length(rows) + 1L]] <- data.table(ticker = tk, created_time = tr$created_time, count = num(tr$count_fp),
                                                         yes_price = num(tr$yes_price_dollars), taker_side = tr$taker_side)
    cursor <- if (is.null(j$cursor)) "" else j$cursor
    if (!nzchar(cursor) || !NROW(tr) || page >= MAX_PAGES) break
  }
}
log <- rbindlist(log); trades <- rbindlist(rows)
ct <- as.POSIXct(substr(trades$created_time, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
stopifnot(!any(format(ct, "%Y") == "2025"))
fwrite(trades, file.path(out, "kalshi_trades.csv.gz"))
fwrite(log, file.path(out, "kalshi_trades_log.csv"))
fwrite(pick[, .(ticker, series, game_id, kick = format(kick, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))], file.path(out, "kalshi_trades_sample.csv"))
cat(sprintf("contracts %d; requests %d (failed %d); contracts that hit the page cap %d; trades %d\n", nrow(pick), nrow(log),
            sum(is.na(log$status) | log$status >= 400), log[, .(p = max(page)), by = ticker][p >= MAX_PAGES, .N], nrow(trades)))
