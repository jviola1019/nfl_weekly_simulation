# VVF stage S1, the screen (backtest/vvf/s1_screen.R): known-answer tests from
# the design (2026-10-20 §4). The LR and F statistics equal anova(); a planted
# effect is found; null false-positive rates sit in the binomial band, for the
# week-clustered test and for the wild cluster bootstrap below 30 clusters; the
# MDE reproduces mde.R; BH runs within each family; S0 runs first.

vs <- vvf_test_env(c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R"),
                   v1_files = VVF_TEST_V1_FILES)

# n games in `weeks` week clusters; the anchor is a realistic market logit
sim_screen_data <- function(n, weeks, beta = 0, seed = 1, linear = FALSE) {
  set.seed(seed)
  d <- data.table::data.table(wk = rep(seq_len(weeks), length.out = n), lp_anchor = stats::rnorm(n, 0.2, 0.8),
                              z = as.numeric(scale(stats::rnorm(n))))
  d[, p_anchor := stats::plogis(lp_anchor)]
  d[, y := stats::rbinom(n, 1, stats::plogis(lp_anchor + beta * z))]
  if (linear) d[, delta := beta * z + stats::rnorm(n, 0, 0.3)]
  data.table::setattr(d, "vvf_anchor", "open")
  d
}

test_that("the outcome LR statistic and p equal anova(m0, m1, test = 'Chisq')", {
  d <- sim_screen_data(600, 40, beta = 0.15, seed = 3)
  r <- vs$vvf_s1_one(d, "outcome", "z", "y")
  m0 <- stats::glm(y ~ 1, offset = lp_anchor, family = stats::binomial(), data = d)
  m1 <- stats::glm(y ~ 1 + z, offset = lp_anchor, family = stats::binomial(), data = d)
  a <- stats::anova(m0, m1, test = "Chisq")
  expect_equal(r$stat, a$Deviance[2], tolerance = 1e-10)
  expect_equal(r$p_test, a$`Pr(>Chi)`[2], tolerance = 1e-10)
  expect_equal(r$estimate, unname(stats::coef(m1)[["z"]]))
})

test_that("the movement F statistic and p equal anova(lm(delta ~ 1), lm(delta ~ 1 + x))", {
  d <- sim_screen_data(300, 35, beta = 0.05, seed = 4, linear = TRUE)
  r <- vs$vvf_s1_one(d, "movement", "z", "delta")
  a <- stats::anova(stats::lm(delta ~ 1, data = d), stats::lm(delta ~ 1 + z, data = d))
  expect_equal(r$stat, a$F[2], tolerance = 1e-10)
  expect_equal(r$p_test, a$`Pr(>F)`[2], tolerance = 1e-10)
})

test_that("a planted effect of 0.5 log-odds per SD (n = 2,000) is rejected at p < 0.01, above and below 30 clusters", {
  d <- sim_screen_data(2000, 100, beta = 0.5, seed = 5)
  r <- vs$vvf_s1_one(d, "outcome", "z", "y")
  expect_equal(r$robust_method, "vcovCL HC0")
  expect_lt(r$p, 0.01)
  d15 <- sim_screen_data(2000, 15, beta = 0.5, seed = 5)
  r15 <- vs$vvf_s1_one(d15, "outcome", "z", "y")
  expect_match(r15$robust_method, "^wild score bootstrap")
  expect_lt(r15$p, 0.01)
  expect_equal(r15$p_robust, 1 / 10000)   # never 0: (1 + hits) / (B + 1)
  expect_equal(r$effect_per_sd, r$estimate * r$sd_x)
})

test_that("over 500 null simulations the false-positive rate is inside the binomial band", {
  band <- stats::qbinom(c(0.025, 0.975), 500, 0.05) / 500
  rej <- vapply(seq_len(500), function(s) {
    d <- sim_screen_data(400, 40, beta = 0, seed = 1000 + s)
    vs$vvf_s1_one(d, "outcome", "z", "y")$p_test < 0.05
  }, logical(1))
  expect_gte(mean(rej), band[1]); expect_lte(mean(rej), band[2])
})

test_that("with 12 week clusters the wild bootstrap holds its size under the null", {
  band <- stats::qbinom(c(0.025, 0.975), 500, 0.05) / 500
  rej_o <- rej_l <- logical(500)
  for (s in seq_len(500)) {
    d <- sim_screen_data(240, 12, beta = 0, seed = 5000 + s, linear = TRUE)
    rej_o[s] <- vs$vvf_s1_one(d, "outcome", "z", "y", B = 999L)$p_robust < 0.05
    rej_l[s] <- vs$vvf_s1_one(d, "movement", "z", "delta", B = 999L)$p_robust < 0.05
  }
  expect_gte(mean(rej_o), band[1]); expect_lte(mean(rej_o), band[2])
  expect_gte(mean(rej_l), band[1]); expect_lte(mean(rej_l), band[2])
})

test_that("the wild bootstrap is reproducible, keeps the caller's RNG, and agrees with vcovCL when clusters are many", {
  d <- sim_screen_data(400, 12, beta = 0.2, seed = 9, linear = TRUE)
  set.seed(11); before <- stats::runif(1); set.seed(11)
  a <- vs$vvf_wild_p_linear(d$delta, d$z, d$wk, B = 999L, seed = 7L)
  expect_equal(stats::runif(1), before)
  expect_identical(a, vs$vvf_wild_p_linear(d$delta, d$z, d$wk, B = 999L, seed = 7L))
  many <- sim_screen_data(3000, 150, beta = 0.06, seed = 12)
  set.seed(13); many[, delta := 0.012 * z + stats::rnorm(.N, 0, 0.3)]
  r <- vs$vvf_s1_one(many, "movement", "z", "delta")
  w <- vs$vvf_wild_p_linear(many$delta, many$z, many$wk, B = 9999L, seed = 7L)
  expect_lt(abs(w - r$p_robust), 0.02)
  ws <- vs$vvf_wild_p_score(many$y, many$lp_anchor, many$z, many$wk, B = 9999L, seed = 7L)
  ro <- vs$vvf_s1_one(many, "outcome", "z", "y")
  expect_lt(abs(ws - ro$p_robust), 0.02)
})

test_that("the MDE per SD reproduces mde.R on the 2024 ESPN BET openers", {
  d <- utils::read.csv(file.path(PROJECT_ROOT, "backtest", "data", "espn_open_close.csv"), colClasses = "character")
  am <- function(x) { x <- as.numeric(x); ifelse(x < 0, -x / (-x + 100), 100 / (x + 100)) }
  p <- am(d$h_open) / (am(d$h_open) + am(d$a_open))
  v <- mean(p[is.finite(p)] * (1 - p[is.finite(p)]))
  expect_equal(round(vs$vvf_mde_per_sd(205, "outcome", v = v), 3), 0.417)
  expect_equal(round(vs$vvf_mde_per_sd(284, "outcome", v = v), 3), 0.354)
  expect_equal(round(vs$vvf_mde_per_sd(284, "outcome", v = v, k = 36), 3), 0.511)
  expect_equal(round(vs$vvf_mde_per_sd(489, "outcome", v = v, k = 36), 3), 0.389)
  expect_equal(vs$vvf_mde_per_sd(100, "spread", sigma = 13), (stats::qnorm(0.975) + stats::qnorm(0.8)) * 13 / 10)
})

test_that("the screen runs S0 first, applies BH within each family and labels each verdict", {
  withr::local_dir(PROJECT_ROOT)
  reg <- vs$vvf_registry()
  d <- sim_screen_data(800, 40, beta = 0, seed = 21, linear = TRUE)
  set.seed(22)
  d[, `:=`(rest_diff = stats::rnorm(.N), abs_tz_away = z, turf = stats::rbinom(.N, 1, 0.5), neutral_site = 0L)]
  expect_error(vs$vvf_s1_screen(d, c("rest_diff", "d_c1"), "open_isa", families = c(outcome = "y"), registry = reg),
               "known-at violation")
  s <- vs$vvf_s1_screen(d, c("rest_diff", "abs_tz_away", "turf", "neutral_site"), "open_isa",
                        families = c(outcome = "y", movement = "delta"), registry = reg)
  f <- s$features
  expect_equal(nrow(f), 8L)
  expect_identical(f[feature == "neutral_site", unique(verdict)], "not testable (constant)")
  for (fam in c("outcome", "movement")) {
    x <- f[family == fam & is.finite(p)]
    expect_equal(x$q_bh, stats::p.adjust(x$p, "BH"))
    expect_equal(x$p, pmax(x$p_test, x$p_robust))
  }
  expect_true(all(grepl("^(signal \\(q < 0.05\\)|no evidence \\(MDE = [0-9.]+ per SD\\))$", f[is.finite(p), verdict])))
  expect_identical(unique(f$anchor), "open"); expect_identical(unique(f$decision), "open_isa")
  bare <- data.table::data.table(y = 1)
  expect_error(vs$vvf_s1_screen(bare, "rest_diff", "open_isa", registry = reg), "no anchor")
})

test_that("the joint test counts only estimable coefficients and equals anova() on the same models", {
  d <- sim_screen_data(700, 40, beta = 0.1, seed = 31)
  set.seed(32)
  d[, `:=`(x1 = stats::rnorm(.N), x2 = stats::rnorm(.N))]
  d[, x3 := x1 + x2]
  j <- vs$vvf_s1_joint(d, "outcome", c("z", "x1", "x2", "x3"), "y")
  m0 <- stats::glm(y ~ 1, offset = lp_anchor, family = stats::binomial(), data = d)
  m1 <- stats::glm(y ~ 1 + z + x1 + x2 + x3, offset = lp_anchor, family = stats::binomial(), data = d)
  a <- stats::anova(m0, m1, test = "Chisq")
  expect_equal(j$df, 3L)
  expect_equal(j$df, a$Df[2])
  expect_equal(j$stat, a$Deviance[2], tolerance = 1e-10)
  expect_equal(j$p_test, a$`Pr(>Chi)`[2], tolerance = 1e-10)
  expect_identical(j$aliased, "x3")
  expect_equal(j$k_entered, 4L)
})
