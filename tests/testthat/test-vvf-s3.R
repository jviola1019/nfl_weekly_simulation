# VVF stage S3, incremental skill (backtest/vvf/s3_skill.R): the weekly refit
# sees only earlier weeks; a planted effect shows skill and a null does not;
# a copy of the anchor scores exactly 0; the declared order is enforced; S0 runs first.

v3 <- vvf_test_env(c("common.R", "registry.R", "provenance.R", "s3_skill.R"), v1_files = VVF_TEST_V1_FILES)

sim_s3 <- function(seasons = 2016:2020, weeks = 17L, per_week = 14L, beta = 0, seed = 1) {
  set.seed(seed)
  g <- data.table::CJ(season = seasons, week = seq_len(weeks), k = seq_len(per_week))
  g[, game_id := sprintf("%d_%02d_%02d", season, week, k)]
  g[, kickoff := as.POSIXct(sprintf("%d-09-01 17:00:00", season), tz = "UTC") + (week - 1) * 7 * 86400 + k * 60]
  g[, wk := season * 100L + week]
  g[, lp_anchor := stats::rnorm(.N, 0.2, 0.8)]
  g[, p_anchor := stats::plogis(lp_anchor)]
  g[, z := stats::rnorm(.N)]
  g[, y := stats::rbinom(.N, 1, stats::plogis(lp_anchor + beta * z))]
  data.table::setattr(g, "vvf_anchor", "open")
  g
}

test_that("the weekly refit uses only earlier weeks", {
  d <- sim_s3(beta = 0.3, seed = 2)
  weeks <- v3$bt_week_schedule(d, 2019:2020)
  a <- v3$vvf_s3_refit(d, "z", weeks)
  d2 <- data.table::copy(d)
  target <- weeks$wk[10]
  d2[kickoff >= weeks$cutoff[10], y := 1L - y]
  data.table::setattr(d2, "vvf_anchor", "open")
  b <- v3$vvf_s3_refit(d2, "z", weeks)
  ids <- d[wk == target, game_id]
  expect_equal(a[game_id %in% ids, p], b[game_id %in% ids, p])
  expect_false(isTRUE(all.equal(a[game_id %in% d[wk == weeks$wk[11], game_id], p],
                                b[game_id %in% d[wk == weeks$wk[11], game_id], p])))
})

test_that("a planted effect shows skill and a null does not", {
  wk_planted <- sim_s3(beta = 0.5, seed = 3)
  w <- v3$bt_week_schedule(wk_planted, 2019:2020)
  x <- wk_planted[season %in% 2019:2020]
  x <- merge(x, v3$vvf_s3_refit(wk_planted, "z", w)[, .(game_id, p_z = p)], by = "game_id")
  s <- v3$vvf_s3_skill(x, "p_z", order = "p_z")
  expect_gt(s$skill_lo, 0)
  expect_lt(s$dm_p_better_bh, 0.05)
  expect_match(s$verdict, "^incremental skill")
  nul <- sim_s3(beta = 0, seed = 4)
  y <- nul[season %in% 2019:2020]
  y <- merge(y, v3$vvf_s3_refit(nul, "z", w)[, .(game_id, p_z = p)], by = "game_id")
  sn <- v3$vvf_s3_skill(y, "p_z", order = "p_z")
  expect_lte(sn$skill_lo, 0); expect_gte(sn$skill_hi, 0)
  expect_identical(sn$verdict, "no incremental skill")
})

test_that("a copy of the anchor scores exactly 0, with a [0, 0] interval", {
  x <- sim_s3(seed = 5)[season %in% 2019:2020]
  x[, p_copy := p_anchor]
  s <- v3$vvf_s3_skill(x, "p_copy", order = "p_copy")
  expect_identical(s$skill, 0)
  expect_identical(c(s$skill_lo, s$skill_hi), c(0, 0))
  expect_identical(s$brier_diff, 0)
  expect_identical(s$logloss_diff, 0)
  expect_equal(s$dm_p_better, 1)
})

test_that("candidates must be exactly the declared order", {
  x <- sim_s3(seed = 6)[season == 2020]
  x[, `:=`(p_a = p_anchor, p_b = p_anchor)]
  expect_error(v3$vvf_s3_skill(x, c("p_a", "p_b"), order = c("p_b", "p_a")), "declared order")
  expect_error(v3$vvf_s3_skill(x, "p_a", order = c("p_a", "p_b")), "declared order")
})

test_that("the screen runs S0 first, reports skipped weeks, and scores every feature in order", {
  withr::local_dir(PROJECT_ROOT)
  d <- sim_s3(seasons = 2018:2020, beta = 0, seed = 7)
  d[, `:=`(rest_diff = z, turf = as.integer(z > 0))]
  expect_error(v3$vvf_s3_screen(d, c("rest_diff", "d_c1"), "open_isa", 2020L), "known-at violation")
  s <- v3$vvf_s3_screen(d, c("rest_diff", "turf"), "open_isa", 2019:2020, B = 2000L)
  expect_equal(s$skill$feature, c("rest_diff", "turf"))
  expect_equal(s$meta$rest_diff$weeks_skipped_min_train, 0L)
  expect_identical(s$anchor, "open")
  short <- v3$vvf_s3_screen(d, "rest_diff", "open_isa", 2018L, B = 2000L)
  expect_gt(short$meta$rest_diff$weeks_skipped_min_train, 0L)
  expect_error(v3$vvf_s3_screen(d, "rest_diff", "open_isa", 2025L), "sealed-season guard")
})

test_that("S3 refuses a close anchor at an opener decision and a table with a sealed season (A3a C1, I5)", {
  withr::local_dir(PROJECT_ROOT)
  d <- sim_s3(seasons = 2018:2020, beta = 0, seed = 8)
  d[, rest_diff := z]
  data.table::setattr(d, "vvf_anchor", "close")
  expect_error(v3$vvf_s3_screen(d, "rest_diff", "open_isa", 2020L, B = 99L), "the close anchor is known only at close")
  s <- sim_s3(seasons = 2018:2020, beta = 0, seed = 9)
  s[, rest_diff := z]
  s[1, season := 2025L]
  expect_error(v3$vvf_s3_screen(s, "rest_diff", "open_isa", 2020L, B = 99L), "sealed-season guard")
})
