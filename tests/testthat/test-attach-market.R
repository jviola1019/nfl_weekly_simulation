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

test_that("a game without a market line has no probability edge and no model-market disagreement", {
  gap_env <- load_script_functions(file.path(PROJECT_ROOT, "NFLsimulation.R"), "market_gap")
  # the second game's market is attach_market_probs()'s fill with the model's own probability
  expect_equal(gap_env$market_gap(c(0.62, 0.71), c(0.55, 0.71), c(TRUE, FALSE)), c(0.07, NA_real_))
  src <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  for (col in c("model_uncertainty", "prob_edge_home", "prob_edge_away")) {
    line <- grep(sprintf("^[[:space:]]*%s = ", col), src, value = TRUE)
    expect_length(line, 1L)
    expect_match(line, "market_gap(", fixed = TRUE, info = col)   # not the fill
  }
})
