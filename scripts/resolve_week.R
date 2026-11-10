#!/usr/bin/env Rscript
# =============================================================================
# The week and season a run simulates, for .github/workflows/weekly-sim.yml (C1, 2026-10-20)
#   Rscript scripts/resolve_week.R [week] [season]
# Empty arguments mean the upcoming week from the nflverse schedule (R/run_config.R).
# Prints "week=<n>" and "season=<yyyy>", and appends the same two lines to the file $GITHUB_OUTPUT
# names when a workflow step sets it. The workflow never redirects stdout there: R's startup can
# print to stdout (renv's "- The project is out-of-sync ..."), and one such line fails the step.
# The "Auto-resolved ..." line goes to stderr.
# =============================================================================

source("R/run_config.R")
args <- commandArgs(trailingOnly = TRUE)
target <- resolve_run_target(parse_run_args(args[nzchar(args)]))
lines <- c(sprintf("week=%d", target$week), sprintf("season=%d", target$season))
writeLines(lines)
github_output <- Sys.getenv("GITHUB_OUTPUT")
if (nzchar(github_output)) {
  con <- file(github_output, open = "ab")   # binary append: LF on every OS
  writeLines(lines, con, sep = "\n")
  close(con)
}
