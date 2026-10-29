# Family H of PLAN.md: ESPN BET's 2023-2024 moneyline open and close (D1's archive) against the results.
# - H1 does the open-to-close move overreact (Moskowitz 2021)? y ~ offset(logit close) + (logit close - logit open),
#   clustered by season-week (H1: coefficient < 0).
# - H2 is the move predictable from the opener? A linear model of the move on the opener's logit, the home favourite
#   flag and the favourite's distance from 0.5, fit on 2023 and scored on 2024: the correlation of predicted and actual
#   moves (one-sided > 0), and the closing-line value of betting the predicted side at the open (in no-vig probability).
# Run from the repository root:  Rscript reports/2026-10-29/hypotheses/opening_lines.R <out_dir> <espn_game_odds.csv>
suppressPackageStartupMessages(library(data.table))
a <- commandArgs(trailingOnly = TRUE); out <- a[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
lg <- function(p) stats::qlogis(pmin(pmax(p, 0.005), 0.995))
od <- fread(a[2])
stopifnot(all(od$season %in% c(2023, 2024)))   # the archive's seasons; 2025 is never present
ml <- od[market_id == "moneyline" & venue_id == "espn_bet" & game_type == "REG"]
imp <- function(o) ifelse(o < 0, -o / (-o + 100), 100 / (o + 100))
w <- dcast(ml, game_id + season + week ~ snapshot_kind + side, value.var = "price_american", fun.aggregate = function(v) v[1])
w <- w[!is.na(open_home) & !is.na(open_away) & !is.na(close_home) & !is.na(close_away)]
w[, `:=`(p_open = imp(open_home) / (imp(open_home) + imp(open_away)), p_close = imp(close_home) / (imp(close_home) + imp(close_away)))]
g <- fread(file.path("backtest", "data", "games.csv"))[season %in% c(2023, 2024) & !is.na(home_score), .(game_id, home_score, away_score)]
w <- merge(w, g, by = "game_id")[home_score != away_score]
w[, `:=`(y = as.integer(home_score > away_score), move = lg(p_close) - lg(p_open), sw = paste(season, week),
         home_fav = as.integer(p_open > 0.5), fav_dist = abs(p_open - 0.5))]

h1m <- stats::glm(y ~ offset(lg(p_close)) + move, family = stats::quasibinomial(), data = w)
V1 <- sandwich::vcovCL(h1m, cluster = w$sw, type = "HC1"); G1 <- uniqueN(w$sw); b1 <- unname(stats::coef(h1m)["move"]); se1 <- sqrt(V1["move", "move"])
h1 <- data.table(id = "H1", test = "the open-to-close move overreacts (coefficient < 0)", games = nrow(w), clusters = G1, estimate = b1,
                 lo = b1 - stats::qt(0.975, G1 - 1) * se1, hi = b1 + stats::qt(0.975, G1 - 1) * se1, p = stats::pt(b1 / se1, G1 - 1),
                 moved = mean(abs(w$p_close - w$p_open) > 0), sd_move_bps = stats::sd(1e4 * (w$p_close - w$p_open)))
tr <- w[season == 2023]; te <- copy(w[season == 2024])
h2m <- stats::lm(move ~ lg(p_open) + home_fav + fav_dist, data = tr)
te[, pred := stats::predict(h2m, newdata = te)]
ct <- stats::cor.test(te$pred, te$move, alternative = "greater")
# CLV of the predicted side at the open: home if the predicted move is positive, away otherwise
te[, clv_bps := 1e4 * fifelse(pred > 0, p_close - p_open, p_open - p_close)]
cl <- te[, .(s = sum(clv_bps), n = .N), by = sw]
set.seed(20261029)
bt <- replicate(2000, { i <- sample.int(nrow(cl), replace = TRUE); sum(cl$s[i]) / sum(cl$n[i]) })
h2 <- data.table(id = "H2", test = "the move is predictable from the opener (fit 2023, score 2024)", games = nrow(te), clusters = nrow(cl),
                 estimate = unname(ct$estimate), p = ct$p.value, clv_bps = mean(te$clv_bps), clv_lo = stats::quantile(bt, 0.025), clv_hi = stats::quantile(bt, 0.975),
                 r2_train = summary(h2m)$r.squared)
res <- rbindlist(list(h1, h2), fill = TRUE)
res[, q_bh := stats::p.adjust(p, "BH")]
fwrite(res[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "opening_lines_tests.csv"))
options(width = 200)
print(res[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)])
print(summary(h2m)$coefficients)
