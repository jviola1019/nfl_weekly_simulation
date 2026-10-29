# How did Kalshi settle each contract the capture archive priced? One keyless, read-only pass over
# /markets?status=settled for every series in the captures, windowed by close time (by default 2026-10-13 to
# 2026-10-28, the games of 2026 weeks 6 and 7), so no other market, and none from 2025, is requested. Settled markets after
# Kalshi's historical cutoff (2026-08-29) stay under /markets. Requests go through the capture layer's GET
# (R/capture_raw.R: truthful user agent, 20 s timeout, at most one request a second, a 403 is not retried).
# Run from the repository root, with each extracted archive in its own directory:
#   Rscript reports/2026-10-28/feasibility/kalshi_settled.R <out_dir> <capture_dir> [<capture_dir> ...] [--from=YYYY-MM-DD --to=YYYY-MM-DD]
# Writes <out_dir>/raw/ (the responses, gzipped) and <out_dir>/kalshi_settled.csv.gz (one row per contract). The capture
# directories only name the series; --from and --to move the close-time window (weeks 1-5: 2026-09-09 to 2026-10-13).
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default) { hit <- grep(sprintf("^--%s=", name), args, value = TRUE); if (length(hit)) sub(sprintf("^--%s=", name), "", hit[1]) else default }
WINDOW <- as.POSIXct(c(opt("from", "2026-10-13"), opt("to", "2026-10-28")), format = "%Y-%m-%d", tz = "UTC")
stopifnot(!anyNA(WINDOW), WINDOW[1] >= as.POSIXct("2026-08-01", tz = "UTC"), WINDOW[1] < WINDOW[2])   # 2026 only: the 2025 seal
args <- grep("^--", args, value = TRUE, invert = TRUE)
out <- args[1]; dirs <- args[-1]
raw <- file.path(out, "raw"); dir.create(raw, recursive = TRUE, showWarnings = FALSE)
cfg <- new.env(); sys.source("config.R", envir = cfg); source("R/capture_raw.R")
files <- list.files(dirs, pattern = "^KXNFL[A-Z0-9]+_p[0-9]+__[0-9]{8}T[0-9]{6}Z\\.json\\.gz$", recursive = TRUE)
series <- sort(unique(sub("_p[0-9]+__.*$", "", basename(files))))
fld <- function(m, n) if (n %in% names(m)) as.character(m[[n]]) else rep(NA_character_, NROW(m))
log <- list(); rows <- list()
for (s in series) {
  cursor <- ""; page <- 0L
  repeat {
    page <- page + 1L
    url <- sprintf("%s/markets?series_ticker=%s&status=settled&min_close_ts=%d&max_close_ts=%d&limit=1000%s", KALSHI_BASE,
                   utils::URLencode(s, reserved = TRUE), as.integer(WINDOW[1]), as.integer(WINDOW[2]),
                   if (nzchar(cursor)) paste0("&cursor=", utils::URLencode(cursor, reserved = TRUE)) else "")
    r <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC, cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
    log[[length(log) + 1L]] <- data.table(series = s, page = page, status = r$status, error = r$error, bytes = length(r$body))
    if (identical(r$status, 403L)) stop("kalshi_settled: HTTP 403, so the venue is dropped for this run, never retried", call. = FALSE)
    if (is.null(r$body)) break
    con <- gzfile(file.path(raw, sprintf("%s_p%d.json.gz", s, page)), "wb"); writeBin(r$body, con); close(con)
    j <- jsonlite::fromJSON(rawToChar(r$body), simplifyVector = TRUE)
    m <- j$markets
    if (NROW(m)) rows[[length(rows) + 1L]] <- data.table(series = s, ticker = fld(m, "ticker"), event_ticker = fld(m, "event_ticker"),
      market_type = fld(m, "market_type"), status = fld(m, "status"), result = fld(m, "result"),
      settlement_value = suppressWarnings(as.numeric(fld(m, "settlement_value_dollars"))), close_time = fld(m, "close_time"),
      settlement_ts = fld(m, "settlement_ts"), label = fld(m, "no_sub_title"))
    cursor <- if (is.null(j$cursor)) "" else j$cursor
    if (!nzchar(cursor) || !NROW(m)) break
  }
}
log <- rbindlist(log); st <- rbindlist(rows)
ct <- as.POSIXct(st$close_time, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
stopifnot(all(ct >= WINDOW[1] & ct <= WINDOW[2]), !any(substr(st$close_time, 1, 4) == "2025"))   # the window held; the seal held
st <- unique(st, by = "ticker")
fwrite(st, file.path(out, "kalshi_settled.csv.gz"))
fwrite(log, file.path(out, "kalshi_settled_log.csv"))
cat(sprintf("series queried %d; requests %d (failed %d); settled contracts %d in %d series\n", length(series), nrow(log),
            sum(is.na(log$status) | log$status >= 400), nrow(st), uniqueN(st$series)))
print(st[, .N, by = .(result, has_value = !is.na(settlement_value))])
