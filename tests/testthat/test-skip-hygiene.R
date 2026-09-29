# Static guards on the test suite itself: a test must not pass or skip for a
# reason the runner (scripts/run_tests.R) cannot see.

# R sources under tests/testthat/, excluding this file (it names the banned
# patterns) and any listed exceptions
test_sources <- function(exclude = character()) {
  files <- list.files(file.path(PROJECT_ROOT, "tests", "testthat"), pattern = "\\.R$",
                      recursive = TRUE, full.names = TRUE)
  files[!basename(files) %in% c("test-skip-hygiene.R", exclude)]
}

# "file:line" for every line matching a fixed string or a regex
find_hits <- function(files, pattern, fixed = TRUE) {
  hits <- character()
  for (f in files) {
    txt <- readLines(f, warn = FALSE, encoding = "UTF-8")
    ln <- grep(pattern, txt, fixed = fixed, perl = !fixed)
    if (length(ln)) hits <- c(hits, sprintf("%s:%s", basename(f), paste(ln, collapse = ",")))
  }
  hits
}

test_that("LIVE skips go through the connectivity-checked helper only", {
  # skip("LIVE: ...") is allowlisted, so calling it directly would skip without
  # checking that the host is really unreachable. Use skip_live()/with_live().
  hits <- find_hits(test_sources(exclude = "helper-live.R"), "skip\\s*\\(.*LIVE:", fixed = FALSE)
  expect_equal(hits, character())
})

test_that("skip_live() and with_live() skip only for an unreachable host", {
  # .invalid never resolves (RFC 2606)
  expect_false(live_host_reachable("nonexistent.invalid", timeout = 2))
  expect_condition(skip_live("nonexistent.invalid", timeout = 2),
                   "LIVE: nonexistent\\.invalid unreachable", class = "skip")
  expect_condition(with_live("nonexistent.invalid", stop("download failed")),
                   "LIVE: nonexistent\\.invalid unreachable", class = "skip")
  expect_identical(with_live("nonexistent.invalid", 42), 42)
  # A reachable host turns the same error into a failure, not a skip
  skip_live("github.com")
  expect_error(with_live("github.com", stop("real failure")), "real failure")
})

test_that("no test passes vacuously or swallows errors into an empty result", {
  files <- test_sources()
  expect_equal(find_hits(files, "expect_true(TRUE)"), character())
  expect_equal(find_hits(files, "error = function(e) tibble::tibble()"), character())
})

test_that("the hygiene scan sees the suite and would catch a planted violation", {
  expect_gt(length(test_sources()), 20)
  planted <- tempfile(fileext = ".R")
  writeLines(c(paste0("skip(", "\"LIVE: example.com unreachable\")"), paste0("expect_true(", "TRUE)")), planted)
  expect_length(find_hits(planted, "skip\\s*\\(.*LIVE:", fixed = FALSE), 1)
  expect_length(find_hits(planted, "expect_true(TRUE)"), 1)
})
