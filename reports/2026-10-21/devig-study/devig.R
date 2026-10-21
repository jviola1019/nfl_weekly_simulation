# =============================================================================
# M3: devig comparison, as pre-registered in PROTOCOL.md (committed c393d5d before this ran)
#   Rscript --vanilla reports/2026-10-21/devig-study/devig.R <repo root>
# Reads only backtest/data/games.csv (frozen nflverse inputs), seasons 2006-2022. No network.
# =============================================================================
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1]] else "."
suppressPackageStartupMessages(library(data.table))
source(file.path(root, "backtest", "common.R"))
source(file.path(root, "backtest", "metrics.R"))

g <- data.table::fread(file.path(root, "backtest", "data", "games.csv"))
n_all <- nrow(g[season >= 2006 & season <= 2022])
g <- g[season >= 2006 & season <= 2022 & !is.na(home_moneyline) & !is.na(away_moneyline) &
         !is.na(home_score) & !is.na(away_score) & home_score != away_score]
stopifnot(nrow(g) > 0, max(g$season) <= 2022, !any(g$season >= 2023))

am <- function(x) ifelse(x < 0, -x / (-x + 100), 100 / (x + 100))
qh <- am(g$home_moneyline); qa <- am(g$away_moneyline); S <- qh + qa
sane <- is.finite(S) & S > 1 & S < 1.25
cat(sprintf("Games 2006-2022: %d; with both moneylines, decided: %d; overround outside (1, 1.25) dropped: %d\n",
            n_all, nrow(g), sum(!sane)))
g <- g[sane]; qh <- qh[sane]; qa <- qa[sane]; S <- S[sane]
y <- as.integer(g$home_score > g$away_score)
ord <- order(g$season, g$week, if ("gameday" %in% names(g)) g$gameday else g$game_id, g$game_id)
g <- g[ord]; qh <- qh[ord]; qa <- qa[ord]; S <- S[ord]; y <- y[ord]

solve_or_na <- function(f, lo, hi) tryCatch(stats::uniroot(f, c(lo, hi), tol = 1e-12)$root, error = function(e) NA_real_)
power_one <- function(a, b) { k <- solve_or_na(function(k) a^k + b^k - 1, 0.5, 5); a^k }
shin_one <- function(a, b) {
  s <- a + b
  pz <- function(q, z) (sqrt(z^2 + 4 * (1 - z) * q^2 / s) - z) / (2 * (1 - z))
  z <- solve_or_na(function(z) pz(a, z) + pz(b, z) - 1, 0, 0.5)
  pz(a, z)
}
or_one <- function(a, b) {
  f <- function(c) a / (c + a - c * a) + b / (c + b - c * b) - 1
  c <- solve_or_na(f, 0.5, 3)
  a / (c + a - c * a)
}
P <- list(
  proportional = qh / S,
  additive     = pmin(pmax(qh - (S - 1) / 2, 0.001), 0.999),
  power        = mapply(power_one, qh, qa),
  shin         = mapply(shin_one, qh, qa),
  odds_ratio   = mapply(or_one, qh, qa)
)
fails <- vapply(P, function(p) sum(!is.finite(p)), integer(1))
cat("Solver failures per method:", paste(names(fails), fails, sep = "=", collapse = ", "), "\n")
stopifnot(all(fails == 0))

wk <- as.integer(factor(paste(g$season, g$week)))
W <- max(wk)
C <- bt_boot_counts(W, BT_BOOT_B, seed = 20261021L)
n_w <- tabulate(wk, nbins = W)
boot_mean <- function(d) {
  s_w <- as.numeric(tapply(d, factor(wk, levels = seq_len(W)), sum)); s_w[is.na(s_w)] <- 0
  as.numeric(C %*% s_w) / as.numeric(C %*% n_w)
}

ll <- lapply(P, bt_logloss_vec, y = y)
br <- lapply(P, bt_brier_vec, y = y)
rows <- lapply(names(P), function(m) {
  cal <- bt_calibration(P[[m]], y)
  fav <- P[[m]] >= 0.75; dog <- P[[m]] <= 0.25
  data.frame(method = m, n = length(y),
             logloss = mean(ll[[m]]), brier = mean(br[[m]]),
             cal_slope = cal$slope, cal_intercept = cal$intercept,
             flb_fav = mean(y[fav] - P[[m]][fav]), flb_dog = mean(y[dog] - P[[m]][dog]))
})
summ <- do.call(rbind, rows)

alts <- setdiff(names(P), "proportional")
cmp <- do.call(rbind, lapply(alts, function(m) {
  d_ll <- ll[[m]] - ll$proportional
  d_br <- br[[m]] - br$proportional
  ci_ll <- bt_quantile_ci(boot_mean(d_ll)); ci_br <- bt_quantile_ci(boot_mean(d_br))
  dm <- bt_dm_hln(d_ll)
  data.frame(method = m, d_logloss = mean(d_ll), ll_lo = ci_ll[1], ll_hi = ci_ll[2],
             dm_p = dm$p_two_sided, d_brier = mean(d_br), br_lo = ci_br[1], br_hi = ci_br[2])
}))
cmp$holm_p <- stats::p.adjust(cmp$dm_p, method = "holm")
cmp$adopt <- cmp$d_logloss < 0 & cmp$holm_p < 0.05 & cmp$br_hi <= 0 & -cmp$d_logloss >= 0.0005

options(width = 200)
cat("\n== Accuracy and calibration by method ==\n"); print(summ, digits = 6, row.names = FALSE)
cat("\n== Paired against proportional (week-block bootstrap B = 10000, seed 20261021; DM-HLN; Holm) ==\n")
print(cmp, digits = 6, row.names = FALSE)
cat(sprintf("\nDecision (pre-registered): %s\n",
            if (any(cmp$adopt)) paste("adopt", paste(cmp$method[cmp$adopt], collapse = ", ")) else "keep proportional"))
