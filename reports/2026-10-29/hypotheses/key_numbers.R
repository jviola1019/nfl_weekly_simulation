# Family A1-A2 of PLAN.md: do Kalshi's spread, total and team-total ladders misprice the NFL's key numbers?
# A model of P(margin > x | spread), P(total > x | total line) and P(points > x | implied team total) from history
# (nflverse closing lines and scores, 2015-2024 regular season; 1999-2024 as the secondary sample), a Gaussian kernel
# on the line (bandwidth 1.5), centred on nflverse's 2026 closing line. Scored against Kalshi's close (kalshi_candles.R)
# on every settled 2026 week 1-7 contract, as a Brier difference paired by game (H1: the model is better) and as a
# taker's return after the spread and Kalshi's fee. A shape-only variant (not in PLAN.md, exploratory) centres the same
# shape on Kalshi's own median instead. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/key_numbers.R <out_dir> --settled=<a>,<b> --candles=<a>,<b>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
BW <- 1.5
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")[series %in% c("KXNFLSPREAD", "KXNFLTOTAL", "KXNFLTEAMTOTAL")]
cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
stopifnot(!any(substr(st$close_time, 1, 4) == "2025"))

hist_all <- as.data.table(nflreadr::load_schedules(1999:2024))
stopifnot(!any(hist_all$season > 2024))   # the seal
hist_all <- hist_all[game_type == "REG" & !is.na(result) & !is.na(spread_line) & !is.na(total_line)]
s26 <- as.data.table(nflreadr::load_schedules(2026))[game_type == "REG" & !is.na(result)]
sched <- props_schedule()

d <- merge(st[, .(ticker, series, event_ticker, label, result, y = settlement_value)], props_event_games(st$event_ticker, sched), by = "event_ticker")
d[, outcome := props_outcome(series, game_id, result, y)]
d <- merge(d[outcome == "settled"], cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker")
d <- d[is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid]
d[, `:=`(mid = (bid + ask) / 2, spread = ask - bid, x = as.numeric(sub("^.*[Oo]ver ([0-9.]+)( points)?.*$", "\\1", label)),   # a few team totals omit "points"
         team = fifelse(series == "KXNFLTOTAL", NA_character_, sub("^.*-([A-Z]+)[0-9]+$", "\\1", ticker)))]
d <- merge(d, s26[, .(game_id, home_team, away_team, spread_line, total_line, result_26 = result)], by = "game_id")
same <- function(a, b) a == b | (a == "LAR" & b == "LA") | (a == "LA" & b == "LAR") | (a == "JAC" & b == "JAX") | (a == "WSH" & b == "WAS") | (a == "LVR" & b == "LV")
d[, side := fifelse(is.na(team), "game", fifelse(same(team, home_team), "home", fifelse(same(team, away_team), "away", NA_character_)))]
stopifnot(!anyNA(d$side), !anyNA(d$x))
d[, `:=`(s_team = fifelse(side == "home", spread_line, -spread_line))]
d[, centre := fcase(series == "KXNFLSPREAD", s_team, series == "KXNFLTOTAL", total_line, default = (total_line + s_team) / 2)]

# the empirical conditional survival from history, both teams' perspectives for margins and team points
emp <- function(h) list(
  KXNFLSPREAD = rbind(h[, .(c = spread_line, v = result)], h[, .(c = -spread_line, v = -result)]),
  KXNFLTOTAL = h[, .(c = total_line, v = home_score + away_score)],
  KXNFLTEAMTOTAL = rbind(h[, .(c = (total_line + spread_line) / 2, v = home_score)], h[, .(c = (total_line - spread_line) / 2, v = away_score)]))
surv <- function(hist, c, x) vapply(seq_along(c), function(i) { w <- stats::dnorm((hist$c - c[i]) / BW); sum(w * (hist$v > x[i])) / sum(w) }, numeric(1))
H15 <- emp(hist_all[season >= 2015]); H99 <- emp(hist_all)
d[, `:=`(p15 = surv(H15[[series[1]]], centre, x), p99 = surv(H99[[series[1]]], centre, x)), by = series]
# exploratory shape-only: centre the same shape on Kalshi's own median for the ladder (a team's ladder, or the game's total)
d[, ladder := paste(game_id, series, side)]
med <- d[, { o <- order(mid); ms <- mid[o]; xs <- x[o]   # price falls as the threshold rises: interpolate x at a price of 0.5
  m <- if (any(ms >= 0.5) && any(ms < 0.5)) stats::approx(ms, xs, 0.5, ties = mean)$y else NA_real_
  .(kalshi_median = m) }, by = ladder]
d <- merge(d, med, by = "ladder")
d[, p_shape := NA_real_]
d[!is.na(kalshi_median), p_shape := surv(H15[[series[1]]], kalshi_median, x), by = series]
ok <- d[spread <= MAX_SPREAD & mid > 0 & mid < 1]

evaluate <- function(x, pcol) {
  x <- x[!is.na(get(pcol))]
  if (uniqueN(x$game_id) < 3) return(data.table(contracts = nrow(x), games = uniqueN(x$game_id)))
  x[, `:=`(p = pmin(pmax(get(pcol), 0.001), 0.999))]
  x[, dl := (p - y)^2 - (mid - y)^2]
  gm <- x[, .(dl = mean(dl)), by = game_id]
  x[, side_bet := fcase(p > ask + fee(ask), "yes", 1 - p > 1 - bid + fee(1 - bid), "no", default = "none")]
  x[, `:=`(pnl = fcase(side_bet == "yes", y - ask - fee(ask), side_bet == "no", bid - y - fee(1 - bid), default = 0),
           stake = fcase(side_bet == "yes", ask + fee(ask), side_bet == "no", 1 - bid + fee(1 - bid), default = 0))]
  b <- x[side_bet != "none"]; g <- unique(b$game_id)
  set.seed(20261029)
  bt <- if (length(g) > 1) replicate(2000, { bb <- b[data.table(game_id = sample(g, replace = TRUE)), on = "game_id", allow.cartesian = TRUE]; sum(bb$pnl) / sum(bb$stake) }) else NA_real_
  data.table(contracts = nrow(x), games = nrow(gm), brier_kalshi = mean((x$mid - x$y)^2), brier_model = mean((x$p - x$y)^2),
             skill = 1 - mean((x$p - x$y)^2) / mean((x$mid - x$y)^2), p_model_better = stats::t.test(gm$dl, alternative = "less")$p.value,
             bets = nrow(b), roi = if (nrow(b)) sum(b$pnl) / sum(b$stake) else NA_real_,
             roi_lo = stats::quantile(bt, 0.025, na.rm = TRUE), roi_hi = stats::quantile(bt, 0.975, na.rm = TRUE))
}
key <- function(series, x) (series == "KXNFLSPREAD" & abs(x) %in% c(2.5, 3.5, 6.5, 7.5, 9.5, 10.5, 13.5, 14.5))
res <- rbindlist(list(
  ok[, cbind(model = "2015-2024, nflverse close (primary)", evaluate(.SD, "p15")), by = series],
  ok[, cbind(model = "1999-2024, nflverse close (secondary)", evaluate(.SD, "p99")), by = series],
  ok[, cbind(model = "2015-2024 shape on Kalshi's median (exploratory)", evaluate(.SD, "p_shape")), by = series],
  ok[key(series, x), cbind(model = "2015-2024, key-number rungs only (descriptive)", evaluate(.SD, "p15")), by = series]), fill = TRUE)
fwrite(res[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "key_numbers.csv"))
# the mass each source puts on the favourite winning by exactly 3 (P(> 2.5) - P(> 3.5)) for ladders that list both rungs
m3 <- ok[series == "KXNFLSPREAD" & x %in% c(2.5, 3.5) & s_team > 0, .(n = .N, k25 = mid[x == 2.5][1], k35 = mid[x == 3.5][1], m25 = p15[x == 2.5][1],
                                                                       m35 = p15[x == 3.5][1], y25 = y[x == 2.5][1], y35 = y[x == 3.5][1]), by = ladder][n == 2]
mass3 <- m3[, .(ladders = .N, kalshi_mass_3 = mean(k25 - k35), model_mass_3 = mean(m25 - m35), realized_exactly_3 = mean(y25 - y35))]
fwrite(mass3[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "key_numbers_mass3.csv"))
options(width = 220)
print(res[, .(series, model, contracts, games, brier_kalshi = signif(brier_kalshi, 4), brier_model = signif(brier_model, 4), skill = signif(skill, 3),
              p_model_better = signif(p_model_better, 2), bets, roi = signif(roi, 3), roi_lo = signif(roi_lo, 3), roi_hi = signif(roi_hi, 3))])
print(mass3)
cat(sprintf("\nhistory: %d games 2015-2024, %d 1999-2024; contracts fitted %d in %d games\n", hist_all[season >= 2015, .N], nrow(hist_all), nrow(ok), uniqueN(ok$game_id)))
