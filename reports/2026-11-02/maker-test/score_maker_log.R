# Scores the owner's live maker test of A3 (MAKER_TEST.md). Reads maker_log.csv, one row per order leg, and fetches each
# logged contract's settlement (GET /markets/{ticker}) and hourly candles (GET /markets/candlesticks), keyless, through
# R/capture_raw.R's GET (truthful user agent, at most one request a second; a 403 stops the run). Writes:
# - fills: per leg, the share of orders that filled and the median minutes to the first fill; the share of pairs complete;
# - adverse selection: the mid's move from the fill to the kickoff (the last candle at or before each), in the filled
#   side's favour (a negative mean is adverse);
# - returns: per filled contract, the settlement against the limit price and Kalshi's maker fee (0.0175 P (1 - P)); per
#   completed pair, the two legs together; 90% intervals resample games (B = 2,000, seed 20261102);
# - the verdict: live when at least 30% of pairs complete and the completed pairs' 90% lower bound is above 0.
# Run from the repository root:
#   Rscript reports/2026-11-02/maker-test/score_maker_log.R <out_dir> --log=<maker_log.csv>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
log_csv <- sub("^--log=", "", grep("^--log=", args, value = TRUE))
cfg <- new.env(); sys.source("config.R", envir = cfg); source("R/capture_raw.R")
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
MAKER_FEE <- function(p) 0.0175 * p * (1 - p)
lg <- fread(log_csv, colClasses = list(character = c("pair_id", "placed_utc", "ticker", "leg", "fill_utc", "cancelled_utc")))
stopifnot(nrow(lg) > 0, all(lg$leg %in% c("protected_buy", "unprotected_sell")), all(is.finite(lg$limit_price)))
lg <- lg[!grepl("EXAMPLE", ticker)]   # the template's rows
tp <- function(x) as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
lg[, `:=`(placed = tp(placed_utc), filled_at = tp(fill_utc), filled = filled_contracts > 0)]
get <- function(url) { r <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC, cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
  if (identical(r$status, 403L)) stop("score_maker_log: HTTP 403, stopping", call. = FALSE)
  if (is.null(r$body)) NULL else jsonlite::parse_json(rawToChar(r$body)) }
mk <- rbindlist(lapply(unique(lg$ticker), function(tk) { m <- get(sprintf("%s/markets/%s", KALSHI_BASE, tk))$market
  data.table(ticker = tk, event_ticker = m$event_ticker %||% NA_character_, result = m$result %||% NA_character_,
             y = suppressWarnings(as.numeric(m$settlement_value_dollars %||% NA))) }))
mk <- merge(mk, props_event_games(mk$event_ticker, props_schedule()), by = "event_ticker", all.x = TRUE)
stopifnot(!any(format(mk$kick, "%Y") == "2025", na.rm = TRUE))
# hourly candles over each game's window, for the mid at the fill and at the kickoff
at <- function(ts, v, t) { i <- which(ts <= t); if (length(i)) v[max(i)] else NA_real_ }
cd <- rbindlist(lapply(split(mk[!is.na(game_id)], by = "game_id"), function(g) {
  t0 <- as.integer(min(lg[ticker %in% g$ticker, placed])) - 3600L; t1 <- as.integer(g$kick[1])
  j <- get(sprintf("%s/markets/candlesticks?market_tickers=%s&start_ts=%d&end_ts=%d&period_interval=60", KALSHI_BASE,
                   utils::URLencode(paste(g$ticker, collapse = ","), reserved = TRUE), t0, t1))$markets
  rbindlist(lapply(j, function(m) { cs <- m$candlesticks
    data.table(ticker = m$market_ticker, ts = vapply(cs, function(c) as.numeric(c$end_period_ts), 0),
               mid = vapply(cs, function(c) (as.numeric(c$yes_bid$close_dollars %||% NA) + as.numeric(c$yes_ask$close_dollars %||% NA)) / 2, 0)) }))
}), fill = TRUE)
x <- merge(lg, mk[, .(ticker, game_id, kick, result, y)], by = "ticker", all.x = TRUE)
x[, `:=`(mid_fill = mapply(function(tk, t) if (is.na(t)) NA_real_ else at(cd[ticker == tk, ts], cd[ticker == tk, mid], as.numeric(t)), ticker, filled_at),
         mid_kick = mapply(function(tk, t) at(cd[ticker == tk, ts], cd[ticker == tk, mid], as.numeric(t)), ticker, kick))]
x[, sign := fifelse(leg == "protected_buy", 1, -1)]
x[filled == TRUE, `:=`(move_for = sign * (mid_kick - mid_fill), pnl = sign * (y - limit_price) - MAKER_FEE(limit_price))]
gci <- function(v, g) { set.seed(20261102); u <- unique(g); if (length(u) < 2) return(c(NA_real_, NA_real_))
  s <- tapply(v, g, sum)[u]; n <- tapply(v, g, length)[u]
  unname(stats::quantile(replicate(2000, { i <- sample.int(length(u), replace = TRUE); sum(s[i]) / sum(n[i]) }), c(0.05, 0.95))) }
fills <- x[, .(orders = .N, filled_share = mean(filled), median_minutes_to_fill = stats::median(as.numeric(difftime(filled_at, placed, units = "mins")), na.rm = TRUE)), by = leg]
pairs <- x[, .(legs = .N, both = all(filled), game_id = game_id[1]), by = pair_id]
pp <- x[pair_id %in% pairs[both == TRUE, pair_id], .(pnl = sum(pnl), game_id = game_id[1]), by = pair_id]
legs <- x[filled == TRUE & is.finite(pnl)]
res <- data.table(measure = c("pairs placed", "pairs complete (share)", "filled legs", "adverse selection: mean move for the filled side (dollars)",
                              "return per filled contract (dollars)", "return per completed pair (dollars)"),
                  value = c(nrow(pairs), mean(pairs$both), nrow(legs), mean(legs$move_for, na.rm = TRUE), mean(legs$pnl), if (nrow(pp)) mean(pp$pnl) else NA_real_),
                  lo90 = c(NA, NA, NA, gci(legs$move_for[is.finite(legs$move_for)], legs$game_id[is.finite(legs$move_for)])[1], gci(legs$pnl, legs$game_id)[1],
                           if (nrow(pp)) gci(pp$pnl, pp$game_id)[1] else NA),
                  hi90 = c(NA, NA, NA, gci(legs$move_for[is.finite(legs$move_for)], legs$game_id[is.finite(legs$move_for)])[2], gci(legs$pnl, legs$game_id)[2],
                           if (nrow(pp)) gci(pp$pnl, pp$game_id)[2] else NA))
verdict <- data.table(rule = "live when at least 30% of pairs complete and the completed pairs' 90% lower bound is above 0",
                      live = isTRUE(mean(pairs$both) >= 0.30 && nrow(pp) > 1 && gci(pp$pnl, pp$game_id)[1] > 0))
fwrite(fills, file.path(out, "maker_fills.csv"), eol = "\n"); fwrite(res, file.path(out, "maker_results.csv"), eol = "\n")
fwrite(verdict, file.path(out, "maker_verdict.csv"), eol = "\n")
options(width = 200); print(fills); print(res); print(verdict)
