# Family T2 (PLAN.md, pre-registered in 90f47f6 before any of its numbers): does C2's lead at the opener replicate on
# SBR's opening point spreads, 2018-2021, seasons T1 never used? Picks follow v1's rule (C2 minus the opener's
# probability of at least 0.03 either way); a spread becomes a probability through the market's own exchange rate (an
# isotonic fit of the proportional no-vig closing moneyline on the closing spread, every nflverse game of 2006-2024 with
# both: prices only), applied to SBR's open and close alike. T2: the mean CLV of C2's picks, pooled, is above 0
# (one-sided, v1's season-week block bootstrap, B = 10,000, seed 20260929). Everything else is reported.
# The SBR pages are read from a private folder (sportsbookreviewsonline.com/scoresoddsarchives/nfl-odds-YYYY-YY/, fetched
# 2026-11-02) and are never committed; only aggregates are written. No 2025 data. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/opener_spread_clv.R <out_dir> --sbr=<folder with nfl-odds-2018-19.html ...>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE))
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
for (f in c("backtest/common.R", "backtest/metrics.R")) source(f)
SEED <- 20260929L; TAU <- 0.03; SEASONS <- 2018:2021
options(timeout = 600)

# --- SBR's games matched to nflverse's, and the market's spread-to-probability exchange rate (sbr_common.R) ----------------------
source(file.path("reports", "2026-10-29", "hypotheses", "sbr_common.R"))
sched <- sbr_schedules()
xr <- spread_exchange_rate(sched); p_of_spread <- xr$f; exr <- xr$rate   # home win probability for a home line (positive = home favoured)
sm <- sbr_matched(opt("sbr"), SEASONS, sched); mm <- sm$games
mm[, `:=`(p_open = p_of_spread(home_open), p_close = p_of_spread(home_close), p_close_nflverse = p_of_spread(spread_line))]

checks <- data.table(check = c("SBR games parsed, 2018-2021", "matched to nflverse games", "with an opening and a closing spread",
                               "SBR close within 0.5 points of nflverse's closing spread (share)",
                               "median |SBR close - nflverse close| (points)",
                               "SBR closing moneyline no-vig within 2 points of nflverse's (share)",
                               "exchange-rate lines (nflverse 2006-2024 games with a spread and both moneylines)"),
                     value = c(sm$parsed, nrow(mm), mm[is.finite(home_open) & is.finite(home_close), .N],
                               mm[is.finite(home_close) & is.finite(spread_line), mean(abs(home_close - spread_line) <= 0.5)],
                               mm[is.finite(home_close) & is.finite(spread_line), stats::median(abs(home_close - spread_line))],
                               mm[is.finite(sbr_p_close_ml) & is.finite(p_novig), mean(abs(sbr_p_close_ml - p_novig) <= 0.02)], xr$lines))

# --- v1's walk-forward predictions, and the starter caveat -------------------------------------------------------------------------
pr <- fread(file.path("reports", "2026-09-29", "backtest-games-v1", "predictions.csv"))[candidate %in% c("C1", "C2") & season %in% SEASONS]
pw <- dcast(pr, game_id ~ candidate, value.var = "p"); setnames(pw, c("C1", "C2"), c("p_c1", "p_c2"))
gm <- fread(file.path("backtest", "data", "games.csv"))[, .(game_id, home_team, away_team, home_qb_id, away_qb_id, kickoff_utc)]
tg <- rbind(gm[, .(game_id, team = home_team, qb = home_qb_id, kickoff_utc)], gm[, .(game_id, team = away_team, qb = away_qb_id, kickoff_utc)])
setorder(tg, team, kickoff_utc); tg[, changed := qb != shift(qb), by = team]
ch <- tg[, .(starter_changed = any(changed %in% TRUE)), by = game_id]
d <- merge(merge(mm[is.finite(p_open) & is.finite(p_close)], pw, by = "game_id"), ch, by = "game_id", all.x = TRUE)
d[, wk := paste(season, sprintf("%02d", week))]

# --- CLV of a candidate's picks, with v1's season-week block bootstrap ----------------------------------------------------------------
clv_test <- function(x, col, close = "p_close", label) {
  edge <- x[[col]] - x$p_open
  side <- fifelse(edge >= TAU, "home", fifelse(edge <= -TAU, "away", NA_character_)); k <- !is.na(side)
  if (!any(k)) return(NULL)
  clv <- 10000 * fifelse(side[k] == "home", x[[close]][k] - x$p_open[k], x$p_open[k] - x[[close]][k])
  wk_f <- factor(x$wk[k]); counts <- bt_boot_counts(nlevels(wk_f), BT_BOOT_B, SEED); n_w <- tabulate(as.integer(wk_f), nlevels(wk_f))
  b <- drop(counts %*% as.numeric(tapply(clv, wk_f, sum))) / drop(counts %*% n_w)
  data.table(sample = label, candidate = sub("^p_", "", col), close = close, picks = sum(k), home_picks = sum(side[k] == "home"), mean_clv_bps = mean(clv),
             lo90 = stats::quantile(b, 0.05), lo95 = stats::quantile(b, 0.025), hi95 = stats::quantile(b, 0.975), p_one_sided = mean(b <= 0))
}
t2 <- clv_test(d, "p_c2", label = "2018-2021 pooled (T2)")
res <- rbindlist(c(list(t2, clv_test(d, "p_c1", label = "2018-2021 pooled"), clv_test(d, "p_c2", "p_close_nflverse", "2018-2021 pooled, to nflverse's close")),
                   lapply(SEASONS, function(s) clv_test(d[season == s], "p_c2", label = as.character(s))),
                   list(clv_test(d[starter_changed == FALSE], "p_c2", label = "same starters as last game"),
                        clv_test(d[starter_changed == TRUE], "p_c2", label = "a starter changed"))))
# the movement slope (logit close - logit open) on (logit C2 - logit open), clustered by season-week
lgt <- function(p) stats::qlogis(pmin(pmax(p, 0.005), 0.995))
mv <- d[, .(game_id, wk, move = lgt(p_close) - lgt(p_open), lean = lgt(p_c2) - lgt(p_open))]
mm_fit <- stats::lm(move ~ lean, data = mv); V <- sandwich::vcovCL(mm_fit, cluster = mv$wk, type = "HC1"); G <- uniqueN(mv$wk)
slope <- data.table(test = "movement slope: (logit close - logit open) on (logit C2 - logit open)", games = nrow(mv), clusters = G,
                    estimate = unname(stats::coef(mm_fit)["lean"]), se = sqrt(V["lean", "lean"]))
slope[, `:=`(lo = estimate - stats::qt(0.975, G - 1) * se, hi = estimate + stats::qt(0.975, G - 1) * se, p_one_sided = stats::pt(-estimate / se, G - 1))]
dr <- d[, .(edge = p_c2 - p_open, p_open, p_close)][abs(edge) >= TAU]
dr[, `:=`(band = cut(abs(edge), c(TAU, 0.05, 0.08, 1), right = FALSE, labels = c("3-5 points", "5-8 points", "8+ points")),
          clv = 10000 * fifelse(edge > 0, p_close - p_open, p_open - p_close))]
dose <- dr[, .(picks = .N, mean_clv_bps = mean(clv), se_bps = stats::sd(clv) / sqrt(.N)), by = band][order(band)]
moved <- d[, .(games = .N, share_line_moved = mean(home_open != home_close), mean_abs_move_points = mean(abs(home_close - home_open)))]

s4 <- function(x) x[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)]
fwrite(s4(res), file.path(out, "opener_spread_clv.csv")); fwrite(s4(slope), file.path(out, "opener_spread_clv_slope.csv"))
fwrite(s4(dose), file.path(out, "opener_spread_clv_by_edge.csv")); fwrite(s4(checks), file.path(out, "opener_spread_clv_checks.csv"))
fwrite(s4(moved), file.path(out, "opener_spread_clv_moves.csv"))
fwrite(s4(exr[games >= 30]), file.path(out, "opener_spread_exchange_rate.csv"))   # the spread-to-probability rate (prices only)
options(width = 220); print(checks); print(moved); print(s4(res)); print(s4(slope)); print(dose)
