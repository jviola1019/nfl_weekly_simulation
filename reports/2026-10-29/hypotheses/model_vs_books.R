# Family M, the owner's question of 2026-11-02: does our model beat any book? The 2026 week-7 run (written 2026-10-20
# 19:45Z, before any week-7 game) against every price held for those games:
# - books: the consensus at decision time (the run's own market input, nflverse on 2026-10-20), the consensus close
#   (nflverse), DraftKings (ESPN's feed at the last capture before kickoff, out/cross_venue/) and Kalshi's close (the
#   hourly candle at kickoff, reports/2026-10-28/feasibility/props/);
# - games: the moneyline from the simulator's raw probability, the GLMM blend and the shrunk final (C3); spreads and
#   totals from the simulated margin and total distributions, at the consensus close's lines and on Kalshi's ladders;
# - props: the props module's projected means (that run's baseline_props.csv) against Kalshi's close, in Family G's frame
#   (props_projection.R's dispersion model, so only the mean differs), head to head with G's own projection.
# Week 7 has 14 games, so these are measurements of where the model stands, not tests with power. Inputs copied from the
# run are in out/model_vs_books/inputs/. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/model_vs_books.R <out_dir> --settled=<a>,<b> --candles=<a>,<b> --dk=<cross_venue_games.csv>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; inp <- file.path(out, "inputs")
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
dec <- function(o) ifelse(o < 0, 1 + 100 / -o, 1 + o / 100)
ll <- function(p, y) -mean(y * log(pmin(pmax(p, 1e-6), 1 - 1e-6)) + (1 - y) * log(1 - pmin(pmax(p, 1e-6), 1 - 1e-6)))
WEEK <- 7L
set.seed(20261102)

# --- the run's game probabilities and distributions; results and the consensus close -------------------------------------
gp <- as.data.table(jsonlite::fromJSON(file.path(inp, "w07_game_predictions.json")))
bg <- fread(file.path(inp, "w07_baseline_games.csv"))
sd <- jsonlite::fromJSON(file.path(inp, "w07_score_distributions.json"), simplifyVector = TRUE)
sched <- as.data.table(nflreadr::load_schedules(2026))[game_type == "REG" & week == WEEK]
stopifnot(all(sched$season == 2026), !anyNA(sched$result))
g <- merge(gp[candidate == "C3", .(game_id, raw = p_home_raw, final = p_home_final, cons_dec = p_home_mkt_novig)], bg[, .(game_id, blend = blend_home_prob)], by = "game_id")
g <- merge(g, sched[, .(game_id, home_team, away_team, result, total = home_score + away_score, spread_line, total_line, home_moneyline, away_moneyline)], by = "game_id")
g[, `:=`(y = fifelse(result > 0, 1, fifelse(result < 0, 0, 0.5)),
         cons_close = (1 / dec(home_moneyline)) / (1 / dec(home_moneyline) + 1 / dec(away_moneyline)))]
dk <- fread(opt("dk"))[game_id %in% g$game_id, .(game_id, dk = p_dk, ml_home_dk = ml_home, ml_away_dk = ml_away)]
g <- merge(g, dk, by = "game_id", all.x = TRUE)

# Kalshi's close: game, spread and total contracts of week 7, mid of the candle at kickoff
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")
cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
ev <- props_event_games(st$event_ticker, props_schedule())
k <- merge(merge(st[, .(ticker, series, event_ticker, label, result_k = result, yk = settlement_value)], ev, by = "event_ticker")[week == WEEK],
           cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker")
k <- merge(k, g[, .(game_id, home_team, away_team)], by = "game_id")
k <- k[result_k %in% c("yes", "no") & is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & ask - bid <= MAX_SPREAD][, mid := (bid + ask) / 2]
k[, team := sub("^.*-([A-Z]+)[0-9]*$", "\\1", ticker)]
same <- function(a, b) a == b | (a == "LAR" & b == "LA") | (a == "LA" & b == "LAR") | (a == "JAC" & b == "JAX") | (a == "WSH" & b == "WAS") | (a == "LVR" & b == "LV")
kg <- k[series == "KXNFLGAME" & same(team, home_team), .(game_id, kalshi_close = mid, k_bid = bid, k_ask = ask)]
g <- merge(g, kg, by = "game_id", all.x = TRUE)

# --- 1. moneyline: accuracy of each forecast, and the model's bets at each book ------------------------------------------------
series <- c("raw", "blend", "final", "cons_dec", "cons_close", "dk", "kalshi_close")
acc <- rbindlist(lapply(series, function(s) { x <- g[is.finite(get(s))]
  data.table(forecast = s, games = nrow(x), brier = mean((x[[s]] - x$y)^2), logloss = ll(x[[s]], x$y), mean_abs_gap_to_close_pp = 100 * mean(abs(x[[s]] - x$cons_close))) }))
boot_diff <- function(a, b) { d <- (g[[a]] - g$y)^2 - (g[[b]] - g$y)^2; d <- d[is.finite(d)]
  bs <- replicate(4000, mean(sample(d, replace = TRUE))); c(mean(d), stats::quantile(bs, c(0.025, 0.975))) }
acc_vs <- rbindlist(lapply(c("raw", "blend", "final"), function(m) rbindlist(lapply(c("cons_dec", "cons_close", "dk", "kalshi_close"), function(v) {
  z <- boot_diff(m, v); data.table(model = m, book = v, brier_diff = z[1], lo = z[2], hi = z[3]) }))))
# bets: the side the model prices above the book's cost, one unit each; Kalshi at the ask plus the taker fee
bet_rows <- function(m) rbindlist(list(
  g[, .(game_id, model = m, book = "consensus close", p = get(m), y, d_h = dec(home_moneyline), d_a = dec(away_moneyline))],
  g[is.finite(ml_home_dk), .(game_id, model = m, book = "DraftKings", p = get(m), y, d_h = dec(ml_home_dk), d_a = dec(ml_away_dk))],
  g[is.finite(k_ask), .(game_id, model = m, book = "Kalshi close", p = get(m), y, d_h = 1 / (k_ask + fee(k_ask)), d_a = 1 / ((1 - k_bid) + fee(1 - k_bid)))]))
bets <- rbindlist(lapply(c("raw", "blend", "final"), bet_rows))
bets[, side := fcase(p * d_h > 1, "home", (1 - p) * d_a > 1, "away", default = "none")]
bets[, units := fcase(side == "home", fifelse(y == 1, d_h - 1, fifelse(y == 0.5, 0, -1)), side == "away", fifelse(y == 0, d_a - 1, fifelse(y == 0.5, 0, -1)), default = 0)]
bets[, claimed_ev := fcase(side == "home", p * d_h - 1, side == "away", (1 - p) * d_a - 1, default = NA_real_)]
bet_sum <- bets[side != "none", .(bets = .N, wins = sum(units > 0), units = sum(units), roi = sum(units) / .N, mean_claimed_ev = mean(claimed_ev)), by = .(model, book)]

# --- 2. spreads and totals from the simulated distributions ---------------------------------------------------------------------
bins <- as.data.table(sd)[, rbindlist(bins), by = .(game_id, kind)]
p_gt <- function(gid, kd, x) { b <- bins[game_id == gid & kind == kd]; sum(b$p[b$x > x]) / sum(b$p) }
p_eq <- function(gid, kd, x) { b <- bins[game_id == gid & kind == kd]; sum(b$p[b$x == x]) / sum(b$p) }
ats <- g[, .(game_id, line = spread_line, result, total, total_line)]
ats[, `:=`(p_home_cover = mapply(function(i, l) p_gt(i, "margin", l), game_id, line), p_push = mapply(function(i, l) p_eq(i, "margin", l), game_id, line),
           p_over = mapply(function(i, t) p_gt(i, "total", t), game_id, total_line), p_tpush = mapply(function(i, t) p_eq(i, "total", t), game_id, total_line))]
ats[, `:=`(q_home = p_home_cover / (1 - p_push), q_over = p_over / (1 - p_tpush))]
BREAKEVEN <- 110 / 210   # -110
ats[, `:=`(ats_side = fcase(q_home > BREAKEVEN, "home", 1 - q_home > BREAKEVEN, "away", default = "none"), ou_side = fcase(q_over > BREAKEVEN, "over", 1 - q_over > BREAKEVEN, "under", default = "none"))]
ats[, `:=`(ats_units = fcase(ats_side == "none" | result == line, 0, (ats_side == "home") == (result > line), 100 / 110, default = -1),
           ou_units = fcase(ou_side == "none" | total == total_line, 0, (ou_side == "over") == (total > total_line), 100 / 110, default = -1))]
ats_sum <- data.table(market = c("spread at the consensus close, -110", "total at the consensus close, -110"),
                      bets = c(sum(ats$ats_side != "none"), sum(ats$ou_side != "none")), units = c(sum(ats$ats_units), sum(ats$ou_units)),
                      brier_model = c(mean((ats$q_home - (ats$result > ats$line))[ats$result != ats$line]^2), mean((ats$q_over - (ats$total > ats$total_line))[ats$total != ats$total_line]^2)))
# Kalshi's spread and total ladders at the close against the simulated distributions: Brier and the information test
lad <- k[series %in% c("KXNFLSPREAD", "KXNFLTOTAL")]
lad[, x := as.numeric(sub("^.*[Oo]ver ([0-9.]+)( points)?.*$", "\\1", label))]
lad[, p_model := fifelse(series == "KXNFLTOTAL", mapply(function(i, xx) p_gt(i, "total", xx), game_id, x),
                         fifelse(same(team, home_team), mapply(function(i, xx) p_gt(i, "margin", xx), game_id, x), mapply(function(i, xx) 1 - p_gt(i, "margin", -xx - 1e-9), game_id, x)))]
lad <- lad[is.finite(x) & is.finite(p_model)][, p_model := pmin(pmax(p_model, 0.005), 0.995)]
info_test <- function(d, y, p, mkt) { m <- stats::glm(stats::as.formula(sprintf("%s ~ offset(lg(%s)) + I(lg(%s) - lg(%s))", y, mkt, p, mkt)), family = stats::quasibinomial(), data = d)
  V <- sandwich::vcovCL(m, cluster = d$game_id, type = "HC1"); G <- uniqueN(d$game_id); b <- unname(stats::coef(m)[2]); se <- sqrt(V[2, 2])
  data.table(n = nrow(d), games = G, coef = b, lo = b - stats::qt(0.975, G - 1) * se, hi = b + stats::qt(0.975, G - 1) * se, p_one_sided = stats::pt(-b / se, G - 1)) }
lad_tests <- rbindlist(lapply(c("KXNFLSPREAD", "KXNFLTOTAL"), function(s) { d <- lad[series == s]
  cbind(ladder = s, info_test(d, "yk", "p_model", "mid"), brier_kalshi = mean((d$mid - d$yk)^2), brier_model = mean((d$p_model - d$yk)^2)) }))

# --- 3. props: the module's projected means against Kalshi's close, in Family G's frame --------------------------------------------
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
ps <- as.data.table(nflreadr::load_player_stats(seasons = 2026))[season_type == "REG" & week < WEEK]
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
nxt <- long[, .(mu_raw = { w <- 0.5^((.N - seq_len(.N)) / 3); sum(w * v) / sum(w) }, n_prior = .N), by = .(player_id, key, team, pos, stat)]   # for week 7
listed <- unique(merge(st[, .(event_ticker, series, label)], ev, by = "event_ticker")[week < WEEK & series %in% names(LADDERS),
                                                                                     .(week, key = norm(sub(":.*$", "", label)), stat = unname(LADDERS[series]))])
prior <- merge(long, listed, by = c("week", "key", "stat"))
tgt <- prior[, .(m_pos = mean(v)), by = .(stat, pos)]
# dispersion by stat and position from the earlier weeks' residuals around their own projections (G's fit)
fitd <- merge(prior[n_prior > 0], tgt, by = c("stat", "pos"))[, mu := (n_prior * mu_raw + 3 * m_pos) / (n_prior + 3)][is.finite(mu) & is.finite(v)]
disp <- fitd[, .(theta = { e2 <- mean((v - mu)^2); mm <- mean(mu); if (is.finite(e2) && e2 > mm) mean(mu^2) / (e2 - mm) else Inf },
                 p0 = mean(v <= 0), kappa = { pv <- v > 0; if (sum(pv) > 5) mean(mu[pv]^2) / mean((v[pv] - mu[pv])^2) else 1 }), by = .(stat, pos)]
ew <- merge(nxt, tgt, by = c("stat", "pos"))[, mu_g := (n_prior * mu_raw + 3 * m_pos) / (n_prior + 3)]
mod <- fread(file.path(inp, "w07_baseline_props.csv"))
mod[, `:=`(stat = fifelse(prop_type == "anytime_td", "touchdowns", prop_type), akey = norm(sub(".", " ", player, fixed = TRUE)))]
pr <- merge(pr, mod[, .(akey, pteam = team, stat, mu_mod = projection, p_td_mod = p_over)], by = c("akey", "pteam", "stat"))
pr <- merge(pr, ew[, .(key, pteam = team, stat, pos, mu_g)], by = c("key", "pteam", "stat"), all.x = TRUE)
pr <- merge(pr, disp, by = c("stat", "pos"), all.x = TRUE)
p_of <- function(mu, stat, kk, theta, p0, kappa) fifelse(stat %in% COUNTS, 1 - stats::pnbinom(kk - 1, size = pmin(theta, 1e6), mu = pmax(mu, 1e-6)),
  (1 - pmin(p0, 0.99)) * (1 - stats::pgamma(kk, shape = pmax(kappa, 0.05), rate = pmax(kappa, 0.05) / pmax(mu / (1 - pmin(p0, 0.99)), 1e-6))))
pr[, `:=`(p_mod = fifelse(stat == "touchdowns" & kk == 1, p_td_mod, p_of(mu_mod, stat, kk, theta, p0, kappa)), p_g = p_of(mu_g, stat, kk, theta, p0, kappa))]
pr <- pr[is.finite(p_mod)][, p_mod := pmin(pmax(p_mod, 0.005), 0.995)][, p_g := pmin(pmax(p_g, 0.005), 0.995)]
stopifnot(!anyDuplicated(pr$ticker))   # one row per Kalshi contract: a name shared by two module rows would double-count it
props_tests <- rbind(cbind(forecast = "props module", info_test(pr, "yk", "p_mod", "mid")), cbind(forecast = "Family G projection", info_test(pr[is.finite(p_g)], "yk", "p_g", "mid")))
props_tests[, `:=`(brier_kalshi = c(mean((pr$mid - pr$yk)^2), mean((pr[is.finite(p_g)]$mid - pr[is.finite(p_g)]$yk)^2)),
                   brier_forecast = c(mean((pr$p_mod - pr$yk)^2), mean((pr[is.finite(p_g)]$p_g - pr[is.finite(p_g)]$yk)^2)))]
pr[, side := fcase(p_mod > ask + fee(ask), "yes", 1 - p_mod > 1 - bid + fee(1 - bid), "no", default = "none")]
pr[, `:=`(pnl = fcase(side == "yes", yk - ask - fee(ask), side == "no", bid - yk - fee(1 - bid), default = 0),
          stake = fcase(side == "yes", ask + fee(ask), side == "no", 1 - bid + fee(1 - bid), default = 0))]
pb <- pr[side != "none"]; gg <- unique(pb$game_id)
bt <- replicate(2000, { bb <- pb[data.table(game_id = sample(gg, replace = TRUE)), on = "game_id", allow.cartesian = TRUE]; sum(bb$pnl) / sum(bb$stake) })
props_bets <- data.table(contracts = nrow(pr), bets = nrow(pb), roi = sum(pb$pnl) / sum(pb$stake), lo = stats::quantile(bt, 0.025), hi = stats::quantile(bt, 0.975))
props_by_stat <- pr[, .(contracts = .N, players = uniqueN(akey), brier_kalshi = mean((mid - yk)^2), brier_module = mean((p_mod - yk)^2),
                        mean_gap_pp = 100 * mean(abs(p_mod - mid))), by = stat]

# --- 4. how far the model sits from the market, against how far the books sit from each other ---------------------------------------
gaps <- data.table(comparison = c("simulator raw vs consensus at decision", "blend vs consensus at decision", "final (shown) vs consensus at decision",
                                  "DraftKings vs consensus close", "Kalshi close vs consensus close", "consensus at decision vs consensus close"),
                   mean_abs_gap_pp = 100 * c(mean(abs(g$raw - g$cons_dec)), mean(abs(g$blend - g$cons_dec)), mean(abs(g$final - g$cons_dec)),
                                             mean(abs(g$dk - g$cons_close), na.rm = TRUE), mean(abs(g$kalshi_close - g$cons_close), na.rm = TRUE), mean(abs(g$cons_dec - g$cons_close))))

dir.create(out, recursive = TRUE, showWarnings = FALSE)
fwrite(signif_dt(acc, 4), file.path(out, "games_accuracy.csv")); fwrite(signif_dt(acc_vs, 4), file.path(out, "games_brier_vs_books.csv"))
fwrite(signif_dt(bet_sum, 4), file.path(out, "games_bets.csv")); fwrite(signif_dt(ats_sum, 4), file.path(out, "games_spread_total.csv"))
fwrite(signif_dt(lad_tests, 4), file.path(out, "games_kalshi_ladders.csv")); fwrite(signif_dt(gaps, 4), file.path(out, "games_gaps.csv"))
fwrite(signif_dt(props_tests, 4), file.path(out, "props_tests.csv")); fwrite(signif_dt(props_bets, 4), file.path(out, "props_bets.csv"))
fwrite(signif_dt(props_by_stat, 4), file.path(out, "props_by_stat.csv"))
fwrite(signif_dt(g[, .(game_id, y, raw, blend, final, cons_dec, cons_close, dk, kalshi_close)], 4), file.path(out, "games_week7.csv"))
options(width = 220)
print(signif_dt(acc, 4)); print(signif_dt(acc_vs, 3)); print(signif_dt(bet_sum, 3)); print(signif_dt(ats_sum, 3)); print(signif_dt(lad_tests, 3)); print(signif_dt(gaps, 3))
print(signif_dt(props_tests, 3)); print(signif_dt(props_bets, 3)); print(signif_dt(props_by_stat, 3))
cat(sprintf("\nprops matched: %d contracts, %d players, %d games; module rows %d\n", nrow(pr), uniqueN(pr$akey), uniqueN(pr$game_id), nrow(mod)))
