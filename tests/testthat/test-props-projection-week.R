# load_player_projections() is point in time: in the target season it uses only games before `week`; earlier seasons
# count whole, and week = NULL keeps every game (sports/nfl/props/data_sources.R). Without the week filter, a run for a
# past week averaged in the games played after it.

fake_player_stats <- function() data.frame(
  player_id = "P1", player_name = "A.Receiver", position = "WR", recent_team = "KC",
  season = c(2025L, 2025L, 2026L, 2026L, 2026L, 2026L), week = c(17L, 18L, 1L, 2L, 3L, 4L),
  passing_yards = 0, rushing_yards = 0, receiving_yards = c(10, 20, 30, 40, 50, 150),
  receptions = c(1, 2, 3, 4, 5, 9), targets = 5, passing_tds = 0L, rushing_tds = 0L, receiving_tds = 0L,
  stringsAsFactors = FALSE)

test_that("load_player_projections uses only the target season's games before the week", {
  env <- new.env()
  sys.source(file.path(.test_project_root, "sports", "nfl", "props", "data_sources.R"), envir = env)
  fake <- fake_player_stats()
  local_mocked_bindings(load_player_stats = function(seasons, ...) fake[fake$season %in% seasons, ], .package = "nflreadr")
  wk4 <- suppressMessages(env$load_player_projections(2026, week = 4, min_games = 1))
  expect_equal(wk4$games_played, 5L)                              # 2025's two games and 2026 weeks 1-3
  expect_equal(wk4$avg_receiving_yards, mean(c(10, 20, 30, 40, 50)))
  expect_equal(wk4$avg_receptions, mean(1:5))
})

test_that("load_player_projections keeps every game when no week is given", {
  env <- new.env()
  sys.source(file.path(.test_project_root, "sports", "nfl", "props", "data_sources.R"), envir = env)
  fake <- fake_player_stats()
  local_mocked_bindings(load_player_stats = function(seasons, ...) fake[fake$season %in% seasons, ], .package = "nflreadr")
  all_games <- suppressMessages(env$load_player_projections(2026, week = NULL, min_games = 1))
  expect_equal(all_games$games_played, 6L)
  expect_equal(all_games$avg_receiving_yards, mean(c(10, 20, 30, 40, 50, 150)))
})
