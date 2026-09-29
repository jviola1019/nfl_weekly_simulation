# Every literal source("...") target in the runtime entry points must exist,
# so deleting a file can never silently break run_week.R.

literal_source_targets <- function(path) {
  txt <- readLines(path, warn = FALSE)
  txt <- txt[!grepl("^\\s*#", txt)]
  hits <- regmatches(txt, gregexpr('source\\(\\s*"[^"]+\\.R"', txt))
  unique(sub('source\\(\\s*"', "", sub('"$', "", unlist(hits))))
}

test_that("literal source() targets in entry points exist", {
  entry <- c("run_week.R", "NFLsimulation.R", "NFLmarket.R",
             file.path("R", list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$")))
  targets <- unique(unlist(lapply(file.path(PROJECT_ROOT, entry), literal_source_targets)))
  missing <- targets[!file.exists(file.path(PROJECT_ROOT, targets))]
  expect_equal(missing, character())
})
