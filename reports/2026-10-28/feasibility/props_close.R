# Kalshi's NFL prices at kickoff, 2026 weeks 1-7. Every settled contract of every single-game series is priced at its
# close (the last hourly candle ending at or before the scheduled kickoff, kalshi_candles.R) and scored against Kalshi's
# own settlement (kalshi_settled.R). It needs no capture archive, so it covers the weeks the archive does not hold yet.
# With props_common.R's tests it reports:
# - calibration for each series and for player props, game props, game lines and scalar ladders pooled, by game
#   cluster, BH over the series, and the smallest slope departure each pooled fit could detect;
# - calibration by week, reliability, and the coherence of the mutually exclusive sets at kickoff;
# - out of sample, a recalibration fit on weeks 1-5 and scored on weeks 6-7, and walk-forward (each week from all the
#   weeks before it, pooled), as Brier and as a taker's return after the spread and Kalshi's fee;
# - the last day's price movement (24, 3 and 1 hours before kickoff to the close) and the picks a CLV test would need.
# Only 2026 is read. Run from the repository root:
#   Rscript reports/2026-10-28/feasibility/props_close.R <out_dir> --settled=<a.csv.gz>,<b.csv.gz> --candles=<a.csv.gz>,<b.csv.gz>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")
cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
stopifnot(!any(substr(st$close_time, 1, 4) == "2025"), !any(substr(cn$kick, 1, 4) == "2025"))   # the seal: 2026 only
stopifnot(all(st[result == "yes", settlement_value] == 1), all(st[result == "no", settlement_value] == 0))

options(timeout = 600)
sched <- props_schedule()
d <- merge(st[, .(ticker, series, event_ticker, label, result, y = settlement_value)], props_event_games(st$event_ticker, sched), by = "event_ticker", all.x = TRUE)
d[, outcome := props_outcome(series, game_id, result, y)]
ex <- props_exclusive(d)
d <- merge(d, cn[, .(ticker, close_end, bid = bid_close, ask = ask_close, bid_24h, ask_24h, bid_3h, ask_3h, bid_1h, ask_1h)], by = "ticker", all.x = TRUE)
d[, `:=`(group = group_of(series), name = sub(":.*$", "", label), mid = (bid + ask) / 2, spread = ask - bid,
         hours_before = as.numeric(difftime(kick, as.POSIXct(close_end, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "hours")))]
d[, pg := paste(game_id, name)]
two <- d[, is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid]
ok <- d[outcome %in% c("settled", "payout") & two & spread <= MAX_SPREAD & mid > 0 & mid < 1]

# --- calibration: every week, by week, and the smallest departure each pooled fit could see ------------------------------
cal <- props_calibration(ok, ex$series); calib <- cal$calib
calib[, mde_slope := (stats::qt(0.975, games - 1) + stats::qnorm(0.8)) * (slope_hi - slope_lo) / (2 * stats::qt(0.975, games - 1))]
fwrite(signif_dt(calib), file.path(out, "close_calibration.csv"))
by_week <- ok[, fit_one(.SD, FALSE), by = .(week, group)][order(group, week)]
fwrite(signif_dt(by_week), file.path(out, "close_calibration_by_week.csv"))
rel <- props_reliability(ok)
fwrite(signif_dt(rel), file.path(out, "close_reliability.csv"))

# --- coherence at kickoff: every contract of an exclusive set, at its close -------------------------------------------------
co <- d[series %in% ex$series & outcome == "settled" & two,
        .(n_quoted = .N, sum_mid = sum(mid), sum_ask = sum(ask), sum_bid = sum(bid), yes_all = 1 - sum(ask + fee(ask)),
          no_all = (.N - 1) - sum(1 - bid + fee(1 - bid))), by = .(series, event_ticker)]
co <- merge(co, ex$ev_y, by = c("series", "event_ticker"))[n_quoted == n_settled]
coherence <- co[, .(events = .N, mean_contracts = mean(n_quoted), mean_sum_mid = mean(sum_mid), mean_sum_ask = mean(sum_ask), mean_sum_bid = mean(sum_bid),
                    events_yes_all_pays = sum(yes_all > 0), events_no_all_pays = sum(no_all > 0), best_profit = max(pmax(yes_all, no_all))), by = series]
fwrite(signif_dt(coherence), file.path(out, "close_coherence.csv"))

# --- out of sample ---------------------------------------------------------------------------------------------------------
weeks <- sort(unique(ok$week))
split_oos <- rbind(ok[, oos_one(.SD, weeks[weeks <= 5], weeks[weeks >= 6]), by = group],
                   cbind(data.table(group = "all"), oos_one(ok, weeks[weeks <= 5], weeks[weeks >= 6])), fill = TRUE)
walk <- function(x) {   # each week from all the weeks before it
  te <- rbindlist(lapply(weeks[-1], function(w) recal_predict(x[week < w], x[week == w])), fill = TRUE)
  if (!nrow(te)) return(NULL)
  oos_summary(te, "all earlier weeks", paste(range(te$week), collapse = "-"))
}
walk_oos <- rbind(ok[, walk(.SD), by = group], cbind(data.table(group = "all"), walk(ok)), fill = TRUE)
oos <- rbind(cbind(design = "weeks 1-5 -> 6-7", split_oos), cbind(design = "walk-forward", walk_oos), fill = TRUE)
fwrite(signif_dt(oos), file.path(out, "close_oos.csv"))

# --- the last day's movement, and the picks a CLV test would need -----------------------------------------------------------
late <- rbindlist(lapply(c("24h", "3h", "1h"), function(h) {
  b <- ok[[paste0("bid_", h)]]; a <- ok[[paste0("ask_", h)]]
  x <- ok[is.finite(b) & is.finite(a) & a > 0 & a >= b & a - b <= MAX_SPREAD]
  x[, `:=`(move = 1e4 * (mid - (get(paste0("bid_", h)) + get(paste0("ask_", h))) / 2), unit = fifelse(group %in% c("player", "player scalar"), pg, game_id))]
  # the picks a CLV test needs, one contract a pick (props_common.R's clv_picks), and the within-game ICC for the design effect
  merge(x[, .(before_kickoff = h, contracts = .N, share_moved = mean(move != 0), median_abs_bps = stats::median(abs(move)),
              p90_abs_bps = stats::quantile(abs(move), 0.9), sd_bps = stats::sd(move)), by = group], x[, clv_power(.SD), by = group], by = "group")
}))
fwrite(signif_dt(late), file.path(out, "close_late_movement.csv"))

coverage <- data.table(item = c("settled contracts read", "  in single-game series", "  with an outcome (binary, tie share or scalar payout)",
                                "  settled at the pre-game fair price (no outcome, excluded)", "  with an outcome and a two-sided close at kickoff",
                                "  of them with spread <= 0.10 (fitted)", "weeks", "games fitted", "player-games fitted", "series fitted on their own",
                                "series set aside: fewer than 10 events or non-events", "exclusive series"),
                       value = c(nrow(st), d[!is.na(game_id), .N], d[outcome %in% c("settled", "payout"), .N],
                                 d[outcome == "settled at the fair price (no outcome)", .N], d[outcome %in% c("settled", "payout") & two, .N], nrow(ok),
                                 paste(weeks, collapse = " "), uniqueN(ok$game_id), uniqueN(ok[group %in% c("player", "player scalar"), pg]),
                                 length(cal$fittable), paste(cal$rare, collapse = "; "), paste(ex$series, collapse = " ")))
fwrite(coverage, file.path(out, "close_coverage.csv"))

options(width = 220)
print(coverage)
cat("\n--- calibration at kickoff (game-clustered, t with G - 1 df) ---\n")
print(calib[, .(series, group, exclusive, contracts, games, mean_y = signif(mean_y, 3), slope = signif(slope, 3), slope_lo = signif(slope_lo, 3),
                slope_hi = signif(slope_hi, 3), p_slope = signif(p_slope, 2), q_slope = signif(q_slope, 2), mde = signif(mde_slope, 2),
                citl = signif(citl, 3), p_citl = signif(p_citl, 2), q_citl = signif(q_citl, 2))], nrows = 300)
cat("\n--- by week ---\n"); print(signif_dt(by_week[, .(week, group, contracts, games, slope, slope_lo, slope_hi, citl, brier)], 3), nrows = 100)
cat("\n--- coherence at kickoff ---\n"); print(signif_dt(coherence, 4))
cat("\n--- out of sample ---\n"); print(signif_dt(oos, 4))
cat("\n--- the last day's movement ---\n"); print(signif_dt(late, 4))
