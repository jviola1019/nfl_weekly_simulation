#!/usr/bin/env Rscript
# Run the testthat suite and enforce the skip policy (R/test_policy.R).
# Exit 0 only with 0 failures, 0 errors and every skip allowlisted.
if (!file.exists("tests/skip_allowlist.txt")) stop("Run from the repository root")
source("R/test_policy.R")
res <- testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
rows <- list()
for (r in res) for (x in r$results) if (inherits(x, "expectation_skip")) {
  rows[[length(rows) + 1]] <- data.frame(file = r$file, test = r$test,
                                         reason = sub("^Reason: ", "", conditionMessage(x)))
}
skips <- if (length(rows)) do.call(rbind, rows) else data.frame(file = character(), test = character(), reason = character())
allow <- trimws(readLines("tests/skip_allowlist.txt", warn = FALSE))
allow <- allow[nzchar(allow) & !startsWith(allow, "#")]
out <- summarize_test_run(df, skips, classify_skips(skips$reason, allow))
cat("\n", paste(out$lines, collapse = "\n"), "\n", sep = "")
if (nrow(skips)) { cat("All skips:\n"); print(as.data.frame(table(reason = skips$reason)), row.names = FALSE) }
quit(status = if (out$ok) 0 else 1)
