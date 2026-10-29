# Family D of PLAN.md: Kalshi's in-game moneyline against nflfastR's public win probability, 2026 weeks 1-7.
# At each one-minute candle (kalshi_live_candles.R), Kalshi's price is the home team's mid (or 1 - the away mid), within
# the spread limit. The model's is vegas_home_wp, pre-snap, of the first play that starts after the minute's end less a
# buffer. Ties are dropped.
# Ruling (after the first run): PLAN.md's definition (no buffer) looks ahead. A play in progress when the minute ends
# can finish up to ~30 s later, and the next play's pre-snap probability includes its result. The model may only use
# plays that started a buffer before the minute ended, so every run reports buffers of 0, 30, 60 and 120 s; a result
# counts only if it survives 60 s.
# - D1 paired Brier by game (one value per game; two-sided);
# - D2 y ~ offset(logit Kalshi) + (logit model - logit Kalshi), clustered by game (H1: the model adds information);
# - D3 Kalshi's next-minute change on both sources' change now, clustered by game (does Kalshi lag the play-by-play?).
# Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/live_wp.R <out_dir> --live=<kalshi_live_candles.csv.gz> --settled=<a>,<b>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
BUFFERS <- c(0, 30, 60, 120)
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
lv <- read_gz(opt("live"))
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")[series == "KXNFLGAME"]
sched <- props_schedule()
g <- merge(st[, .(ticker, event_ticker, result)], props_event_games(st$event_ticker, sched), by = "event_ticker")
g <- merge(g, sched[, .(game_id, home_team, away_team, home_score, away_score)], by = "game_id")
stopifnot(!any(format(g$kick, "%Y") == "2025"))
code <- sub("^.*-([A-Z]+)$", "\\1", g$ticker)
is_home <- function(c, h) c == h | (c == "LAR" & h == "LA") | (c == "JAC" & h == "JAX") | (c == "WSH" & h == "WAS") | (c == "LVR" & h == "LV")
g[, home := is_home(code, home_team)]
g <- g[home_score != away_score]                                     # ties dropped
g[, y_home := as.integer(home_score > away_score)]
lv <- merge(lv, g[, .(ticker, game_id, home)], by = "ticker")
lv <- lv[is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & ask - bid <= MAX_SPREAD]
lv[, p_home := fifelse(home, (bid + ask) / 2, 1 - (bid + ask) / 2)]
kal <- lv[, .(p_k = if (any(home)) p_home[home][1] else p_home[1]), by = .(game_id, end_ts)]   # the home contract when both are quoted
pbp <- as.data.table(nflreadr::load_pbp(2026))[!is.na(time_of_day) & !is.na(vegas_home_wp),
                                              .(game_id, t = as.numeric(as.POSIXct(substr(time_of_day, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")), wp = vegas_home_wp)]
setorder(pbp, game_id, t)
first_last <- pbp[, .(t0 = min(t), t1 = max(t)), by = game_id]
yy <- unique(g[, .(game_id, y = y_home)])

analyse <- function(buffer) {
  k <- copy(kal)[, `:=`(t = as.numeric(end_ts), tj = as.numeric(end_ts) - buffer)]
  # the model's price: the first play that starts after (minute end - buffer), a rolling join forward
  x <- pbp[k, on = .(game_id, t = tj), roll = -Inf, .(game_id, t = i.t, p_k = i.p_k, p_m = x.wp)]
  x <- merge(x, first_last, by = "game_id")[t >= t0 & t < t1 & !is.na(p_m)]
  x <- merge(x, yy, by = "game_id")
  x[, `:=`(p_k = pmin(pmax(p_k, 0.005), 0.995), p_m = pmin(pmax(p_m, 0.005), 0.995))]
  gm <- x[, .(minutes = .N, d = mean((p_m - y)^2 - (p_k - y)^2), brier_k = mean((p_k - y)^2), brier_m = mean((p_m - y)^2)), by = game_id]
  m2 <- stats::glm(y ~ offset(lg(p_k)) + I(lg(p_m) - lg(p_k)), family = stats::quasibinomial(), data = x)
  V2 <- sandwich::vcovCL(m2, cluster = x$game_id, type = "HC1"); G <- uniqueN(x$game_id); b2 <- unname(stats::coef(m2)[2]); se2 <- sqrt(V2[2, 2])
  setorder(x, game_id, t)
  x[, `:=`(dk = c(NA, diff(lg(p_k))), dm = c(NA, diff(lg(p_m)))), by = game_id]
  x[, dk_next := shift(dk, type = "lead"), by = game_id]
  z <- x[is.finite(dk) & is.finite(dm) & is.finite(dk_next)]
  m3 <- stats::lm(dk_next ~ dk + dm, data = z); V3 <- sandwich::vcovCL(m3, cluster = z$game_id, type = "HC1")
  data.table(buffer_s = buffer, games = nrow(gm), minutes = nrow(x), brier_kalshi = mean(gm$brier_k), brier_model = mean(gm$brier_m),
             d1_estimate = mean(gm$d), d1_p = stats::t.test(gm$d)$p.value, d2_estimate = b2, d2_lo = b2 - stats::qt(0.975, G - 1) * se2,
             d2_hi = b2 + stats::qt(0.975, G - 1) * se2, d2_p = stats::pt(-b2 / se2, G - 1),
             d3_model_now = unname(stats::coef(m3)["dm"]), d3_model_now_se = sqrt(V3["dm", "dm"]),
             d3_kalshi_now = unname(stats::coef(m3)["dk"]), d3_kalshi_now_se = sqrt(V3["dk", "dk"]), cor_same_minute = stats::cor(z$dk, z$dm))
}
res <- rbindlist(lapply(BUFFERS, analyse))
fwrite(signif_dt(res), file.path(out, "live_wp_tests.csv"))
options(width = 220)
print(signif_dt(res, 4))
cat("\nD1/D2 of record use the 60 s buffer; D3 is descriptive.\n")
