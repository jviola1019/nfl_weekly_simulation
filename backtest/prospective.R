#!/usr/bin/env Rscript
# =============================================================================
# Prospective weekly bundle from the nfl_games_v1 candidates.
#
#   Rscript backtest/prospective.R <raw_dir> [out_root] [season week]
#
# <raw_dir> holds the current nflverse games.csv and play_by_play_<season>.rds
# (2006 onward). The candidates use the hyperparameters nfl_games_v1 selected on
# its Tune window (metrics.json) and are refit on every completed game before the
# target week's first kickoff. Only games that have NOT been played are predicted:
# no prediction for any past game (the 2025 holdout included) is computed for output,
# so nothing here scores or reveals the sealed holdout.
#
# B1[E1] and K[E1] are fit on nfl_games_v1's own out-of-fold E1 predictions
# (2018-2024), the same training data the protocol used.
#
# Market input: the nflverse consensus moneyline (no timestamp or book), devigged.
# Every candidate is "not better than market" (RESULT.md), so the bundle labels them
# unvalidated and the recommendations are paper-only leans with zero stake.
# =============================================================================

suppressPackageStartupMessages(library(data.table))
source("R/bundle_writer.R")
for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R", "blends.R", "calibrators.R")) {
  sys.source(file.path("backtest", f), envir = globalenv())
}
# builders only (build_inputs.R runs nothing when sourced)
sys.source(file.path("backtest", "build_inputs.R"), envir = globalenv())

PR_RESULT_DIR <- file.path("reports", "2026-09-29", "backtest-games-v1")
PR_PAPER_EDGE <- 0.03   # the protocol's decision-time threshold (PROTOCOL.md §9)

pr_games <- function(raw_games) {
  g <- fread(raw_games, na.strings = c("", "NA"))
  g[, kickoff_utc := bt_kickoff_utc(gameday, gametime)]
  g[, `:=`(home_franchise = bt_franchise(home_team), away_franchise = bt_franchise(away_team))]
  keep <- c("game_id", "season", "game_type", "week", "gameday", "gametime", "kickoff_utc",
            "home_team", "away_team", "home_franchise", "away_franchise", "home_score", "away_score",
            "location", "home_rest", "away_rest", "home_moneyline", "away_moneyline", "spread_line",
            "div_game", "roof", "home_qb_id", "away_qb_id")
  bt_prepare_games(g[, ..keep][, home_qb_id := as.character(home_qb_id)][, away_qb_id := as.character(away_qb_id)])
}

pr_pbp_inputs <- function(raw_dir, seasons) {
  tgs <- list(); qbs <- list()
  for (s in seasons) {
    f <- file.path(raw_dir, sprintf("play_by_play_%d.rds", s))
    if (!file.exists(f)) stop("prospective: missing ", f)
    parts <- bt_team_games_one_season(readRDS(f))
    tgs[[length(tgs) + 1]] <- parts$team_games; qbs[[length(qbs) + 1]] <- parts$qb_games
  }
  tg <- rbindlist(tgs); qb <- rbindlist(qbs)
  tg[, `:=`(team = bt_franchise(team), opp = bt_franchise(opp))]
  qb[, team := bt_franchise(team)]
  list(team_games = tg, qb_games = qb)
}

#' Predict the target week's unplayed games with every v1 candidate
pr_predict <- function(games, team_games, qb_games, sel, oof, target_season, target_week) {
  target <- games[season == target_season & week == target_week & !played]
  if (!nrow(target)) stop(sprintf("prospective: no unplayed games in %d week %d", target_season, target_week))
  cutoff <- min(target$kickoff)
  stopifnot(all(target$season >= 2026L))   # never predict a past season (2025 holdout sealed)

  elo <- bt_elo_run(games[kickoff < cutoff | game_id %in% target$game_id], sel$c1$K, sel$c1$hfa, sel$c1$regress)
  feats <- bt_epa_features(games, team_games, qb_games, sel$c2$halflife, seq(BT_EPA_FIRST_TRAIN_SEASON, target_season))
  d <- merge(feats, games[, .(game_id, y)], by = "game_id")
  train <- d[kickoff < cutoff & season >= BT_EPA_FIRST_TRAIN_SEASON & !is.na(y)]
  tgt <- d[game_id %in% target$game_id]
  stopifnot(max(train$kickoff) < cutoff)
  c2 <- data.table(game_id = tgt$game_id, p_c2 = bt_epa_fit_predict(train, tgt, sel$c2$lambda))

  out <- merge(merge(target[, .(game_id, p_c0)], elo, by = "game_id"), c2, by = "game_id")
  out[, p_e1 := bt_e1(p_c1, p_c2)]

  # B1[E1] and K[E1] from v1's out-of-fold E1 (2018-2024)
  tr <- oof[!is.na(y) & is.finite(p_c0) & is.finite(p_e1)]
  X <- cbind(int = 1, mkt = bt_logit(bt_clip(tr$p_c0)), model = bt_logit(bt_clip(tr$p_e1)))
  beta <- bt_ridge_logistic(X, tr$y, sel$b1$e1, unpenalized = 1L)
  Xt <- cbind(1, bt_logit(bt_clip(out$p_c0)), bt_logit(bt_clip(out$p_e1)))
  out[, p_b1_e1 := drop(bt_expit(Xt %*% beta))]
  out[, p_b2_e1 := bt_b2(p_e1, p_c0, sel$b2_e1$w)]
  kf <- bt_calib_fit(tr$p_e1, tr$y, sel$k_e1$method)
  out[, p_k_e1 := kf(p_e1)]
  attr(out, "b1_beta") <- beta
  out[]
}

pr_main <- function(raw_dir, out_root = "bundles", target_season = NA, target_week = NA) {
  metrics <- jsonlite::read_json(file.path(PR_RESULT_DIR, "metrics.json"), simplifyVector = TRUE)
  run_meta <- jsonlite::read_json(file.path(PR_RESULT_DIR, "run_meta.json"), simplifyVector = TRUE)
  sel <- metrics$selections
  games <- pr_games(file.path(raw_dir, "games.csv"))
  if (is.na(target_season)) {
    nxt <- games[!played & kickoff > Sys.time()][order(kickoff)][1]
    target_season <- nxt$season; target_week <- nxt$week
  }
  target_season <- as.integer(target_season); target_week <- as.integer(target_week)
  pbp <- pr_pbp_inputs(raw_dir, BT_MIN_PBP_SEASON:target_season)

  pv <- fread(file.path(PR_RESULT_DIR, "predictions.csv"))
  oof <- dcast(pv, game_id + y ~ candidate, value.var = "p")[, .(game_id, y, p_c0 = C0, p_e1 = E1)]

  pred <- pr_predict(games, pbp$team_games, pbp$qb_games, sel, oof, target_season, target_week)
  target <- games[game_id %in% pred$game_id]

  labels <- c(p_c0 = "C0", p_c1 = "C1", p_c2 = "C2", p_e1 = "E1", p_b1_e1 = "B1[E1]", p_b2_e1 = "B2[E1]", p_k_e1 = "K[E1]")
  gp <- rbindlist(lapply(names(labels), function(col) {
    data.table(game_id = pred$game_id, candidate = labels[[col]], p_home_raw = pred[[col]],
               p_home_final = pred[[col]], p_home_mkt_novig = pred$p_c0)
  }))

  # Paper-only leans for the prospective hypothesis (C2 vs the market, 3-point edge);
  # stake is always 0 because no candidate passed its gates.
  rec <- merge(pred[, .(game_id, p_c2, p_c0)],
               target[, .(game_id, home_moneyline, away_moneyline)], by = "game_id")
  rec[, edge_home := p_c2 - p_c0]
  rec[, side := fifelse(edge_home >= PR_PAPER_EDGE, "home", fifelse(edge_home <= -PR_PAPER_EDGE, "away", "none"))]
  rec[, p_side := fifelse(side == "away", 1 - p_c2, p_c2)]
  rec[, mkt_side := fifelse(side == "away", 1 - p_c0, p_c0)]
  rec[, price := fifelse(side == "away", away_moneyline, home_moneyline)]
  rec[, ev := fifelse(side == "none", NA_real_, p_side * (bt_amer_to_dec(price) - 1) - (1 - p_side))]
  recommendations <- rec[, .(
    rec_id = sprintf("%s:C2", game_id), game_id, candidate = "C2", side,
    price_american = fifelse(side == "none", NA_integer_, as.integer(price)),
    p_model = p_side, p_mkt_novig = mkt_side, ev, stake_pct = 0,
    tier = fifelse(side == "none", "pass", "lean"),
    pass_reason = fifelse(side == "none", "edge below 3 points",
                          "paper only: C2 is unvalidated (nfl_games_v1: not better than market)")
  )]

  now <- bw_utc()
  latest_played <- games[played == TRUE, max(kickoff)]
  source_status <- data.table(
    source = c("nflverse_schedules", "nflverse_pbp", "espn_core_odds", "kalshi_markets"),
    status = c("ok", "ok", "unavailable", "unavailable"),
    last_success_utc = c(now, bw_utc(latest_played + BT_GAME_DURATION_SEC), NA, NA),
    detail = c("consensus closing/current moneylines, no timestamp or book",
               sprintf("play-by-play through %s", format(latest_played, "%Y-%m-%d")),
               "not fetched by this run (forward capture archives raw snapshots separately)",
               "not fetched by this run (forward capture archives raw snapshots separately)")
  )
  teams <- fread(file.path("data", "reference", "teams.csv"))[, .(team_id, full_name, division, tz)]
  games_tbl <- data.table(
    game_id = target$game_id, season = target$season, week = target$week, game_type = target$game_type,
    home_team_id = target$home_franchise, away_team_id = target$away_franchise,
    kickoff_utc = bw_utc(target$kickoff), roof = target$roof, neutral = target$neutral,
    home_score = as.integer(target$home_score), away_score = as.integer(target$away_score)
  )
  git <- bw_git_state()
  meta <- list(
    cycle_id = sprintf("%d-w%02d-%s", target_season, target_week, format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")),
    season = target_season, week = target_week,
    model_label = "nfl_games_v1 candidates (prospective; unvalidated)",
    data_asof_utc = now, code_git_sha = git$code_git_sha, code_dirty = git$code_dirty,
    config = list(protocol_id = "nfl_games_v1", result_sha256 = run_meta$result_sha256,
                  selections = sel, paper_edge = PR_PAPER_EDGE,
                  b1_e1_coefficients = as.list(setNames(round(attr(pred, "b1_beta"), 6), c("intercept", "market", "model"))),
                  market_source = "nflverse consensus moneyline, proportional devig"),
    seed = NULL, n_sims = NULL
  )
  m <- bw_write_bundle(out_root, "weekly", meta,
                       list(teams = teams, games = games_tbl, game_predictions = gp,
                            recommendations = recommendations, source_status = source_status))
  cat(sprintf("bundle %s -> %s (qa ok: %s)\n", m$bundle_sha256, m$dir, m$qa$ok))
  if (!isTRUE(m$qa$ok)) cat(paste(" -", unlist(m$qa$failures)), sep = "\n")
  invisible(m)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (!length(a)) stop("usage: Rscript backtest/prospective.R <raw_dir> [out_root] [season week]")
  do.call(pr_main, as.list(a))
}
