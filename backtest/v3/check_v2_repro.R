#!/usr/bin/env Rscript
# =============================================================================
# Blend research v3: confirm that re-running the v2 stages reproduces v2's
# committed outputs byte for byte (v3 changes no v2 code).
#
#   Rscript backtest/v2/sprint.R --out <rerun> --stages screen,models,handicap,controls
#   Rscript backtest/v2/report.R <rerun>
#   Rscript backtest/v3/check_v2_repro.R <rerun> reports/2026-10-01/blend-research/v2_reproduction.csv
#
# Writes one row per file with both sha256s; exits 1 if any file differs.
# run_meta.json is not compared (it holds timestamps and timings).
# =============================================================================

suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) stop("usage: Rscript backtest/v3/check_v2_repro.R <rerun dir> <out csv>")
rerun <- args[1]; out <- args[2]
committed <- file.path("reports", "2026-09-30", "validation-sprint")
files <- c("screen/features.csv", "screen/joint.csv", "models/scores_tune.csv", "models/reliability_tune.csv",
           "models/boosting_rounds.csv", "models/control_shuffled_labels.csv", "handicap/scores_tune.csv",
           "handicap/betting_tune.csv", "tracking/moneyline_tune.csv", "tracking/handicap_tune.csv", "TABLES.md")
sha <- function(f) if (file.exists(f)) digest::digest(file = f, algo = "sha256") else NA_character_
res <- data.table(file = files,
                  sha256_committed = vapply(file.path(committed, files), sha, character(1), USE.NAMES = FALSE),
                  sha256_rerun = vapply(file.path(rerun, files), sha, character(1), USE.NAMES = FALSE))
res[, identical := !is.na(sha256_rerun) & sha256_committed == sha256_rerun]
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
fwrite(res, out, eol = "\n")
print(res[, .(file, identical)])
cat(sprintf("%d of %d v2 files reproduced byte for byte\n", sum(res$identical), nrow(res)))
quit(status = if (all(res$identical)) 0L else 1L)
