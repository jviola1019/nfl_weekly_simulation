# VVF stage S2, structure (backtest/vvf/s2_structure.R): VIF <= 5 with the
# declared-first feature kept, aliased and constant features logged, per-period
# signs, the feature x period LR test equal to anova(), and season halves for
# windows of two seasons or fewer, labelled weak.

v2s <- vvf_test_env(c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s2_structure.R"),
                    v1_files = VVF_TEST_V1_FILES)

sim_s2 <- function(n = 1200, seasons = 2018:2021, seed = 1, slope_by_season = NULL) {
  set.seed(seed)
  d <- data.table::data.table(season = rep(seasons, length.out = n), week = rep(1:18, length.out = n))
  d[, wk := season * 100L + week]
  d[, lp_anchor := stats::rnorm(.N, 0.2, 0.8)]
  d[, `:=`(x1 = stats::rnorm(.N), x3 = stats::rnorm(.N))]
  d[, x2 := x1 + stats::rnorm(.N, 0, 0.1)]
  d[, x4 := x1 + x3]
  d[, k0 := 1]
  if (is.null(slope_by_season)) d[, b := 0.4] else d[, b := unname(slope_by_season[as.character(season)])]
  d[, y := stats::rbinom(.N, 1, stats::plogis(lp_anchor + b * x3))]
  d[, delta := 0.1 * x3 + stats::rnorm(.N, 0, 0.3)]
  data.table::setattr(d, "vvf_anchor", "open")
  d
}

test_that("VIF above 5 drops the later-declared feature; aliased and constant features are logged", {
  d <- sim_s2()
  a <- v2s$vvf_s2_vif(d, c("x1", "x3", "x2", "x4", "k0"), "y")
  expect_equal(a$kept, c("x1", "x3"))
  expect_true(all(a$vif <= 5))
  expect_equal(a$dropped$feature, c("k0", "x4", "x2"))
  expect_equal(a$dropped$reason[1:2], c("constant", "aliased"))
  expect_match(a$dropped$reason[3], "^collinear with x1, declared first \\(VIF [0-9.]+ > 5\\)$")
  b <- v2s$vvf_s2_vif(d, c("x2", "x3", "x1"), "y")
  expect_equal(b$kept, c("x2", "x3"))
  expect_equal(b$dropped$feature, "x1")
})

test_that("the feature x period LR statistic equals anova(), and the F test for a linear family", {
  d <- sim_s2(seed = 2)
  s <- v2s$vvf_s2_stability(d, "outcome", "x3", "y")
  m0 <- stats::glm(y ~ factor(season) + x3, offset = lp_anchor, family = stats::binomial(), data = d)
  m1 <- stats::glm(y ~ factor(season) * x3, offset = lp_anchor, family = stats::binomial(), data = d)
  a <- stats::anova(m0, m1, test = "Chisq")
  expect_equal(s$int_stat, a$Deviance[2], tolerance = 1e-10)
  expect_equal(s$int_df, 3L)
  expect_equal(s$int_p, a$`Pr(>Chi)`[2], tolerance = 1e-10)
  l <- v2s$vvf_s2_stability(d, "movement", "x3", "delta")
  al <- stats::anova(stats::lm(delta ~ factor(season) + x3, data = d), stats::lm(delta ~ factor(season) * x3, data = d))
  expect_equal(l$int_stat, al$F[2], tolerance = 1e-10)
  expect_identical(l$periods, "season")
})

test_that("a stable effect keeps its sign in every season; a flipping one is caught", {
  st <- v2s$vvf_s2_stability(sim_s2(seed = 3), "outcome", "x3", "y")
  expect_true(st$sign_consistent)
  expect_equal(st$n_periods, 4L)
  flip <- sim_s2(seed = 4, slope_by_season = c(`2018` = 0.8, `2019` = -0.8, `2020` = 0.8, `2021` = -0.8))
  fl <- v2s$vvf_s2_stability(flip, "outcome", "x3", "y")
  expect_false(fl$sign_consistent)
  expect_lt(fl$int_p, 0.001)
  expect_match(fl$by_period, "^2018: [+-][0-9.]+; 2019: ")
})

test_that("windows of two seasons or fewer use season halves, labelled weak", {
  d <- sim_s2(n = 600, seasons = 2023:2024, seed = 5)
  h <- v2s$vvf_s2_stability(d, "outcome", "x3", "y")
  expect_identical(h$periods, "season halves (weak)")
  expect_equal(h$n_periods, 4L)
  expect_match(h$by_period, "2023 wk<=9")
})

test_that("S2 runs S0 first and reports every family", {
  withr::local_dir(PROJECT_ROOT)
  reg <- v2s$vvf_registry()
  d <- sim_s2(seed = 6)
  d[, `:=`(rest_diff = x1, abs_tz_away = x2, turf = as.integer(x3 > 0))]
  expect_error(v2s$vvf_s2_structure(d, c("rest_diff", "d_c1"), "open_isa", families = c(outcome = "y"), registry = reg),
               "known-at violation")
  s <- v2s$vvf_s2_structure(d, c("rest_diff", "abs_tz_away", "turf"), "open_isa",
                            families = c(outcome = "y", movement = "delta"), registry = reg)
  expect_equal(nrow(s$stability), 6L)
  expect_equal(s$vif[family == "outcome", dropped], "abs_tz_away")
  expect_identical(unique(s$stability$anchor), "open")
})

test_that("the first-declared feature stays when only it is over the limit; its most collinear later partner yields (review I1)", {
  set.seed(7)
  n <- 2000
  d <- data.table::data.table(g1 = stats::rbinom(n, 1, 0.5), g2 = stats::rbinom(n, 1, 0.5), y = stats::rnorm(n))
  d[, f1 := 4 * g1 - 2 * g2 + stats::rnorm(n)]
  v0 <- car::vif(stats::lm(y ~ f1 + g1 + g2, data = d))
  expect_gt(v0[["f1"]], 5)                                           # only the first-declared feature is over the limit
  expect_true(all(v0[c("g1", "g2")] < 5))
  a <- v2s$vvf_s2_vif(d, c("f1", "g1", "g2"), "y")
  expect_equal(a$kept, c("f1", "g2"))
  expect_equal(a$dropped$feature, "g1")
  expect_match(a$dropped$reason, "^collinear with f1, declared first \\(VIF [0-9.]+ > 5\\)$")
  last <- v2s$vvf_s2_vif(d, c("g1", "g2", "f1"), "y")                # declared last, it yields itself
  expect_equal(last$kept, c("g1", "g2"))
  expect_match(last$dropped$reason, "^VIF [0-9.]+ > 5$")
})

test_that("S2 refuses a close anchor at an opener decision, and a sealed season (review C1, I5)", {
  withr::local_dir(PROJECT_ROOT)
  reg <- v2s$vvf_registry()
  d <- sim_s2(seed = 8)
  d[, `:=`(rest_diff = x1, turf = as.integer(x3 > 0))]
  data.table::setattr(d, "vvf_anchor", "close")
  expect_error(v2s$vvf_s2_structure(d, c("rest_diff", "turf"), "open_isa", families = c(outcome = "y"), registry = reg),
               "the close anchor is known only at close")
  s <- sim_s2(seed = 9)
  s[, `:=`(rest_diff = x1, turf = as.integer(x3 > 0))]
  s[1, season := 2025L]
  expect_error(v2s$vvf_s2_structure(s, c("rest_diff", "turf"), "open_isa", families = c(outcome = "y"), registry = reg),
               "sealed-season guard")
})
