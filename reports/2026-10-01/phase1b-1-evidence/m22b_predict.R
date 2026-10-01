# Evidence for Plan 1b-1 Task 4 (audit M22b): predicted change in score SDs when the
# total-based SD blend uses the simulated means instead of the legacy chain's total_mu.
# Usage: Rscript m22b_predict.R [games_ready.rds]   (default: newest run_logs/games_ready_*.rds)
args <- commandArgs(trailingOnly = TRUE)
path <- if (length(args)) args[[1]] else sort(list.files("run_logs", "^games_ready_.*rds$", full.names = TRUE), decreasing = TRUE)[1]
g <- readRDS(path)
curve <- function(t) pmin(pmax(12 + 0.195 * (t - 38), 9.5), 17)   # sd_total_curve, NFLsimulation.R:5070-5074
goal_old <- curve(g$total_mu)
# Invert today's blend (valid where the 5.0 floor did not bind):
#   sd = pmax(pmax(0.6 * fit + 0.4 * goal / sqrt(2), 5) + sd_adj, 5)   (NFLsimulation.R:5076-5083, :6121-6122)
fit_h <- (g$sd_home - g$sd_home_adj - 0.4 * goal_old / sqrt(2)) / 0.6
fit_a <- (g$sd_away - g$sd_away_adj - 0.4 * goal_old / sqrt(2)) / 0.6
floor_bound <- (0.6 * fit_h + 0.4 * goal_old / sqrt(2)) < 5 | (0.6 * fit_a + 0.4 * goal_old / sqrt(2)) < 5
goal_new <- curve(g$mu_home + g$mu_away)
sd_h_new <- pmax(pmax(0.6 * fit_h + 0.4 * goal_new / sqrt(2), 5) + g$sd_home_adj, 5)
sd_a_new <- pmax(pmax(0.6 * fit_a + 0.4 * goal_new / sqrt(2), 5) + g$sd_away_adj, 5)
dh <- sd_h_new - g$sd_home; da <- sd_a_new - g$sd_away
cat("file:", path, "| games where the 5.0 floor bound (inversion unreliable):", sum(floor_bound), "\n")
cat(sprintf("sd_goal: today %.2f..%.2f -> predicted %.2f..%.2f\n", min(goal_old), max(goal_old), min(goal_new), max(goal_new)))
cat(sprintf("sd_home change %.2f..%.2f (up in %d games) | sd_away change %.2f..%.2f (up in %d games)\n",
            min(dh), max(dh), sum(dh > 0), min(da), max(da), sum(da > 0)))
i <- which.max(abs(dh) + abs(da))
cat(sprintf("largest change: %s (legacy total %.1f, simulated total %.1f)\n", g$game_id[i], g$total_mu[i], g$mu_home[i] + g$mu_away[i]))
