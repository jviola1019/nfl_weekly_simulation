# Minimum detectable effect (MDE) of the opener-anchored LR screen, from real 2024 ESPN BET openers.
# For y ~ Bernoulli(p), logit(p) = logit(p_open) + b * z with z standardized (SD 1), the Fisher
# information for b at b = 0 is sum_i p_i (1 - p_i) z_i^2 ~ n * mean(p (1 - p)), so
#   SE(b) ~ 1 / sqrt(n * v),  v = mean(p_open (1 - p_open)),
#   MDE per SD (two-sided alpha, power 1 - beta) = (z_{1-alpha/2} + z_{1-beta}) * SE(b).
# BH across k features is approximated by Bonferroni alpha / k (conservative).
# Usage: Rscript --vanilla mde.R <repo root>
args <- commandArgs(trailingOnly = TRUE)
d <- utils::read.csv(file.path(args[[1]], "backtest", "data", "espn_open_close.csv"), colClasses = "character")
am <- function(x) { x <- as.numeric(x); ifelse(x < 0, -x / (-x + 100), 100 / (x + 100)) }
ph <- am(d$h_open); pa <- am(d$a_open)
p_open <- ph / (ph + pa)                      # proportional devig of the opener
p_open <- p_open[is.finite(p_open)]
v <- mean(p_open * (1 - p_open))
cat(sprintf("2024 ESPN BET openers: n = %d, mean p(1-p) = %.4f\n", length(p_open), v))
mde <- function(n, alpha, power = 0.8) (stats::qnorm(1 - alpha / 2) + stats::qnorm(power)) / sqrt(n * v)
for (n in c(205, 284, 489)) {
  cat(sprintf("n = %3d: MDE per SD (log-odds) single test %.3f | 36 features (Bonferroni) %.3f\n",
              n, mde(n, 0.05), mde(n, 0.05 / 36)))
}
# Translate a per-SD log-odds effect into probability points at p = 0.5 (dp/dlogit = 0.25)
cat(sprintf("At p = 0.5, 0.25 log-odds = %.1f probability points\n", 100 * (stats::plogis(0.25) - 0.5)))
