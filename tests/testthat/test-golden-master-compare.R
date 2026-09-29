source(file.path(PROJECT_ROOT, "scripts", "golden_master.R"), local = TRUE)   # defines functions; main() only runs via Rscript

test_that("gm_diff reports changed numeric columns per game", {
  g <- data.frame(game_id = c("a", "b"), p = c(0.5, 0.6), q = c(1, 2))
  c1 <- data.frame(game_id = c("b", "a"), p = c(0.6, 0.55), q = c(2, 1))
  d <- gm_diff(g, c1)
  expect_equal(d$column, "p"); expect_equal(d$n_games_changed, 1L); expect_equal(d$max_abs_diff, 0.05)
  expect_equal(nrow(gm_diff(g, g)), 0L)
  expect_error(gm_diff(g, c1[1, ]), "game_id")
})

test_that("gm_diff treats NA-to-value changes as infinite differences", {
  g <- data.frame(game_id = c("a", "b"), p = c(NA, 0.6))
  expect_equal(gm_diff(g, g)$column, character())
  d <- gm_diff(g, data.frame(game_id = c("a", "b"), p = c(0.4, 0.6)))
  expect_equal(d$max_abs_diff, Inf)
})

test_that("gm_attribute prints commit-by-commit and head-vs-baseline diffs", {
  root <- withr::local_tempdir()
  write_run <- function(name, p) {
    dir.create(file.path(root, name))
    utils::write.csv(data.frame(game_id = c("a", "b"), p = p), file.path(root, name, "final_numeric.csv"), row.names = FALSE)
    writeLines("{}", file.path(root, name, "meta.json"))
  }
  write_run("c1", c(0.5, 0.6)); write_run("c1-rep2", c(0.5, 0.6))
  write_run("c2", c(0.5, 0.6)); write_run("c3", c(0.52, 0.6))
  out <- capture.output(gm_attribute(root, c("c1", "c2", "c3")))
  expect_true(any(grepl("determinism: c1 recorded twice", out)))
  expect_true(any(grepl("c2 vs previous commit c1", out)))
  expect_equal(sum(grepl("golden master: no differences", out)), 2L)   # determinism and c2
  expect_true(any(grepl("head c3 vs baseline c1", out)))
  expect_true(any(grepl("^ *p +1 +0.02", out)))
})
