#!/usr/bin/env Rscript
# =============================================================================
# Blend research v3: confirm that a second full run of backtest/v3/sprint.R
# reproduces every CSV of the committed run byte for byte. compute/seconds.csv
# and run_meta.json hold timings and are not compared.
#
#   Rscript backtest/v3/sprint.R --out <rerun> --workers 8
#   Rscript backtest/v3/check_rerun.R reports/2026-10-01/blend-research <rerun> \
#     reports/2026-10-01/blend-research/determinism.csv
#
# Exits 1 if any file differs or is missing.
# =============================================================================

suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L) stop("usage: Rscript backtest/v3/check_rerun.R <committed dir> <rerun dir> <out csv>")
a <- args[1]; b <- args[2]; out <- args[3]
files <- sort(list.files(a, pattern = "\\.csv$", recursive = TRUE))
files <- setdiff(files, c("compute/seconds.csv", "v2_reproduction.csv", "determinism.csv"))
sha <- function(f) if (file.exists(f)) digest::digest(file = f, algo = "sha256") else NA_character_
res <- data.table(file = files,
                  sha256_committed = vapply(file.path(a, files), sha, character(1), USE.NAMES = FALSE),
                  sha256_rerun = vapply(file.path(b, files), sha, character(1), USE.NAMES = FALSE))
res[, identical := !is.na(sha256_rerun) & sha256_committed == sha256_rerun]
fwrite(res, out, eol = "\n")
cat(sprintf("%d of %d CSVs reproduced byte for byte\n", sum(res$identical), nrow(res)))
quit(status = if (all(res$identical)) 0L else 1L)
