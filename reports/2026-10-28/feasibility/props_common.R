# Shared by props_probe.R, props_close.R and kalshi_candles.R: the 2026 schedule's kickoffs, the game each Kalshi event
# belongs to, how each contract settled, and the calibration and out-of-sample tests.
# Kalshi's occurrence_datetime is not a kickoff: it falls 3 hours after the scheduled kickoff (props/props_occurrence_gaps.csv).
MAX_SPREAD <- 0.10   # contracts with a wider bid-ask spread are counted but kept out of the fits
MIN_FIT <- 50L       # contracts a series needs before it gets its own fit
TAKER_FEE <- 0.07    # Kalshi's taker fee per contract is 0.07 * P * (1 - P), rounded up per order (makers pay none on most sports series)
fee <- function(p) TAKER_FEE * p * (1 - p)
LADDERS <- c(KXNFLTD = "touchdowns", KXNFLREC = "receptions", KXNFLRECYDS = "receiving_yards", KXNFLRSHYDS = "rushing_yards",
             KXNFLPASSYDS = "passing_yards", KXNFLPASSTDS = "passing_tds", KXNFLPASSATT = "attempts", KXNFLPASSCOMP = "completions",
             KXNFLRSHATT = "carries", KXNFLPASSINT = "passing_interceptions", KXNFLRRYDS = "rush_rec_yards")
PLAYER <- c(names(LADDERS), "KXNFLTDPROT", "KXNFLRECPROT", "KXNFLRECYDSPROT", "KXNFLRSHYDSPROT", "KXNFLPASSYDSPROT", "KXNFLPASSTDSPROT",
            "KXNFLFFPTS", "KXNFLLONGREC", "KXNFLLONGRSH", "KXNFLFIRSTTD", "KXNFLTEAMFIRSTTD", "KXNFLMOSTRECYDS", "KXNFLMOSTRSHYDS",
            "KXNFLFFPTSLADDER", "KXNFLLADDERREC", "KXNFLLADDERRECYDS", "KXNFLLADDERRSHYDS", "KXNFLESCALATORREC", "KXNFLESCALATORRECYDS",
            "KXNFLESCALATORRSHYDS", "KXNFLPASSYDSH2H", "KXNFLRECYDSH2H", "KXNFLRSHYDSH2H")
SCALAR <- grep("LADDER|ESCALATOR", PLAYER, value = TRUE)   # pay a fraction of $1 that grows with a stat
TIE_SPLIT <- c("KXNFLMOSTRECYDS", "KXNFLMOSTRSHYDS")      # an N-way tie pays 1/N
LINES <- c("KXNFLGAME", "KXNFLSPREAD", "KXNFLTOTAL")
group_of <- function(s) fcase(s %in% SCALAR, "player scalar", s %in% PLAYER, "player", s %in% LINES, "game line", default = "game prop")
lg <- function(p) stats::qlogis(pmin(pmax(p, 0.005), 0.995))

props_schedule <- function() {
  sched <- as.data.table(nflreadr::load_schedules(2026))[game_type == "REG"]
  sched[, kick := as.POSIXct(paste(gameday, gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")]
  attr(sched$kick, "tzone") <- "UTC"   # the same instant, shown in Kalshi's zone
  sched
}

# An event ticker carries the game's ET date and the two team codes in either order, and some carry a suffix
# (KXNFLTEAMFIRSTTD-26OCT22NECHI-NE, KXNFLRACE-26OCT22NECHI-35); season and novelty events do not, and get no row.
props_event_games <- function(event_tickers, sched) {
  pat <- "^KXNFL[A-Z0-9]+-([0-9]{2}[A-Z]{3}[0-9]{2})([A-Z]{4,6})(-[A-Z0-9]+)?$"
  ev <- data.table(event_ticker = unique(event_tickers))[grepl(pat, event_ticker)]
  ev[, `:=`(gameday = format(as.Date(sub(pat, "\\1", event_ticker), format = "%y%b%d"), "%Y-%m-%d"), teams = sub(pat, "\\2", event_ticker))]
  cand <- merge(ev, sched[, .(game_id, week, gameday, home_team, away_team, kick)], by = "gameday", allow.cartesian = TRUE)
  alias <- function(x) c(x, switch(x, LA = "LAR", JAX = "JAC", WAS = "WSH", LV = "LVR", character(0)))
  hit <- vapply(seq_len(nrow(cand)), function(i) {
    h <- alias(cand$home_team[i]); a <- alias(cand$away_team[i])
    any(outer(h, a, function(hh, aa) paste0(aa, hh) == cand$teams[i] | paste0(hh, aa) == cand$teams[i]))
  }, logical(1))
  unique(cand[hit], by = "event_ticker")[, .(event_ticker, game_id, week, kick)]
}

# How a contract settled. Kalshi marks a binary contract settled at the pre-game fair price (a player who never took a
# snap, or a protected contract's player out after the half) with result "scalar"; its value can round to 0 or 1.
props_outcome <- function(series, game_id, result, y) {
  fcase(is.na(game_id), "not a single game's market",
        is.na(y), "not settled in the window (later games, or voided)",
        series %in% SCALAR, "payout",
        result %in% c("yes", "no"), "settled",
        series %in% TIE_SPLIT & round(y, 2) %in% c(0.25, 0.33, 0.5), "settled",   # a tie's 1/N share
        default = "settled at the fair price (no outcome)")
}

# Series whose every event settles exactly one contract (a tie's shares included): mutually exclusive, exhaustive sets.
props_exclusive <- function(d) {
  ev_y <- unique(d[outcome == "settled", .(ticker, event_ticker, series, y)], by = "ticker")[, .(sum_y = sum(y), n_settled = .N), by = .(series, event_ticker)]
  list(ev_y = ev_y, series = ev_y[, .(all_one = all(abs(sum_y - 1) < 0.02), events = .N), by = series][all_one == TRUE & events >= 5, series])
}

# Calibration of one set of contracts (columns y, mid, spread, game_id, pg, hours_before): Brier, the slope and the
# calibration-in-the-large, clustered by game (players in one game share its script; with ~30 games, HC1 and t with
# G - 1 df), and the slope clustered by player-game. quasibinomial gives the logit's estimates for 0/1 outcomes and takes
# the scalar payouts and tie shares.
fit_one <- function(d, by_pg) {
  G <- uniqueN(d$game_id); tq <- stats::qt(0.975, G - 1)
  m <- stats::glm(y ~ lg(mid), family = stats::quasibinomial(), data = d)
  V <- sandwich::vcovCL(m, cluster = d$game_id, type = "HC1")
  m0 <- stats::glm(y ~ 1, offset = lg(mid), family = stats::quasibinomial(), data = d)
  V0 <- sandwich::vcovCL(m0, cluster = d$game_id, type = "HC1")
  b <- unname(stats::coef(m)[2]); se <- sqrt(V[2, 2]); a <- unname(stats::coef(m0)[1]); se0 <- sqrt(V0[1, 1])
  r <- data.table(contracts = nrow(d), player_games = if (by_pg) uniqueN(d$pg) else NA_integer_, games = G, mean_y = mean(d$y),
                  mean_mid = mean(d$mid), brier = mean((d$mid - d$y)^2), slope = b, slope_lo = b - tq * se, slope_hi = b + tq * se,
                  p_slope = 2 * stats::pt(-abs(b - 1) / se, G - 1), citl = a, citl_lo = a - tq * se0, citl_hi = a + tq * se0,
                  p_citl = 2 * stats::pt(-abs(a) / se0, G - 1), median_spread = stats::median(d$spread),
                  median_hours_before = stats::median(d$hours_before))
  sp <- if (by_pg) sqrt(sandwich::vcovCL(m, cluster = d$pg, type = "HC1")[2, 2]) else NA_real_
  r[, `:=`(slope_lo_pg = b - 1.96 * sp, slope_hi_pg = b + 1.96 * sp)]
}

# Every series with enough contracts on its own (BH over the series), and each group pooled. In an exclusive set each
# game's outcomes sum to 1, so its calibration-in-the-large carries no outcome noise and tests only whether the prices sum
# to 1 (props_coherence.csv): those series stay out of the calibration-in-the-large family.
props_calibration <- function(ok, exclusive) {
  # a series' own fit needs MIN_FIT contracts, 5 games and at least 10 events and 10 non-events (a safety or a tie, a
  # handful a season, gives no slope)
  cnt <- ok[, .(n = .N, ev = sum(y), ne = sum(1 - y), G = uniqueN(game_id), sdm = stats::sd(lg(mid))), by = series]
  fittable <- cnt[n >= MIN_FIT & ev >= 10 & ne >= 10 & G >= 5 & sdm > 0, series]
  rare <- cnt[n >= MIN_FIT & G >= 5 & sdm > 0 & (ev < 10 | ne < 10), sprintf("%s (%.0f events)", series, pmin(ev, ne))]
  per <- ok[series %in% fittable, fit_one(.SD, group_of(.BY$series) != "game line" & group_of(.BY$series) != "game prop"), by = series]
  per[, `:=`(group = group_of(series), exclusive = series %in% exclusive, q_slope = stats::p.adjust(p_slope, "BH"), q_citl = NA_real_)]
  per[exclusive == FALSE, q_citl := stats::p.adjust(p_citl, "BH")]
  pooled <- rbind(ok[, fit_one(.SD, .BY$group %in% c("player", "player scalar")), by = group],
                  cbind(data.table(group = "all"), fit_one(ok, FALSE)), fill = TRUE)
  pooled[, series := paste("pooled:", group)]
  calib <- rbind(pooled, per, fill = TRUE)
  setcolorder(calib, c("series", "group"))
  list(calib = calib, fittable = fittable, rare = rare)
}

# Out of sample: a recalibration fit on the training weeks, scored on the test weeks, as Brier (paired over games, one
# value per game: the conservative unit) and as a taker's return. The taker buys Yes at the ask when the recalibrated p
# beats it after the fee, or No at 1 - bid when 1 - p beats that; the interval resamples games.
recal_predict <- function(tr, te) {
  if (nrow(tr) < MIN_FIT || nrow(te) < MIN_FIT) return(NULL)
  rc <- stats::glm(y ~ lg(mid), family = stats::quasibinomial(), data = tr)
  te <- copy(te)
  te[, `:=`(p = stats::predict(rc, newdata = te, type = "response"), recal_slope = unname(stats::coef(rc)[2]))]
}
oos_one <- function(d, train_weeks, test_weeks) {
  te <- recal_predict(d[week %in% train_weeks], d[week %in% test_weeks])
  if (is.null(te)) return(NULL)
  oos_summary(te, train_weeks, test_weeks)
}
oos_summary <- function(te, train_weeks, test_weeks) {
  te <- copy(te)
  te[, dl := (p - y)^2 - (mid - y)^2]
  gm <- te[, .(dl = mean(dl)), by = game_id]$dl
  te[, side := fcase(p > ask + fee(ask), "yes", 1 - p > 1 - bid + fee(1 - bid), "no", default = "none")]
  te[, `:=`(pnl = fcase(side == "yes", y - ask - fee(ask), side == "no", bid - y - fee(1 - bid), default = 0),
            stake = fcase(side == "yes", ask + fee(ask), side == "no", 1 - bid + fee(1 - bid), default = 0))]
  bets <- te[side != "none"]
  set.seed(20261028)
  g <- unique(bets$game_id)
  boot <- if (length(g) > 1) replicate(2000, { b <- bets[data.table(game_id = sample(g, replace = TRUE)), on = "game_id", allow.cartesian = TRUE]
                                                sum(b$pnl) / sum(b$stake) }) else NA_real_
  z <- stats::qnorm(0.95) + stats::qnorm(0.8)
  wk <- function(w) if (is.character(w)) w else if (length(w) == 1) as.character(w) else paste(range(w), collapse = "-")
  data.table(train_week = wk(train_weeks), test_week = wk(test_weeks), contracts = nrow(te), games = length(gm), recal_slope = stats::median(te$recal_slope),
             brier_mid = mean((te$mid - te$y)^2), brier_recalibrated = mean((te$p - te$y)^2),
             skill = 1 - mean((te$p - te$y)^2) / mean((te$mid - te$y)^2), p_game_t = stats::t.test(gm, alternative = "less")$p.value,
             # games a one-sided 5% test needs for 80% power at the observed per-game Brier change (when it favours recalibrating)
             games_needed = if (mean(gm) < 0) ceiling((z * stats::sd(gm) / mean(gm))^2) else NA_real_,
             bets = nrow(bets), bets_yes = sum(bets$side == "yes"), staked = sum(bets$stake), pnl = sum(bets$pnl),
             roi = if (nrow(bets)) sum(bets$pnl) / sum(bets$stake) else NA_real_,
             roi_lo = stats::quantile(boot, 0.025, na.rm = TRUE), roi_hi = stats::quantile(boot, 0.975, na.rm = TRUE))
}

props_reliability <- function(ok) {
  bins <- c(0, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.8, 0.9, 0.95, 1)
  ok[, bin := cut(mid, bins, include.lowest = TRUE)]
  ok[, .(contracts = .N, mean_mid = mean(mid), mean_y = mean(y), gap = mean(y) - mean(mid), se = stats::sd(y) / sqrt(.N)), keyby = .(group, bin)]
}

signif_dt <- function(x, digits = 5) x[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, digits) else v)]

# The picks a CLV test needs, as the A2 study computes them (reports/2026-09-29/clv-power): two-sided 5%, 80% power,
# Bonferroni over the candidates, n = ((z + z_power) * sd / effect)^2, before the design effect of picks that share a game.
clv_picks <- function(sd_bps, effect_bps, candidates = 1) {
  ceiling(((stats::qnorm(1 - 0.05 / (2 * candidates)) + stats::qnorm(0.8)) * sd_bps / effect_bps)^2)
}
# The within-game ICC of one move per unit (the ANOVA estimator): k picks from one game multiply n by 1 + (k - 1) * ICC.
icc_anova <- function(x, g) {
  a <- stats::anova(stats::lm(x ~ factor(g))); msb <- a[1, "Mean Sq"]; msw <- a[2, "Mean Sq"]
  n <- as.numeric(table(g)); N <- sum(n); k0 <- (N - sum(n^2) / N) / (length(n) - 1)
  max(0, (msb - msw) / (msb + (k0 - 1) * msw))
}
clv_power <- function(x) {   # x: one row per contract with move (bps), unit and game_id
  u <- x[, .(m = mean(move)), by = .(unit, game_id)]
  data.table(icc_within_game = icc_anova(u$m, u$game_id), picks_100bps = clv_picks(stats::sd(x$move), 100),
             picks_100bps_8_candidates = clv_picks(stats::sd(x$move), 100, 8), picks_50bps = clv_picks(stats::sd(x$move), 50),
             picks_50bps_8_candidates = clv_picks(stats::sd(x$move), 50, 8))
}
