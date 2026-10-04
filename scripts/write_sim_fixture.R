#!/usr/bin/env Rscript
# =============================================================================
# Web test fixture: a simulator bundle, contracts/fixtures/bundles/weekly-sim-2024-w15
#
#   Rscript scripts/write_sim_fixture.R [out_root]   (default contracts/fixtures/bundles)
#
# NOT model output. Three 2024 week-15 games from the committed backtest inputs
# (backtest/data/games.csv) get synthetic score draws: negative-binomial quantiles at
# fixed means, paired by a fixed permutation, so the fixture is the same on every OS
# and needs no RNG or network. BUF @ DET loses its market the way NFLsimulation.R
# flags a missing line (market_available = FALSE with the model probability left in
# home_p_2w_mkt), so the web tests cover the no-market path (audit M11).
# Written by the production builder (R/sim_bundle.R); test-sim-bundle.R checks that
# the committed tables equal what this script writes. Exit 1 when QA fails.
# =============================================================================

source("R/bundle_writer.R")
source("R/sim_bundle.R")

SF_CYCLE <- "weekly-sim-2024-w15"
SF_NOW <- as.POSIXct("2026-10-03 12:00:00", tz = "UTC")
SF_N <- 20000L
SF_SIZE <- 6
# synthetic expected points (home, away), not estimates
SF_MEANS <- list("2024_15_LA_SF" = c(23, 21), "2024_15_BAL_NYG" = c(16, 27), "2024_15_BUF_DET" = c(28, 26))
SF_NO_MARKET <- "2024_15_BUF_DET"
SF_MARKET_WEIGHT <- 0.7   # synthetic blend: 70% market

sf_draws <- function(mu_home, mu_away) {
  u <- stats::ppoints(SF_N)
  home <- stats::qnbinom(u, size = SF_SIZE, mu = mu_home)
  # 7919 is prime and coprime with SF_N, so this is a permutation of 1..SF_N
  away <- stats::qnbinom(u, size = SF_SIZE, mu = mu_away)[(seq_len(SF_N) * 7919L) %% SF_N + 1L]
  list(home = home, away = away, total = home + away, margin = home - away, n_trials = SF_N)
}

sf_novig_home <- function(home_ml, away_ml) {
  q <- function(ml) ifelse(ml < 0, -ml / (-ml + 100), 100 / (ml + 100))
  q(home_ml) / (q(home_ml) + q(away_ml))
}

sf_inputs <- function(games_csv = file.path("backtest", "data", "games.csv")) {
  ids <- names(SF_MEANS)
  all_games <- utils::read.csv(games_csv, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  schedule <- all_games[match(ids, all_games$game_id), ]
  sims <- lapply(SF_MEANS, function(m) sf_draws(m[1], m[2]))
  final <- do.call(rbind, lapply(ids, function(id) {
    s <- schedule[schedule$game_id == id, ]
    d <- sims[[id]]
    p_model <- sum(d$margin > 0) / sum(d$margin != 0)
    p_mkt <- sf_novig_home(s$home_moneyline, s$away_moneyline)
    has_mkt <- id != SF_NO_MARKET
    data.frame(game_id = id, season = s$season, week = s$week, home_team = s$home_team, away_team = s$away_team,
               home_p_2w_model = p_model,
               home_p_2w_blend = if (has_mkt) (1 - SF_MARKET_WEIGHT) * p_model + SF_MARKET_WEIGHT * p_mkt else p_model,
               home_p_2w_mkt = if (has_mkt) p_mkt else p_model,
               market_available = has_mkt,
               margin_median = stats::median(d$margin), total_median = stats::median(d$total),
               stringsAsFactors = FALSE)
  }))
  quality <- list(injury = list(status = "full", missing_seasons = character()),
                  weather = list(status = "partial_fallback", fallback_games = "2024_15_BAL_NYG"),
                  market = list(status = "partial", missing_games = SF_NO_MARKET),
                  calibration = list(method = "none", leakage_free = FALSE))
  list(final = final, sims = sims, schedule = schedule, quality = quality)
}

sf_write <- function(out_root = file.path("contracts", "fixtures", "bundles")) {
  i <- sf_inputs()
  write_sim_bundle(i$final, i$sims, i$schedule, i$quality, season = 2024L, week = 15L, seed = NULL,
                   n_sims = SF_N, out_root = out_root, now = SF_NOW, cycle_id = SF_CYCLE)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  m <- sf_write(if (length(a)) a[[1]] else file.path("contracts", "fixtures", "bundles"))
  cat(sprintf("fixture %s -> %s (qa ok: %s)\n", substr(m$bundle_sha256, 1, 12), m$dir, m$qa$ok))
  if (!isTRUE(m$qa$ok)) {
    cat(paste(" -", unlist(m$qa$failures)), sep = "\n")
    quit(status = 1)
  }
}
