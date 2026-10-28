# Build the close-anchored Tune table once (v2's inputs, 2018-2022; the loaders refuse 2025) and cache it.
#   Rscript research-table.R <out_rds>          (run from the a3dry root)
args <- commandArgs(trailingOnly = TRUE)
e <- environment()
for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R", "blends.R",
            "calibrators.R", "metrics.R", "controls.R")) sys.source(file.path("backtest", f), envir = e)
for (f in c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s3_skill.R", "s4_controls.R",
            "s5_curves.R", "s5_scores.R", "s5_anova.R", "reproduce_v2.R")) sys.source(file.path("backtest", "vvf", f), envir = e)
source(file.path("backtest", "vvf", "run_a3b_close.R"), local = e)
tab <- vvf_a3b_table()
full <- tab$full
saveRDS(list(full = full, features = VVF_V2_FEATURES, tune = VVF_V2_TUNE,
             joint_sets = if (exists("VVF_V2_JOINT_SETS")) VVF_V2_JOINT_SETS else NULL), args[1])
cat("rows", nrow(full), " tune rows", nrow(full[season %in% VVF_V2_TUNE]), "\n")
cat("columns:", paste(names(full), collapse = " "), "\n")
cat("joint sets:", if (exists("VVF_V2_JOINT_SETS")) paste(names(VVF_V2_JOINT_SETS), collapse = ", ") else "none", "\n")
