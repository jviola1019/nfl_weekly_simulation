#!/usr/bin/env Rscript
# =============================================================================
# The week and season a run simulates, for .github/workflows/weekly-sim.yml (C1, 2026-10-20)
#   Rscript scripts/resolve_week.R [week] [season]
# Empty arguments mean the upcoming week from the nflverse schedule (R/run_config.R).
# Prints "week=<n>" and "season=<yyyy>", the lines the workflow appends to $GITHUB_OUTPUT;
# the "Auto-resolved ..." line goes to stderr, so it lands in the log, not in the outputs.
# =============================================================================

source("R/run_config.R")
args <- commandArgs(trailingOnly = TRUE)
target <- resolve_run_target(parse_run_args(args[nzchar(args)]))
cat(sprintf("week=%d\nseason=%d\n", target$week, target$season))
