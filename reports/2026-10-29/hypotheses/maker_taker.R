# Family C of PLAN.md: who earns before kickoff on Kalshi, the maker or the taker? From kalshi_trades.R's sample of
# 2026 week 1-7 contracts (every KXNFLGAME contract and 2,000 others), each trade in the 72 hours before kickoff:
# - the maker's P&L per contract is p - y when the taker bought YES at p, and y - p when the taker bought NO at 1 - p;
#   the taker's is the negative, less the taker fee 0.07 P (1 - P); the maker fee 0.0175 P (1 - P) gives the net maker P&L;
# - C1 the net maker P&L per contract, count-weighted, clustered by game (H1: > 0);
# - C2 the last day's net YES share of taker volume against the outcome beyond the close: y ~ offset(logit close) + share,
#   clustered by game (two-sided).
# Contracts settled at the pre-game fair price are dropped. The trades come summed by contract, taker side, price and
# window (kalshi_trades_agg.R); a sensitivity drops the contracts whose fetch hit the page cap. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/maker_taker.R <out_dir> --trades=<agg.csv.gz> --sample=<csv> --settled=<a>,<b> --candles=<a>,<b>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
tr <- fread(opt("trades")); smp <- fread(opt("sample"))
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")
cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
maker_fee <- function(p) 0.0175 * p * (1 - p)
smp <- merge(smp, st[, .(ticker, result, y = settlement_value)], by = "ticker")
smp[, outcome := props_outcome(series, game_id, result, y)]
smp <- smp[outcome %in% c("settled", "payout")]
smp[, group := group_of(series)]
stopifnot(!any(substr(smp$kick, 1, 4) == "2025"))
tr <- merge(tr, smp[, .(ticker, game_id, group, y)], by = "ticker")
tr[, maker_gross := fifelse(taker_side == "yes", yes_price - y, y - yes_price)]
tr[, `:=`(maker_net = maker_gross - maker_fee(yes_price), taker_net = -maker_gross - fee(yes_price))]
cl_mean <- function(v, w, g) {   # a count-weighted mean, its game-clustered SE and the one-sided p of > 0
  x <- data.table(v, w, g)[, .(s = sum(v * w), n = sum(w)), by = g]; m <- sum(x$s) / sum(x$n); G <- nrow(x)
  se <- sqrt(G / (G - 1) * sum((x$s - m * x$n)^2)) / sum(x$n)
  list(mean = m, lo = m - stats::qt(0.975, G - 1) * se, hi = m + stats::qt(0.975, G - 1) * se, p_greater = stats::pt(-m / se, G - 1), games = G,
       mde = (stats::qt(0.95, G - 1) + stats::qt(0.8, G - 1)) * se)   # the effect a one-sided 5% test detects with 80% power
}
seg <- function(x, by) x[, { a <- cl_mean(maker_net, count, game_id); b <- cl_mean(maker_gross, count, game_id); c2 <- cl_mean(taker_net, count, game_id)
  .(trades = sum(trades), contracts = sum(count), games = a$games, maker_net = a$mean, maker_net_lo = a$lo, maker_net_hi = a$hi, p = a$p_greater,
    maker_gross = b$mean, taker_net = c2$mean, taker_net_lo = c2$lo, taker_net_hi = c2$hi) }, by = by]
tr[, bucket := cut(yes_price, c(0, 0.1, 0.3, 0.5, 0.7, 0.9, 1), include.lowest = TRUE)]
tr[, all := "all"]
c1 <- seg(tr, "all"); c1_group <- seg(tr, "group"); c1_bucket <- seg(tr, "bucket"); c1_window <- seg(tr, "window")
c1_uncapped <- seg(tr[capped == FALSE], "all")[, all := "without the page-capped contracts"]
# C2: the last day's taker flow against the outcome beyond the close
fl <- tr[window != "(24,72]", .(yes = sum(count[taker_side == "yes"]), no = sum(count[taker_side == "no"])), by = .(ticker, game_id, y)]
fl[, share := (yes - no) / (yes + no)]
fl <- merge(fl, cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker")
fl <- fl[is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & ask - bid <= MAX_SPREAD][, mid := (bid + ask) / 2][mid > 0 & mid < 1]
m2 <- stats::glm(y ~ offset(lg(mid)) + share, family = stats::quasibinomial(), data = fl)
V2 <- sandwich::vcovCL(m2, cluster = fl$game_id, type = "HC1"); G2 <- uniqueN(fl$game_id); b2 <- unname(stats::coef(m2)["share"]); se2 <- sqrt(V2["share", "share"])
tests <- data.table(id = c("C1", "C2"), test = c("makers earn a positive return before kickoff, net of the maker fee (one-sided > 0)",
                                                "the last day's net YES taker share predicts the outcome beyond the close (two-sided)"),
                    n = c(c1$contracts, nrow(fl)), games = c(c1$games, G2), estimate = c(c1$maker_net, b2),
                    lo = c(c1$maker_net_lo, b2 - stats::qt(0.975, G2 - 1) * se2), hi = c(c1$maker_net_hi, b2 + stats::qt(0.975, G2 - 1) * se2),
                    p = c(c1$p, 2 * stats::pt(-abs(b2 / se2), G2 - 1)),
                    mde_80 = c(cl_mean(tr$maker_net, tr$count, tr$game_id)$mde, (stats::qt(0.975, G2 - 1) + stats::qt(0.8, G2 - 1)) * se2))
tests[, q_bh := stats::p.adjust(p, "BH")]
fwrite(signif_dt(tests), file.path(out, "maker_taker_tests.csv"))
fwrite(signif_dt(rbindlist(list(cbind(cut = "group", c1_group), cbind(cut = "price", c1_bucket), cbind(cut = "hours before kickoff", c1_window),
                                cbind(cut = "sensitivity", c1_uncapped)), fill = TRUE)), file.path(out, "maker_taker_segments.csv"))
options(width = 220)
print(signif_dt(tests, 4)); print(signif_dt(rbind(c1, c1_uncapped), 4))
cat("\nby group, price and time:\n"); print(signif_dt(rbindlist(list(c1_group, c1_bucket, c1_window), fill = TRUE), 3))
cat(sprintf("\ncontracts in the sample with an outcome: %d; with trades before kickoff: %d; trades: %d\n", nrow(smp), uniqueN(tr$ticker), sum(tr$trades)))
