# VVF feature builder (backtest/vvf/features.R, ported from PR #205): the
# helpers that carry their own history are point-in-time, the injury weights
# are as specified, rows after the window are refused, and the anchor-relative
# features follow the anchor.

vf <- vvf_test_env(c("common.R", "features.R"), v1_files = VVF_TEST_V1_FILES)

test_that("referee tendencies for a season use only earlier seasons", {
  d <- data.table::data.table(season = rep(2019:2021, each = 4L), referee = "Ref A",
                              y = c(1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 0), p_c0 = 0.5,
                              total = 50, total_line = 44)
  a <- vf$vvf_referee_tendencies(d)
  d2 <- data.table::copy(d); d2[season == 2021, `:=`(y = 1 - y, total = 10)]
  b <- vf$vvf_referee_tendencies(d2)
  expect_equal(a[season == 2021, ref_ml_resid], b[season == 2021, ref_ml_resid])
  expect_equal(a[season == 2021, ref_tot_resid], b[season == 2021, ref_tot_resid])
  # 2020 uses 2019 only: 4 home wins at p = 0.5 -> sum 2, shrunk by 50 pseudo-games
  expect_equal(a[season == 2020, ref_ml_resid], 2 / (4 + 50))
  expect_false(2019L %in% a$season)
})

test_that("the QB-out flag is the previous starter listed Out or Doubtful for this game", {
  g <- data.table::data.table(
    game_id = c("g1", "g2", "g3"), kickoff = as.POSIXct(c("2020-09-13", "2020-09-20", "2020-09-27"), tz = "UTC"),
    season = 2020L, home_franchise = c("AAA", "BBB", "AAA"), away_franchise = c("BBB", "AAA", "BBB"),
    home_qb_id = c("Q1", "Q2", "Q9"), away_qb_id = c("Q2", "Q1", "Q2"))
  inj <- data.table::data.table(game_id = "g3", season = 2020L, team = "AAA", gsis_id = "Q1", status = "out")
  x <- vf$vvf_qb_out(g, inj)
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
  x <- vf$vvf_injury_index(row)
  expect_equal(x$inj_ol, 2.75)
  expect_equal(x$inj_skill, 1)
  expect_equal(x$inj_all, 3.75)
})

test_that("feature building refuses any season after the window, and the sealed season", {
  withr::local_dir(PROJECT_ROOT)
  base <- list(pred = data.table::data.table(season = c(2022L, 2023L)))
  expect_error(vf$vvf_build_features(base, list(), max_season = 2022L), "sealed-season guard")
  base25 <- list(pred = data.table::data.table(season = 2025L))
  expect_error(vf$vvf_build_features(base25, list(), max_season = 2026L), "sealed-season guard")
})

test_that("anchor features follow the anchor: the close, or the opener with its movement", {
  d <- data.table::data.table(game_id = c("a", "b"), p_c0 = c(0.6, 0.15), p_open = c(0.55, 0.25),
                              p_close_venue = c(0.62, 0.18), p_c1 = c(0.5, 0.3), p_c2 = c(0.7, 0.1), p_e1 = c(0.6, 0.15))
  lg <- function(p) log(p / (1 - p))
  cl <- vf$vvf_anchor_features(d, "close")
  expect_identical(attr(cl, "vvf_anchor"), "close")
  expect_equal(cl$lp_anchor, lg(c(0.6, 0.15)))
  expect_equal(cl$d_c1, lg(c(0.5, 0.3)) - lg(c(0.6, 0.15)))
  expect_equal(cl$d_e1, c(0, 0))
  expect_equal(cl$home_dog, c(0L, 1L))
  expect_equal(cl$big_fav, c(0L, 1L))
  op <- vf$vvf_anchor_features(d, "open")
  expect_equal(op$lp_anchor, lg(c(0.55, 0.25)))
  expect_equal(op$delta, lg(c(0.62, 0.18)) - lg(c(0.55, 0.25)))
  expect_equal(op$big_fav, c(0L, 0L))
  expect_false("lp_anchor" %in% names(d))
  expect_error(vf$vvf_anchor_features(d[, !"p_open"], "open"), "needs column p_open")
})
