# Do late schedule changes carry news the opener lacked? Opener-to-close movement for changed games
# against the rest, 2023-2024, from the D1 archive (ESPN BET openers and closes).
#   Rscript late-movement.R <espn_game_odds.csv> <flex-games.csv> <out.csv>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
a <- fread(args[1]); lc <- fread(args[2])[kind != "network only" & season %in% 2023:2024]
imp <- function(x) ifelse(x < 0, -x / (-x + 100), 100 / (x + 100))
ml <- a[market_id == "moneyline" & is.finite(price_american)]
ml <- dcast(ml, game_id + snapshot_kind ~ side, value.var = "price_american", fun.aggregate = function(v) v[1])
ml <- ml[is.finite(home) & is.finite(away)]
ml[, p_home := imp(home) / (imp(home) + imp(away))]
mv <- dcast(ml, game_id ~ snapshot_kind, value.var = "p_home")[is.finite(open) & is.finite(close)]
mv[, move_logit := abs(qlogis(close) - qlogis(open))]
sp <- a[market_id == "spread" & side == "home" & is.finite(line)]
sp <- dcast(sp, game_id ~ snapshot_kind, value.var = "line", fun.aggregate = function(v) v[1])[is.finite(open) & is.finite(close)]
sp[, move_points := abs(close - open)]
d <- merge(mv[, .(game_id, move_logit)], sp[, .(game_id, move_points)], by = "game_id", all = TRUE)
d[, changed := game_id %in% lc$game_id]
d[, late := game_id %in% lc[kind %in% c("date", "venue") | week >= 17L, game_id]]
perm_p <- function(v, g, R = 20000L) {           # difference in means, permutation reference
  v <- v[is.finite(v)]; g <- g[seq_along(v)]
  obs <- mean(v[g]) - mean(v[!g]); set.seed(20261028L)
  sims <- replicate(R, { s <- sample(g); mean(v[s]) - mean(v[!s]) })
  c(diff = obs, p = (1 + sum(abs(sims) >= abs(obs))) / (R + 1))
}
res <- rbindlist(lapply(c("changed", "late"), function(ind) rbindlist(lapply(c("move_logit", "move_points"), function(m) {
  ok <- is.finite(d[[m]]); v <- d[[m]][ok]; g <- d[[ind]][ok]
  pp <- perm_p(v, g)
  data.table(indicator = ind, measure = m, n_flag = sum(g), n_other = sum(!g), mean_flag = mean(v[g]), mean_other = mean(v[!g]),
             median_flag = stats::median(v[g]), median_other = stats::median(v[!g]), diff = pp[["diff"]], perm_p = pp[["p"]],
             wilcox_p = suppressWarnings(stats::wilcox.test(v[g], v[!g])$p.value))
}))))
fwrite(res, args[3]); print(res[, lapply(.SD, function(x) if (is.numeric(x)) signif(x, 3) else x)])
