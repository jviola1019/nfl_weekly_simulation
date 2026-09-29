#!/usr/bin/env Rscript
# =============================================================================
# Game backtest v1: walk-forward shootout driver.
#
#   Rscript backtest/walk_forward.R --window backtest/eval_windows/nfl_games_v1.json \
#       --stage dev|score --out <dir> [--no-controls] [--no-repro]
#
# dev   : Tune seasons only (predictions stop at the last Tune season). For
#         development; the Confirm window is never predicted.
# score : requires the window's PROTOCOL.md to match protocol_sha256 and to be
#         committed unchanged in git. Selects on Tune, scores Tune and Confirm,
#         runs the controls, and re-runs itself once to check the result hash.
# The Holdout is sealed: the committed inputs contain no season after 2024.
# =============================================================================

bt_script_dir <- function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else file.path(getwd(), "backtest")
}

bt_source_all <- function(dir = bt_script_dir(), envir = parent.frame()) {
  for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R",
              "blends.R", "calibrators.R", "metrics.R", "controls.R")) {
    sys.source(file.path(dir, f), envir = envir)
  }
  invisible(envir)
}

BT_CANDIDATES <- c("C1" = "p_c1", "C2" = "p_c2", "E1" = "p_e1", "B1[C1]" = "p_b1_c1",
                   "B1[C2]" = "p_b1_c2", "B1[E1]" = "p_b1_e1", "B2[E1]" = "p_b2_e1", "K[E1]" = "p_k_e1")
BT_REFERENCE <- c("C0" = "p_c0")
BT_DECISION_TIME <- c("C1", "C2", "E1", "K[E1]")   # inputs known before the opener

bt_git <- function(...) {
  out <- suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  list(status = if (is.null(st)) 0L else st, out = out)
}

#' score stage precondition: PROTOCOL.md hash matches and it is committed unchanged
bt_check_protocol <- function(win, window_path) {
  proto <- win$protocol_path
  if (!file.exists(proto)) stop("protocol check: missing ", proto, call. = FALSE)
  got <- digest::digest(file = proto, algo = "sha256")
  if (!identical(got, win$protocol_sha256)) {
    stop(sprintf("protocol check: sha256(%s) = %s but window says %s", proto, got, win$protocol_sha256), call. = FALSE)
  }
  for (f in c(proto, window_path)) {
    if (bt_git("ls-files", "--error-unmatch", f)$status != 0) stop("protocol check: not committed: ", f, call. = FALSE)
    if (bt_git("diff", "--quiet", "HEAD", "--", f)$status != 0) stop("protocol check: uncommitted changes in ", f, call. = FALSE)
  }
  log <- bt_git("log", "-1", shQuote("--format=%H %cI"), "--", proto)$out
  list(protocol_sha256 = got, protocol_commit = sub(" .*", "", log[1]), protocol_committed_at = sub("^\\S+ ", "", log[1]))
}

bt_tune_loss <- function(pred, col, tune_ids) {
  x <- pred[game_id %in% tune_ids]
  if (nrow(x) != length(tune_ids) || anyNA(x[[col]])) stop("tune loss: missing predictions for ", col, call. = FALSE)
  mean(bt_logloss_vec(x[[col]], x$y))
}

#' All candidate predictions for fixed selections. `games` may carry shuffled scores.
bt_predict_all <- function(games, feats_by_hl, weeks, sel, pred_seasons) {
  c1 <- bt_elo_run(games, sel$c1$K, sel$c1$hfa, sel$c1$regress)
  c2 <- bt_epa_walk_forward(feats_by_hl[[as.character(sel$c2$halflife)]], games, weeks, sel$c2$lambda)
  d <- games[season %in% pred_seasons,
             .(game_id, season, week, wk, kickoff, phase, y, tie, home_score, away_score, p_c0)]
  d <- merge(merge(d, c1, by = "game_id"), c2, by = "game_id", all.x = TRUE)
  d[, p_e1 := bt_e1(p_c1, p_c2)]
  for (base in c("c1", "c2", "e1")) {
    b <- bt_b1_walk_forward(d[, .(game_id, kickoff, season, wk, y, p_mkt = p_c0, p_model = get(paste0("p_", base)))],
                            weeks, sel$b1[[base]])
    d <- merge(d, b[, .(game_id, tmp = p)], by = "game_id", all.x = TRUE)
    setnames(d, "tmp", paste0("p_b1_", base))
    if (base == "e1") d <- merge(d, b[, .(game_id, b1_e1_mkt = b_mkt, b1_e1_model = b_model)], by = "game_id", all.x = TRUE)
  }
  d[, p_b2_e1 := bt_b2(p_e1, p_c0, sel$b2_e1$w)]
  k <- bt_calib_walk_forward(d[, .(game_id, kickoff, season, wk, y, p = p_e1)], weeks, sel$k_e1$method)
  d <- merge(d, k[, .(game_id, p_k_e1 = p)], by = "game_id", all.x = TRUE)
  setorder(d, kickoff, game_id)
  d[]
}

#' Select every hyperparameter on the Tune window (mean log loss, first in grid order on ties)
bt_select <- function(games, feats_by_hl, weeks, tune_ids, pred_seasons) {
  tune_weeks <- weeks[wk %in% games[game_id %in% tune_ids, unique(wk)]]
  lab <- games[game_id %in% tune_ids, .(game_id, y)]
  grid_log <- list()

  c1_loss <- vapply(seq_len(nrow(BT_ELO_GRID)), function(i) {
    g <- BT_ELO_GRID[i]
    p <- merge(bt_elo_run(games, g$K, g$hfa, g$regress), lab, by = "game_id")
    bt_tune_loss(p, "p_c1", tune_ids)
  }, numeric(1))
  i1 <- which.min(c1_loss)
  grid_log$c1 <- cbind(BT_ELO_GRID, tune_logloss = c1_loss)

  c2_loss <- vapply(seq_len(nrow(BT_EPA_GRID)), function(i) {
    g <- BT_EPA_GRID[i]
    p <- merge(bt_epa_walk_forward(feats_by_hl[[as.character(g$halflife)]], games, tune_weeks, g$lambda), lab, by = "game_id")
    bt_tune_loss(p, "p_c2", tune_ids)
  }, numeric(1))
  i2 <- which.min(c2_loss)
  grid_log$c2 <- cbind(BT_EPA_GRID, tune_logloss = c2_loss)

  sel <- list(c1 = as.list(BT_ELO_GRID[i1]), c2 = as.list(BT_EPA_GRID[i2]))
  # base predictions (2010+) for the blends and calibrators
  c1 <- bt_elo_run(games, sel$c1$K, sel$c1$hfa, sel$c1$regress)
  c2 <- bt_epa_walk_forward(feats_by_hl[[as.character(sel$c2$halflife)]], games, weeks, sel$c2$lambda)
  d <- merge(merge(games[season %in% pred_seasons, .(game_id, season, wk, kickoff, y, p_c0)], c1, by = "game_id"),
             c2, by = "game_id", all.x = TRUE)
  d[, p_e1 := bt_e1(p_c1, p_c2)]

  sel$b1 <- list()
  for (base in c("c1", "c2", "e1")) {
    losses <- vapply(BT_B1_LAMBDA_GRID, function(l) {
      b <- bt_b1_walk_forward(d[, .(game_id, kickoff, season, wk, y, p_mkt = p_c0, p_model = get(paste0("p_", base)))],
                              tune_weeks, l)
      bt_tune_loss(merge(b, lab, by = "game_id"), "p", tune_ids)
    }, numeric(1))
    sel$b1[[base]] <- BT_B1_LAMBDA_GRID[which.min(losses)]
    grid_log[[paste0("b1_", base)]] <- data.table(lambda = BT_B1_LAMBDA_GRID, tune_logloss = losses)
  }
  w_loss <- vapply(BT_B2_W_GRID, function(w) {
    x <- d[game_id %in% tune_ids]
    mean(bt_logloss_vec(bt_b2(x$p_e1, x$p_c0, w), x$y))
  }, numeric(1))
  sel$b2_e1 <- list(w = BT_B2_W_GRID[which.min(w_loss)])
  grid_log$b2_e1 <- data.table(w = BT_B2_W_GRID, tune_logloss = w_loss)

  k_loss <- vapply(BT_K_METHODS, function(m) {
    k <- bt_calib_walk_forward(d[, .(game_id, kickoff, season, wk, y, p = p_e1)], tune_weeks, m)
    bt_tune_loss(merge(k, lab, by = "game_id"), "p", tune_ids)
  }, numeric(1))
  sel$k_e1 <- list(method = BT_K_METHODS[which.min(k_loss)])
  grid_log$k_e1 <- data.table(method = BT_K_METHODS, tune_logloss = k_loss)
  list(selections = sel, grids = grid_log)
}

bt_window_ids <- function(games, seasons) games[season %in% seasons & !is.na(y), game_id]

bt_score_all <- function(pred, windows, seed) {
  out <- list()
  for (wn in names(windows)) {
    d <- pred[season %in% windows[[wn]] & !is.na(y)]
    out[[wn]] <- list(ties_excluded = pred[season %in% windows[[wn]] & tie == TRUE, .N],
                      pooled = bt_score_window(copy(d), BT_CANDIDATES, BT_REFERENCE, seed = seed))
    for (ph in c("REG", "POST")) {
      dp <- d[phase == ph]
      if (nrow(dp) >= 20L) out[[wn]][[ph]] <- bt_score_window(copy(dp), BT_CANDIDATES, BT_REFERENCE, seed = seed)
    }
  }
  out
}

bt_gates <- function(scores_confirm, controls_passed, clv) {
  ref <- scores_confirm[[BT_REFERENCE]]
  res <- list()
  for (nm in names(BT_CANDIDATES)) {
    s <- scores_confirm[[BT_CANDIDATES[[nm]]]]
    g1 <- s$skill > 0 && s$skill_ci[1] > 0
    g2 <- isTRUE(s$dm_p_better_bh < 0.05)
    g3 <- s$slope_ci[1] <= 1 && s$slope_ci[2] >= 1 && s$ece <= ref$ece + 0.005
    g4 <- isTRUE(controls_passed)
    confirm_all <- g1 && g2 && g3 && g4
    bv <- clv[[nm]]
    bv_status <- if (is.null(bv)) "not evaluable in v1: inputs not known at the opener" else
      if (bv$n < 400L) sprintf("not evaluable: %d decision-time picks < 400", bv$n) else
        if (bv$mean_clv_bps >= 100 && bv$clv_ci[1] > 0 && bv$roi_ci[1] > -0.02) "passes" else "fails"
    res[[nm]] <- list(
      g1_skill_ci_above_zero = g1, g2_dm_bh = g2, g3_calibration = g3, g4_controls = g4,
      brier_status = if (confirm_all) "passes Confirm; Holdout pending" else "not better than market",
      betting_value_status = bv_status
    )
  }
  res
}

bt_write_json <- function(x, path) {
  rnd <- function(v) if (is.list(v)) lapply(v, rnd) else if (is.numeric(v)) bt_round(v) else v
  jsonlite::write_json(rnd(x), path, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null")
}

bt_run <- function(window_path, stage, out_dir, run_controls = TRUE, run_repro = TRUE) {
  stopifnot(stage %in% c("dev", "score"))
  win <- jsonlite::read_json(window_path, simplifyVector = TRUE)
  proto <- if (stage == "score") bt_check_protocol(win, window_path) else list()
  inp <- bt_load_inputs(win$data_dir, win$data_sha256)
  games <- inp$games
  if (max(games$season) > win$max_input_season) stop("sealed holdout: inputs contain seasons after ", win$max_input_season)

  tune <- win$windows$tune$seasons
  confirm <- win$windows$confirm$seasons
  max_season <- if (stage == "dev") max(tune) else max(confirm)
  games <- games[season <= max_season]
  pred_seasons <- seq(win$first_prediction_season, max_season)
  weeks <- bt_week_schedule(games, pred_seasons)
  tune_ids <- bt_window_ids(games, tune)

  feats_by_hl <- lapply(setNames(nm = as.character(unique(BT_EPA_GRID$halflife))), function(hl) {
    bt_epa_features(games, inp$team_games, inp$qb_games, as.numeric(hl), seq(BT_EPA_FIRST_TRAIN_SEASON, max_season))
  })

  sel <- bt_select(games, feats_by_hl, weeks, tune_ids, pred_seasons)
  pred <- bt_predict_all(games, feats_by_hl, weeks, sel$selections, pred_seasons)

  windows <- list(tune = tune)
  if (stage == "score") windows$confirm <- confirm
  scores <- bt_score_all(pred, windows, seed = win$bootstrap_seed)

  # CLV at the ESPN BET opener (decision-time candidates, Confirm seasons with opener data)
  clv <- list()
  if (stage == "score") {
    oc <- bt_market_open_close(inp$espn_open_close)
    dc <- merge(pred[season %in% confirm], oc, by = "game_id")
    for (nm in BT_DECISION_TIME) clv[[nm]] <- bt_clv(dc, BT_CANDIDATES[[nm]], tau = win$clv_edge_threshold,
                                                     seed = win$bootstrap_seed)
    clv$meta <- list(venue = "ESPN BET", seasons = sort(unique(dc$season)), games_with_opener = nrow(dc),
                     tau = win$clv_edge_threshold)
  }

  long <- melt(pred[season %in% unlist(windows)],
               id.vars = c("game_id", "season", "week", "phase", "y"),
               measure.vars = c(BT_REFERENCE, BT_CANDIDATES), variable.name = "column", value.name = "p")
  lab <- c(BT_REFERENCE, BT_CANDIDATES)
  long[, candidate := names(lab)[match(column, lab)]]
  long[, window := fifelse(season %in% tune, "tune", "confirm")]
  long <- long[, .(game_id, season, week, phase, window, y, candidate, p = bt_round(p))]
  setorder(long, game_id, candidate)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(long, file.path(out_dir, "predictions.csv"))
  metrics <- list(protocol = "nfl_games_v1", stage = stage, windows = windows, selections = sel$selections,
                  grids = sel$grids, scores = scores, clv = clv)

  controls <- NULL
  if (run_controls) {
    eval_ids <- bt_window_ids(games, if (stage == "score") confirm else tune)
    can <- bt_control_canary(feats_by_hl[[as.character(sel$selections$c2$halflife)]], games, weeks,
                             sel$selections$c2$lambda, eval_ids)
    shuf_games <- bt_shuffle_scores(games)
    sp <- bt_predict_all(shuf_games, feats_by_hl, weeks, sel$selections, pred_seasons)
    sp <- merge(sp, bt_climatology(shuf_games, weeks), by = "wk")
    sd_ <- sp[game_id %in% eval_ids & !is.na(y)]
    shuf <- bt_score_window(copy(sd_), BT_CANDIDATES, c(CLIM = "p_clim"), seed = win$bootstrap_seed)
    shuf_lower <- vapply(BT_CANDIDATES, function(cc) shuf[[cc]]$skill_ci[1], numeric(1))
    ev <- pred[game_id %in% eval_ids]
    copy_scores <- bt_score_window(copy(ev[, .(game_id, kickoff, wk, y, p_c0, p_copy = p_c0)]), c(COPY = "p_copy"),
                                   BT_REFERENCE, B = 200L, seed = win$bootstrap_seed)
    b1c <- bt_b1_walk_forward(pred[, .(game_id, kickoff, season, wk, y, p_mkt = p_c0, p_model = p_c0)],
                              weeks[wk %in% ev$wk], 1)
    slope_sum <- mean(b1c$b_mkt + b1c$b_model)
    worst_skill <- max(vapply(BT_CANDIDATES, function(cc) scores[[length(scores)]]$pooled[[cc]]$skill, numeric(1)))
    controls <- list(
      leak_canary = can,
      implausible_skill_guard = list(threshold = BT_IMPLAUSIBLE_SKILL, max_candidate_skill = worst_skill,
                                     passed = worst_skill <= BT_IMPLAUSIBLE_SKILL),
      shuffled_labels = list(seed = BT_SHUFFLE_SEED, reference = "expanding-window climatology",
                             skill_ci_lower = as.list(setNames(shuf_lower, names(BT_CANDIDATES))),
                             skill = as.list(setNames(vapply(BT_CANDIDATES, function(cc) shuf[[cc]]$skill, numeric(1)),
                                                      names(BT_CANDIDATES))),
                             passed = all(shuf_lower <= 0)),
      market_copy = list(skill = copy_scores$p_copy$skill, brier_diff = copy_scores$p_copy$brier_diff,
                         b1_total_market_slope = slope_sum, slope_band = BT_MARKET_COPY_SLOPE,
                         passed = copy_scores$p_copy$skill == 0 && copy_scores$p_copy$brier_diff == 0 &&
                           slope_sum >= BT_MARKET_COPY_SLOPE[1] && slope_sum <= BT_MARKET_COPY_SLOPE[2])
    )
  }
  if (stage == "score") {
    metrics$gates <- bt_gates(scores$confirm$pooled,
                              controls_passed = if (is.null(controls)) NA else
                                all(vapply(controls, function(x) isTRUE(x$passed), logical(1))),
                              clv = clv)
  }
  bt_write_json(metrics, file.path(out_dir, "metrics.json"))
  result_sha256 <- digest::digest(paste0(digest::digest(file = file.path(out_dir, "predictions.csv"), algo = "sha256"),
                                         digest::digest(file = file.path(out_dir, "metrics.json"), algo = "sha256")),
                                  algo = "sha256", serialize = FALSE)

  if (run_controls && run_repro) {
    tmp <- tempfile("bt_repro_")
    # The second process runs the same controls (except this one), because gate G4 in
    # the hashed metrics.json depends on them; only the reproducibility re-run is skipped.
    args <- c(file.path(bt_script_dir(), "walk_forward.R"), "--window", window_path, "--stage", stage,
              "--out", tmp, "--no-repro")
    st <- system2(file.path(R.home("bin"), "Rscript"), args, stdout = FALSE, stderr = FALSE)
    rm <- tryCatch(jsonlite::read_json(file.path(tmp, "run_meta.json")), error = function(e) NULL)
    controls$reproducibility <- list(first = result_sha256, second = if (is.null(rm$result_sha256)) NA else rm$result_sha256,
                                     passed = identical(st, 0L) && identical(rm$result_sha256, result_sha256))
  }
  if (!is.null(controls)) {
    controls$all_passed <- all(vapply(controls, function(x) isTRUE(x$passed), logical(1)))
    controls$run_status <- if (controls$all_passed) "complete" else "void"
    bt_write_json(controls, file.path(out_dir, "controls.json"))
  }
  pkgs <- c("data.table", "jsonlite", "digest")
  meta <- c(list(result_sha256 = result_sha256, stage = stage, window = window_path,
                 generated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                 code_git_sha = bt_git("rev-parse", "HEAD")$out[1],
                 code_dirty = bt_git("diff", "--quiet", "HEAD", "--", "backtest")$status != 0,
                 r_version = R.version.string,
                 packages = as.list(setNames(vapply(pkgs, function(p) as.character(utils::packageVersion(p)), ""), pkgs))),
            proto)
  bt_write_json(meta, file.path(out_dir, "run_meta.json"))
  invisible(list(pred = pred, metrics = metrics, controls = controls, meta = meta))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag) { i <- match(flag, args); if (is.na(i)) NULL else args[i + 1] }
  window_path <- get_arg("--window"); stage <- get_arg("--stage"); out_dir <- get_arg("--out")
  if (is.null(window_path) || is.null(stage) || is.null(out_dir)) {
    stop("usage: Rscript backtest/walk_forward.R --window <json> --stage dev|score --out <dir> [--no-controls] [--no-repro]")
  }
  bt_source_all(envir = environment())
  bt_run(window_path, stage, out_dir, run_controls = !("--no-controls" %in% args), run_repro = !("--no-repro" %in% args))
}
