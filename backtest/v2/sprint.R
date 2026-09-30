#!/usr/bin/env Rscript
# =============================================================================
# Validation sprint v2 runner (Tune window 2018-2022 only).
#
#   Rscript backtest/v2/sprint.R --out reports/2026-09-30/validation-sprint [--stages screen,models,handicap]
#
# base      v1 candidates (Elo, EPA GLM, ensemble) regenerated walk-forward on
#           seasons <= 2022 and checked against the committed v1 Tune predictions
# screen    feature significance beyond the close (backtest/v2/screen.R)
# models    blends: logistic stack, glmnet, xgboost, gbm; calibration maps
# handicap  against-the-spread and totals
# The Confirm (2023-24) and Holdout (2025) seasons are never loaded: every table is
# cut at BT2_MAX_SPRINT_SEASON before any feature or model sees it.
# =============================================================================

bt2_sprint_dir <- function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else file.path(getwd(), "backtest", "v2")
}

bt2_source_all <- function(envir = parent.frame()) {
  v2 <- bt2_sprint_dir(); v1 <- dirname(v2)
  for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R",
              "blends.R", "calibrators.R", "metrics.R", "controls.R")) sys.source(file.path(v1, f), envir = envir)
  for (f in c("common.R", "features.R", "screen.R", "models.R", "handicap.R")) {
    p <- file.path(v2, f)
    if (file.exists(p)) sys.source(p, envir = envir)
  }
  invisible(envir)
}

#' Regenerated base predictions must equal the committed v1 Tune predictions
bt2_check_base_vs_v1 <- function(base, v1_pred_path = "reports/2026-09-29/backtest-games-v1/predictions.csv") {
  v1 <- fread(v1_pred_path)[window == "tune" & candidate %in% c("C1", "C2", "E1")]
  v1 <- dcast(v1, game_id ~ candidate, value.var = "p")
  m <- merge(base$pred[, .(game_id, p_c1, p_c2, p_e1)], v1, by = "game_id")
  list(games_compared = nrow(m),
       max_abs_diff = c(C1 = max(abs(m$p_c1 - m$C1)), C2 = max(abs(m$p_c2 - m$C2)), E1 = max(abs(m$p_e1 - m$E1))))
}

bt2_sprint_main <- function(out_dir, stages) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  win <- jsonlite::read_json("backtest/eval_windows/nfl_games_v1.json", simplifyVector = TRUE)
  inp_v1 <- bt_load_inputs(win$data_dir, win$data_sha256)
  inp_v1$games <- inp_v1$games[season <= BT2_MAX_SPRINT_SEASON]
  inp_v2 <- bt2_load_v2_inputs()
  t0 <- Sys.time()
  base <- bt2_base_predictions(inp_v1)
  chk <- bt2_check_base_vs_v1(base)
  cat(sprintf("base: %d games 2010-%d; vs v1 Tune predictions (%d games) max |diff| C1 %.2e C2 %.2e E1 %.2e\n",
              nrow(base$pred), BT2_MAX_SPRINT_SEASON, chk$games_compared, chk$max_abs_diff[["C1"]],
              chk$max_abs_diff[["C2"]], chk$max_abs_diff[["E1"]]))
  if (any(chk$max_abs_diff > 1e-9)) stop("base predictions do not reproduce v1", call. = FALSE)
  d <- bt2_build_features(base, inp_v2)
  meta <- list(generated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
               max_season_loaded = max(d$season), tune_seasons = BT2_TUNE_SEASONS,
               base_check_vs_v1 = chk, r_version = R.version.string,
               packages = lapply(setNames(nm = c("data.table", "sandwich", "glmnet", "xgboost", "gbm", "mgcv")),
                                 function(p) as.character(utils::packageVersion(p))))

  if ("screen" %in% stages) {
    s <- bt2_run_screen(d)
    bt2_write_csv(s$features[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)],
                  file.path(out_dir, "screen", "features.csv"))
    bt2_write_csv(s$joint[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)],
                  file.path(out_dir, "screen", "joint.csv"))
    meta$screen <- list(n = s$n, seasons = s$seasons)
    cat("screen: ", paste(names(s$n), unlist(s$n), collapse = ", "), "\n")
  }
  if ("models" %in% stages && exists("bt2_run_models")) meta$models <- bt2_run_models(d, base$weeks, out_dir)
  if ("handicap" %in% stages && exists("bt2_run_handicap")) meta$handicap <- bt2_run_handicap(d, base$weeks, out_dir)
  if ("controls" %in% stages && exists("bt2_control_shuffle")) {
    ctl <- bt2_control_shuffle(d, base$weeks)
    bt2_write_csv(ctl[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)], file.path(out_dir, "models", "control_shuffled_labels.csv"))
    meta$control_shuffled_labels <- list(all_passed = all(ctl$passed), seed = BT2_SEED)
    print(ctl)
  }
  meta$runtime_sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  bt2_write_json(meta, file.path(out_dir, "run_meta.json"))
  invisible(list(d = d, meta = meta))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i)) default else args[i + 1] }
  out_dir <- get_arg("--out")
  if (is.null(out_dir)) stop("usage: Rscript backtest/v2/sprint.R --out <dir> [--stages screen,models,handicap]")
  stages <- strsplit(get_arg("--stages", "screen,models,handicap"), ",")[[1]]
  bt2_source_all(envir = environment())
  bt2_sprint_main(out_dir, stages)
}
