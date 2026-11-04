# Why the engine's calibration simulations favour team_margin: their home edge, per estimator.
# Production gives the home team its full home field (HFA_pts = home_hfa); week_inputs_and_sim_2w
# gives the margin only (home_hfa - away_hfa)/2. This compares each run's simulated home margin
# with the results and the closing spread on the same 1,322 games (2019-2023).
# Usage: Rscript bias.R <repo> <home_league> <home_strength_free> <home_team_margin> <out.csv>
suppressPackageStartupMessages(library(data.table))
a <- commandArgs(trailingOnly = TRUE)
repo <- a[1]; homes <- setNames(a[2:4], c("league", "strength_free", "team_margin")); out_csv <- a[5]
games <- fread(file.path(repo, "backtest", "data", "games.csv"), na.strings = c("", "NA"),
               select = c("game_id", "home_score", "away_score", "spread_line"))
games[, margin := home_score - away_score]
rows <- lapply(names(homes), function(est) {
  f <- list.files(file.path(homes[[est]], ".cache", "nfl_sim_calib_cache"), pattern = "\\.rds$", full.names = TRUE)
  stopifnot(length(f) == 1L)
  d <- merge(as.data.table(readRDS(f))[, .(game_id, p = p_home_2w_sim, m = margin_mean_sim, y = y_home)],
             games, by = "game_id")[is.finite(margin) & is.finite(spread_line)]
  fit <- stats::lm(margin ~ m, data = d)
  data.table(estimator = est, games = nrow(d),
             sim_home_margin = mean(d$m), actual_home_margin = mean(d$margin),
             spread_home_margin = mean(d$spread_line),
             sim_home_win = mean(d$p), actual_home_win = mean(d$y),
             fit_intercept = unname(coef(fit)[1]), fit_slope = unname(coef(fit)[2]),
             cor_sim_actual = stats::cor(d$m, d$margin), cor_spread_actual = stats::cor(d$spread_line, d$margin))
})
out <- rbindlist(rows)
print(out[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 3) else x)])
fwrite(out, out_csv)
