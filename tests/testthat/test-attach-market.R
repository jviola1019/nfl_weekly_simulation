# Audit M11: a game without a market line must be flagged, logged and tracked
env <- load_script_functions(file.path(PROJECT_ROOT, "NFLsimulation.R"), c("attach_market_probs", ".clp"))

test_that("games without a market line are flagged, warned about and tracked", {
  final <- data.frame(game_id = c("g1", "g2"), home_p_2w_cal = c(0.6, 0.4), away_p_2w_cal = c(0.4, 0.6))
  mkt <- data.frame(game_id = "g1", home_p_2w_mkt = 0.55)
  expect_warning(out <- env$attach_market_probs(final, mkt), "g2")
  expect_equal(out$market_available, c(TRUE, FALSE))
  expect_equal(out$home_p_2w_mkt[1], 0.55)
  # blend input keeps working (internal fill from home_p_2w_cal) but is explicitly marked
  expect_equal(out$home_p_2w_mkt[2], 0.4)
  expect_equal(out$away_p_2w_mkt, 1 - out$home_p_2w_mkt)
  q <- get_data_quality()
  expect_equal(q$market$status, "partial")
  expect_true("g2" %in% q$market$missing_games)
})

test_that("all games with lines report full market quality and no warning", {
  final <- data.frame(game_id = "g1", home_p_2w_cal = 0.6, away_p_2w_cal = 0.4)
  expect_silent(out <- env$attach_market_probs(final, data.frame(game_id = "g1", home_p_2w_mkt = 0.52)))
  expect_true(out$market_available)
  expect_equal(get_data_quality()$market$status, "full")
})

test_that("no market line at all marks market quality unavailable", {
  final <- data.frame(game_id = c("g1", "g2"), home_p_2w_cal = c(0.6, 0.4), away_p_2w_cal = c(0.4, 0.6))
  expect_warning(out <- env$attach_market_probs(final, data.frame(game_id = character(), home_p_2w_mkt = numeric())), "2 game")
  expect_false(any(out$market_available))
  expect_equal(get_data_quality()$market$status, "unavailable")
})
