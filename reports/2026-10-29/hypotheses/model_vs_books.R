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
source(file.path("reports", "2026-10-29", "hypotheses", "props_frame.R"))   # info_test, module_props
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
lad_tests <- rbindlist(lapply(c("KXNFLSPREAD", "KXNFLTOTAL"), function(s) { d <- lad[series == s]
  cbind(ladder = s, info_test(d, "yk", "p_model", "mid"), brier_kalshi = mean((d$mid - d$yk)^2), brier_model = mean((d$p_model - d$yk)^2)) }))

# --- 3. props: the module's projected means against Kalshi's close, in Family G's frame (props_frame.R) -------------------------
mp <- module_props(k, st, ev, WEEK, fread(file.path(inp, "w07_baseline_props.csv")), cn)
pr <- mp$pr; mod <- mp$mod; props_tests <- mp$tests; props_bets <- mp$bets; props_by_stat <- mp$by_stat; props_timing <- mp$timing

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
fwrite(signif_dt(props_timing, 4), file.path(out, "props_timing.csv"))
fwrite(signif_dt(g[, .(game_id, y, raw, blend, final, cons_dec, cons_close, dk, kalshi_close)], 4), file.path(out, "games_week7.csv"))
options(width = 220)
print(signif_dt(acc, 4)); print(signif_dt(acc_vs, 3)); print(signif_dt(bet_sum, 3)); print(signif_dt(ats_sum, 3)); print(signif_dt(lad_tests, 3)); print(signif_dt(gaps, 3))
print(signif_dt(props_tests, 3)); print(signif_dt(props_bets, 3)); print(signif_dt(props_by_stat, 3)); print(signif_dt(props_timing, 3))
cat(sprintf("\nprops matched: %d contracts, %d players, %d games; module rows %d\n", nrow(pr), uniqueN(pr$akey), uniqueN(pr$game_id), nrow(mod)))
