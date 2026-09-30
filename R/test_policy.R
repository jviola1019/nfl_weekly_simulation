# =============================================================================
# Test-run policy: failures, errors and unapproved skips all fail the run.
# Used by scripts/run_tests.R (CI) and unit-tested in test-test-policy.R.
# =============================================================================

#' TRUE for each skip reason matching at least one allowlist regex
classify_skips <- function(reasons, allow_patterns) {
  vapply(reasons, function(r) any(vapply(allow_patterns, grepl, logical(1), x = r, perl = TRUE)),
         logical(1), USE.NAMES = FALSE)
}

#' Audit IDs listed in the first column of the audit ledgers' tables ("| M14 |",
#' "| P2/P3 |" -> P2, P3)
known_defect_ids <- function(paths) {
  ids <- character()
  for (p in paths) {
    lines <- readLines(p, warn = FALSE, encoding = "UTF-8")
    m <- regmatches(lines, regexec("^\\|\\s*([A-Z]+[0-9]+(/[A-Z]*[0-9]+)*)\\s*\\|", lines))
    cells <- vapply(m, function(x) if (length(x)) x[2] else NA_character_, character(1))
    for (cell in cells[!is.na(cells)]) {
      parts <- strsplit(cell, "/", fixed = TRUE)[[1]]
      prefix <- sub("[0-9]+$", "", parts[1])
      ids <- c(ids, ifelse(grepl("^[0-9]+$", parts), paste0(prefix, parts), parts))
    }
  }
  unique(ids)
}

#' TRUE for each skip reason that is not a KNOWN-DEFECT skip or cites a listed audit ID
classify_known_defects <- function(reasons, ids) {
  cited <- sub("^KNOWN-DEFECT ([A-Z]+[0-9]+):.*$", "\\1", reasons)
  is_kd <- grepl("^KNOWN-DEFECT", reasons)
  !is_kd | (grepl("^KNOWN-DEFECT [A-Z]+[0-9]+:", reasons) & cited %in% ids)
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
