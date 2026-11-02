# Family F of PLAN.md: Kalshi's moneyline against DraftKings', 2026 weeks 6-7. DraftKings' price is ESPN's odds
# feed in the capture archive (provider 100), at each game's last capture before kickoff; Kalshi's is the last hourly
# candle at or before that capture time (the raw candles saved by reports/2026-10-28/feasibility/kalshi_candles.R).
# - F1 buying one side on DraftKings and the other on Kalshi (at the ask, with the taker fee) locks a profit when the
#   two costs sum below $1 (count, and the smallest combined cost);
# - F2 DraftKings' no-vig price against Kalshi's mid, paired Brier by game (two-sided).
# Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/cross_venue.R <out_dir> --captures=<dir>,<dir> --candles_raw=<dir> --settled=<a>,<b>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
num <- function(v) suppressWarnings(as.numeric(v))
sched <- props_schedule()
s26 <- as.data.table(nflreadr::load_schedules(2026))[game_type == "REG", .(game_id, espn = as.character(espn))]
# DraftKings' moneyline at each capture
files <- list.files(opt("captures"), pattern = "^[0-9]+__[0-9]{8}T[0-9]{6}Z\\.json\\.gz$", recursive = TRUE, full.names = TRUE)
files <- files[grepl("espn_game_odds", files, fixed = TRUE)]
dk <- rbindlist(lapply(files, function(f) {
  j <- jsonlite::fromJSON(gzfile(f), simplifyVector = FALSE)
  it <- Filter(function(i) identical(i$provider$id, "100"), j$items)
  if (!length(it)) return(NULL)
  i <- it[[1]]
  data.table(espn = sub("__.*$", "", basename(f)), captured = as.POSIXct(sub("^.*__([0-9]{8}T[0-9]{6}Z)\\.json\\.gz$", "\\1", basename(f)), format = "%Y%m%dT%H%M%SZ", tz = "UTC"),
             ml_home = num(i$homeTeamOdds$moneyLine), ml_away = num(i$awayTeamOdds$moneyLine))
}))
dk <- merge(dk, s26, by = "espn")
dk <- merge(dk, sched[, .(game_id, kick, home_team, away_team, home_score, away_score)], by = "game_id")
stopifnot(!any(format(dk$kick, "%Y") == "2025"))
dk <- dk[captured < kick & is.finite(ml_home) & is.finite(ml_away)]
setorder(dk, game_id, captured)
dk <- dk[, .SD[.N], by = game_id]                                      # each game's last capture before kickoff
dec <- function(o) ifelse(o < 0, 1 + 100 / -o, 1 + o / 100)
imp <- function(o) 1 / dec(o)
dk[, p_dk := imp(ml_home) / (imp(ml_home) + imp(ml_away))]
# Kalshi's hourly candles for the moneyline contracts
st <- unique(rbindlist(lapply(opt("settled"), function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE)))), by = "ticker")[series == "KXNFLGAME"]
gm <- merge(st[, .(ticker, event_ticker)], props_event_games(st$event_ticker, sched), by = "event_ticker")
gm <- merge(gm, sched[, .(game_id, home_team)], by = "game_id")
gm[, home := { c <- sub("^.*-([A-Z]+)$", "\\1", ticker); c == home_team | (c == "LAR" & home_team == "LA") | (c == "JAC" & home_team == "JAX") | (c == "WSH" & home_team == "WAS") | (c == "LVR" & home_team == "LV") }]
cf <- list.files(opt("candles_raw"), pattern = "^candles_[0-9]+\\.json\\.gz$", full.names = TRUE)
kc <- rbindlist(lapply(cf, function(f) {
  j <- jsonlite::fromJSON(gzfile(f), simplifyVector = TRUE)$markets
  keep <- which(j$market_ticker %in% gm$ticker)
  rbindlist(lapply(keep, function(i) { cs <- j$candlesticks[[i]]; if (!NROW(cs)) return(NULL)
    data.table(ticker = j$market_ticker[i], end_ts = cs$end_period_ts, bid = num(cs$yes_bid$close_dollars), ask = num(cs$yes_ask$close_dollars)) }))
}))
kc <- merge(kc, gm[, .(ticker, game_id, home)], by = "ticker")
setorder(kc, ticker, end_ts)
dk[, t := as.numeric(captured)]
kq <- kc[, .(ticker, game_id, home, t = as.numeric(end_ts), bid, ask)]
setkey(kq, game_id, home, t)
at_time <- function(hh) kq[J(dk$game_id, hh, dk$t), roll = TRUE, .(bid, ask)]
kh <- at_time(TRUE); ka <- at_time(FALSE)
dk[, `:=`(bid_h = kh$bid, ask_h = kh$ask, bid_a = ka$bid, ask_a = ka$ask)]
dk <- dk[is.finite(ask_h) & is.finite(ask_a) & ask_h > 0 & ask_a > 0 & home_score != away_score]
dk[, `:=`(y = as.integer(home_score > away_score), p_k = ((bid_h + ask_h) / 2 + 1 - (bid_a + ask_a) / 2) / 2,
          lock_dk_home = 1 / dec(ml_home) + ask_a + fee(ask_a), lock_dk_away = 1 / dec(ml_away) + ask_h + fee(ask_h))]
f1 <- data.table(id = "F1", test = "one side on DraftKings, the other on Kalshi: combined cost below $1", games = nrow(dk),
                 locks = sum(dk$lock_dk_home < 1 | dk$lock_dk_away < 1), min_combined_cost = min(pmin(dk$lock_dk_home, dk$lock_dk_away)),
                 median_combined_cost = stats::median(pmin(dk$lock_dk_home, dk$lock_dk_away)))
dd <- (dk$p_dk - dk$y)^2 - (dk$p_k - dk$y)^2
f2 <- data.table(id = "F2", test = "DraftKings' no-vig price against Kalshi's mid (paired Brier, two-sided)", games = nrow(dk),
                 brier_dk = mean((dk$p_dk - dk$y)^2), brier_kalshi = mean((dk$p_k - dk$y)^2), estimate = mean(dd), p = if (nrow(dk) > 2) stats::t.test(dd)$p.value else NA_real_,
                 mean_abs_gap = mean(abs(dk$p_dk - dk$p_k)), hours_before = stats::median(as.numeric(difftime(dk$kick, dk$captured, units = "hours"))))
res <- rbindlist(list(f1, f2), fill = TRUE)
fwrite(signif_dt(res), file.path(out, "cross_venue_tests.csv"))
fwrite(signif_dt(dk[, .(game_id, captured = format(captured, "%Y-%m-%dT%H:%M:%SZ"), ml_home, ml_away, p_dk, bid_h, ask_h, bid_a, ask_a, p_k, y, lock_dk_home, lock_dk_away)]),
       file.path(out, "cross_venue_games.csv"))
options(width = 200)
print(signif_dt(res, 4))
