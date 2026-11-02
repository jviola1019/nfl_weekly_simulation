# Shared by model_vs_books.R (week 7) and score_week.R (the prospective weeks): the information test against a market
# price, and the props module's projections scored against Kalshi's close in Family G's frame (HYPOTHESES.md §13, §15).
# Needs props_common.R (LADDERS, MAX_SPREAD, fee, lg) and data.table.

# y ~ offset(logit market) + (logit forecast - logit market), quasibinomial, clustered by game; H1: coefficient > 0
info_test <- function(d, y, p, mkt) { m <- stats::glm(stats::as.formula(sprintf("%s ~ offset(lg(%s)) + I(lg(%s) - lg(%s))", y, mkt, p, mkt)), family = stats::quasibinomial(), data = d)
  V <- sandwich::vcovCL(m, cluster = d$game_id, type = "HC1"); G <- uniqueN(d$game_id); b <- unname(stats::coef(m)[2]); se <- sqrt(V[2, 2])
  data.table(n = nrow(d), games = G, coef = b, lo = b - stats::qt(0.975, G - 1) * se, hi = b + stats::qt(0.975, G - 1) * se, p_one_sided = stats::pt(-b / se, G - 1)) }

# k: the week's Kalshi contracts at the close (settled yes/no, within MAX_SPREAD), with game_id, home_team, away_team, mid,
# bid, ask and the settlement yk; st, ev: every settlement and its game (for the earlier weeks' listed players); mod: the
# run's baseline_props.csv; cn: the candles (for the 24-hour price). Draws from the caller's random-number stream.
module_props <- function(k, st, ev, wk, mod, cn) {
  COUNTS <- c("receptions", "carries", "completions", "attempts", "passing_tds", "touchdowns", "passing_interceptions")
  norm <- function(x) { x <- tolower(iconv(x, to = "ASCII//TRANSLIT")); x <- gsub("[.'`-]", "", x); x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("\\s+", " ", trimws(x)) }
  abbr <- function(full) { z <- strsplit(norm(full), " ", fixed = TRUE); vapply(z, function(t) if (length(t) < 2) NA_character_ else paste(substr(t[1], 1, 1), paste(t[-1], collapse = " ")), "") }
  pr <- k[series %in% names(LADDERS)][, `:=`(kk = as.numeric(sub("^.*: ([0-9]+)\\+$", "\\1", label)), name = sub(":.*$", "", label), stat = unname(LADDERS[series]),
                                           seg = substring(ticker, nchar(event_ticker) + 2L))]
  aliases <- function(x) c(x, switch(x, LA = "LAR", JAX = "JAC", WAS = "WSH", LV = "LVR", character(0)))
  pr[, pteam := vapply(seq_len(.N), function(i) { cand <- c(stats::setNames(aliases(home_team[i]), rep(home_team[i], length(aliases(home_team[i])))),
                                                            stats::setNames(aliases(away_team[i]), rep(away_team[i], length(aliases(away_team[i])))))
    hit <- cand[startsWith(seg[i], cand)]; if (length(hit)) names(hit)[which.max(nchar(hit))] else NA_character_ }, character(1))]
  pr <- pr[!is.na(kk) & !is.na(pteam)][, `:=`(key = norm(name), akey = abbr(name))]
  # Family G: each player's walk-forward EWMA (half-life 3) of his earlier 2026 games, shrunk toward listed players at his
  # position (weight n / (n + 3)); dispersion by stat and position from the earlier weeks
  ps <- as.data.table(nflreadr::load_player_stats(seasons = 2026))[season_type == "REG" & week < wk]
  stopifnot(nrow(ps) > 0, all(ps$season == 2026))
  z0 <- function(v) fifelse(is.na(v), 0, as.numeric(v))
  ps[, `:=`(touchdowns = z0(rushing_tds) + z0(receiving_tds) + z0(special_teams_tds), rush_rec_yards = z0(rushing_yards) + z0(receiving_yards),
            key = norm(player_display_name), pos = fifelse(position == "FB", "RB", position))]
  long <- melt(ps[, c("player_id", "key", "team", "pos", "week", unique(LADDERS)), with = FALSE], id.vars = c("player_id", "key", "team", "pos", "week"),
               variable.name = "stat", value.name = "v", variable.factor = FALSE)[, v := z0(v)]
  setorder(long, player_id, stat, week)
  # each row's walk-forward EWMA of the player's earlier games (half-life 3 games), as props_projection.R does
  long[, c("mu_raw", "n_prior") := { m <- rep(NA_real_, .N)
    for (i in seq_len(.N)) if (i > 1) { w <- 0.5^((i - 1 - seq_len(i - 1)) / 3); m[i] <- sum(w * v[seq_len(i - 1)]) / sum(w) }
    list(m, seq_len(.N) - 1L) }, by = .(player_id, stat)]
  nxt <- long[, .(mu_raw = { w <- 0.5^((.N - seq_len(.N)) / 3); sum(w * v) / sum(w) }, n_prior = .N), by = .(player_id, key, team, pos, stat)]   # for the week scored
  listed <- unique(merge(st[, .(event_ticker, series, label)], ev, by = "event_ticker")[week < wk & series %in% names(LADDERS),
                                                                                       .(week, key = norm(sub(":.*$", "", label)), stat = unname(LADDERS[series]))])
  prior <- merge(long, listed, by = c("week", "key", "stat"))
  tgt <- prior[, .(m_pos = mean(v)), by = .(stat, pos)]
  # dispersion by stat and position from the earlier weeks' residuals around their own projections (G's fit)
  fitd <- merge(prior[n_prior > 0], tgt, by = c("stat", "pos"))[, mu := (n_prior * mu_raw + 3 * m_pos) / (n_prior + 3)][is.finite(mu) & is.finite(v)]
  disp <- fitd[, .(theta = { e2 <- mean((v - mu)^2); mm <- mean(mu); if (is.finite(e2) && e2 > mm) mean(mu^2) / (e2 - mm) else Inf },
                   p0 = mean(v <= 0), kappa = { pv <- v > 0; if (sum(pv) > 5) mean(mu[pv]^2) / mean((v[pv] - mu[pv])^2) else 1 }), by = .(stat, pos)]
  ew <- merge(nxt, tgt, by = c("stat", "pos"))[, mu_g := (n_prior * mu_raw + 3 * m_pos) / (n_prior + 3)]
  mod <- copy(mod)[, `:=`(stat = fifelse(prop_type == "anytime_td", "touchdowns", prop_type), akey = norm(sub(".", " ", player, fixed = TRUE)))]
  pr <- merge(pr, mod[, .(akey, pteam = team, stat, mu_mod = projection, p_td_mod = p_over)], by = c("akey", "pteam", "stat"))
  pr <- merge(pr, ew[, .(key, pteam = team, stat, pos, mu_g)], by = c("key", "pteam", "stat"), all.x = TRUE)
  pr <- merge(pr, disp, by = c("stat", "pos"), all.x = TRUE)
  p_of <- function(mu, stat, kk, theta, p0, kappa) fifelse(stat %in% COUNTS, 1 - stats::pnbinom(kk - 1, size = pmin(theta, 1e6), mu = pmax(mu, 1e-6)),
    (1 - pmin(p0, 0.99)) * (1 - stats::pgamma(kk, shape = pmax(kappa, 0.05), rate = pmax(kappa, 0.05) / pmax(mu / (1 - pmin(p0, 0.99)), 1e-6))))
  pr[, `:=`(p_mod = fifelse(stat == "touchdowns" & kk == 1, p_td_mod, p_of(mu_mod, stat, kk, theta, p0, kappa)), p_g = p_of(mu_g, stat, kk, theta, p0, kappa))]
  pr <- pr[is.finite(p_mod)][, p_mod := pmin(pmax(p_mod, 0.005), 0.995)][, p_g := pmin(pmax(p_g, 0.005), 0.995)]
  stopifnot(!anyDuplicated(pr$ticker))   # one row per Kalshi contract: a name shared by two module rows would double-count it
  tests <- rbind(cbind(forecast = "props module", info_test(pr, "yk", "p_mod", "mid")), cbind(forecast = "Family G projection", info_test(pr[is.finite(p_g)], "yk", "p_g", "mid")))
  tests[, `:=`(brier_kalshi = c(mean((pr$mid - pr$yk)^2), mean((pr[is.finite(p_g)]$mid - pr[is.finite(p_g)]$yk)^2)),
               brier_forecast = c(mean((pr$p_mod - pr$yk)^2), mean((pr[is.finite(p_g)]$p_g - pr[is.finite(p_g)]$yk)^2)))]
  pr[, side := fcase(p_mod > ask + fee(ask), "yes", 1 - p_mod > 1 - bid + fee(1 - bid), "no", default = "none")]
  pr[, `:=`(pnl = fcase(side == "yes", yk - ask - fee(ask), side == "no", bid - yk - fee(1 - bid), default = 0),
            stake = fcase(side == "yes", ask + fee(ask), side == "no", 1 - bid + fee(1 - bid), default = 0))]
  pb <- pr[side != "none"]; gg <- unique(pb$game_id)
  bt <- replicate(2000, { bb <- pb[data.table(game_id = sample(gg, replace = TRUE)), on = "game_id", allow.cartesian = TRUE]; sum(bb$pnl) / sum(bb$stake) })
  bets <- data.table(contracts = nrow(pr), bets = nrow(pb), roi = sum(pb$pnl) / sum(pb$stake), lo = stats::quantile(bt, 0.025), hi = stats::quantile(bt, 0.975))
  by_stat <- pr[, .(contracts = .N, players = uniqueN(akey), brier_kalshi = mean((mid - yk)^2), brier_module = mean((p_mod - yk)^2),
                    mean_gap_pp = 100 * mean(abs(p_mod - mid))), by = stat]
  # timing (HYPOTHESES.md §15): does the module's projection, made days before, predict Kalshi's move from 24 h before kickoff to the close?
  tmv <- merge(pr, cn[, .(ticker, bid24 = bid_24h, ask24 = ask_24h)], by = "ticker")
  tmv <- tmv[is.finite(bid24) & is.finite(ask24) & ask24 > 0 & ask24 >= bid24 & ask24 - bid24 <= MAX_SPREAD][, mid24 := (bid24 + ask24) / 2][mid24 > 0 & mid24 < 1]
  tmv[, `:=`(move = lg(mid) - lg(mid24), lean = lg(p_mod) - lg(mid24))]
  mtm <- stats::lm(move ~ lean, data = tmv); Vtm <- sandwich::vcovCL(mtm, cluster = tmv$game_id, type = "HC1"); Gtm <- uniqueN(tmv$game_id)
  btm <- unname(stats::coef(mtm)["lean"]); setm <- sqrt(Vtm["lean", "lean"])
  tmv[, side := fcase(p_mod - mid24 >= 0.05, "yes", p_mod - mid24 <= -0.05, "no", default = "none")]
  pkm <- tmv[side != "none"][, clv_bps := 10000 * fifelse(side == "yes", mid - mid24, mid24 - mid)]
  ggm <- unique(pkm$game_id)
  bcm <- replicate(2000, { bb <- pkm[data.table(game_id = sample(ggm, replace = TRUE)), on = "game_id", allow.cartesian = TRUE]; mean(bb$clv_bps) })
  timing <- data.table(id = c("MT1", "MT2"), test = c("the module predicts the move from 24 h before kickoff to the close (one-sided > 0)",
                                                      "mean CLV (bps) of picks 5+ points from the 24-hour mid, to the close"),
                       contracts = nrow(tmv), games = Gtm, picks = c(NA, nrow(pkm)), estimate = c(btm, mean(pkm$clv_bps)),
                       lo = c(btm - stats::qt(0.975, Gtm - 1) * setm, stats::quantile(bcm, 0.025)), hi = c(btm + stats::qt(0.975, Gtm - 1) * setm, stats::quantile(bcm, 0.975)),
                       p_one_sided = c(stats::pt(-btm / setm, Gtm - 1), mean(bcm <= 0)))
  list(pr = pr, tests = tests, bets = bets, by_stat = by_stat, timing = timing, mod = mod)
}
