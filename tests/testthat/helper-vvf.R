#' A fresh environment with the v1 backtest helpers and the named VVF files
#' (backtest/vvf/) sourced in order. VVF code reads paths relative to the
#' repository root, so tests that load data call withr::local_dir(PROJECT_ROOT).
vvf_test_env <- function(vvf_files, v1_files = "common.R") {
  e <- new.env(parent = globalenv())
  for (f in v1_files) sys.source(file.path(PROJECT_ROOT, "backtest", f), envir = e)
  for (f in vvf_files) sys.source(file.path(PROJECT_ROOT, "backtest", "vvf", f), envir = e)
  e
}

#' Every v1 helper the VVF feature builder and screens call
VVF_TEST_V1_FILES <- c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R",
                       "blends.R", "calibrators.R", "metrics.R", "controls.R")
