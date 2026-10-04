# Schedule context for the game model. Audit M24: nflverse marks neutral sites with
# location == "Neutral"; the engine looked for neutral_site/neutral/is_neutral, found none,
# and gave the listed home team full home field at international games and the Super Bowl.

test_that("nflverse location marks neutral sites (audit M24)", {
  s <- data.frame(game_id = c("2024_01_GB_PHI", "2024_15_KC_CLE"), location = c("Neutral", "Home"))
  expect_identical(neutral_site_flag(s), c(TRUE, FALSE))
})

test_that("a missing location column or value stops", {
  expect_error(neutral_site_flag(data.frame(game_id = "g1")), "no 'location' column")
  expect_error(neutral_site_flag(data.frame(game_id = c("g_home", "g_na"), location = c("Home", NA))), "for g_na$")
  expect_error(neutral_site_flag(data.frame(game_id = "g_away", location = "Away")), "for g_away$")
})

test_that("a neutral site gets no home-field points, even in the Super Bowl (audit M24)", {
  expect_equal(home_field_points(home_hfa = 2.1, league_hfa = 1.7, playoff_mult = 1.2, neutral_site = TRUE), 0)
  expect_equal(home_field_points(2.1, 1.7, 1.2, FALSE), 2.1 * 1.2)
})

test_that("home-field points fall back to the league value and are capped at 6", {
  expect_equal(home_field_points(c(NA, 9, -8), 1.7, 1, c(FALSE, FALSE, FALSE)), c(1.7, 6, -6))
})

test_that("the engine flags neutral sites and uses the flag for home field (audit M24)", {
  code <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_true(any(grepl('source(file.path(base_path, "schedule_context.R"))', code, fixed = TRUE)))
  expect_true(any(grepl("sched$neutral_site <- neutral_site_flag(sched)", code, fixed = TRUE)))
  expect_true(any(grepl("season %in% seasons_hfa, !neutral_site)", code, fixed = TRUE)))
  expect_true(any(grepl("home_field_points(home_hfa, league_hfa, .playoff_hfa_mult, neutral_site)", code, fixed = TRUE)))
  expect_true(any(grepl("margin_shift = dplyr::if_else(neutral_site, 0,", code, fixed = TRUE)))
  expect_false(any(grepl('intersect(c("neutral_site","neutral","is_neutral")', code, fixed = TRUE)))
})
