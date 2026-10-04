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

rest <- function(slate, tg, season = 2024L, week = 15L) {
  compute_rest_table(slate, tg, season, week, short_penalty = -0.85, long_bonus = 0.5, bye_bonus = 1)
}
no_games <- data.frame(team = character(), season = integer(), week = integer())

test_that("rest comes from each team's own game, not the week's first kickoff (audit M23)", {
  # 2024 week 15 opened on Thursday (LA @ SF); DAL @ CAR was Sunday, CHI @ MIN Monday
  slate <- data.frame(game_id = c("2024_15_LA_SF", "2024_15_DAL_CAR", "2024_15_CHI_MIN"),
                      home_team = c("SF", "CAR", "MIN"), away_team = c("LA", "DAL", "CHI"),
                      home_rest = c(4, 7, 8), away_rest = c(4, 7, 8))
  tg <- data.frame(team = c("SF", "LA", "CAR", "DAL", "MIN", "CHI"), season = 2024L, week = 14L)
  r <- rest(slate, tg)
  expect_equal(r$rest_points[match(c("SF", "LA"), r$team)], c(-0.85, -0.85))
  expect_equal(r$rest_points[match(c("CAR", "DAL", "MIN", "CHI"), r$team)], c(0, 0, 0, 0))
})

test_that("a Sunday game after a Monday game is short rest", {
  slate <- data.frame(game_id = "g", home_team = "LV", away_team = "ATL", home_rest = 6, away_rest = 6)
  r <- rest(slate, data.frame(team = c("LV", "ATL"), season = 2024L, week = 14L))
  expect_equal(r$rest_points, c(-0.85, -0.85))
})

test_that("a team off a bye gets the bye bonus, not the long-rest bonus", {
  slate <- data.frame(game_id = "g", home_team = "KC", away_team = "DEN", home_rest = 14, away_rest = 10)
  tg <- data.frame(team = c("KC", "DEN"), season = 2024L, week = c(13L, 14L))
  r <- rest(slate, tg)
  expect_equal(r$rest_points[r$team == "KC"], 1)     # last game in week 13: bye in week 14
  expect_equal(r$rest_points[r$team == "DEN"], 0.5)  # 10 days without a bye: long rest
})

test_that("week 1 is neutral: seven days and no game yet this season", {
  slate <- data.frame(game_id = "g", home_team = "PHI", away_team = "GB", home_rest = 7, away_rest = 7)
  tg <- data.frame(team = c("PHI", "GB"), season = 2023L, week = 20L)   # last games were last season
  expect_equal(rest(slate, tg, season = 2024L, week = 1L)$rest_points, c(0, 0))
})

test_that("missing rest days or a duplicated team stop the run", {
  bad <- data.frame(game_id = "g", home_team = "KC", away_team = "DEN", home_rest = NA, away_rest = 7)
  expect_error(rest(bad, no_games), "no rest days for g")
  dup <- data.frame(game_id = c("a", "b"), home_team = c("KC", "KC"), away_team = c("DEN", "LV"),
                    home_rest = 7, away_rest = 7)
  expect_error(rest(dup, no_games), "twice.*KC")
})

test_that("both rest tables in NFLsimulation.R use compute_rest_table (audit M23)", {
  code <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_equal(sum(grepl("compute_rest_table(", code, fixed = TRUE)), 2L)
  expect_false(any(grepl("week_slate$game_date[1]", code, fixed = TRUE)))
  expect_false(any(grepl("fake_slate_date", code, fixed = TRUE)))
})
