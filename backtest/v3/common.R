# =============================================================================
# Blend research v3 (Tune window 2018-2022 only): shared constants and helpers.
#
# v3 reuses the v1 helpers (backtest/*.R) and the v2 harness (backtest/v2/*.R)
# without changing them, so every v2 output stays byte-for-byte identical.
# Every v3 fit refuses rows after BT2_MAX_SPRINT_SEASON (2022): the Confirm
# window (2023-24) and the sealed 2025 holdout are never built or scored here.
# =============================================================================

# Level-0 predictions the meshes combine (v2 walk-forward, out of fold)
BT3_LEVEL0 <- c(LR_E1 = "p_LR_E1", GLMNET = "p_GLMNET", XGB = "p_XGB", GBM = "p_GBM",
                C1 = "p_c1", C2 = "p_c2", E1 = "p_e1")
# Level-0 families that learn from outcomes (refit on permuted labels in the control);
# C1, C2 and E1 are computed from game scores and are inputs, not learners
BT3_LEVEL0_LEARNERS <- c("LR_E1", "GLMNET", "XGB", "GBM")
BT3_META_MIN_TRAIN <- 500L      # S1/R1: level-0 out-of-fold games needed before a meta fit
BT3_META_MIN_SEASONS <- 3L      # season-grouped CV needs at least 3 seasons
BT3_FAMILY_MIN_TRAIN <- 800L    # G2/N1: as v2 (BT2_BLEND_MIN_TRAIN)
BT3_T1_SEASONS <- 3L            # T1 rolling window: the current season to date + 2 prior seasons
BT3_T1_MIN_TRAIN <- 400L
BT3_V2_DIR <- file.path("reports", "2026-09-30", "validation-sprint")

#' Stop if any season is after the Tune window (Confirm and Holdout are off limits)
bt3_guard <- function(seasons, what = "v3 rows") bt2_guard_seasons(seasons, BT2_MAX_SPRINT_SEASON, what)

#' Source the v1 helpers, the v2 harness and the v3 code into `envir`
bt3_source_all <- function(root = ".", envir = parent.frame()) {
  bt <- file.path(root, "backtest")
  for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R",
              "blends.R", "calibrators.R", "metrics.R", "controls.R")) sys.source(file.path(bt, f), envir = envir)
  for (f in c("common.R", "features.R", "screen.R", "models.R")) sys.source(file.path(bt, "v2", f), envir = envir)
  for (f in c("common.R", "meshes.R", "families.R", "score.R")) {
    p <- file.path(bt, "v3", f)
    if (file.exists(p)) sys.source(p, envir = envir)
  }
  invisible(envir)
}

#' Run `fname(chunk, ...)` over chunks of `weeks` (round-robin split, so early and
#' late weeks are spread across workers). With a cluster the chunks run in
#' parallel; every fit sets its own seed, so the result does not depend on the
#' split (tested in test-backtest-v3-meshes.R). Returns the per-chunk results.
bt3_map_weeks <- function(weeks, fname, ..., cl = NULL) {
  n <- if (is.null(cl)) 1L else length(cl)
  idx <- seq_len(nrow(weeks))
  chunks <- unname(split(weeks, (idx - 1L) %% max(1L, min(n, nrow(weeks)))))
  if (is.null(cl)) {
    fun <- get(fname, mode = "function")
    return(lapply(chunks, function(ch) fun(ch, ...)))
  }
  work <- function(ch, fname, args) do.call(fname, c(list(ch), args))
  environment(work) <- globalenv()
  parallel::parLapply(cl, chunks, work, fname = fname, args = list(...))
}

#' Combine chunk results that are lists of data.tables (pred, diag) and a named
#' numeric `seconds`; rows are put back in kickoff order of `d`
bt3_combine <- function(res, d) {
  pred <- rbindlist(lapply(res, `[[`, "pred"), use.names = TRUE, fill = TRUE)
  pred <- pred[order(match(game_id, d$game_id))]
  diag_list <- lapply(res, `[[`, "diag")
  diag <- if (all(vapply(diag_list, is.null, logical(1)))) NULL else rbindlist(diag_list, use.names = TRUE, fill = TRUE)
  if (!is.null(diag) && "wk" %in% names(diag)) diag <- diag[order(wk)]
  secs <- Reduce(`+`, lapply(res, `[[`, "seconds"))
  list(pred = pred, diag = diag, seconds = secs)
}

#' PSOCK cluster whose workers have this project's library and code loaded
bt3_cluster <- function(workers, root = getwd()) {
  if (is.null(workers) || workers <= 1L) return(NULL)
  cl <- parallel::makePSOCKcluster(workers)
  root <- normalizePath(root, winslash = "/")
  parallel::clusterCall(cl, function(lib, root) {
    .libPaths(lib)
    setwd(root)
    suppressPackageStartupMessages(library(data.table))
    e <- globalenv()
    sys.source(file.path(root, "backtest", "v3", "common.R"), envir = e)
    bt3_source_all(root, envir = e)
    invisible(NULL)
  }, .libPaths(), root)
  cl
}

#' Round numeric columns for committed CSVs
bt3_signif <- function(x, digits = 6) x[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, digits) else v)]
