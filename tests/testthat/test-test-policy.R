test_that("classify_skips accepts only allowlisted reasons", {
  allow <- c("^LIVE: ", "^KNOWN-DEFECT (M|P|S|U|T|H|D|SEC)[0-9]+: ")
  reasons <- c("LIVE: api.sleeper.app unreachable", "KNOWN-DEFECT P1: edge label is column-wide",
               "On CRAN", "correlated_props.R not found", "empty test", "KNOWN-DEFECT X9: bogus id")
  expect_equal(classify_skips(reasons, allow), c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE))
})

test_that("the shipped allowlist does not allow On CRAN skips", {
  allow <- trimws(readLines(file.path(PROJECT_ROOT, "tests", "skip_allowlist.txt"), warn = FALSE))
  allow <- allow[nzchar(allow) & !startsWith(allow, "#")]
  expect_false(classify_skips("On CRAN", allow))
  expect_true(classify_skips("LIVE: github.com unreachable", allow))
})

test_that("classify_skips handles no skips", {
  expect_equal(classify_skips(character(), "^LIVE: "), logical())
})

test_that("summarize_test_run fails on failures, errors or unapproved skips", {
  df <- data.frame(failed = c(0L, 0L), error = c(FALSE, FALSE), skipped = c(FALSE, TRUE), passed = c(3L, 0L))
  skips <- data.frame(file = "test-a.R", test = "t", reason = "empty test")
  expect_false(summarize_test_run(df, skips, allowed = FALSE)$ok)
  expect_true(summarize_test_run(df, skips, allowed = TRUE)$ok)
  df$failed[1] <- 1L
  expect_false(summarize_test_run(df, skips, allowed = TRUE)$ok)
})

test_that("KNOWN-DEFECT skips must cite an ID listed in the audit ledgers", {
  ids <- known_defect_ids(file.path(PROJECT_ROOT, "reports", c("2026-09-28/AUDIT.md", "2026-09-29/AUDIT-ADDENDUM.md")))
  expect_true(all(c("M1", "M15", "M16", "M17", "P2", "P3", "P13", "SEC4") %in% ids))
  expect_false("M999" %in% ids)
  reasons <- c("KNOWN-DEFECT M999: bogus", "KNOWN-DEFECT M15: snap loader", "LIVE: github.com unreachable",
               "KNOWN-DEFECT: no id")
  expect_equal(classify_known_defects(reasons, ids), c(FALSE, TRUE, TRUE, FALSE))
})

test_that("known_defect_ids splits combined IDs", {
  f <- withr::local_tempfile(fileext = ".md")
  writeLines(c("| ID | Sev |", "|---|---|", "| P2/P3 | High |", "| M4 | Critical |", "text | X1 |"), f)
  expect_equal(sort(known_defect_ids(f)), c("M4", "P2", "P3"))
})
