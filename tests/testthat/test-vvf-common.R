# VVF shared helpers (backtest/vvf/common.R): the 2025 seal, the forbidden
# 2024-2025 price file, the sha256-locked inputs ported from PR #205, and the
# geometry helpers the features use.

vc <- vvf_test_env("common.R")

test_that("the season guard refuses the sealed season and anything after the input ceiling", {
  withr::local_dir(PROJECT_ROOT)
  expect_error(vc$vvf_guard_seasons(c(2023L, 2025L), 2024L, "probe"), "sealed-season guard")
  expect_error(vc$vvf_guard_seasons(2026L, 2026L, "probe", sealed = 2025L), NA)
  expect_error(vc$vvf_guard_seasons(2025L, 2026L, "probe", sealed = 2025L), "sealed-season guard")
  expect_invisible(vc$vvf_guard_seasons(c(2009L, 2024L), 2024L, "probe"))
})

test_that("a table is checked by its season column or the season in its game_id (review I5)", {
  withr::local_dir(PROJECT_ROOT)
  expect_error(vc$vvf_guard_table(data.table::data.table(season = c(2024L, 2025L)), "probe"), "sealed-season guard")
  expect_error(vc$vvf_guard_table(data.table::data.table(game_id = c("2024_01_AAA_BBB", "2025_02_CCC_DDD")), "probe"),
               "sealed-season guard")
  expect_invisible(vc$vvf_guard_table(data.table::data.table(game_id = c("2024_01_AAA_BBB", "x")), "probe"))
  expect_invisible(vc$vvf_guard_table(data.table::data.table(z = 1), "probe"))   # nothing to check
})

test_that("sealed seasons join config.R's SEALED_SEASONS when it is defined (PR #218)", {
  tmp <- withr::local_tempdir()
  with_seal <- file.path(tmp, "with.R")
  writeLines(c("A <- 1", "SEALED_SEASONS <- c(2025L, 2026L)"), with_seal)
  expect_equal(vc$vvf_sealed_seasons(with_seal), c(2025L, 2026L))
  without <- file.path(tmp, "without.R")
  writeLines("A <- 1", without)
  expect_equal(vc$vvf_sealed_seasons(without), 2025L)
  expect_error(vc$vvf_sealed_seasons(file.path(tmp, "absent.R")), "missing")
})

test_that("a config value is read without running the rest of config.R", {
  tmp <- withr::local_tempdir()
  f <- file.path(tmp, "config.R")
  writeLines(c("stop('the rest of config.R ran')", "CAPTURE_TIMEOUT_SEC <- 20"), f)
  expect_equal(vc$vvf_config_value("CAPTURE_TIMEOUT_SEC", f), 20)
  expect_null(vc$vvf_config_value("NOT_THERE", f, required = FALSE))
  expect_error(vc$vvf_config_value("NOT_THERE", f), "not assigned")
})

test_that("the 2024-2025 ESPN opener/close file is refused by name and by directory", {
  tmp <- withr::local_tempdir()
  f <- file.path(tmp, "espn_open_close_2024_2025.csv")
  writeLines("season,h_open\n2025,-110", f)
  expect_error(vc$vvf_read_csv(f), "refused")
  expect_error(vc$vvf_assert_readable("reports/2026-09-29/clv-power/output.txt"), "refused")
  expect_error(vc$vvf_assert_readable("C:\\repo\\reports\\2026-09-29\\clv-power\\any.csv"), "refused")
  expect_invisible(vc$vvf_assert_readable(file.path("backtest", "vvf", "data", "venues.csv")))
})

test_that("no backtest code names the forbidden file or its directory, except the guard and v1's builder", {
  # backtest/build_inputs.R (v1) read the file on 2026-09-29 to build the frozen
  # backtest/data/espn_open_close.csv, keeping 2024 rows only. That read is
  # disclosed in docs/VARIABLE_LEDGER.md; the owner decides whether the v1
  # builder should refuse it too (plan A3a, owner checkpoint).
  files <- list.files(file.path(PROJECT_ROOT, "backtest"), pattern = "\\.R$", recursive = TRUE)
  hits <- character()
  for (f in files) {
    txt <- readLines(file.path(PROJECT_ROOT, "backtest", f), warn = FALSE)
    if (any(grepl("espn_open_close_2024_2025|clv-power|clv_power", txt))) hits <- c(hits, f)
  }
  expect_setequal(hits, c("build_inputs.R", "vvf/common.R"))
  v1 <- readLines(file.path(PROJECT_ROOT, "backtest", "build_inputs.R"), warn = FALSE)
  expect_equal(sum(grepl("espn_open_close_2024_2025", v1)), 1L)
})

test_that("the ported inputs load against their sha256 locks and stop at 2024", {
  withr::local_dir(PROJECT_ROOT)
  inp <- vc$vvf_load_inputs()
  expect_setequal(names(inp), c("game_context", "injuries_team", "injuries_qb", "venues"))
  for (nm in c("game_context", "injuries_team", "injuries_qb")) expect_lte(max(inp[[nm]]$season), 2024L)
  v1 <- data.table::fread(file.path("backtest", "data", "games.csv"), select = c("game_id", "season"))
  expect_true(all(inp$game_context$game_id %in% v1$game_id))
  expect_true(all(inp$injuries_team$game_id %in% v1$game_id))
})

test_that("a tampered input is rejected", {
  withr::local_dir(PROJECT_ROOT)
  tmp <- withr::local_tempdir()
  file.copy(list.files(file.path("backtest", "vvf", "data"), full.names = TRUE), tmp)
  f <- file.path(tmp, "venues.csv")
  txt <- readLines(f)
  txt[2] <- sub("ATL00", "ATL99", txt[2])
  writeLines(txt, f)
  expect_error(vc$vvf_load_inputs(tmp), "sha256")
})

test_that("v1 inputs load against the eval window and are cut at the requested season", {
  withr::local_dir(PROJECT_ROOT)
  inp <- vc$vvf_load_v1_inputs(max_season = 2012L)
  expect_lte(max(inp$games$season), 2012L)
  expect_true(all(c("team_games", "qb_games") %in% names(inp)))
})

test_that("every game's stadium has finite coordinates and a time zone", {
  withr::local_dir(PROJECT_ROOT)
  inp <- vc$vvf_load_inputs()
  used <- unique(inp$game_context$stadium_id[!is.na(inp$game_context$stadium_id)])
  v <- inp$venues[stadium_id %in% used]
  expect_setequal(v$stadium_id, used)
  expect_true(all(is.finite(v$latitude) & is.finite(v$longitude)))
  expect_true(all(nzchar(v$timezone)))
})

test_that("geometry helpers are correct", {
  # New York to Los Angeles is about 3,940 km
  expect_equal(vc$vvf_haversine_km(40.7128, -74.0060, 34.0522, -118.2437), 3936, tolerance = 0.01)
  t <- as.POSIXct("2024-12-15 18:00:00", tz = "UTC")
  expect_equal(vc$vvf_utc_offset_h(t, "America/New_York"), -5)
  expect_equal(vc$vvf_local_hour(t, "America/Los_Angeles"), 10)
})

test_that("the result hash depends on every file's bytes and their order", {
  tmp <- withr::local_tempdir()
  a <- file.path(tmp, "a.csv"); b <- file.path(tmp, "b.csv")
  writeLines("x\n1", a); writeLines("x\n2", b)
  h <- vc$vvf_result_sha256(c(a, b))
  expect_match(h, "^[0-9a-f]{64}$")
  expect_false(identical(h, vc$vvf_result_sha256(c(b, a))))
  writeLines("x\n3", b)
  expect_false(identical(h, vc$vvf_result_sha256(c(a, b))))
})
