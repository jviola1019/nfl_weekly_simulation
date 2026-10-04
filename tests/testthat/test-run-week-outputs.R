# =============================================================================
# run_week.R outputs (checkpoint A8): a web bundle for the local app and the two
# audit CSVs; no HTML report and no browser. run_week.R runs the whole engine, so
# these checks read its source; the end-to-end run is the close-out demo.
# =============================================================================

run_week_code <- function() {
  src <- readLines(file.path(.test_project_root, "run_week.R"), warn = FALSE, encoding = "UTF-8")
  src[!grepl("^\\s*#", src)]
}

test_that("run_week.R writes the web bundle once, after the simulation, and reports it", {
  code <- run_week_code()
  expect_equal(sum(grepl("write_sim_bundle(", code, fixed = TRUE)), 1L)
  expect_equal(sum(grepl("report_sim_bundle(sim_bundle)", code, fixed = TRUE)), 1L)
  expect_lt(grep('source("NFLsimulation.R")', code, fixed = TRUE), grep("write_sim_bundle(", code, fixed = TRUE))
  # git state is read before the run rewrites the tracked artifacts/*.csv
  expect_lt(grep("run_git <- sb_git_state()", code, fixed = TRUE), grep('source("NFLsimulation.R")', code, fixed = TRUE))
})
