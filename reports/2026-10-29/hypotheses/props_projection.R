# Family G of PLAN.md: does a simple public projection add information to Kalshi's prop prices? 2026 weeks 2-7.
# For each player and stat, the projection for week w uses only his 2026 games before w: an exponentially weighted mean
# (half-life 3 games), shrunk toward the mean of prop-listed players at his position in earlier weeks with weight
# n / (n + 3). Counts take a negative binomial and yards a gamma with a mass at zero, their dispersion fit by position on
# the earlier weeks' projections and results. Scored against Kalshi's close on the eleven counting-stat ladders:
# - G1 y ~ offset(logit close) + (logit model - logit close), clustered by game (H1: coefficient > 0);
# - G2 a taker buys where the model beats the ask (or 1 - bid) after the fee; return with a game-resampled interval.
# Run from the repository root:  Rscript reports/2026-10-29/hypotheses/props_projection.R <out_dir> --settled=<a>,<b> --candles=<a>,<b>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
HALF_LIFE <- 3; SHRINK_N <- 3
COUNTS <- c("receptions", "carries", "completions", "attempts", "passing_tds", "touchdowns", "passing_interceptions")
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")[series %in% names(LADDERS)]
cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
sched <- props_schedule()
norm <- function(x) { x <- tolower(iconv(x, to = "ASCII//TRANSLIT")); x <- gsub("[.'`-]", "", x)
  x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("\\s+", " ", trimws(x)) }

# Kalshi contracts at the close, with the player's team from the ticker (the longest matching team code wins)
d <- merge(st[, .(ticker, series, event_ticker, label, result, y = settlement_value)], props_event_games(st$event_ticker, sched), by = "event_ticker")
d <- merge(d[result %in% c("yes", "no")], cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker")
d <- merge(d, sched[, .(game_id, home_team, away_team)], by = "game_id")
d <- d[is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & ask - bid <= MAX_SPREAD]
d[, `:=`(mid = (bid + ask) / 2, k = as.numeric(sub("^.*: ([0-9]+)\\+$", "\\1", label)), key = norm(sub(":.*$", "", label)), stat = unname(LADDERS[series]),
         seg = substring(ticker, nchar(event_ticker) + 2L))]
aliases <- function(x) c(x, switch(x, LA = "LAR", JAX = "JAC", WAS = "WSH", LV = "LVR", character(0)))
d[, team := vapply(seq_len(.N), function(i) { h <- aliases(home_team[i]); a <- aliases(away_team[i])
  cand <- c(stats::setNames(h, rep(home_team[i], length(h))), stats::setNames(a, rep(away_team[i], length(a))))
  hit <- cand[startsWith(seg[i], cand)]; if (length(hit)) names(hit)[which.max(nchar(hit))] else NA_character_ }, character(1))]
d <- d[!is.na(k) & !is.na(team) & mid > 0 & mid < 1]

# 2026 weekly player stats, long by stat
ps <- as.data.table(nflreadr::load_player_stats(seasons = 2026))[season_type == "REG"]
stopifnot(nrow(ps) > 0, all(ps$season == 2026))
z0 <- function(v) fifelse(is.na(v), 0, as.numeric(v))
ps[, `:=`(touchdowns = z0(rushing_tds) + z0(receiving_tds) + z0(special_teams_tds), rush_rec_yards = z0(rushing_yards) + z0(receiving_yards),
          key = norm(player_display_name), pos = fifelse(position == "FB", "RB", position))]
long <- melt(ps[, c("player_id", "key", "team", "pos", "week", unique(LADDERS)), with = FALSE], id.vars = c("player_id", "key", "team", "pos", "week"),
             variable.name = "stat", value.name = "v", variable.factor = FALSE)
long[, v := z0(v)]
setorder(long, player_id, stat, week)
# the walk-forward projection for each player-week from his earlier 2026 games
long[, c("mu_raw", "n_prior") := {
  m <- rep(NA_real_, .N); n <- seq_len(.N) - 1L
  for (i in seq_len(.N)) if (i > 1) { w <- 0.5^((i - 1 - seq_len(i - 1)) / HALF_LIFE); m[i] <- sum(w * v[seq_len(i - 1)]) / sum(w) }
  list(m, n) }, by = .(player_id, stat)]
# prop-listed player-weeks (a Kalshi contract on that stat): the shrinkage target and the dispersion fit use only them
listed <- unique(d[, .(week, team, key, stat)])
long <- merge(long, listed[, listed := TRUE], by = c("week", "team", "key", "stat"), all.x = TRUE)
long[is.na(listed), listed := FALSE]
proj <- rbindlist(lapply(2:7, function(w) {
  prior <- long[listed == TRUE & week < w]
  tgt <- prior[, .(m_pos = mean(v)), by = .(stat, pos)]
  cur <- merge(long[week == w & listed == TRUE], tgt, by = c("stat", "pos"))
  cur[, mu := fifelse(n_prior > 0, (n_prior * mu_raw + SHRINK_N * m_pos) / (n_prior + SHRINK_N), m_pos)]
  # dispersion by stat and position from the earlier weeks' own projections (weeks with a projection)
  fitd <- merge(prior[n_prior > 0], tgt, by = c("stat", "pos"))
  fitd[, mu := (n_prior * mu_raw + SHRINK_N * m_pos) / (n_prior + SHRINK_N)]
  fitd <- fitd[is.finite(mu) & is.finite(v)]
  disp <- fitd[, .(theta = { e2 <- mean((v - mu)^2); mm <- mean(mu); if (is.finite(e2) && e2 > mm) mean(mu^2) / (e2 - mm) else Inf },
                   p0 = mean(v <= 0), kappa = { pos_v <- v > 0; if (sum(pos_v) > 5) mean(mu[pos_v]^2) / mean((v[pos_v] - mu[pos_v])^2) else 1 }), by = .(stat, pos)]
  merge(cur, disp, by = c("stat", "pos"))
}), fill = TRUE)
d <- merge(d, proj[, .(week, team, key, stat, mu, theta, p0, kappa, n_prior)], by = c("week", "team", "key", "stat"))
d[, p_model := fifelse(stat %in% COUNTS,
                       1 - stats::pnbinom(k - 1, size = pmin(theta, 1e6), mu = pmax(mu, 1e-6)),
                       (1 - pmin(p0, 0.99)) * (1 - stats::pgamma(k, shape = pmax(kappa, 0.05), rate = pmax(kappa, 0.05) / pmax(mu / (1 - pmin(p0, 0.99)), 1e-6))))]
d[, p_model := pmin(pmax(p_model, 0.005), 0.995)]

m <- stats::glm(y ~ offset(lg(mid)) + I(lg(p_model) - lg(mid)), family = stats::quasibinomial(), data = d)
V <- sandwich::vcovCL(m, cluster = d$game_id, type = "HC1"); G <- uniqueN(d$game_id); b <- unname(stats::coef(m)[2]); se <- sqrt(V[2, 2])
g1 <- data.table(id = "G1", test = "the projection adds information to Kalshi's close (one-sided > 0)", contracts = nrow(d), games = G, estimate = b,
                 lo = b - stats::qt(0.975, G - 1) * se, hi = b + stats::qt(0.975, G - 1) * se, p = stats::pt(-b / se, G - 1),
                 brier_kalshi = mean((d$mid - d$y)^2), brier_model = mean((d$p_model - d$y)^2))
d[, side := fcase(p_model > ask + fee(ask), "yes", 1 - p_model > 1 - bid + fee(1 - bid), "no", default = "none")]
d[, `:=`(pnl = fcase(side == "yes", y - ask - fee(ask), side == "no", bid - y - fee(1 - bid), default = 0),
         stake = fcase(side == "yes", ask + fee(ask), side == "no", 1 - bid + fee(1 - bid), default = 0))]
bets <- d[side != "none"]; gg <- unique(bets$game_id)
set.seed(20261029)
bt <- replicate(2000, { bb <- bets[data.table(game_id = sample(gg, replace = TRUE)), on = "game_id", allow.cartesian = TRUE]; sum(bb$pnl) / sum(bb$stake) })
g2 <- data.table(id = "G2", test = "betting the projection's disagreements pays after costs", contracts = nrow(d), games = G, bets = nrow(bets),
                 bets_yes = sum(bets$side == "yes"), roi = sum(bets$pnl) / sum(bets$stake), lo = stats::quantile(bt, 0.025), hi = stats::quantile(bt, 0.975))
by_stat <- d[, { mm <- stats::glm(y ~ offset(lg(mid)) + I(lg(p_model) - lg(mid)), family = stats::quasibinomial(), data = .SD)
  .(contracts = .N, coef = unname(stats::coef(mm)[2]), brier_kalshi = mean((mid - y)^2), brier_model = mean((p_model - y)^2)) }, by = stat]
res <- rbindlist(list(g1, g2), fill = TRUE)
res[, q_bh := NA_real_][id == "G1", q_bh := p]
fwrite(signif_dt(res), file.path(out, "projection_tests.csv"))
fwrite(signif_dt(by_stat), file.path(out, "projection_by_stat.csv"))

# Timing (added 2026-11-02, HYPOTHESES.md §15): does the projection, known before the week, predict Kalshi's move from 24 hours
# before kickoff to the close? GT1: the coefficient of (logit close - logit 24h) on (logit model - logit 24h), clustered by
# game (H1 > 0); GT2: the CLV of picks where the model differs from the 24-hour mid by at least 5 points
tm <- merge(d, cn[, .(ticker, bid24 = bid_24h, ask24 = ask_24h)], by = "ticker")
tm <- tm[is.finite(bid24) & is.finite(ask24) & ask24 > 0 & ask24 >= bid24 & ask24 - bid24 <= MAX_SPREAD][, mid24 := (bid24 + ask24) / 2][mid24 > 0 & mid24 < 1]
tm[, `:=`(move = lg(mid) - lg(mid24), lean = lg(p_model) - lg(mid24))]
mt <- stats::lm(move ~ lean, data = tm); Vt <- sandwich::vcovCL(mt, cluster = tm$game_id, type = "HC1"); Gt <- uniqueN(tm$game_id)
bt_ <- unname(stats::coef(mt)["lean"]); set_ <- sqrt(Vt["lean", "lean"])
tm[, side := fcase(p_model - mid24 >= 0.05, "yes", p_model - mid24 <= -0.05, "no", default = "none")]
pk <- tm[side != "none"][, clv_bps := 10000 * fifelse(side == "yes", mid - mid24, mid24 - mid)]
gg2 <- unique(pk$game_id)
bc <- replicate(2000, { bb <- pk[data.table(game_id = sample(gg2, replace = TRUE)), on = "game_id", allow.cartesian = TRUE]; mean(bb$clv_bps) })
timing <- data.table(id = c("GT1", "GT2"), test = c("the projection predicts the move from 24 h before kickoff to the close (one-sided > 0)",
                                                     "mean CLV (bps) of picks 5+ points from the 24-hour mid, to the close"),
                     contracts = nrow(tm), games = Gt, picks = c(NA, nrow(pk)), estimate = c(bt_, mean(pk$clv_bps)),
                     lo = c(bt_ - stats::qt(0.975, Gt - 1) * set_, stats::quantile(bc, 0.025)), hi = c(bt_ + stats::qt(0.975, Gt - 1) * set_, stats::quantile(bc, 0.975)),
                     p_one_sided = c(stats::pt(-bt_ / set_, Gt - 1), mean(bc <= 0)))
fwrite(signif_dt(timing), file.path(out, "projection_timing.csv"))
print(signif_dt(timing, 4))
options(width = 200)
print(signif_dt(res, 4)); print(signif_dt(by_stat, 4))
cat(sprintf("\nplayer-weeks projected: %d; contracts matched: %d of the ladders' %d at the close\n", nrow(proj), nrow(d), nrow(st)))
