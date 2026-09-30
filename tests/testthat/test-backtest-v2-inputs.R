# Validation sprint v2 inputs (backtest/data_v2/): sealed-season guard, sha256 locks,
# joins to the v1 locked schedule, and the geometry helpers the features use.

bt2_env <- new.env()
sys.source(file.path(PROJECT_ROOT, "backtest", "common.R"), envir = bt2_env)
sys.source(file.path(PROJECT_ROOT, "backtest", "v2", "common.R"), envir = bt2_env)
bt2 <- function(name) get(name, envir = bt2_env)

test_that("the sealed-season guard refuses any 2025 row", {
  expect_error(bt2("bt2_guard_seasons")(c(2023L, 2025L), 2024L, "probe"), "sealed-season guard")
  expect_invisible(bt2("bt2_guard_seasons")(c(2010L, 2024L), 2024L, "probe"))
})

test_that("v2 inputs load against their sha256 locks and stop at 2024", {
  withr::local_dir(PROJECT_ROOT)
  inp <- bt2("bt2_load_v2_inputs")()
  expect_setequal(names(inp), c("game_context", "injuries_team", "injuries_qb", "venues"))
  for (nm in c("game_context", "injuries_team", "injuries_qb")) expect_lte(max(inp[[nm]]$season), 2024L)
  v1 <- data.table::fread(file.path("backtest", "data", "games.csv"), select = c("game_id", "season"))
  expect_true(all(inp$game_context$game_id %in% v1$game_id))
  expect_true(all(inp$injuries_team$game_id %in% v1$game_id))
})

test_that("a tampered v2 input is rejected", {
  withr::local_dir(PROJECT_ROOT)
  tmp <- withr::local_tempdir()
  file.copy(list.files(file.path("backtest", "data_v2"), full.names = TRUE), tmp)
  f <- file.path(tmp, "venues.csv")
  txt <- readLines(f)
  txt[2] <- sub("ATL00", "ATL99", txt[2])
  writeLines(txt, f)
  expect_error(bt2("bt2_load_v2_inputs")(tmp), "sha256")
})

test_that("every game's stadium has finite coordinates and a time zone", {
  withr::local_dir(PROJECT_ROOT)
  inp <- bt2("bt2_load_v2_inputs")()
  used <- unique(inp$game_context$stadium_id[!is.na(inp$game_context$stadium_id)])
  v <- inp$venues[stadium_id %in% used]
  expect_setequal(v$stadium_id, used)
  expect_true(all(is.finite(v$latitude) & is.finite(v$longitude)))
  expect_true(all(nzchar(v$timezone)))
})

test_that("geometry helpers are correct", {
  # New York to Los Angeles is about 3,940 km
  d <- bt2("bt2_haversine_km")(40.7128, -74.0060, 34.0522, -118.2437)
  expect_equal(d, 3936, tolerance = 0.01)
  t <- as.POSIXct("2024-12-15 18:00:00", tz = "UTC")
  expect_equal(bt2("bt2_utc_offset_h")(t, "America/New_York"), -5)
  expect_equal(bt2("bt2_local_hour")(t, "America/Los_Angeles"), 10)
})
