#!/usr/bin/env Rscript
# =============================================================================
# A3b's close-anchored run on v2's Tune window (2018-22), the inputs of the v2
# reproduction (reproduce_v2.R): S3 for v2's 36 features, every S4 control, and
# the S5 diagnostics that need no simulator (C3 has no point-in-time
# walk-forward until G1, so its curves, CRPS and PIT wait for G2).
#
#   Rscript backtest/vvf/run_a3b_close.R --out reports/2026-10-28/vvf-a3b-close
#
# S4 has two statuses: s4_status gates on the spec's controls (the status of
# record) and s4_status_amended on the proposed amendment, unsigned, which puts
# the anchor null in place of the label shuffle (reports/2026-10-28/a3-research).
# The learning curve and the fit gap score the anchor plus every feature, the
# high-variance end of the trade-off, beside the anchor on the same games.
# S5's validation curve is C2's half-life over the amendment's grid and v1's 16.
# The engine's settings (RECENCY_HALFLIFE, GLMM_BLEND_W, SOS_STRENGTH, N_RECENT,
# SHRINKAGE) need C3's walk-forward and wait for G2.
# The input checks (input_schema.R) run before any stage. The v1 games are cut
# at 2022 before the base models run; the VVF inputs load through 2024 and the
# features are cut at 2022; every loader guards the sealed season.
# =============================================================================

VVF_A3B_RESULT_FILES <- c("s3_skill.csv", "s5_murphy.csv", "s5_calibration.csv", "s5_bias_variance.csv",
                          "s5_team_effects.csv", "s5_loss_anova.csv", "s5_curve_c2_halflife.csv",
                          "s5_learning_curve.csv", "s5_fit_gap.csv")
VVF_A3B_C2_GRID <- c(Inf, 16, 8, 6, 4, 3, 2, 1)   # the amendment's half-lives and v1's 16, simplest (no decay) first
VVF_A3B_MODELS <- c(C0 = "p_c0", C1 = "p_c1", C2 = "p_c2", E1 = "p_e1")
VVF_A3B_N_TRAIN <- 2:8           # the table starts in 2010, so 8 seasons is the most 2018 allows
VVF_A3B_CONFIRM <- 2023:2024     # where a Tune choice is evaluated, under G3; never scored here
VVF_A3B_AMENDMENT <- "proposed 2026-10-28, unsigned"

#' The close-anchored table for every predicted season through 2022 (S3 trains
#' on the seasons before Tune), with the v1 and VVF inputs it came from. The
#' input checks run first and stop on any violation.
vvf_a3b_table <- function(inp_v1 = vvf_load_v1_inputs(max_season = VVF_V2_MAX_SEASON), inp = vvf_load_inputs()) {
  vvf_assert_inputs(vvf_schema_tables(inp_v1, inp, VVF_V2_MAX_SEASON))
  base <- vvf_base_predictions(inp_v1, VVF_V2_MAX_SEASON)
  full <- vvf_anchor_features(vvf_build_features(base, inp, VVF_V2_MAX_SEASON), "close")
  list(full = full, inp_v1 = inp_v1, inp = inp)
}

vvf_a3b_tune <- function(full) {
  x <- full[season %in% VVF_V2_TUNE]
  setattr(x, "vvf_anchor", "close")
  x
}

#' C2's walk-forward predictions at half-life h (lambda fixed at v1's 100)
vvf_a3b_c2_at <- function(inp_v1) {
  function(h, seasons) {
    g <- inp_v1$games
    feats <- bt_epa_features(g, inp_v1$team_games[game_id %in% g$game_id], inp_v1$qb_games[game_id %in% g$game_id], h,
                             seq(BT_EPA_FIRST_TRAIN_SEASON, VVF_V2_MAX_SEASON))
    p <- bt_epa_walk_forward(feats, g, bt_week_schedule(g, seasons), VVF_V1_SELECTIONS$c2$lambda)
    data.table(game_id = p$game_id, p = p$p_c2)
  }
}

#' fit_predict(train, target) for the anchor plus every feature: an unpenalized
#' logit with the anchor as offset, centred and scaled on the training rows,
#' with constant and aliased columns dropped. A missing value predicts at the
#' training mean. If `log` (an environment) is given, each call adds to its
#' counts: fits, fits_converged, train_rows_dropped, target_cells_imputed.
vvf_a3b_joint_fit <- function(features, log = NULL) {
  function(train, target) {
    X <- as.matrix(train[, ..features])
    ok <- stats::complete.cases(X)
    X <- X[ok, , drop = FALSE]
    m <- colMeans(X)
    s <- apply(X, 2, stats::sd)
    keep <- which(is.finite(s) & s > 0)
    Z <- sweep(sweep(X[, keep, drop = FALSE], 2, m[keep]), 2, s[keep], "/")
    q <- qr(cbind(1, Z))
    cols <- setdiff(q$pivot[seq_len(q$rank)], 1L) - 1L
    fit <- stats::glm.fit(cbind(1, Z[, cols, drop = FALSE]), train$y[ok], offset = train$lp_anchor[ok],
                          family = stats::binomial())
    Zt <- sweep(sweep(as.matrix(target[, ..features])[, keep, drop = FALSE], 2, m[keep]), 2, s[keep], "/")[, cols, drop = FALSE]
    imputed <- sum(!is.finite(Zt))
    Zt[!is.finite(Zt)] <- 0
    if (!is.null(log)) {
      add <- function(k, v) assign(k, (if (exists(k, envir = log, inherits = FALSE)) get(k, envir = log) else 0L) + as.integer(v), envir = log)
      add("fits", 1L)
      add("fits_converged", isTRUE(fit$converged))
      add("train_rows_dropped", sum(!ok))
      add("target_cells_imputed", imputed)
    }
    stats::plogis(target$lp_anchor + drop(cbind(1, Zt) %*% fit$coefficients))
  }
}

#' The learning curve (2 to 8 training seasons) and the fit gap of the joint
#' model, each with the anchor's log loss on the same games and each row's fit
#' diagnostics (fits, fits_converged, train_rows_dropped, target_cells_imputed)
vvf_a3b_bias_variance <- function(full, features = VVF_V2_FEATURES, eval_seasons = VVF_V2_TUNE, n_train = VVF_A3B_N_TRAIN) {
  d <- full[is.finite(lp_anchor)]
  ev <- d[season %in% eval_seasons & !is.na(y)]
  diag <- function(log) data.table(fits = log$fits, fits_converged = log$fits_converged,
                                   train_rows_dropped = log$train_rows_dropped, target_cells_imputed = log$target_cells_imputed)
  lc <- rbindlist(lapply(n_train, function(n) {
    log <- new.env()
    cbind(vvf_learning_curve(vvf_a3b_joint_fit(features, log), d, eval_seasons, n), diag(log))
  }))
  lc[, logloss_anchor := mean(bt_logloss_vec(ev$p_anchor, ev$y))]
  fg <- rbindlist(lapply(eval_seasons, function(s) {
    log <- new.env()
    cbind(vvf_fit_gap(d, vvf_a3b_joint_fit(features, log), s), diag(log))
  }))
  fg <- merge(fg, ev[, .(logloss_anchor = mean(bt_logloss_vec(p_anchor, y))), by = season], by = "season")
  setcolorder(lc, c("n_train_seasons", "n", "logloss", "brier", "logloss_anchor"))
  setcolorder(fg, c("season", "logloss_in", "logloss_wf", "gap", "logloss_anchor"))
  list(learning_curve = lc[], fit_gap = fg[])
}

#' S3 and S5: writes VVF_A3B_RESULT_FILES to out_dir and returns their result_sha256
vvf_a3b_results <- function(tab, out_dir) {
  x <- vvf_a3b_tune(tab$full)
  s3 <- vvf_s3_screen(tab$full, VVF_V2_FEATURES, "close", VVF_V2_TUNE)$skill
  y <- x[!is.na(y)]
  murphy <- rbindlist(lapply(names(VVF_A3B_MODELS), function(m) {
    r <- vvf_murphy(y[[VVF_A3B_MODELS[[m]]]], y$y)
    data.table(model = m, n = nrow(y), brier = r$brier, reliability = r$reliability, resolution = r$resolution,
               uncertainty = r$uncertainty, within_bin_variance = r$within_bin_variance,
               within_bin_covariance = r$within_bin_covariance, bins = r$bins)
  }))
  calib <- rbindlist(lapply(names(VVF_A3B_MODELS), function(m) {
    r <- vvf_calibration_label(y[[VVF_A3B_MODELS[[m]]]], y$y)
    data.table(model = m, slope = r$slope, slope_lo = r$slope_ci[1], slope_hi = r$slope_ci[2], intercept = r$intercept,
               intercept_lo = r$intercept_ci[1], intercept_hi = r$intercept_ci[2], label = r$label)
  }))
  bv <- rbindlist(list(
    c(list(target = "margin vs closing spread_line"), vvf_bias_variance(x$spread_line, x$margin)),
    c(list(target = "total vs closing total_line"), vvf_bias_variance(x$total_line, x$total))))
  teams <- rbind(vvf_team_effects(x), vvf_team_effects(x, family = "spread", response = "ats_resid"))
  la <- rbind(vvf_loss_anova(x, "p_e1", "p_c0", by = "season"), vvf_loss_anova(x, "p_e1", "p_c0", by = "part"))
  la[, q_bh := stats::p.adjust(p, method = "BH")]   # BH over the four ANOVA tests (review I-5)
  curve <- vvf_validation_curve(VVF_A3B_C2_GRID, vvf_a3b_c2_at(tab$inp_v1), y, seasons = VVF_V2_TUNE,
                                eval_seasons = VVF_A3B_CONFIRM)
  bvt <- vvf_a3b_bias_variance(tab$full)
  rnd <- function(t) t[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)]
  tabs <- list(s3, murphy, calib, bv, teams, la, curve, bvt$learning_curve, bvt$fit_gap)
  paths <- file.path(out_dir, VVF_A3B_RESULT_FILES)
  for (k in seq_along(tabs)) vvf_write_csv(rnd(tabs[[k]]), paths[k])
  vvf_result_sha256(paths)
}

#' Every S4 control on the close-anchored Tune data
vvf_a3b_controls <- function(tab, results_sha) {
  build <- function(inp) vvf_build_features(vvf_base_predictions(inp$v1, inp$max_season), inp$v2, inp$max_season)
  ctl <- list(
    canary = vvf_control_canary(build, list(v1 = tab$inp_v1, v2 = tab$inp, max_season = VVF_V2_MAX_SEASON), vvf_canary_append),
    placebo = vvf_control_placebo(vvf_a3b_tune(tab$full)),
    shuffled_labels = vvf_control_shuffle(tab$full, VVF_V2_FEATURES, "close", VVF_V2_TUNE),
    anchor_null = vvf_control_null(tab$full, VVF_V2_FEATURES, "close", VVF_V2_TUNE, null = "anchor"),
    permuted_x = vvf_control_null(tab$full, VVF_V2_FEATURES, "close", VVF_V2_TUNE, null = "permuted_x"),
    anchor_copy = vvf_control_anchor_copy(tab$full, VVF_V2_TUNE))
  # reproducibility: a second run of S3 and S5 into a scratch directory gives the same hash
  tmp <- tempfile("vvf-a3b-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  second <- vvf_a3b_results(tab, tmp)
  ctl$reproducibility <- list(passed = identical(results_sha, second), sha = c(results_sha, second))
  ctl
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 2L || args[1] != "--out") stop("usage: Rscript backtest/vvf/run_a3b_close.R --out <dir>", call. = FALSE)
  out_dir <- args[2]
  e <- environment()
  for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R", "blends.R",
              "calibrators.R", "metrics.R", "controls.R")) sys.source(file.path("backtest", f), envir = e)
  for (f in c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s3_skill.R", "s4_controls.R",
              "s5_curves.R", "s5_scores.R", "s5_anova.R", "reproduce_v2.R", "input_schema.R")) sys.source(file.path("backtest", "vvf", f), envir = e)
  t0 <- Sys.time()
  tab <- vvf_a3b_table()
  sha <- vvf_a3b_results(tab, out_dir)
  ctl <- vvf_a3b_controls(tab, sha)
  rep <- vvf_s4_report(ctl, gating = VVF_S4_GATING_SPEC)
  amended <- vvf_s4_report(ctl, gating = VVF_S4_GATING_AMENDED)
  null_detail <- function(r) sprintf("%s null; %d claims; %d intervals wholly above 0, %d wholly below, of %d", r$null, r$claims,
                                     r$above, r$below, nrow(r$skill))
  detail <- c(
    canary = sprintf("%d rows unchanged, %d appended, changed columns: %s", ctl$canary$rows, ctl$canary$added,
                     if (length(ctl$canary$changed)) paste(ctl$canary$changed, collapse = " ") else "none"),
    placebo = sprintf("%d placebos, n = %d, rejection rate %.3f at alpha 0.05 (band %.3f-%.3f)", ctl$placebo$k, ctl$placebo$n,
                      ctl$placebo$rate, VVF_PLACEBO_BAND[1], VVF_PLACEBO_BAND[2]),
    shuffled_labels = sprintf("within %s; %d of %d intervals include 0; range of skill %.5f to %.5f", ctl$shuffled_labels$within,
                              sum(ctl$shuffled_labels$skill[, skill_lo <= 0 & skill_hi >= 0]), nrow(ctl$shuffled_labels$skill),
                              min(ctl$shuffled_labels$skill$skill), max(ctl$shuffled_labels$skill$skill)),
    anchor_null = null_detail(ctl$anchor_null),
    permuted_x = null_detail(ctl$permuted_x),
    anchor_copy = sprintf("skill %s", format(ctl$anchor_copy$skill)),
    reproducibility = sprintf("results_sha256 of the %d result files: %s and %s", length(VVF_A3B_RESULT_FILES),
                              substr(ctl$reproducibility$sha[1], 1, 16), substr(ctl$reproducibility$sha[2], 1, 16)))
  rep$table[, `:=`(gates_amended = control %in% VVF_S4_GATING_AMENDED, detail = detail[control])]
  vvf_write_csv(rep$table, file.path(out_dir, "s4_controls.csv"))
  files <- c(VVF_A3B_RESULT_FILES, "s4_controls.csv")
  meta <- list(generated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
               purpose = "A3b close-anchored run: S3, S4 controls and S5 diagnostics on v2's Tune window",
               seasons_scored = VVF_V2_TUNE, anchor = "close", decision = "close", s4_status = rep$status,
               s4_status_amended = amended$status, s4_amendment = VVF_A3B_AMENDMENT,
               placebo_rate = ctl$placebo$rate, r_version = R.version.string,
               runtime_sec = as.numeric(difftime(Sys.time(), t0, units = "secs")),
               result_files = files, result_sha256 = vvf_result_sha256(file.path(out_dir, files)))
  vvf_write_json(meta, file.path(out_dir, "run_meta.json"))
  print(rep$table)
  cat(sprintf("S4 status: %s under the spec, %s under the proposed amendment; result_sha256: %s\n", rep$status,
              amended$status, meta$result_sha256))
}
