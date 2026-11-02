# Compare a from-scratch rerun of the A3 research (rerun_research.sh) with the committed outputs, file by file.
# Run from the repository root:  Rscript reports/2026-10-28/feasibility/compare_research.R <rerun_dir> <out_csv>
suppressPackageStartupMessages(library(data.table))
a <- commandArgs(trailingOnly = TRUE); rerun <- a[1]; out_csv <- a[2]
R <- file.path("reports", "2026-10-28", "a3-research")
files <- c("cluster_icc.csv", "cluster_design_effects.csv", "late_tests.csv", "late_s1_sensitivity.csv", "late_movement.csv",
           "joint_size.csv", "joint_size_linear.csv", "s4_power.csv", "s4-null-diagnostic.csv", "s4_nulls.csv", "flex-games.csv")
res <- rbindlist(lapply(files, function(f) {
  committed <- if (f == "flex-games.csv") file.path(R, "data", f) else file.path(R, f)
  if (!file.exists(file.path(rerun, f)) || !file.exists(committed)) {
    return(data.table(file = f, rows = NA_integer_, identical = FALSE, max_abs_diff = NA_real_,
                      note = sprintf("missing: %s", paste(c(if (!file.exists(file.path(rerun, f))) "rerun", if (!file.exists(committed)) "committed"), collapse = ", "))))
  }
  x <- fread(file.path(rerun, f)); y <- fread(committed)
  same <- isTRUE(all.equal(x, y, check.attributes = FALSE, tolerance = 0))
  num <- intersect(names(x)[vapply(x, is.numeric, logical(1))], names(y)[vapply(y, is.numeric, logical(1))])
  d <- if (identical(dim(x), dim(y)) && length(num)) max(vapply(num, function(c) max(abs(x[[c]] - y[[c]]), na.rm = TRUE), numeric(1))) else NA_real_
  data.table(file = f, rows = nrow(x), identical = same, max_abs_diff = d,
             note = if (same) "" else if (!identical(dim(x), dim(y))) sprintf("dims %s vs committed %s", paste(dim(x), collapse = "x"), paste(dim(y), collapse = "x")) else "values differ")
}))
fwrite(res, out_csv)
print(res)
