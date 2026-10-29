# Family B of PLAN.md: information and behaviour in Kalshi's props, 2026 weeks 1-7, every contract at its close
# (kalshi_candles.R) against Kalshi's settlement (kalshi_settled.R). Calibration-in-the-large tests are quasibinomial
# logits with the close's logit as offset, clustered by game (HC1, t with G - 1 df):
# - B1 teammates of a prop player who was Out on the final injury report or never took a snap (H1: underpriced);
# - B2 players listed Questionable who played (H1: underpriced; a no-snap settles at the fair price);
# - B3 the last day's move, logit(close) - logit(24 h before) (H1: it overreacts, coefficient < 0);
# - B4 a recalibration of the price 24 h out, fit on weeks 1-5 and scored on weeks 6-7, and a taker at that price;
# - B5 the bottom against the top tercile of 48 h volume (two-sided);
# - B6 contracts priced under 20 cents (H1: YES overpriced; seen in the feasibility study).
# BH over B1-B6. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/kalshi_behaviour.R <out_dir> --settled=<a>,<b> --candles=<a>,<b> --volume=<csv.gz>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")
cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
vol <- read_gz(opt("volume"))
stopifnot(!any(substr(st$close_time, 1, 4) == "2025"))
sched <- props_schedule()
d <- merge(st[, .(ticker, series, event_ticker, label, result, y = settlement_value)], props_event_games(st$event_ticker, sched), by = "event_ticker")
d[, outcome := props_outcome(series, game_id, result, y)]
d <- merge(d, sched[, .(game_id, home_team, away_team)], by = "game_id")
d <- merge(d, cn[, .(ticker, bid = bid_close, ask = ask_close, bid_24h, ask_24h)], by = "ticker", all.x = TRUE)
d <- merge(d, vol[, .(ticker, volume_48h)], by = "ticker", all.x = TRUE)
d[, `:=`(group = group_of(series), mid = (bid + ask) / 2, spread = ask - bid, mid_24h = (bid_24h + ask_24h) / 2)]

# each player contract's team (the ticker's segment after the event starts with one of the two teams' Kalshi codes,
# the longest match wins: LAC before LA) and the player's name key
aliases <- function(x) c(x, switch(x, LA = c("LAR"), JAX = "JAC", WAS = "WSH", LV = "LVR", character(0)))
d[, seg := substring(ticker, nchar(event_ticker) + 2L)]
d[, team := vapply(seq_len(.N), function(i) {
  cand <- c(stats::setNames(aliases(home_team[i]), rep(home_team[i], length(aliases(home_team[i])))),
            stats::setNames(aliases(away_team[i]), rep(away_team[i], length(aliases(away_team[i])))))
  hit <- cand[startsWith(seg[i], cand)]
  if (length(hit)) names(hit)[which.max(nchar(hit))] else NA_character_ }, character(1))]
norm <- function(x) { x <- tolower(iconv(x, to = "ASCII//TRANSLIT")); x <- gsub("[.'`-]", "", x)
  x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("\\s+", " ", trimws(x)) }
d[, key := norm(sub(":.*$", "", label))]
player <- d[group == "player" & !grepl("D/ST|No Touchdown", label) & !is.na(team)]

inj <- as.data.table(nflreadr::load_injuries(2026))[game_type == "REG"]
stopifnot(all(inj$season == 2026))
inj[, key := norm(full_name)]
relevant <- unique(player$key)                                  # players with a Kalshi prop at some point in 2026
absent <- unique(rbind(player[outcome == "settled at the fair price (no outcome)", .(game_id, team, key)],
                       merge(inj[report_status == "Out" & key %in% relevant, .(week, team, key)], unique(player[, .(game_id, week, team)]),
                             by = c("week", "team"))[, .(game_id, team, key)]))
questionable <- unique(inj[report_status == "Questionable", .(week, team, key)])

ok <- d[outcome %in% c("settled", "payout") & is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & spread <= MAX_SPREAD & mid > 0 & mid < 1]
okp <- ok[ticker %in% player$ticker]
okp[, teammate_absent := as.integer(paste(game_id, team) %in% absent[, paste(game_id, team)] & !paste(game_id, team, key) %in% absent[, paste(game_id, team, key)])]
okp[, questionable_played := as.integer(paste(week, team, key) %in% questionable[, paste(week, team, key)])]
# Ruling (after the literal B1 ran): the literal definition flags 80% of contracts, since most teams list some prop player
# Out most weeks, so it has no contrast. The refined absence: a player who played his team's previous game with a Kalshi
# prop and did not play this game (no prop listed, a fair-price settlement, or Out on the report).
pgm <- unique(player[, .(played = any(outcome %in% c("settled", "payout"))), by = .(game_id, team, key)])
tg <- unique(player[, .(game_id, team)])[sched[, .(game_id, gameday)], on = "game_id", nomatch = 0]
setorder(tg, team, gameday)
tg[, prev_game := shift(game_id), by = team]
was <- merge(tg[!is.na(prev_game), .(game_id, team, prev_game)], pgm[played == TRUE, .(prev_game = game_id, team, key)], by = c("prev_game", "team"), allow.cartesian = TRUE)
now <- pgm[played == TRUE, .(game_id, team, key, here = TRUE)]
gone <- merge(was, now, by = c("game_id", "team", "key"), all.x = TRUE)[is.na(here), .(game_id, team, key)]
okp[, teammate_absent_refined := as.integer(paste(game_id, team) %in% gone[, paste(game_id, team)])]
# Ruling (after B1r ran and still flagged 70%: Kalshi does not list every player every week, so "not listed" is no
# absence): the snap-count absence. A player who took offensive snaps in his team's previous game with a Kalshi prop and
# took none in this one (nflverse snap counts); only teammates in his position group (WR/TE, RB/FB, QB) are flagged.
sn <- as.data.table(nflreadr::load_snap_counts(seasons = 2026))
if (!nrow(sn)) stop("kalshi_behaviour: no 2026 snap counts were loaded", call. = FALSE)
sn <- sn[game_type == "REG", .(offense_snaps = sum(offense_snaps, na.rm = TRUE), position = position[1]), by = .(week, team, key = norm(player))]
sn[, pos_group := fcase(position %in% c("WR", "TE"), "receiver", position %in% c("RB", "FB"), "back", position == "QB", "qb", default = NA_character_)]
gw <- unique(player[, .(game_id, week, team)])
tg2 <- merge(tg, unique(gw[, .(game_id, week)]), by = "game_id")
tg2[, prev_week := shift(week), by = team]
had <- unique(player[outcome %in% c("settled", "payout"), .(game_id, team, key)])
rel <- merge(merge(tg2[!is.na(prev_game), .(game_id, week, team, prev_game, prev_week)], had[, .(prev_game = game_id, team, key)], by = c("prev_game", "team")),
             sn[offense_snaps > 0, .(prev_week = week, team, key, pos_group)], by = c("prev_week", "team", "key"))
rel <- merge(rel, sn[, .(week, team, key, snaps_now = offense_snaps)], by = c("week", "team", "key"), all.x = TRUE)
gone_s <- rel[(is.na(snaps_now) | snaps_now == 0) & !is.na(pos_group), .(game_id, team, key, pos_group)]
okp <- merge(okp, sn[, .(week, team, key, my_group = pos_group)], by = c("week", "team", "key"), all.x = TRUE)
okp[, teammate_absent_snaps := as.integer(paste(game_id, team, my_group) %in% gone_s[, paste(game_id, team, pos_group)] &
                                            !paste(game_id, team, key) %in% gone_s[, paste(game_id, team, key)])]

# one coefficient, clustered by game; returns the estimate, its CI and the one- and two-sided p
coef_test <- function(f, x, term) {
  m <- stats::glm(f, family = stats::quasibinomial(), data = x)
  V <- sandwich::vcovCL(m, cluster = x$game_id, type = "HC1"); G <- uniqueN(x$game_id)
  b <- unname(stats::coef(m)[term]); se <- sqrt(V[term, term]); tq <- stats::qt(0.975, G - 1); t <- b / se
  data.table(n = nrow(x), games = G, flagged = if (term %in% names(x)) sum(x[[term]]) else NA_integer_, estimate = b, lo = b - tq * se, hi = b + tq * se,
             p_greater = stats::pt(-t, G - 1), p_less = stats::pt(t, G - 1), p_two = 2 * stats::pt(-abs(t), G - 1))
}
res <- list()
res$B1 <- cbind(id = "B1", hypothesis = "teammates of an absent prop player are underpriced", side = "greater",
                coef_test(y ~ offset(lg(mid)) + teammate_absent, okp, "teammate_absent"))
res$B1r <- cbind(id = "B1r", hypothesis = "teammates of a player absent after playing the previous game are underpriced (ruling)", side = "greater",
                 coef_test(y ~ offset(lg(mid)) + teammate_absent_refined, okp, "teammate_absent_refined"))
res$B1s <- cbind(id = "B1s", hypothesis = "position-group teammates of a player who played last game and took no snap now are underpriced (ruling)",
                 side = "greater", coef_test(y ~ offset(lg(mid)) + teammate_absent_snaps, okp, "teammate_absent_snaps"))
res$B2 <- cbind(id = "B2", hypothesis = "Questionable players who played are underpriced", side = "greater",
                coef_test(y ~ offset(lg(mid)) + questionable_played, okp, "questionable_played"))
m3 <- ok[is.finite(bid_24h) & is.finite(ask_24h) & ask_24h > 0 & ask_24h >= bid_24h & ask_24h - bid_24h <= MAX_SPREAD & mid_24h > 0 & mid_24h < 1]
m3[, move := lg(mid) - lg(mid_24h)]
res$B3 <- cbind(id = "B3", hypothesis = "the last day's move overreacts", side = "less", coef_test(y ~ offset(lg(mid)) + move, m3, "move"))
b3_groups <- m3[, cbind(id = "B3", group = .BY$group, coef_test(y ~ offset(lg(mid)) + move, .SD, "move")), by = group]
ok[, tercile := cut(rank(volume_48h, ties.method = "first") / .N, c(0, 1 / 3, 2 / 3, 1), labels = c("thin", "middle", "thick"))]
b5 <- ok[tercile %in% c("thin", "thick")][, thin := as.integer(tercile == "thin")]
res$B5 <- cbind(id = "B5", hypothesis = "thin markets are miscalibrated (slope differs, thin vs thick)", side = "two",
                coef_test(y ~ lg(mid) * thin, b5, "lg(mid):thin"))
b5_citl <- cbind(id = "B5", hypothesis = "thin markets: calibration-in-the-large differs", side = "two", coef_test(y ~ offset(lg(mid)) + thin, b5, "thin"))
b5_terciles <- ok[!is.na(tercile), cbind(fit_one(.SD, FALSE), volume_median = stats::median(.SD$volume_48h)), by = tercile]
cheap <- ok[mid < 0.2][, one := 1]
res$B6 <- cbind(id = "B6", hypothesis = "contracts under 20 cents: YES overpriced (seen)", side = "less",
                coef_test(y ~ 0 + one + offset(lg(mid)), cheap, "one"))
# B4: the price 24 h out, recalibrated on weeks 1-5 and scored on weeks 6-7 (and a taker at the 24 h bid and ask)
p24 <- copy(m3)[, `:=`(mid = mid_24h, bid = bid_24h, ask = ask_24h)]
b4 <- rbind(p24[, oos_one(.SD, 1:5, 6:7), by = group], cbind(group = "all", oos_one(p24, 1:5, 6:7)), fill = TRUE)
tab <- rbindlist(res, fill = TRUE)
tab[, p := fcase(side == "greater", p_greater, side == "less", p_less, default = p_two)]
b4_all <- b4[group == "all"]
tab <- rbind(tab, data.table(id = "B4", hypothesis = "a recalibration of the 24 h price beats it out of sample (two-sided)", side = "two",
                             n = b4_all$contracts, games = b4_all$games, estimate = b4_all$skill, p = 2 * min(b4_all$p_game_t, 1 - b4_all$p_game_t)), fill = TRUE)
tab[, q_bh := stats::p.adjust(p, "BH")]
setorder(tab, id)
fwrite(signif_dt(tab), file.path(out, "behaviour_tests.csv"))
fwrite(signif_dt(rbind(b3_groups, b5_citl, fill = TRUE)), file.path(out, "behaviour_details.csv"))
fwrite(signif_dt(b5_terciles), file.path(out, "behaviour_volume_terciles.csv"))
fwrite(signif_dt(b4), file.path(out, "behaviour_b4_oos.csv"))
options(width = 220)
print(tab[, .(id, hypothesis, n, games, flagged, estimate = signif(estimate, 3), lo = signif(lo, 3), hi = signif(hi, 3), p = signif(p, 2), q_bh = signif(q_bh, 2))])
cat("\nB3 by group:\n"); print(signif_dt(b3_groups[, .(group, n, games, estimate, lo, hi, p_less)], 3))
cat("\nB5 terciles:\n"); print(signif_dt(b5_terciles[, .(tercile, contracts, volume_median, slope, slope_lo, slope_hi, citl, brier)], 3))
cat("\nB4 (24 h price, weeks 1-5 -> 6-7):\n"); print(signif_dt(b4[, .(group, contracts, games, skill, p_game_t, bets, roi, roi_lo, roi_hi)], 3))
cat(sprintf("\nplayer contracts at the close: %d; teammates of an absent player: %d (refined: %d, from %d absences; snap-count: %d, from %d absences); Questionable who played: %d\n",
            nrow(okp), sum(okp$teammate_absent), sum(okp$teammate_absent_refined), nrow(gone), sum(okp$teammate_absent_snaps), nrow(gone_s),
            sum(okp$questionable_played)))
