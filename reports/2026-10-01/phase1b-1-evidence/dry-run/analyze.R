# Compare dry-run engine outputs with the Plan 1b-1 predictions.
# Usage: Rscript analyze.R <pre-fix games_ready.rds> <worktree after Tasks 1-3> <worktree after Tasks 1-7>
# Each worktree must hold the run_logs/ written by `scripts/golden_master.R compare 15 2024 ...` there.
args <- commandArgs(trailingOnly = TRUE)
newest <- function(dir, pat) sort(list.files(file.path(dir, "run_logs"), pat, full.names = TRUE), decreasing = TRUE)[1]
base <- readRDS(args[[1]])
d3 <- args[[2]]; d7 <- args[[3]]
al <- function(g) g[match(base$game_id, g$game_id), ]
g3 <- al(readRDS(newest(d3, "^games_ready_"))); g7 <- al(readRDS(newest(d7, "^games_ready_")))
t3 <- readRDS(newest(d3, "^mu_terms_")); t7 <- readRDS(newest(d7, "^mu_terms_"))

cat("== Tasks 1-3 vs the pre-fix run (claim: means bit-identical) ==\n")
cat("mu_home identical:", identical(g3$mu_home, base$mu_home), "| mu_away identical:", identical(g3$mu_away, base$mu_away),
    "| max |d mu|:", signif(max(abs(c(g3$mu_home - base$mu_home, g3$mu_away - base$mu_away))), 3), "\n")
cat("sd_home identical:", identical(g3$sd_home, base$sd_home), "| max |d sd|:", signif(max(abs(c(g3$sd_home - base$sd_home, g3$sd_away - base$sd_away))), 3),
    "| rho max |d|:", signif(max(abs(g3$rho_game - base$rho_game)), 3), "\n")
sz <- sapply(names(t3$home)[-1], function(t) max(abs(c(t3$home[[t]], t3$away[[t]]))))
cat("mu_terms max |term| (Tasks 1-3):", paste(names(sz), round(sz, 2), sep = "=", collapse = " "), "\n")

cat("\n== Tasks 1-7 vs Tasks 1-3 ==\n")
dh <- g7$HFA_pts - g3$HFA_pts
cat(sprintf("HFA_pts change %.3f..%.3f | |change| > 0.05: %s\n", min(dh), max(dh),
            paste(sort(sub("^2024_15_[A-Z]+_", "", g7$game_id[abs(dh) > 0.05])), collapse = ", ")))
cat("mu_home - HFA change max |residual|:", signif(max(abs((g7$mu_home - g3$mu_home) - dh)), 3),
    "| mu_away identical:", identical(g7$mu_away, g3$mu_away), "\n")
cat(sprintf("sd_goal Tasks 1-7: %.2f..%.2f | sd_home change vs pre-fix %.2f..%.2f (up in %d) | sd_away change %.2f..%.2f (up in %d)\n",
            min(g7$sd_goal), max(g7$sd_goal), min(g7$sd_home - base$sd_home), max(g7$sd_home - base$sd_home), sum(g7$sd_home > base$sd_home),
            min(g7$sd_away - base$sd_away), max(g7$sd_away - base$sd_away), sum(g7$sd_away > base$sd_away)))
cat("total_mu == mu_home + mu_away (Tasks 1-7):", isTRUE(all.equal(g7$total_mu, g7$mu_home + g7$mu_away, tolerance = 0)), "\n")
cat("neutral_site in games_ready:", "neutral_site" %in% names(g7), "| any neutral:", any(g7$neutral_site), "\n")
r <- data.frame(game = sub("^2024_15_", "", t7$home$game_id), home_rest = t7$home$rest, away_rest = t7$away$rest)
cat("rest term (Tasks 1-7):\n"); print(r, row.names = FALSE)
cat("teams with -0.85 (short rest):", sum(c(r$home_rest, r$away_rest) == -0.85), "of 32\n")
