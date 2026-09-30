#!/usr/bin/env Rscript
# =============================================================================
# Write the web bundle for a scored game backtest (spec §3, bundle kind "backtest").
#
#   Rscript scripts/write_backtest_bundle.R [result_dir] [out_root]
#
# Defaults: reports/2026-09-29/backtest-games-v1 -> bundles/. Everything comes from
# committed files: the scored run (metrics.json, controls.json, predictions.csv,
# run_meta.json), the eval window, the backtest inputs and docs/EVIDENCE_LEDGER.md.
# Per-pick CLV rows are recomputed with the protocol's rule and must reproduce the
# run's aggregate CLV exactly; any mismatch is a QA failure.
# =============================================================================

suppressPackageStartupMessages(library(data.table))
source("R/bundle_writer.R")
for (f in c("common.R", "candidates/market.R", "metrics.R")) sys.source(file.path("backtest", f), envir = globalenv())

BT_LABELS <- c(p_c0 = "C0", p_c1 = "C1", p_c2 = "C2", p_e1 = "E1", p_b1_c1 = "B1[C1]", p_b1_c2 = "B1[C2]",
               p_b1_e1 = "B1[E1]", p_b2_e1 = "B2[E1]", p_k_e1 = "K[E1]")

bb_teams <- function(path = file.path("data", "reference", "teams.csv")) {
  t <- fread(path)
  t[, .(team_id, full_name, division, tz)]
}

bb_games <- function(games, ids) {
  g <- games[game_id %in% ids]
  data.table(
    game_id = g$game_id, season = g$season, week = g$week,
    game_type = g$game_type, home_team_id = g$home_franchise, away_team_id = g$away_franchise,
    kickoff_utc = bw_utc(g$kickoff), roof = g$roof, neutral = g$neutral,
    home_score = as.integer(g$home_score), away_score = as.integer(g$away_score)
  )
}

bb_metrics <- function(scores, bt_run_id) {
  rows <- list()
  for (wn in names(scores)) for (ph in c("pooled", "REG", "POST")) {
    block <- scores[[wn]][[ph]]
    if (is.null(block)) next
    for (col in names(block)) {
      s <- block[[col]]
      rows[[length(rows) + 1]] <- data.table(
        bt_run_id = bt_run_id, split = wn, phase = ph, candidate = BT_LABELS[[col]], n = as.integer(s$n),
        brier = s$brier, logloss = s$logloss, accuracy = s$accuracy, ece = s$ece,
        slope = s$slope, slope_lo = s$slope_ci[[1]], slope_hi = s$slope_ci[[2]],
        skill = s$skill, skill_lo = s$skill_ci[[1]], skill_hi = s$skill_ci[[2]],
        dm_p_better_bh = if (is.null(s$dm_p_better_bh)) NA_real_ else s$dm_p_better_bh
      )
    }
  }
  rbindlist(rows)
}

# Ten equal-mass bins per window and candidate (the same binning as the ECE metric)
bb_calibration_bins <- function(pred, bt_run_id) {
  p <- pred[!is.na(y)]
  p[, bin := {
    r <- rank(p, ties.method = "first")
    as.integer(cut(r, breaks = 10L, labels = FALSE))
  }, by = .(window, candidate)]
  p[, .(bt_run_id = bt_run_id, p_mean = mean(p), y_mean = mean(y), n = .N), by = .(split = window, candidate, bin)][
    order(split, candidate, bin), .(bt_run_id, split, candidate, bin, p_mean, y_mean, n)]
}

bb_gates <- function(gates, bt_run_id) {
  rbindlist(lapply(names(gates), function(nm) {
    g <- gates[[nm]]
    data.table(bt_run_id = bt_run_id, candidate = nm, g1 = g$g1_skill_ci_above_zero, g2 = g$g2_dm_bh,
               g3 = g$g3_calibration, g4 = g$g4_controls, brier_status = g$brier_status,
               betting_value_status = g$betting_value_status)
  }))
}

# Per-pick CLV at the ESPN BET opener, recomputed with the protocol rule (PROTOCOL §9)
bb_clv_picks <- function(pred, games, espn, clv_meta, clv_agg, bt_run_id) {
  oc <- bt_market_open_close(espn)
  wide <- dcast(pred[window == "confirm"], game_id ~ candidate, value.var = "p")
  d <- merge(merge(wide, oc, by = "game_id"), games[, .(game_id, home_score, away_score)], by = "game_id")
  out <- list(); fails <- character()
  for (cand in setdiff(names(clv_agg), "meta")) {
    edge <- d[[cand]] - d$p_open
    side <- ifelse(edge >= clv_meta$tau, "home", ifelse(edge <= -clv_meta$tau, "away", NA_character_))
    x <- d[!is.na(side)]; side <- side[!is.na(side)]
    home <- side == "home"
    clv <- 10000 * ifelse(home, x$p_close_venue - x$p_open, x$p_open - x$p_close_venue)
    dec <- ifelse(home, bt_amer_to_dec(x$h_open), bt_amer_to_dec(x$a_open))
    win <- (home & x$home_score > x$away_score) | (!home & x$away_score > x$home_score)
    units <- ifelse(x$home_score == x$away_score, 0, ifelse(win, dec - 1, -1))
    if (length(clv) != clv_agg[[cand]]$n || abs(mean(clv) - clv_agg[[cand]]$mean_clv_bps) > 1e-6 ||
        abs(mean(units) - clv_agg[[cand]]$roi) > 1e-9) {
      fails <- c(fails, sprintf("clv_picks: recomputed %s picks do not reproduce metrics.json", cand))
    }
    out[[cand]] <- data.table(bt_run_id = bt_run_id, candidate = cand, game_id = x$game_id, side = side,
                              clv_bps = clv, units = units)
  }
  list(rows = rbindlist(out), fails = fails)
}

bb_ledger <- function(path = file.path("docs", "EVIDENCE_LEDGER.md")) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  rows <- grep("^\\|\\s*[A-Z]", lines, value = TRUE)
  rows <- rows[!grepl("^\\|\\s*claim_id", rows)]
  cells <- lapply(strsplit(rows, "(?<!\\\\)\\|", perl = TRUE), function(x) trimws(gsub("\\|", "|", x[-1], fixed = TRUE)))
  data.table(
    claim_id = vapply(cells, `[`, "", 1), claim = vapply(cells, `[`, "", 2),
    status = vapply(cells, `[`, "", 4), reason = vapply(cells, `[`, "", 5), evidence_path = vapply(cells, `[`, "", 6)
  )
}

bb_main <- function(result_dir = file.path("reports", "2026-09-29", "backtest-games-v1"), out_root = "bundles") {
  metrics <- jsonlite::read_json(file.path(result_dir, "metrics.json"), simplifyVector = FALSE)
  controls <- jsonlite::read_json(file.path(result_dir, "controls.json"), simplifyVector = FALSE)
  run_meta <- jsonlite::read_json(file.path(result_dir, "run_meta.json"), simplifyVector = TRUE)
  win <- jsonlite::read_json(run_meta$window, simplifyVector = FALSE)
  inputs <- bt_load_inputs(win$data_dir, lapply(win$data_sha256, identity))
  pred <- fread(file.path(result_dir, "predictions.csv"))
  bt_run_id <- sprintf("%s:%s", win$protocol_id, substr(run_meta$result_sha256, 1, 12))

  games <- inputs$games
  clv <- bb_clv_picks(pred, games, inputs$espn_open_close, metrics$clv$meta, metrics$clv, bt_run_id)
  tables <- list(
    teams = bb_teams(),
    games = bb_games(games, unique(pred$game_id)),
    eval_windows = data.table(window_id = win$protocol_id, folds = list(win$windows), protocol_sha256 = win$protocol_sha256,
                              frozen_at_utc = bw_utc(as.POSIXct(run_meta$protocol_committed_at, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"))),
    backtest_runs = data.table(bt_run_id = bt_run_id, window_id = win$protocol_id, status = controls$run_status,
                               result_sha256 = run_meta$result_sha256, code_git_sha = run_meta$code_git_sha,
                               generated_utc = run_meta$generated_utc, controls = list(controls),
                               clv_summary = list(metrics$clv)),
    backtest_metrics = bb_metrics(metrics$scores, bt_run_id),
    calibration_bins = bb_calibration_bins(pred, bt_run_id),
    promotion_gates = bb_gates(metrics$gates, bt_run_id),
    clv_picks = clv$rows,
    evidence_ledger = bb_ledger()
  )
  git <- bw_git_state()
  meta <- list(
    cycle_id = sprintf("backtest-%s-%s", gsub("_", "-", win$protocol_id), substr(run_meta$result_sha256, 1, 8)),
    season = NULL, week = NULL, model_label = sprintf("%s model and blend shootout", win$protocol_id),
    data_asof_utc = bw_utc(max(games$kickoff) + BT_GAME_DURATION_SEC),
    code_git_sha = git$code_git_sha, code_dirty = git$code_dirty,
    config = list(protocol_id = win$protocol_id, protocol_sha256 = win$protocol_sha256,
                  result_sha256 = run_meta$result_sha256, result_code_git_sha = run_meta$code_git_sha,
                  holdout_sealed = isTRUE(win$windows$holdout$sealed)),
    seed = as.integer(win$bootstrap_seed), n_sims = NULL
  )
  m <- bw_write_bundle(out_root, "backtest", meta, tables, extra_qa_failures = clv$fails)
  cat(sprintf("bundle %s -> %s (qa ok: %s)\n", m$bundle_sha256, m$dir, m$qa$ok))
  if (!isTRUE(m$qa$ok)) cat(paste(" -", unlist(m$qa$failures)), sep = "\n")
  invisible(m)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  do.call(bb_main, as.list(a))
}
