# =============================================================================
# Test-run policy: failures, errors and unapproved skips all fail the run.
# Used by scripts/run_tests.R (CI) and unit-tested in test-test-policy.R.
# =============================================================================

#' TRUE for each skip reason matching at least one allowlist regex
classify_skips <- function(reasons, allow_patterns) {
  vapply(reasons, function(r) any(vapply(allow_patterns, grepl, logical(1), x = r, perl = TRUE)),
         logical(1), USE.NAMES = FALSE)
}

#' Decide pass/fail for a testthat run and build a printable summary
summarize_test_run <- function(df, skips, allowed) {
  n_fail <- sum(df$failed)
  n_err <- sum(df$error)
  bad_skips <- skips[!allowed, , drop = FALSE]
  lines <- sprintf("tests=%d passed=%d failed=%d errors=%d skipped=%d unapproved_skips=%d",
                   nrow(df), sum(df$passed), n_fail, n_err, nrow(skips), nrow(bad_skips))
  if (nrow(bad_skips)) {
    lines <- c(lines, "Unapproved skips:",
               sprintf("  %s :: %s :: %s", bad_skips$file, bad_skips$test, bad_skips$reason))
  }
  list(ok = n_fail == 0 && n_err == 0 && nrow(bad_skips) == 0, lines = lines)
}
