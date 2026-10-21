# =============================================================================
# Sealed seasons stay out of the market comparison's diagnostics (owner, 2026-10-21)
# =============================================================================
# The 2026 output audit (reports/2026-10-21/OUTPUT_AUDIT.md, F3) found that production
# calibrates on 2021-2025 and printed 2025 model-against-market numbers: a by-season row
# and rolling windows ending in 2025. The owner chose to keep 2025 in calibration but hide
# its evaluation. compare_to_market() drops SEALED_SEASONS before any diagnostic and says so.

seal_fixture <- function() {
  set.seed(7)
  games <- expand.grid(season = 2023:2025, week = 1:4, k = 1:4)
  games$game_id <- sprintf("%d_%02d_G%d", games$season, games$week, games$k)
  n <- nrow(games)
  home_win <- stats::rbinom(n, 1, 0.55)
  sched <- tibble::tibble(
    game_id = games$game_id, season = games$season, week = games$week, game_type = "REG",
    home_team = "HOM", away_team = "AWY",
    home_score = ifelse(home_win == 1, 24L, 17L), away_score = ifelse(home_win == 1, 17L, 24L),
    home_moneyline = -150L, away_moneyline = 130L
  )
  per_game <- tibble::tibble(game_id = games$game_id, season = games$season, week = games$week,
                             p2_cal = stats::runif(n, 0.35, 0.75))
  by_week <- dplyr::distinct(per_game, season, week)
  list(res = list(per_game = per_game, by_week = by_week), sched = sched)
}

test_that("compare_to_market leaves sealed seasons out of every diagnostic and says so", {
  cmp <- nflmarket_env()$compare_to_market
  fx <- seal_fixture()
  expect_message(
    out <- cmp(fx$res, fx$sched, B = 20L, rolling_window_sizes = 2, sealed_seasons = 2025L),
    "sealed season(s) 2025 omitted", fixed = TRUE
  )
  expect_false(any(out$comp$season == 2025L))
  expect_equal(sort(unique(out$by_season$season)), c(2023L, 2024L))
  expect_equal(out$overall$n_games, sum(fx$sched$season != 2025L))
  if (nrow(out$rolling)) expect_false(any(out$rolling$end_season == 2025L))
})

test_that("with no sealed season every season is evaluated", {
  cmp <- nflmarket_env()$compare_to_market
  fx <- seal_fixture()
  out <- suppressMessages(cmp(fx$res, fx$sched, B = 20L, rolling_window_sizes = 2, sealed_seasons = integer()))
  expect_equal(sort(unique(out$by_season$season)), 2023:2025)
  expect_equal(out$overall$n_games, nrow(fx$sched))
})

test_that("the default comes from config.R's SEALED_SEASONS", {
  expect_identical(SEALED_SEASONS, 2025L)
  expect_identical(formals(nflmarket_env()$compare_to_market)$sealed_seasons, quote(SEALED_SEASONS))
})
