# Audit M10: nflreadr spread_line is positive when the home team is favoured
lines <- utils::read.csv(testthat::test_path("fixtures", "schedules_2024_lines.csv"))

test_that("positive spread_line means the home team is favoured (nflreadr convention)", {
  ml_home <- american_to_probability(lines$home_moneyline)
  ml_away <- american_to_probability(lines$away_moneyline)
  p_ml <- ml_home / (ml_home + ml_away)
  clear <- abs(lines$spread_line) >= 2.5
  p_sp <- spread_line_to_home_prob(lines$spread_line, SPREAD_MARGIN_SD)
  agree <- mean(sign(p_sp[clear] - 0.5) == sign(p_ml[clear] - 0.5))
  expect_gt(agree, 0.97)
})

test_that("spread_line_to_home_prob is monotone, symmetric and NA-safe", {
  expect_gt(spread_line_to_home_prob(7, 13.86), 0.5)
  expect_equal(spread_line_to_home_prob(3, 13.86) + spread_line_to_home_prob(-3, 13.86), 1)
  expect_true(is.na(spread_line_to_home_prob(NA_real_, 13.86)))
  p <- spread_line_to_home_prob(c(-30, 0, 30), 13.86)
  expect_true(all(p > 0 & p < 1)); expect_equal(p[2], 0.5)
})

test_that("NFLsimulation's spread fallback map agrees with the convention", {
  env <- load_script_functions(file.path(PROJECT_ROOT, "NFLsimulation.R"), "map_spread_prob")
  expect_gt(env$map_spread_prob(7), 0.5)
  expect_lt(env$map_spread_prob(-7), 0.5)
})
