# Family A3-A6 of PLAN.md: are related Kalshi contracts priced consistently at the close, 2026 weeks 1-7?
# - A3 protected twins (TDPROT vs TD, ...): a protected YES pays at least the unprotected YES in every state, so an
#   unprotected bid above the protected ask (after both fees) is a sure profit; and is the protection premium (price
#   gap) right on average against the realized payout gap? (two-sided, clustered by game)
# - A4 the touchdown family: scoring the game's first TD implies the team's first, which implies an anytime TD, so a
#   bid on the narrower contract above the ask on the wider one is a sure profit.
# - A5 scalar ladders (LADDERREC $0.05 a catch, LADDERRECYDS and LADDERRSHYDS $0.0025 a yard) against the binary
#   ladder of the same stat: the binary ladder's implied mean (its survival curve, linear between rungs) against the
#   scalar's; does the gap predict the realized stat? (two-sided)
# - A6 rungs of one ladder: a higher rung's bid above a lower rung's ask (after fees) is a sure profit.
# Run from the repository root:  Rscript reports/2026-10-29/hypotheses/kalshi_consistency.R <out_dir> --settled=<a>,<b> --candles=<a>,<b>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")
cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
stopifnot(!any(substr(st$close_time, 1, 4) == "2025"))
sched <- props_schedule()
d <- merge(st[, .(ticker, series, event_ticker, label, result, y = settlement_value)], props_event_games(st$event_ticker, sched), by = "event_ticker")
d <- merge(d, cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker")
d <- d[is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid]
d[, `:=`(mid = (bid + ask) / 2, seg = substring(ticker, nchar(event_ticker) + 2L),
         k = suppressWarnings(as.numeric(sub("^.*: ([0-9.]+)\\+$", "\\1", label))))]
norm <- function(x) { x <- tolower(iconv(x, to = "ASCII//TRANSLIT")); x <- gsub("[.'`-]", "", x)
  x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("\\s+", " ", trimws(x)) }
d[, key := norm(sub(":.*$", "", label))]
gboot <- function(v, g, B = 2000) { set.seed(20261029); gm <- tapply(v, g, mean); G <- length(gm)
  stats::quantile(replicate(B, mean(gm[sample.int(G, replace = TRUE)])), c(0.025, 0.975)) }

# --- A3: protected twins --------------------------------------------------------------------------------------------------
base <- c("KXNFLTD", "KXNFLREC", "KXNFLRECYDS", "KXNFLRSHYDS", "KXNFLPASSYDS", "KXNFLPASSTDS")
pr <- merge(d[series %in% paste0(base, "PROT"), .(game_id, base = sub("PROT$", "", series), seg, bid_p = bid, ask_p = ask, mid_p = mid, y_p = y, result_p = result)],
            d[series %in% base, .(game_id, base = series, seg, bid_u = bid, ask_u = ask, mid_u = mid, y_u = y, result_u = result)], by = c("game_id", "base", "seg"))
pr[, `:=`(arb = bid_u - ask_p - fee(ask_p) - fee(1 - bid_u), price_gap = mid_p - mid_u, payout_gap = y_p - y_u)]
# sure profits use every executable quote; the premium test and the wrong-side count use quotes within the spread limit,
# since a quote with no real bid or ask (0 / 0.99) has a meaningless mid
prq <- pr[ask_p - bid_p <= MAX_SPREAD & ask_u - bid_u <= MAX_SPREAD]
a3_m <- stats::lm(I(payout_gap - price_gap) ~ 1, data = prq)
a3_V <- sandwich::vcovCL(a3_m, cluster = prq$game_id, type = "HC1"); G3 <- uniqueN(prq$game_id)
a3 <- data.table(id = "A3", test = "protection premium priced right on average (payout gap - price gap = 0)", pairs = nrow(prq), games = G3,
                 mean_price_gap = mean(prq$price_gap), mean_payout_gap = mean(prq$payout_gap), estimate = unname(stats::coef(a3_m)[1]),
                 p = 2 * stats::pt(-abs(stats::coef(a3_m)[1] / sqrt(a3_V[1, 1])), G3 - 1), protection_triggered = sum(pr$result_p == "scalar" & pr$result_u != "scalar"),
                 sure_profits = sum(pr$arb > 0), best_sure_profit = max(pr$arb), wrong_side_quotes = sum(prq$mid_p < prq$mid_u), all_pairs = nrow(pr))
# the pair trade (long protected YES, short unprotected YES): a taker pays both asks and both taker fees; a maker trades at
# the mids and pays the maker fee (0.0175 P (1 - P), which Kalshi charges on NFL series) on each leg
maker_fee <- function(p) 0.0175 * p * (1 - p)
prq[, `:=`(pnl_taker = payout_gap - (ask_p - bid_u) - fee(ask_p) - fee(1 - bid_u), pnl_maker = payout_gap - price_gap - maker_fee(mid_p) - maker_fee(1 - mid_u))]
gci <- function(v, g) { set.seed(20261029); gm <- tapply(v, g, sum); n <- tapply(v, g, length); G <- length(gm)
  stats::quantile(replicate(2000, { i <- sample.int(G, replace = TRUE); sum(gm[i]) / sum(n[i]) }), c(0.025, 0.975)) }
a3[, `:=`(taker_pnl_per_pair = mean(prq$pnl_taker), taker_lo = gci(prq$pnl_taker, prq$game_id)[1], taker_hi = gci(prq$pnl_taker, prq$game_id)[2],
          maker_pnl_per_pair = mean(prq$pnl_maker), maker_lo = gci(prq$pnl_maker, prq$game_id)[1], maker_hi = gci(prq$pnl_maker, prq$game_id)[2],
          yes_buyer_saving = mean(prq$payout_gap - prq$price_gap))]
a3_by <- prq[, .(pairs = .N, games = uniqueN(game_id), mean_price_gap = mean(price_gap), mean_payout_gap = mean(payout_gap), protected_cheaper = mean(mid_p < mid_u),
                 taker_pnl = mean(pnl_taker), maker_pnl = mean(pnl_maker)), by = base]

# --- A4: first TD <= team first TD <= anytime TD ---------------------------------------------------------------------------
td <- d[series == "KXNFLTD" & k == 1, .(game_id, key, bid_a = bid, ask_a = ask, y_a = y)]
ft <- d[series == "KXNFLFIRSTTD" & !grepl("D/ST|No Touchdown", label), .(game_id, key, bid_f = bid, ask_f = ask, y_f = y)]
tf <- d[series == "KXNFLTEAMFIRSTTD" & !grepl("D/ST|No ", label), .(game_id, key, bid_t = bid, ask_t = ask, y_t = y)]
tdf <- merge(merge(ft, tf, by = c("game_id", "key")), td, by = c("game_id", "key"))
tdf[, `:=`(arb_ft = bid_f - ask_t - fee(ask_t) - fee(1 - bid_f), arb_ta = bid_t - ask_a - fee(ask_a) - fee(1 - bid_t))]
a4 <- data.table(id = "A4", test = "first TD <= team first TD <= anytime TD at the bid and ask", players = nrow(tdf), games = uniqueN(tdf$game_id),
                 sure_profits = sum(tdf$arb_ft > 0) + sum(tdf$arb_ta > 0), best_sure_profit = max(c(tdf$arb_ft, tdf$arb_ta)),
                 wrong_order_mids = sum((tdf$bid_f + tdf$ask_f) / 2 > (tdf$bid_t + tdf$ask_t) / 2 | (tdf$bid_t + tdf$ask_t) / 2 > (tdf$bid_a + tdf$ask_a) / 2))

# --- A5: scalar ladders against binary ladders -------------------------------------------------------------------------------
pairs5 <- list(KXNFLLADDERREC = list(bin = "KXNFLREC", per = 0.05, cap = 20), KXNFLLADDERRECYDS = list(bin = "KXNFLRECYDS", per = 0.0025, cap = 400),
               KXNFLLADDERRSHYDS = list(bin = "KXNFLRSHYDS", per = 0.0025, cap = 400))
implied_mean <- function(k, s) {   # E[Y] = sum over k >= 1 of P(Y >= k) for a count; P(Y >= k) linear between the rungs,
  o <- order(k); k <- k[o]; s <- cummin(pmin(pmax(s[o], 0), 1))   # with P(Y >= 0) = 1 and one more rung spacing to 0
  top <- max(k) + if (length(k) > 1) diff(utils::tail(k, 2)) else max(k)
  sum(stats::approx(c(0, k, top), c(1, s, 0), xout = seq_len(ceiling(top)), ties = mean)$y)
}
a5d <- rbindlist(lapply(names(pairs5), function(sc) {
  p <- pairs5[[sc]]
  # quotes within the spread limit only: a scalar quoted 0 / 0.99 has a mid of 0.495 and no meaning
  scal <- d[series == sc & result == "scalar" & ask - bid <= MAX_SPREAD, .(game_id, week, key, mid_s = mid, bid_s = bid, ask_s = ask, y_s = y, per = p$per,
                                                                          realized = pmin(y / p$per, p$cap))]
  lad <- d[series == p$bin & !is.na(k) & result %in% c("yes", "no") & ask - bid <= MAX_SPREAD, .(e_ladder = implied_mean(k, mid), rungs = .N), by = .(game_id, key)][rungs >= 2]
  x <- merge(scal, lad, by = c("game_id", "key"))
  x[, `:=`(series = sc, e_scalar = mid_s / p$per)]
}), fill = TRUE)
a5_m <- stats::lm(I(realized - e_scalar) ~ I(e_ladder - e_scalar), data = a5d)
a5_V <- sandwich::vcovCL(a5_m, cluster = a5d$game_id, type = "HC1"); G5 <- uniqueN(a5d$game_id)
a5 <- data.table(id = "A5", test = "the binary ladder's implied mean predicts the stat beyond the scalar's (slope on the gap)", pairs = nrow(a5d), games = G5,
                 mean_gap = mean(a5d$e_ladder - a5d$e_scalar), estimate = unname(stats::coef(a5_m)[2]),
                 p = 2 * stats::pt(-abs(stats::coef(a5_m)[2] / sqrt(a5_V[2, 2])), G5 - 1),
                 mse_scalar = mean((a5d$realized - a5d$e_scalar)^2), mse_ladder = mean((a5d$realized - a5d$e_ladder)^2))
a5_by <- a5d[, .(pairs = .N, mean_e_scalar = mean(e_scalar), mean_e_ladder = mean(e_ladder), mean_realized = mean(realized),
                 mse_scalar = mean((realized - e_scalar)^2), mse_ladder = mean((realized - e_ladder)^2)), by = series]
# A5 as a trade, with no fitted parameter: price the scalar at the binary ladder's mean; a taker buys YES at the ask when that
# beats it after the fee, or NO at 1 - bid; the interval resamples games
a5d[, f := pmin(e_ladder * per, 1)]
a5d[, side := fcase(f > ask_s + fee(ask_s), "yes", 1 - f > 1 - bid_s + fee(1 - bid_s), "no", default = "none")]
a5d[, `:=`(pnl = fcase(side == "yes", y_s - ask_s - fee(ask_s), side == "no", bid_s - y_s - fee(1 - bid_s), default = 0),
           stake = fcase(side == "yes", ask_s + fee(ask_s), side == "no", 1 - bid_s + fee(1 - bid_s), default = 0))]
roi_ci <- function(b) { g <- unique(b$game_id); if (length(g) < 2) return(c(NA_real_, NA_real_)); set.seed(20261029)
  stats::quantile(replicate(2000, { bb <- b[data.table(game_id = sample(g, replace = TRUE)), on = "game_id", allow.cartesian = TRUE]; sum(bb$pnl) / sum(bb$stake) }), c(0.025, 0.975)) }
b5 <- a5d[side != "none"]
a5[, `:=`(bets = nrow(b5), roi = sum(b5$pnl) / sum(b5$stake), roi_lo = roi_ci(b5)[1], roi_hi = roi_ci(b5)[2],
          bets_w67 = b5[week >= 6, .N], roi_w67 = b5[week >= 6, sum(pnl) / sum(stake)])]

# --- A6: rungs of one ladder -------------------------------------------------------------------------------------------------
lad6 <- d[!is.na(k) & series %in% c(names(LADDERS), paste0(base, "PROT")), .(game_id, series, key, k, bid, ask)]
lad6 <- rbind(lad6, d[series %in% c("KXNFLSPREAD", "KXNFLTOTAL", "KXNFLTEAMTOTAL"),
                      .(game_id, series, key = sub("[0-9]+$", "", seg), k = as.numeric(sub("^.*[Oo]ver ([0-9.]+).*$", "\\1", label)), bid, ask)])
setorder(lad6, game_id, series, key, k)
viol <- lad6[, { if (.N < 2) NULL else {
  # every pair of rungs (a lower k, a higher k): buy the lower rung's YES at its ask, sell the higher rung's YES at its bid
  ij <- which(upper.tri(matrix(0, .N, .N)), arr.ind = TRUE)
  g <- bid[ij[, 2]] - ask[ij[, 1]] - fee(ask[ij[, 1]]) - fee(1 - bid[ij[, 2]])
  .(pairs = nrow(ij), sure = sum(g > 0), best = max(g)) } }, by = .(game_id, series, key)]
a6 <- data.table(id = "A6", test = "a higher rung's bid above a lower rung's ask, after fees", ladders = nrow(viol), rung_pairs = sum(viol$pairs),
                 sure_profits = sum(viol$sure), best_sure_profit = max(viol$best))

res <- rbindlist(list(a3, a4, a5, a6), fill = TRUE)
fwrite(signif_dt(res), file.path(out, "consistency_tests.csv"))
fwrite(signif_dt(a5_by), file.path(out, "consistency_a5_by_series.csv"))
fwrite(signif_dt(a3_by), file.path(out, "consistency_a3_by_series.csv"))
options(width = 220)
print(signif_dt(res, 4))
print(signif_dt(a5_by, 4))
print(signif_dt(a3_by, 4))
cat(sprintf("\nA3 pairs where the protection triggered (protected fair price, unprotected settled): %d; A6 sure profits by series: %s\n", a3$protection_triggered,
            paste(viol[sure > 0, .N, by = series][, sprintf("%s %d", series, N)], collapse = "; ")))
