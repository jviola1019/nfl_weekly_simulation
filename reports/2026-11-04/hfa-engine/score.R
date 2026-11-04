# Score the engine's calibration simulations (2019-2023, from a 2024 week 15 run) under each home-field estimator:
# Brier and log loss of p_home_2w_sim against results, paired differences with a week-block bootstrap, and the
# no-vig close for reference. Usage: Rscript hfa_engine_score.R <repo> <home_league> <home_strength_free> <home_team_margin>
suppressPackageStartupMessages(library(data.table))
a <- commandArgs(trailingOnly = TRUE)
repo <- a[1]; homes <- setNames(a[2:4], c("league", "strength_free", "team_margin"))
for (f in c("common.R", "metrics.R")) source(file.path(repo, "backtest", f))
read_cache <- function(h) {
  f <- list.files(file.path(h, ".cache", "nfl_sim_calib_cache"), pattern = "\\.rds$", full.names = TRUE)
  stopifnot(length(f) == 1L)
  as.data.table(readRDS(f))[, .(game_id, season, week, p = p_home_2w_sim, y = y_home)]
}
runs <- lapply(homes, read_cache)
d <- Reduce(function(x, y) merge(x, y, by = c("game_id", "season", "week", "y")),
            lapply(names(runs), function(n) setnames(copy(runs[[n]]), "p", n)))
games <- bt_prepare_games(fread(file.path(repo, "backtest", "data", "games.csv"), na.strings = c("", "NA"),
                                colClasses = list(character = c("home_qb_id", "away_qb_id", "gametime")))[season %in% 2019:2023])
d <- merge(d, games[, .(game_id, p_c0, wk)], by = "game_id")[!is.na(y) & is.finite(p_c0)]
cat(sprintf("%d games (2019-2023) with a result and a no-vig close\n", nrow(d)))
for (cc in c("league", "strength_free", "team_margin", "p_c0"))
  cat(sprintf("%-14s Brier %.5f  log loss %.5f\n", cc, mean(bt_brier_vec(d[[cc]], d$y)), mean(bt_logloss_vec(d[[cc]], d$y))))
wk_f <- factor(d$wk); cnt <- bt_boot_counts(nlevels(wk_f), 10000L, 20261104L); nw <- tabulate(as.integer(wk_f), nlevels(wk_f))
pair <- function(x, y) {
  v <- bt_brier_vec(d[[x]], d$y) - bt_brier_vec(d[[y]], d$y)
  b <- drop(cnt %*% as.numeric(tapply(v, wk_f, sum))) / drop(cnt %*% nw)
  ci <- bt_quantile_ci(b)
  cat(sprintf("%-28s Brier difference %+.5f  (%+.5f to %+.5f)\n", paste(x, "-", y), mean(v), ci[1], ci[2]))
}
pair("league", "team_margin"); pair("strength_free", "team_margin"); pair("league", "strength_free")
