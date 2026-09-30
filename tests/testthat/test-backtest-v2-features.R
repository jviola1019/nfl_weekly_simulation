# Validation sprint v2 features (backtest/v2/features.R): point-in-time logic of
# the helpers that carry their own history (referee tendencies, QB flags) and the
# injury index weights.

ft_env <- new.env()
sys.source(file.path(PROJECT_ROOT, "backtest", "common.R"), envir = ft_env)
for (f in c("common.R", "features.R")) sys.source(file.path(PROJECT_ROOT, "backtest", "v2", f), envir = ft_env)
ft <- function(name) get(name, envir = ft_env)

test_that("referee tendencies for a season use only earlier seasons", {
  d <- data.table::data.table(season = rep(2019:2021, each = 4L), referee = "Ref A",
                              y = c(1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 0), p_c0 = 0.5,
                              total = 50, total_line = 44)
  a <- ft("bt2_referee_tendencies")(d)
  d2 <- data.table::copy(d); d2[season == 2021, `:=`(y = 1 - y, total = 10)]
  b <- ft("bt2_referee_tendencies")(d2)
  expect_equal(a[season == 2021, ref_ml_resid], b[season == 2021, ref_ml_resid])
  expect_equal(a[season == 2021, ref_tot_resid], b[season == 2021, ref_tot_resid])
  # 2020 uses 2019 only: 4 home wins at p = 0.5 -> sum 2, shrunk by 50 pseudo-games
  expect_equal(a[season == 2020, ref_ml_resid], 2 / (4 + 50))
  expect_false(2019L %in% a$season)   # no prior season, no tendency
})

test_that("the QB-out flag is the previous starter listed Out or Doubtful for this game", {
  g <- data.table::data.table(
    game_id = c("g1", "g2", "g3"), kickoff = as.POSIXct(c("2020-09-13", "2020-09-20", "2020-09-27"), tz = "UTC"),
    season = 2020L, home_franchise = c("AAA", "BBB", "AAA"), away_franchise = c("BBB", "AAA", "BBB"),
    home_qb_id = c("Q1", "Q2", "Q9"), away_qb_id = c("Q2", "Q1", "Q2"))
  inj <- data.table::data.table(game_id = "g3", season = 2020L, team = "AAA", gsis_id = "Q1", status = "out")
  x <- ft("bt2_qb_out")(g, inj)
  expect_true(x[game_id == "g3" & team == "AAA", qb_out])
  expect_true(x[game_id == "g3" & team == "AAA", qb_change])
  expect_false(x[game_id == "g3" & team == "BBB", qb_out])
  expect_false(x[game_id == "g2" & team == "BBB", qb_change])
})

test_that("the injury index weights Out 1, Doubtful 0.75, Questionable 0.25", {
  row <- data.table::data.table(game_id = "g1", team = "AAA")
  for (grp in c("qb", "ol", "skill", "dl", "lb", "db", "other")) for (st in c("out", "doubtful", "questionable")) {
    data.table::set(row, j = paste0(grp, "_", st), value = 0L)
  }
  row[, `:=`(ol_out = 2L, ol_doubtful = 1L, skill_questionable = 4L)]
  x <- ft("bt2_injury_index")(row)
  expect_equal(x$inj_ol, 2.75)
  expect_equal(x$inj_skill, 1)
  expect_equal(x$inj_all, 3.75)
})

test_that("feature building refuses any season after the sprint window", {
  base <- list(pred = data.table::data.table(season = c(2022L, 2023L)))
  expect_error(ft("bt2_build_features")(base, list(), max_season = 2022L), "sealed-season guard")
})
