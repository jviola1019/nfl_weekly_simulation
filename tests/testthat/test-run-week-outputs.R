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

test_that("run_week.R makes no HTML report and opens no browser", {
  code <- run_week_code()
  expect_false(any(grepl("export_moneyline_comparison_html|browseURL|NFLvsmarket|baseline_report\\.html|auto_open", code)))
})

test_that("run_week.R still writes both audit CSVs, and the games table no longer depends on props", {
  code <- run_week_code()
  expect_true(any(grepl('"baseline_games.csv"', code, fixed = TRUE)))
  expect_true(any(grepl('"baseline_props.csv"', code, fixed = TRUE)))
  build <- grep("last_comparison_tbl <- build_moneyline_comparison_table(", code, fixed = TRUE)
  expect_length(build, 1L)
  props_block <- grep("if (exists(\"RUN_PLAYER_PROPS\") && isTRUE(RUN_PLAYER_PROPS)) {", code, fixed = TRUE)
  props_end <- grep("^  }$", code)
  props_end <- props_end[props_end > props_block][1]
  expect_gt(build, props_end)
})
