# Home field as of each slate, and the calibration's home field (owner, 2026-11-04: "Complete and fix the home
# field issues"; reports/2026-11-04/hfa-engine/README.md).
# - Audit M5 (look-ahead): one home-field table was built from every game of SEASON-9..SEASON and joined into every
#   calibration week, so each calibration game's team values included that game and later seasons.
# - The calibration gave the margin (home_hfa - away_hfa) / 2, which averages zero, where production gives the home
#   team its full home field; it also added rest, which production has not admitted.
# The as-of tests run on the committed nflverse results (backtest/data/games.csv, 1999-2024).

real_games <- function() {
  g <- utils::read.csv(file.path(PROJECT_ROOT, "backtest", "data", "games.csv"), stringsAsFactors = FALSE)
  data.frame(season = g$season, week = g$week, game_type = g$game_type,
             home_team = g$home_franchise, away_team = g$away_franchise,
             home_score = g$home_score, away_score = g$away_score,
             neutral_site = g$location == "Neutral", stringsAsFactors = FALSE)
}
all_teams <- function(games) sort(unique(c(games$home_team, games$away_team)))

test_that("home-field games stop before the slate's week and span the ten seasons ending with it (audit M5)", {
  games <- real_games()
  h <- hfa_games_asof(games, season = 2019, week = 10)
  keep <- games$game_type == "REG" & !games$neutral_site & is.finite(games$home_score) & is.finite(games$away_score) &
    games$season >= 2010 & (games$season < 2019 | (games$season == 2019 & games$week < 10))
  expect_equal(nrow(h), sum(keep))
  expect_equal(h$margin, (games$home_score - games$away_score)[keep])
  expect_identical(h$team_home, games$home_team[keep])
  # week 1 of a season: the nine seasons before it, and none of its own games
  wk1 <- hfa_games_asof(games, 2019, 1)
  expect_equal(nrow(wk1), sum(games$game_type == "REG" & !games$neutral_site & games$season %in% 2010:2018))
})

test_that("a result from the slate's week or later cannot move home field (leak canary)", {
  games <- real_games()
  asof <- function(g) hfa_table_asof(g, 2019, 10, teams = all_teams(games), den_bonus = 0, estimator = "team_margin")
  base <- asof(games)
  future <- games
  i <- which(future$season == 2019 & future$week == 10 & future$game_type == "REG" & !future$neutral_site)[1]
  future$home_score[i] <- future$home_score[i] + 100   # an absurd result in the slate's own week
  expect_identical(asof(future), base)
  past <- games
  j <- which(past$season == 2019 & past$week == 9 & past$game_type == "REG" & !past$neutral_site)[1]
  past$home_score[j] <- past$home_score[j] + 100       # the week before is history, so it does count
  expect_false(isTRUE(all.equal(asof(past), base)))
})

test_that("the league value is the mean home margin of those games, and every estimator uses it", {
  games <- real_games()
  t <- hfa_table_asof(games, 2019, 10, teams = c("DEN", "KC"), den_bonus = 0.5, estimator = "league")
  expect_equal(t$league_hfa, mean(hfa_games_asof(games, 2019, 10)$margin))
  expect_equal(t$table$hfa, c(t$league_hfa + 0.5, t$league_hfa))
  tm <- hfa_table_asof(games, 2019, 10, teams = c("DEN", "KC"), den_bonus = 0, estimator = "team_margin")
  expect_identical(tm$league_hfa, t$league_hfa)
})

test_that("no result before the cut stops instead of assuming a home field", {
  expect_error(hfa_table_asof(real_games(), 1999, 1, teams = "KC", den_bonus = 0, estimator = "league"),
               "no regular-season result before 1999 week 1")
})

# The composition is arithmetic, so explicit inputs give exact expected means.
calib_rows <- function() {
  data.frame(game_id = c("g1", "g2"), exp_drives_home = c(11, 10), exp_ppd_home = c(2, 2.2),
             exp_drives_away = c(10.5, 11), exp_ppd_away = c(1.8, 2), HFA_pts = c(1.7, 0),
             home_rest_points = c(0.5, 0), away_rest_points = c(-0.85, 1), stringsAsFactors = FALSE)
}

test_that("the calibration's means are production's admitted terms: the home team gets its full home field", {
  g <- calib_rows()
  mu <- compose_mu(calibration_mu_components(g, c("base", "hfa")), c("base", "hfa"))
  expect_equal(mu$mu_home, c(11 * 2 + 1.7, 10 * 2.2))
  expect_equal(mu$mu_away, c(10.5 * 1.8, 11 * 2))
})

test_that("rest enters the calibration only when config admits it", {
  g <- calib_rows()
  base <- compose_mu(calibration_mu_components(g, c("base", "hfa")), c("base", "hfa"))
  rest <- compose_mu(calibration_mu_components(g, c("base", "hfa", "rest")), c("base", "hfa", "rest"))
  expect_equal(rest$mu_home - base$mu_home, c(0.5, 0))
  expect_equal(rest$mu_away - base$mu_away, c(-0.85, 1))
})

test_that("an admitted term the calibration cannot simulate stops it, so the blend never trains on another model", {
  expect_error(calibration_mu_components(calib_rows(), c("base", "hfa", "injury")),
               "cannot simulate admitted term\\(s\\) injury")
})

test_that("production and the calibration build home field as of each slate, the same way (NFLsimulation.R)", {
  code <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_true(any(grepl("hfa_table_asof(hfa_games, SEASON, WEEK_TO_SIM,", code, fixed = TRUE)))
  expect_true(any(grepl("hfa_table_asof(hfa_games, cut_season, cut_week,", code, fixed = TRUE)))
  expect_true(any(grepl("HFA_pts = home_field_points(home_hfa, hfa_cut$league_hfa, 1, neutral_site)", code, fixed = TRUE)))
  expect_true(any(grepl("calibration_mu_components(g, MU_TERMS_ADMITTED)", code, fixed = TRUE)))
  # the calibration week no longer splits a team-vs-team difference, and no longer reads the full-sample table
  env <- load_script_functions(file.path(PROJECT_ROOT, "NFLsimulation.R"), c("week_inputs_and_sim_2w", "recent_form_at_sim"))
  calib <- c(deparse(env$week_inputs_and_sim_2w), deparse(env$recent_form_at_sim))
  expect_false(any(grepl("margin_shift", calib, fixed = TRUE)))
  expect_false(any(grepl("hfa_tbl", calib, fixed = TRUE)))
})
