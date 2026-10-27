# Output audit F11 (2026-10-22): the calibration backtest joined home field from a table built
# only for the teams on the slate being simulated, so every team on a bye that week had no home
# field in every calibration game. Both means went NA and simulate_game_nb replaced them with
# 21.5: in the 2026 week 7 run (byes BUF, JAX, LAC, WAS) 317 of 1,355 calibration games were coin
# flips. The table now covers every team, and a mean that is not finite stops the run.

test_that("home field has a value for every team asked for, including one with no home game", {
  margins <- data.frame(team_home = c("KC", "KC", "DEN", "BUF"), margin = c(7, 3, 10, NA))
  tbl <- team_hfa_table(margins, teams = c("BUF", "DEN", "JAX", "KC"), league_hfa = 1.5, den_bonus = 0.5)
  expect_identical(tbl$team, c("BUF", "DEN", "JAX", "KC"))
  expect_true(all(is.finite(tbl$hfa)))
  # KC: two home games, mean 5, shrunk toward 1.5 with weight 2 / (2 + 60)
  expect_equal(tbl$hfa[tbl$team == "KC"], (2 / 62) * 5 + (60 / 62) * 1.5)
  # DEN: one home game plus the altitude bonus
  expect_equal(tbl$hfa[tbl$team == "DEN"], (1 / 61) * 10 + (60 / 61) * 1.5 + 0.5)
  # JAX: no home game at all, so the league value
  expect_equal(tbl$hfa[tbl$team == "JAX"], 1.5)
  # BUF: a home game without a score counts toward n but not toward the mean (as before)
  expect_equal(tbl$hfa[tbl$team == "BUF"], 1.5)
})

test_that("a calibration week whose means are not finite stops and names the games", {
  g <- data.frame(game_id = c("2024_03_BUF_JAX", "2024_03_KC_LV", "2024_03_DAL_NYG"),
                  mu_home = c(NA, 23.1, 20.2), mu_away = c(NA, 19.4, NaN))
  expect_error(assert_finite_means(g, "calibration 2024 week 3"),
               "calibration 2024 week 3: 2 game\\(s\\) without a finite mean: 2024_03_BUF_JAX, 2024_03_DAL_NYG")
  ok <- g[2, ]
  expect_silent(assert_finite_means(ok, "calibration 2024 week 3"))
})

test_that("a missing mean names the inputs that are missing, with their games", {
  g <- data.frame(game_id = c("2019_01_DEN_OAK", "2019_01_KC_JAX", "2019_01_NE_PIT"),
                  home_team = c("OAK", "JAX", "NE"), exp_ppd_home = c(NA, 2.1, 1.9),
                  margin_shift = c(1, NA, 0.5), home_hfa = c(1.2, 1.5, 1.4),
                  mu_home = c(NA, NA, 24.0), mu_away = c(20, 21, 18.5))
  expect_error(assert_finite_means(g, "calibration 2019 week 1"),
               "2 game\\(s\\) without a finite mean: 2019_01_DEN_OAK, 2019_01_KC_JAX; missing inputs: exp_ppd_home \\(2019_01_DEN_OAK\\); margin_shift \\(2019_01_KC_JAX\\)$")
})

test_that("the engine builds home field for every schedule team and refuses a missing mean (F11)", {
  code <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_false(any(grepl("hfa_tbl <- tibble(team = teams_on_slate)", code, fixed = TRUE)))
  expect_true(any(grepl("hfa_tbl <- team_hfa_table(", code, fixed = TRUE)))
  expect_true(any(grepl("assert_finite_means(g, sprintf(\"calibration %d week %d\", cut_season, cut_week))", code, fixed = TRUE)))
  # a cached calibration built before this fix must not be reused
  expect_true(any(grepl("version = 4L", code, fixed = TRUE)))
})
