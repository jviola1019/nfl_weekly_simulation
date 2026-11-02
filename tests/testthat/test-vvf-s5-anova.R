# VVF stage S5, ANOVA additions (backtest/vvf/s5_anova.R): loss differences by
# season and by part of the season, and team-level residual effects.

v5a <- vvf_test_env("s5_anova.R", v1_files = c("common.R", "metrics.R"))

sim_teams <- function(seed, team_effect = 0, n_seasons = 6L) {
  set.seed(seed)
  teams <- sprintf("T%02d", 1:16)
  g <- data.table::CJ(season = 2015L + seq_len(n_seasons), week = 1:18, k = 1:16)
  g[, phase := data.table::fifelse(week > 17L, "POST", "REG")]
  g[, home_franchise := sample(teams, .N, replace = TRUE)]
  g[, away_franchise := vapply(home_franchise, function(h) sample(setdiff(teams, h), 1), "")]
  g[, lp_anchor := stats::rnorm(.N, 0.2, 0.8)]
  g[, p_anchor := stats::plogis(lp_anchor)]
  g[, y := stats::rbinom(.N, 1, stats::plogis(lp_anchor + team_effect * (home_franchise == "T01")))]
  g[, ats_resid := stats::rnorm(.N, 0, 13) + 8 * team_effect * (home_franchise == "T01")]
  g
}

test_that("the part of the season follows the weeks and the phase", {
  expect_equal(v5a$vvf_season_part(c(1L, 6L, 7L, 12L, 13L, 18L, 19L), c(rep("REG", 6), "POST")),
               c("weeks 1-6", "weeks 1-6", "weeks 7-12", "weeks 7-12", "weeks 13-18", "weeks 13-18", "playoffs"))
})

test_that("a loss difference that changes with the part of the season is detected; a constant one is not", {
  d <- sim_teams(1)
  d[, p_late := data.table::fifelse(week >= 13L, stats::plogis(lp_anchor + 0.8 * (2 * y - 1)), p_anchor)]
  r <- v5a$vvf_loss_anova(d, "p_late", "p_anchor", by = "part")
  expect_equal(r$loss, c("brier", "logloss"))
  expect_true(all(r$p < 1e-6))
  expect_match(r$by_group[1], "weeks 13-18: -")
  x <- d[!is.na(y)]
  dl <- v5a$bt_brier_vec(x$p_late, x$y) - v5a$bt_brier_vec(x$p_anchor, x$y)
  a <- stats::anova(stats::lm(dl ~ 1), stats::lm(dl ~ factor(v5a$vvf_season_part(x$week, x$phase))))
  expect_equal(r$F[1], a$F[2], tolerance = 1e-10)
  d[, p_same := stats::plogis(lp_anchor + 0.01)]
  s <- v5a$vvf_loss_anova(d, "p_same", "p_anchor", by = "season")
  expect_equal(s$groups[1], 6L)
  expect_true(all(s$p > 0.01))
})

test_that("a planted home-team effect is found against the anchor, and no effect is not", {
  big <- v5a$vvf_team_effects(sim_teams(2, team_effect = 1.5))
  expect_lt(big$p, 0.001)
  expect_match(big$largest, "^home T01")
  expect_identical(big$test, "LR chi2")
  expect_equal(big$df, 30L)                              # 15 home + 15 away contrasts
  none <- v5a$vvf_team_effects(sim_teams(3))
  expect_gt(none$p, 0.01)
  sp <- v5a$vvf_team_effects(sim_teams(2, team_effect = 1.5), family = "spread", response = "ats_resid")
  expect_identical(sp$test, "F")
  expect_lt(sp$p, 0.001)
})
