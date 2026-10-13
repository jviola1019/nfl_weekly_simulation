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

test_that("gm_input_drift names the inputs that changed", {
  a <- list(injury = "full", weather = "full", market = "full", calibration = "none")
  expect_equal(gm_input_drift(a, a), character())
  expect_equal(gm_input_drift(a, modifyList(a, list(injury = "partial", market = "partial"))), c("injury", "market"))
  expect_equal(gm_input_drift(NULL, a), character())   # records made before inputs were kept
})

test_that("input statuses survive a write and read", {
  dir <- withr::local_tempdir()
  inputs <- list(injury = "full", weather = "partial_fallback", market = "full", calibration = "none",
                 weather_fallback_games = c("2024_15_WAS_NO", "2024_15_KC_CLE"), market_missing_games = character())
  gm_write_inputs(inputs, dir)
  back <- gm_read_inputs(dir)
  expect_equal(back$weather_fallback_games, "2024_15_KC_CLE;2024_15_WAS_NO")
  expect_equal(back$market_missing_games, "")
  expect_equal(gm_input_drift(inputs, back), character())
  expect_null(gm_read_inputs(withr::local_tempdir()))
})

test_that("gm_input_status reads the data-quality tracker", {
  withr::defer(reset_data_quality())
  reset_data_quality()
  update_injury_quality("partial", missing_seasons = "2024")
  update_weather_quality("partial_fallback", fallback_games = c("b", "a"))
  s <- gm_input_status()
  expect_equal(s$injury, "partial")
  expect_equal(s$weather, "partial_fallback")
  expect_equal(s$weather_fallback_games, c("a", "b"))
})

test_that("gm_attribute flags input drift between recorded commits", {
  root <- withr::local_tempdir()
  write_run <- function(name, p, injury) {
    dir.create(file.path(root, name))
    utils::write.csv(data.frame(game_id = c("a", "b"), p = p), file.path(root, name, "final_numeric.csv"), row.names = FALSE)
    writeLines("{}", file.path(root, name, "meta.json"))
    gm_write_inputs(list(injury = injury, weather = "full", market = "full", calibration = "none"), file.path(root, name))
  }
  write_run("c1", c(0.5, 0.6), "full")
  write_run("c2", c(0.5, 0.7), "partial")
  out <- capture.output(gm_attribute(root, c("c1", "c2")))
  expect_true(any(grepl("INPUT DRIFT at c2 vs baseline c1: injury", out, fixed = TRUE)))
})

# 'C' (0x43) sorts before '_' (0x5F) in C order, but a Windows locale puts "LA_SF" first, so a locale-dependent
# sort makes Linux CI and a Windows run disagree and report a false INPUT DRIFT. testthat runs tests with
# LC_COLLATE=C, which would hide that, so these tests also run the code under the machine's own locale ("").
test_that("gm_flat sorts in C order, so the same game ids flatten identically in any locale", {
  ids <- c("2024_15_LA_SF", "2024_15_LAC_TB")
  expect_equal(gm_flat(ids), "2024_15_LAC_TB;2024_15_LA_SF")
  expect_equal(withr::with_collate("", gm_flat(ids)), "2024_15_LAC_TB;2024_15_LA_SF")
})

test_that("gm_input_status sorts the game-id vectors in C order too", {
  withr::defer(reset_data_quality())
  reset_data_quality()
  ids <- c("2024_15_LA_SF", "2024_15_LAC_TB")
  update_weather_quality("partial_fallback", fallback_games = ids)
  update_market_quality("partial", missing_games = ids)
  s <- withr::with_collate("", gm_input_status())
  expect_equal(s$weather_fallback_games, c("2024_15_LAC_TB", "2024_15_LA_SF"))
  expect_equal(s$market_missing_games, c("2024_15_LAC_TB", "2024_15_LA_SF"))
})

test_that("gm_drift_lines prints golden and current for every drifted field", {
  golden <- list(injury = "full", weather = "partial_fallback",
                 weather_fallback_games = "2024_15_KC_CLE;2024_15_WAS_NO")
  current <- list(injury = "partial", weather = "partial_fallback",
                  weather_fallback_games = c("2024_15_WAS_NO", "2024_15_NYJ_JAX"))
  expect_equal(gm_drift_lines(golden, current), c(
    "INPUT DRIFT: injury golden=full current=partial",
    paste0("INPUT DRIFT: weather_fallback_games golden=2024_15_KC_CLE;2024_15_WAS_NO",
           " current=2024_15_NYJ_JAX;2024_15_WAS_NO")))
  expect_equal(gm_drift_lines(golden, golden), character())
  expect_equal(gm_drift_lines(NULL, current), character())   # golden recorded before inputs were kept
})

test_that("gm_drift_lines names a field that only one side has instead of printing nothing", {
  dir <- withr::local_tempdir()
  gm_write_inputs(list(injury = "full", weather = "full"), dir)   # golden recorded before `extra_field` existed
  golden <- gm_read_inputs(dir)
  current <- list(injury = "full", weather = "full", extra_field = "x")
  expect_equal(gm_input_drift(golden, current), "extra_field")
  expect_equal(gm_drift_lines(golden, current), "INPUT DRIFT: extra_field golden= current=x")
  expect_equal(gm_drift_lines(current, golden), "INPUT DRIFT: extra_field golden=x current=")
})
