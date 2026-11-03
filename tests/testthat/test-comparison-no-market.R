# A game with no market line (no moneyline and no spread on the schedule) has no market in the
# games comparison (artifacts/baseline_games.csv). attach_market_probs() (NFLsimulation.R, audit
# M11) fills such a game's home_p_2w_mkt with the model's own probability, as the blend's input
# only, and marks it market_available = FALSE. The web bundle honours the flag; the comparison did
# not. It took the fill for a market, turned it into moneylines, shrank toward it and recommended
# a bet against it (2026 week 9: ARI at SEA at the model's own -337/+337, "Bet ARI moneyline";
# TB at CHI, "Bet CHI moneyline" with a raw Kelly fraction of 0.053).

# build_snapshot_moneyline_result() is defined inside an `if (!exists(...))` block of
# NFLsimulation.R, which runs the whole pipeline when sourced: evaluate only that definition
load_snapshot_builder <- function() {
  is_def <- function(e) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("build_snapshot_moneyline_result"))
  exprs <- parse(file.path(PROJECT_ROOT, "NFLsimulation.R"), keep.source = FALSE)
  defs <- list()
  for (e in exprs) {
    if (is_def(e)) defs <- c(defs, e)
    if (is.call(e) && identical(e[[1]], as.name("if"))) {
      body <- as.list(e[[3]])
      defs <- c(defs, Filter(is_def, body))
    }
  }
  if (length(defs) != 1) stop("expected one build_snapshot_moneyline_result definition in NFLsimulation.R")
  env <- new.env(parent = nflmarket_env())
  eval(defs[[1]], env)
  env$build_snapshot_moneyline_result
}

final_slate <- function() {
  data.frame(
    game_id = c("2026_09_GB_NE", "2026_09_ARI_SEA"), season = 2026L, week = 9L,
    home_team = c("NE", "SEA"), away_team = c("GB", "ARI"), date = "2026-11-08",
    home_p_2w_blend = c(0.6021, 0.7681), home_p_2w_cal = c(0.6788, 0.7713),
    # as attach_market_probs() leaves them: the second is the fill with home_p_2w_cal
    home_p_2w_mkt = c(0.5830, 0.7713), market_available = c(TRUE, FALSE),
    home_median_blend = c(26, 28), away_median_blend = c(22, 18), total_median_blend = c(48, 46),
    stringsAsFactors = FALSE
  )
}

schedule <- function() {
  data.frame(
    game_id = c("2026_09_GB_NE", "2026_09_ARI_SEA"), season = 2026L, week = 9L, game_type = "REG",
    home_team = c("NE", "SEA"), away_team = c("GB", "ARI"), gameday = "2026-11-08",
    home_moneyline = c(-155, NA), away_moneyline = c(130, NA), spread_line = c(3, NA), total_line = c(46.5, NA),
    stringsAsFactors = FALSE
  )
}

comparison_rows <- function() {
  snap <- load_snapshot_builder()(final_slate(), season = 2026L, week = 9L, verbose = FALSE)
  out <- nflmarket_env()$build_moneyline_comparison_table(list(comp = snap), schedule(),
                                                          join_keys = c("game_id", "season", "week"), vig = 0.10, verbose = FALSE)
  split(out, out$game_id)
}

test_that("the current-week snapshot passes no market probability for a game without a line", {
  snap <- load_snapshot_builder()(final_slate(), season = 2026L, week = 9L, verbose = FALSE)
  expect_equal(snap$p_mkt[snap$game_id == "2026_09_GB_NE"], 0.5830)
  expect_true(is.na(snap$p_mkt[snap$game_id == "2026_09_ARI_SEA"]))
})

test_that("a game with no market line has no market price, source or pick in the comparison", {
  row <- comparison_rows()[["2026_09_ARI_SEA"]]
  expect_true(is.na(row$market_home_prob) && is.na(row$market_away_prob))
  expect_true(is.na(row$market_home_ml) && is.na(row$market_away_ml))
  expect_equal(row$prob_source, "none")
  expect_true(is.na(row$market_pick))
  expect_true(is.na(row$blend_ev_units))
  expect_false(identical(row$blend_pick_type, "ev_positive"))
  expect_equal(row$blend_recommendation, "No Play")
  expect_true(is.na(row$blend_kelly_fraction_raw) || row$blend_kelly_fraction_raw == 0)
})

test_that("a game with no market line keeps the unshrunk blend, as the web bundle's C3 does", {
  row <- comparison_rows()[["2026_09_ARI_SEA"]]
  expect_equal(row$blend_home_prob_shrunk, 0.7681)
  expect_equal(row$blend_home_prob_shrunk + row$blend_away_prob_shrunk, 1)
})

test_that("a game with a moneyline is priced and shrunk toward its no-vig market as before", {
  row <- comparison_rows()[["2026_09_GB_NE"]]
  fair <- (155 / 255) / (155 / 255 + 100 / 230)
  expect_equal(row$market_home_prob, fair, tolerance = 1e-9)
  expect_equal(row$market_home_ml, -155)
  expect_equal(row$prob_source, "moneyline")
  expect_equal(row$blend_home_prob_shrunk, (1 - SHRINKAGE) * 0.6021 + SHRINKAGE * fair, tolerance = 1e-9)
})
