# =============================================================================
# The default suite makes no odds request. Live checks live in tests/live/ and run
# only through scripts/odds_live_smoke.R (roadmap D1 gate).
# =============================================================================

odds_test_files <- function() {
  files <- list.files(file.path(PROJECT_ROOT, "tests", "testthat"), pattern = "^test-odds-.*\\.R$", full.names = TRUE)
  files[!basename(files) %in% "test-odds-no-live.R"]
}

# Calls of `fn(...)` in `txt` (multi-line, balanced parentheses) that do not name `arg`
calls_without_arg <- function(txt, fn, arg) {
  s <- paste(txt, collapse = "\n")
  starts <- gregexpr(paste0(fn, "("), s, fixed = TRUE)[[1]]
  if (starts[1] < 0) return(character())
  chars <- strsplit(s, "", fixed = TRUE)[[1]]
  out <- character()
  for (st in starts) {
    j <- st + nchar(fn)
    depth <- 0L
    while (j <= length(chars)) {
      if (chars[j] == "(") depth <- depth + 1L
      if (chars[j] == ")") { depth <- depth - 1L; if (depth == 0L) break }
      j <- j + 1L
    }
    call <- paste(chars[st:min(j, length(chars))], collapse = "")
    if (!grepl(arg, call, fixed = TRUE)) out <- c(out, call)
  }
  out
}

test_that("the odds tests use the fake fetch seam, never a live helper or the real network call", {
  expect_gt(length(odds_test_files()), 5)
  for (f in odds_test_files()) {
    txt <- readLines(f, warn = FALSE, encoding = "UTF-8")
    expect_false(any(grepl("skip_live\\(|with_live\\(|live_host_reachable\\(", txt)), info = basename(f))
    expect_false(any(grepl("Sys.setenv\\(\\s*NFL_ODDS_FORBID_LIVE", txt)), info = basename(f))
    if (basename(f) != "test-odds-http.R") {
      expect_false(any(grepl("odds_http_get", txt)), info = basename(f))   # only the guard test names it
      # nor may a test lift the live guard another way (controller ruling R3)
      expect_false(any(grepl("local_envvar\\([^)]*NFL_ODDS_FORBID_LIVE|Sys.unsetenv\\([^)]*NFL_ODDS_FORBID_LIVE", txt)), info = basename(f))
    }
    # provider_nflverse()'s default loader is nflreadr, which the live guard does not stop (ruling R5)
    expect_equal(calls_without_arg(txt, "provider_nflverse", "load_schedules_fn"), character(), info = basename(f))
  }
})

test_that("the scan for provider_nflverse() calls sees a call that spans lines", {
  expect_length(calls_without_arg(c("p <- provider_nflverse(", "  cfg = x)"), "provider_nflverse", "load_schedules_fn"), 1)
  expect_length(calls_without_arg(c("p <- provider_nflverse(cfg = x,", "  load_schedules_fn = f)"), "provider_nflverse", "load_schedules_fn"), 0)
})

test_that("the live guard is on for the whole suite, and the live tests are outside tests/testthat", {
  expect_identical(Sys.getenv("NFL_ODDS_FORBID_LIVE"), "1")
  expect_true(file.exists(file.path(PROJECT_ROOT, "tests", "live", "test-odds-live.R")))
  expect_false(file.exists(file.path(PROJECT_ROOT, "tests", "testthat", "test-odds-live.R")))
  runner <- readLines(file.path(PROJECT_ROOT, "scripts", "run_tests.R"), warn = FALSE)
  expect_true(any(grepl('test_dir("tests/testthat"', runner, fixed = TRUE)))
  wf <- yaml::read_yaml(file.path(PROJECT_ROOT, ".github", "workflows", "odds-live-smoke.yml"))
  on <- if (!is.null(wf[["on"]])) wf[["on"]] else wf[["TRUE"]]
  expect_identical(names(on), "workflow_dispatch")        # manual only
})

test_that("the live-smoke workflow installs every package config.R requires", {
  # config.R stops without them, so a fresh runner would fail the smoke before any request
  wf <- yaml::read_yaml(file.path(PROJECT_ROOT, ".github", "workflows", "odds-live-smoke.yml"))
  install <- Filter(function(s) identical(s$name, "Install dependencies"), wf$jobs$smoke$steps)[[1]]$run
  installed <- regmatches(install, gregexpr('(?<=")[A-Za-z0-9.]+(?=")', install, perl = TRUE))[[1]]
  cfg <- paste(readLines(file.path(PROJECT_ROOT, "config.R"), warn = FALSE), collapse = "\n")
  required <- regmatches(cfg, gregexpr('(?<=requireNamespace\\(")[A-Za-z0-9.]+', cfg, perl = TRUE))[[1]]
  expect_gt(length(required), 0)
  expect_equal(setdiff(required, installed), character())
})

test_that("no provider or HTTP code can reach a host outside the owner-approved keyless set", {
  code <- unlist(lapply(list.files(file.path(PROJECT_ROOT, "R", "odds"), pattern = "\\.R$", full.names = TRUE),
                        readLines, warn = FALSE, encoding = "UTF-8"))
  urls <- unique(unlist(regmatches(code, gregexpr("https?://[A-Za-z0-9.-]+", code))))
  hosts <- sub("^https?://", "", urls)
  expect_true(all(hosts %in% c("github.com", "example.test")), info = paste(hosts, collapse = ", "))   # hosts appear only in comments
})
