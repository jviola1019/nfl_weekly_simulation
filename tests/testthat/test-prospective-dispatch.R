# The weekly program's dispatcher (reports/2026-10-29/hypotheses/prospective_dispatch.R): when a step runs again
# after a failure. On 2026-11-03 week 9's preclose_predict failed three times in 30 minutes on a DNS outage and was
# marked missed, with its deadline (the week's first kickoff) still 54 hours ahead. A step now gets three tries at
# successive starts, then one an hour after its last failure, until its deadline, and at most twelve in all.
dispatch <- load_script_functions(file.path(PROJECT_ROOT, "reports", "2026-10-29", "hypotheses", "prospective_dispatch.R"),
                                  c("TRIES", "RETRY_GAP", "MAX_TRIES", "step_state"))

t0 <- as.POSIXct("2026-11-03 18:30:00", tz = "UTC")
step <- data.frame(week = 9L, step = "preclose_predict", due = t0, deadline = as.POSIXct("2026-11-06 01:15:00", tz = "UTC"))

# a store whose week-9 done/ holds `fails` failure markers, the last written at `last`
store_with_failures <- function(fails, last) {
  store <- withr::local_tempdir(.local_envir = parent.frame())
  d <- file.path(store, "w09", "done")
  dir.create(d, recursive = TRUE)
  for (i in seq_len(fails)) {
    f <- file.path(d, sprintf("preclose_predict.fail%d", i))
    file.create(f)
    Sys.setFileTime(f, last - (fails - i) * 900)
  }
  store
}

test_that("a step that failed fewer than three times runs at the next start", {
  store <- store_with_failures(2L, t0 + 900)
  expect_equal(dispatch$step_state(store, step, t0 + 960), "due")
})

test_that("after three failures a step waits an hour from the last one, and is not missed before its deadline", {
  store <- store_with_failures(3L, t0 + 2700)
  expect_equal(dispatch$step_state(store, step, t0 + 2700 + 1800), "backoff")
  expect_equal(dispatch$step_state(store, step, t0 + 2700 + 3660), "due")
})

test_that("a step is missed at its deadline, or after twelve failures", {
  expect_equal(dispatch$step_state(store_with_failures(3L, t0 + 2700), step, step$deadline), "expire")
  expect_equal(dispatch$step_state(store_with_failures(12L, t0 + 20 * 3600), step, t0 + 22 * 3600), "expire")
})

test_that("a finished step stays finished", {
  store <- store_with_failures(1L, t0)
  file.create(file.path(store, "w09", "done", "preclose_predict.ok"))
  expect_equal(dispatch$step_state(store, step, t0 + 3600), "ok")
})
