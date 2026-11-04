# PLAN.md's planned comparison: does the engine's home-field estimator (F6: mean home margin shrunk n/(n+60)) cost
# accuracy against the strength-free team home field (F5) and the league home field (F4)? Paired by game on the
# scored window, with the gauntlet's week-block bootstrap (B = 10,000, seed 20261103).
suppressPackageStartupMessages(library(data.table))
for (f in c("common.R", "metrics.R")) source(file.path("backtest", f))
d <- fread(file.path("reports", "2026-11-03", "model-gauntlet", "out", "predictions_2018_2022.csv"))[!is.na(y)]
wk_f <- factor(d$wk); W <- nlevels(wk_f)
cnt <- bt_boot_counts(W, 10000L, 20261103L); nw <- tabulate(as.integer(wk_f), W)
pair <- function(a, b) {
  diff <- function(loss) { x <- loss(d[[a]], d$y) - loss(d[[b]], d$y); ws <- as.numeric(tapply(x, wk_f, sum))
    bt <- drop(cnt %*% ws) / drop(cnt %*% nw); c(mean(x), bt_quantile_ci(bt), mean(bt >= 0)) }
  br <- diff(bt_brier_vec); ll <- diff(bt_logloss_vec)
  data.table(comparison = sprintf("%s - %s", a, b), n = nrow(d), brier_diff = br[1], brier_lo = br[2], brier_hi = br[3],
             p_not_worse = br[4], logloss_diff = ll[1], logloss_lo = ll[2], logloss_hi = ll[3])
}
res <- rbind(pair("F6", "F5"), pair("F6", "F4"), pair("F5", "F4"))
res <- res[, lapply(.SD, function(x) if (is.numeric(x)) bt_round(x, 10) else x)]
bt_write_csv(res, file.path("reports", "2026-11-03", "model-gauntlet", "out", "home_field_compare.csv"))
print(res)
