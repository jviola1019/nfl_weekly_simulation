# Evidence for Plan 1b-1 (audit M22, M22b): what the simulated means are, and what the
# legacy adjustment chain computes but does not simulate.
# Usage: Rscript m22_terms.R [games_ready.rds]   (default: newest run_logs/games_ready_*.rds)
# A games_ready file is written by every NFLsimulation.R run (scripts/golden_master.R record).
args <- commandArgs(trailingOnly = TRUE)
path <- if (length(args)) args[[1]] else sort(list.files("run_logs", "^games_ready_.*rds$", full.names = TRUE), decreasing = TRUE)[1]
g <- readRDS(path)
cat("file:", path, "| games:", nrow(g), "| season", unique(g$season), "week", unique(g$week), "\n")

# 1. Simulated means vs the rescue formula (NFLsimulation.R:6271-6284)
base_h <- g$exp_drives_home * g$exp_ppd_home
base_a <- g$exp_drives_away * g$exp_ppd_away
cat("mu_home identical to drives x PPD + HFA_pts:", identical(g$mu_home, pmax(base_h + g$HFA_pts, 0)),
    "| mu_away identical to drives x PPD:", identical(g$mu_away, pmax(base_a + 0, 0)), "\n")
cat("home_to_adj non-finite:", sum(!is.finite(g$home_to_adj)), "of", nrow(g),
    "| away_to_adj non-finite:", sum(!is.finite(g$away_to_adj)), "of", nrow(g), "\n")

# 2. The legacy chain as named terms (same expressions as NFLsimulation.R:4497-4648, :4998-5053)
glmm_h <- g$glmm_w * (dplyr::coalesce(g$mu_home_glmm, g$mu_home_model) - g$mu_home_model)
glmm_a <- g$glmm_w * (dplyr::coalesce(g$mu_away_glmm, g$mu_away_model) - g$mu_away_model)
terms_h <- list(base = base_h, hfa = g$HFA_pts, glmm = glmm_h, qb = g$home_off_points_adj, rest = g$home_rest_points,
  injury = g$home_injury_off_total + g$away_injury_def_total, travel = dplyr::coalesce(g$travel_mu_adj_home, 0),
  div_conf = g$div_conf_adj, pressure = -0.6 * g$home_press_mismatch, explosive = 0.16 * 5 * g$expl_edge_home,
  location = 0.7 * g$home_location_boost, special_teams = 0.7 * g$st_impact_home,
  situational = 0.7 * (g$rz_impact_home + g$third_down_edge_home + g$to_edge_home + g$penalty_edge_home +
                       g$situational_home + g$momentum_home + g$div_adjustment_home))
terms_a <- list(base = base_a, hfa = rep(0, nrow(g)), glmm = glmm_a, qb = g$away_off_points_adj, rest = g$away_rest_points,
  injury = g$away_injury_off_total + g$home_injury_def_total, travel = dplyr::coalesce(g$travel_mu_adj_away, 0),
  div_conf = g$div_conf_adj, pressure = -0.6 * g$away_press_mismatch, explosive = 0.16 * 5 * g$expl_edge_away,
  location = 0.7 * g$away_location_penalty, special_teams = 0.7 * g$st_impact_away,
  situational = 0.7 * (g$rz_impact_away + g$third_down_edge_away + g$to_edge_away + g$penalty_edge_away +
                       g$situational_away + g$momentum_away + g$div_adjustment_away))
sum_h <- Reduce(`+`, terms_h); sum_a <- Reduce(`+`, terms_a)
cat("max |sum of terms - legacy total_mu| (before the turnover join):", signif(max(abs(sum_h + sum_a - g$total_mu)), 3),
    "| a side's unclamped legacy mean < 0 in", sum(sum_h < 0 | sum_a < 0), "games | min side mean", round(min(c(sum_h, sum_a)), 2), "\n")

# 3. Term sizes (points per side), and the legacy total that still drives SDs and rho (M22b)
sizes <- t(sapply(names(terms_h)[-1], function(t) { v <- c(terms_h[[t]], terms_a[[t]]); c(min = min(v), max = max(v), mean_abs = mean(abs(v))) }))
print(round(sizes, 2))
gap <- g$total_mu - (g$mu_home + g$mu_away)
cat("legacy total_mu - simulated total: max |gap|", round(max(abs(gap)), 1), "at", g$game_id[which.max(abs(gap))],
    sprintf("(%.1f vs %.1f)", g$total_mu[which.max(abs(gap))], (g$mu_home + g$mu_away)[which.max(abs(gap))]), "\n")
