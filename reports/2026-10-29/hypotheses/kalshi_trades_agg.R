# Family C input: kalshi_trades.R's trades before kickoff, summed by contract, taker side, price and time window, so the
# 2.6 million trades fit in a committed file; a maker's P&L is linear in the contract count, so maker_taker.R needs only
# these sums. Contracts whose fetch hit the 20-page cap (kalshi_trades_log.csv) are flagged: the cap keeps the newest
# trades, so their earliest trades in the 72-hour window are missing. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/kalshi_trades_agg.R <out.csv.gz> <kalshi_trades.csv.gz> <kalshi_trades_sample.csv> <kalshi_trades_log.csv>
suppressPackageStartupMessages(library(data.table))
a <- commandArgs(trailingOnly = TRUE)
tr <- as.data.table(utils::read.csv(gzfile(a[2]), stringsAsFactors = FALSE)); smp <- fread(a[3]); pages <- fread(a[4])
smp[, kick_t := as.POSIXct(kick, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]
tr <- merge(tr, smp[, .(ticker, kick_t)], by = "ticker")
tr[, t := as.POSIXct(substr(created_time, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")]
stopifnot(!anyNA(tr$t), !any(format(tr$t, "%Y") == "2025"))
n_all <- nrow(tr)
tr <- tr[t < kick_t & count > 0 & yes_price > 0 & yes_price < 1 & taker_side %in% c("yes", "no")]
tr[, window := cut(as.numeric(difftime(kick_t, t, units = "hours")), c(0, 1, 6, 24, 72), include.lowest = TRUE)]
ag <- tr[, .(trades = .N, count = sum(count)), by = .(ticker, taker_side, yes_price, window)]
capped <- pages[, .(p = max(page)), by = ticker][p >= 20L, ticker]
ag[, capped := ticker %in% capped]
setorder(ag, ticker, window, taker_side, yes_price)
fwrite(ag, a[1])
cat(sprintf("trades read %d, kept %d (before kickoff, priced inside (0, 1)); rows %d; contracts %d, of them page-capped %d; contracts traded %.0f\n",
            n_all, nrow(tr), nrow(ag), uniqueN(ag$ticker), uniqueN(ag[capped == TRUE, ticker]), sum(ag$count)))
