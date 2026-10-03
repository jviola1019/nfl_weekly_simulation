#!/usr/bin/env Rscript
# =============================================================================
# Blend research v3 runner (Tune window 2018-2022 only).
#
#   Rscript backtest/v3/sprint.R --out reports/2026-10-01/blend-research [--workers 8]
#
# inputs   v1 and v2 sha-locked inputs; every table is cut at 2022 right after
#          its sha256 check, before any feature or model sees it
# level0   the six v2 families walk-forward by week, 2014-2022, with the v2 code
#          unchanged (bt2_walk_models); their Tune predictions must equal v2's
#          committed tracking file
# new      meshes S1, S1_MIN, R1 (on level 0), O1 (online blend) and the families
#          G2, G2_GAPS, T1, N1, N1_NARROW (backtest/v3/meshes.R, families.R)
# score    every candidate, new and v2, against the no-vig close on the Tune
#          games; BH across all of them; probability quality (backtest/v3/score.R)
# control  shuffled labels: v2's permutation, every learner refit walk-forward
# --workers N runs the weekly fits in N local R processes. Each fit sets its own
# seed, so the outputs do not depend on N. Timings go to compute/seconds.csv and
# run_meta.json only; every other output is deterministic.
# TABLES.md is rendered from the CSVs by backtest/v3/report.R.
# =============================================================================

bt3_sprint_dir <- function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else file.path(getwd(), "backtest", "v3")
}

BT3_NEW <- c("S1", "S1_MIN", "R1", "O1", "G2", "G2_GAPS", "T1", "N1", "N1_NARROW")
BT3_KEEP_COLS <- function() unique(c("game_id", "season", "week", "wk", "kickoff", "y", "lp_c0", "p_c0", "p_c1", "p_c2", "p_e1",
                                    "home_franchise", "away_franchise", bt2_model_features(), BT3_G2_VARS))

#' Sha-checked v1 and v2 inputs, cut at the end of the Tune window on load
bt3_load_inputs <- function() {
  win <- jsonlite::read_json("backtest/eval_windows/nfl_games_v1.json", simplifyVector = TRUE)
  v1 <- bt_load_inputs(win$data_dir, win$data_sha256)
  v1$games <- v1$games[season <= BT2_MAX_SPRINT_SEASON]
  v1$team_games <- v1$team_games[game_id %in% v1$games$game_id]
  v1$qb_games <- v1$qb_games[game_id %in% v1$games$game_id]
  v1$espn_open_close <- NULL
  v2 <- bt2_load_v2_inputs()
  for (nm in names(v2)) if ("season" %in% names(v2[[nm]])) v2[[nm]] <- v2[[nm]][season <= BT2_MAX_SPRINT_SEASON]
  bt3_guard(v1$games$season, "v1 games")
  for (nm in names(v2)) if ("season" %in% names(v2[[nm]])) bt3_guard(v2[[nm]]$season, nm)
  list(v1 = v1, v2 = v2)
}

#' Run the new families on feature table `d` and level-0 table `L`
bt3_run_new <- function(d, L, weeks, cl, families = BT3_NEW) {
  tw <- weeks[season %in% BT2_TUNE_SEASONS]
  tune_ids <- d[season %in% BT2_TUNE_SEASONS, game_id]
  out <- list(pred = list(), diag = list(), seconds = c(), wall = c(), o1 = NULL, n1_params = list())
  for (f in families) {
    t0 <- Sys.time()
    if (f %in% BT3_MESHES) {
      r <- bt3_combine(bt3_map_weeks(tw, "bt3_walk_meta", family = f, L = L, cl = cl), d)
    } else if (f == "O1") {
      o <- bt3_run_o1(L, weeks)
      out$o1 <- o
      r <- list(pred = o$pred[game_id %in% tune_ids], diag = o$weights, seconds = o$seconds)
    } else {
      n1p <- NULL
      if (f %in% names(BT3_N1_GRIDS)) {
        fw <- tw[, .SD[which.min(cutoff)], by = season]
        n1p <- rbindlist(bt3_map_weeks(fw, "bt3_n1_params", d = d, decays = BT3_N1_GRIDS[[f]], cl = cl))
        n1p <- n1p[order(season, size, decay)]
        out$n1_params[[f]] <- n1p
      }
      r <- bt3_combine(bt3_map_weeks(tw, "bt3_walk_family", family = f, d = d, n1_params = n1p, cl = cl), d)
      if (!is.null(n1p)) r$seconds <- r$seconds + sum(unique(n1p[, .(season, seconds)])$seconds)
    }
    out$pred[[f]] <- r$pred
    out$diag[[f]] <- r$diag
    out$seconds[f] <- sum(r$seconds)
    out$wall[f] <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    cat(sprintf("  %-9s %5d Tune predictions, fit %.0f s, wall %.0f s\n", f, nrow(r$pred[game_id %in% tune_ids]),
                out$seconds[f], out$wall[f]))
  }
  out
}

BT3_LABELS <- c(
  S1 = "Stacked mesh: ridge meta-logistic on 7 level-0 logits, offset logit(close), lambda.1se",
  S1_MIN = "Stacked mesh, lambda.min (sensitivity)",
  R1 = "Residual mesh: xgboost boosting the anchored glmnet's out-of-fold logit",
  O1 = "Online convex blend (EWA) of 7 level-0 models + the close",
  G2 = "GAM, offset close: Elo/EPA gap smooths + 4 Tune-screened features",
  G2_GAPS = "GAM, offset close: Elo/EPA gap smooths only",
  T1 = "Team mixed model: glmer, offset close, home/away team intercepts, 3-season window",
  N1 = "nnet (size <= 3), skip weight on logit(close) fixed at 1, decay 1-10,000 by CV",
  N1_NARROW = "nnet as N1 with the development decay grid 1-100 (disclosed variant)")

#' One row per scored column: family, calibration, source, description
bt3_candidate_meta <- function(cols_v2, families) {
  v2 <- data.table(column = cols_v2)
  v2[, `:=`(candidate = sub("__.*$", "", sub("^p_", "", column)),
            calibration = fifelse(grepl("__", column), sub("^.*__", "", column), "none"), source = "v2 (committed)")]
  v2[, family := fcase(candidate == "c1", "C1", candidate == "c2", "C2", candidate == "e1", "E1", default = candidate)]
  v2[, description := fcase(family == "LR_E1", "Logistic stack: close + v1 ensemble (L1)",
                            family == "LR_C1C2", "Logistic stack: close + Elo + EPA",
                            family == "GLMNET", "Elastic net, market unpenalised (G1)",
                            family == "XGB", "xgboost anchored on the close (X1)",
                            family == "XGB_FREE", "xgboost without the market anchor",
                            family == "GBM", "gbm anchored on the close",
                            family == "C1", "Elo alone", family == "C2", "EPA GLM alone",
                            family == "E1", "v1 ensemble alone (Elo + EPA)", default = "")]
  nw <- data.table(column = paste0("p_", families), candidate = families, calibration = "none",
                   source = "v3 (new)", family = families, description = unname(BT3_LABELS[families]))
  rbind(v2[, .(column, candidate, family, calibration, source, description)],
        nw[, .(column, candidate, family, calibration, source, description)])
}

bt3_sprint_main <- function(out_dir, workers = 1L, families = BT3_NEW, control = TRUE) {
  t_all <- Sys.time()
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  inp <- bt3_load_inputs()
  base <- bt2_base_predictions(inp$v1)
  d_full <- bt2_build_features(base, inp$v2)
  bt3_guard(d_full$season, "feature table")
  weeks <- base$weeks
  d <- d_full[, BT3_KEEP_COLS(), with = FALSE]
  cat(sprintf("inputs: %d games %d-%d (max season loaded %d), %d weeks\n", nrow(d), min(d$season), max(d$season),
              max(d$season), nrow(weeks)))
  cl <- bt3_cluster(workers)
  if (!is.null(cl)) on.exit(parallel::stopCluster(cl), add = TRUE)

  # 1. level 0: the v2 families, unchanged code, must reproduce v2's committed Tune predictions
  lv <- bt3_level0(d, weeks, cl)
  v2w <- bt3_v2_tracking_wide()
  base_cols <- c("p_c1", "p_c2", "p_e1")
  chk <- bt3_check_level0(merge(lv$pred, d[, c("game_id", base_cols), with = FALSE], by = "game_id"), v2w,
                          c(paste0("p_", BT2_MODELS), base_cols))
  print(chk)
  if (any(chk$max_abs_diff_rounded > 1e-12) || any(chk$games != nrow(v2w))) {
    stop("level 0 does not reproduce v2's committed Tune predictions", call. = FALSE)
  }
  cat(sprintf("level 0: %d games 2014-2022 in %.0f s wall; reproduces v2 (max |diff| %.1e, %.1e after 8-decimal rounding)\n",
              nrow(lv$pred), lv$wall, max(chk$max_abs_diff), max(chk$max_abs_diff_rounded)))
  L <- merge(d, lv$pred, by = "game_id", all.x = TRUE)
  setorder(L, kickoff, game_id)

  # 2. new families
  cat("new families:\n")
  nw <- bt3_run_new(d, L, weeks, cl, families)

  # 3. score every candidate, new and v2, on the same Tune games; BH across all
  ev <- d[season %in% BT2_TUNE_SEASONS & !is.na(y) & is.finite(lp_c0), .(game_id, season, week, wk, kickoff, y, p_c0)]
  ev <- merge(ev, v2w, by = "game_id")
  for (f in families) {
    p <- nw$pred[[f]][, .(game_id, p)]
    setnames(p, "p", paste0("p_", f))
    ev <- merge(ev, p, by = "game_id", all.x = TRUE)
  }
  setorder(ev, kickoff, game_id)
  cols_v2 <- setdiff(names(v2w), "game_id")
  cols_new <- paste0("p_", families)
  miss <- vapply(c(cols_v2, cols_new), function(cc) sum(!is.finite(ev[[cc]])), integer(1))
  if (any(miss > 0)) stop("missing Tune predictions: ", paste(names(miss)[miss > 0], collapse = ", "), call. = FALSE)
  tab <- bt3_score_all(ev, c(cols_v2, cols_new))
  meta_c <- bt3_candidate_meta(cols_v2, families)
  tab <- merge(meta_c, tab, by = "column", all.y = TRUE)
  tab[column == "p_c0", `:=`(candidate = "C0", family = "C0", calibration = "none", source = "market",
                             description = "No-vig closing moneyline (reference)")]
  setorder(tab, -skill)
  bt2_write_csv(bt3_signif(tab), file.path(out_dir, "scores", "scores_tune.csv"))
  rel <- merge(bt3_reliability(ev, c("p_c0", cols_v2, cols_new)), tab[, .(column, candidate, calibration)], by = "column")
  rel <- rel[order(match(column, tab$column), bin), .(candidate, calibration, column, bin, n, mean_p, obs_rate, obs_lo, obs_hi)]
  bt2_write_csv(bt3_signif(rel), file.path(out_dir, "scores", "reliability_tune.csv"))
  # Brier skill by season (stability), uncalibrated columns only
  unc <- tab[calibration == "none", column]
  by_season <- rbindlist(lapply(BT2_TUNE_SEASONS, function(s) {
    e <- ev[season == s]
    b0 <- mean((e$p_c0 - e$y)^2)
    data.table(season = s, column = unc, n = nrow(e),
               skill = vapply(unc, function(cc) 1 - mean((e[[cc]] - e$y)^2) / b0, numeric(1)))
  }))
  by_season <- merge(by_season, tab[, .(column, candidate)], by = "column")[order(match(column, tab$column), season)]
  bt2_write_csv(bt3_signif(by_season[, .(candidate, column, season, n, skill)]), file.path(out_dir, "scores", "skill_by_season.csv"))
  # how much the level-0 models disagree with the close, and with each other (Tune)
  gap_cols <- c(paste0("p_", BT3_LEVEL0_LEARNERS), "p_c1", "p_c2", "p_e1")
  gaps <- as.matrix(ev[, lapply(.SD, function(p) bt_logit(bt_clip(p)) - bt_logit(bt_clip(ev$p_c0))), .SDcols = gap_cols])
  gc <- as.data.table(round(stats::cor(gaps), 4), keep.rownames = "column")
  bt2_write_csv(gc, file.path(out_dir, "meshes", "level0_gap_correlation_tune.csv"))

  # per-game tracking for the new candidates (v2's are in its own tracking file)
  long <- melt(ev[, c("game_id", "season", "week", "y", "p_c0", cols_new), with = FALSE],
               id.vars = c("game_id", "season", "week", "y", "p_c0"), variable.name = "column", value.name = "p_model")
  long[, `:=`(candidate = sub("^p_", "", column), brier = (p_model - y)^2, logloss = bt_logloss_vec(p_model, y),
              brier_market = (p_c0 - y)^2)]
  bt2_write_csv(long[, .(game_id, season, week, candidate, p_model = round(p_model, 8), p_market = round(p_c0, 8), outcome = y,
                         brier = round(brier, 8), logloss = round(logloss, 8), brier_market = round(brier_market, 8))],
                file.path(out_dir, "tracking", "moneyline_tune_v3.csv"))

  # level 0 and mesh/family diagnostics
  l0 <- merge(lv$pred, d[, .(game_id, season, week, p_c0, p_c1, p_c2, p_e1)], by = "game_id")[order(match(game_id, d$game_id))]
  pc <- grep("^p_", names(l0), value = TRUE)
  l0[, (pc) := lapply(.SD, round, 8), .SDcols = pc]
  bt2_write_csv(l0, file.path(out_dir, "level0", "level0_oof.csv"))
  bt2_write_csv(bt3_signif(chk, 4), file.path(out_dir, "level0", "check_vs_v2.csv"))
  bt2_write_csv(lv$rounds, file.path(out_dir, "level0", "boosting_rounds.csv"))
  for (f in families) if (!is.null(nw$diag[[f]]) && nrow(nw$diag[[f]])) {
    sub_dir <- if (f %in% c(BT3_MESHES, "O1")) "meshes" else "families"
    bt2_write_csv(bt3_signif(nw$diag[[f]]), file.path(out_dir, sub_dir, paste0(tolower(f), "_by_week.csv")))
  }
  if (!is.null(nw$o1)) bt2_write_csv(bt3_signif(nw$o1$grid), file.path(out_dir, "meshes", "o1_eta_grid.csv"))
  if (length(nw$n1_params)) {
    n1t <- rbindlist(lapply(names(nw$n1_params), function(v) nw$n1_params[[v]][, variant := v]))
    bt2_write_csv(bt3_signif(n1t[, .(variant, season, size, decay, cv_deviance = deviance, chosen)]),
                  file.path(out_dir, "families", "n1_tuning.csv"))
  }
  # compute (timings vary run to run, so they live outside the scored CSVs)
  compute <- rbind(data.table(family = names(lv$seconds), stage = "level0 (v2 code)", fit_seconds = unname(lv$seconds),
                              wall_seconds = NA_real_),
                   data.table(family = names(nw$seconds), stage = "v3 new", fit_seconds = unname(nw$seconds),
                              wall_seconds = unname(nw$wall[names(nw$seconds)])))

  meta <- list(generated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
               max_season_loaded = max(d$season), tune_seasons = BT2_TUNE_SEASONS,
               n_tune_scored = nrow(ev), n_candidates_bh = length(c(cols_v2, cols_new)),
               level0 = list(first_season = BT2_BLEND_FIRST_PRED_SEASON, games = nrow(lv$pred),
                             reproduces_v2_max_abs_diff = max(chk$max_abs_diff),
                             reproduces_v2_max_abs_diff_after_rounding = max(chk$max_abs_diff_rounded), wall_seconds = lv$wall,
                             fit_seconds = as.list(lv$seconds)),
               burn_in = list(meta_learners = "level-0 OOF predictions 2014-2017 (before Tune); no Tune week excluded; burn-in weeks not scored",
                              meta_min_train = BT3_META_MIN_TRAIN, meta_min_seasons = BT3_META_MIN_SEASONS),
               o1 = if (!is.null(nw$o1)) list(eta = nw$o1$eta, eta_grid = BT3_O1_ETA_GRID, selected_on = BT3_O1_SELECT_SEASONS) else NULL,
               n1_chosen = lapply(nw$n1_params, function(x) x[chosen == TRUE, .(season, size, decay)]),
               new_fit_seconds = as.list(nw$seconds), new_wall_seconds = as.list(nw$wall),
               workers = workers, r_version = R.version.string,
               packages = lapply(setNames(nm = c("data.table", "glmnet", "xgboost", "gbm", "mgcv", "lme4", "nnet", "sandwich")),
                                 function(p) as.character(utils::packageVersion(p))))

  # 4. shuffled-label control: same permutation as v2, every learner refit
  if (control) {
    t0 <- Sys.time()
    cat("control: shuffled labels\n")
    x <- bt3_shuffle_labels(d)
    lvx <- bt3_level0(x, weeks, cl, models = BT3_LEVEL0_LEARNERS)
    Lx <- merge(x, lvx$pred, by = "game_id", all.x = TRUE)
    setorder(Lx, kickoff, game_id)
    nwx <- bt3_run_new(x, Lx, weeks, cl, families)
    preds <- c(setNames(lapply(BT3_LEVEL0_LEARNERS, function(m) lvx$pred[, .(game_id, p = get(paste0("p_", m)))]),
                        BT3_LEVEL0_LEARNERS), nwx$pred)
    ctl <- bt3_score_control(x, weeks, preds)
    ctl[, family_type := fifelse(model %in% BT3_LEVEL0_LEARNERS, "v2 level-0 (refit)", "v3 new")]
    bt2_write_csv(bt3_signif(ctl), file.path(out_dir, "controls", "shuffled_labels.csv"))
    print(ctl)
    meta$control_shuffled_labels <- list(all_passed = all(ctl$passed), seed = BT2_SEED,
                                         wall_seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")),
                                         new_fit_seconds = as.list(nwx$seconds), level0_wall_seconds = lvx$wall)
    compute <- rbind(compute,
                     data.table(family = names(lvx$seconds), stage = "control: level0 refit", fit_seconds = unname(lvx$seconds),
                                wall_seconds = NA_real_),
                     data.table(family = names(nwx$seconds), stage = "control: v3 new", fit_seconds = unname(nwx$seconds),
                                wall_seconds = unname(nwx$wall[names(nwx$seconds)])))
  }
  bt2_write_csv(bt3_signif(compute, 4), file.path(out_dir, "compute", "seconds.csv"))
  meta$runtime_sec <- as.numeric(difftime(Sys.time(), t_all, units = "secs"))
  bt2_write_json(meta, file.path(out_dir, "run_meta.json"))
  invisible(list(d = d, L = L, scores = tab, new = nw, meta = meta))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i)) default else args[i + 1] }
  out_dir <- get_arg("--out")
  if (is.null(out_dir)) stop("usage: Rscript backtest/v3/sprint.R --out <dir> [--workers N] [--families S1,R1,...] [--no-control]")
  workers <- as.integer(get_arg("--workers", "1"))
  families <- strsplit(get_arg("--families", paste(BT3_NEW, collapse = ",")), ",")[[1]]
  suppressPackageStartupMessages(library(data.table))
  sys.source(file.path(bt3_sprint_dir(), "common.R"), envir = globalenv())
  bt3_source_all(dirname(dirname(bt3_sprint_dir())), envir = globalenv())
  bt3_sprint_main(out_dir, workers = workers, families = families, control = !("--no-control" %in% args))
}
