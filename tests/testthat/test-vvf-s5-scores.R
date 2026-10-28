# VVF stage S5, scoring diagnostics (backtest/vvf/s5_scores.R): each identity
# holds exactly, and each diagnostic tells a good forecast from a bad one.

v5s <- vvf_test_env(c("common.R", "s5_scores.R"), v1_files = VVF_TEST_V1_FILES)

test_that("the Murphy decomposition adds up to the Brier score exactly, binned or by value", {
  set.seed(1)
  p <- stats::runif(3000, 0.05, 0.95)
  y <- stats::rbinom(3000, 1, p)
  m <- v5s$vvf_murphy(p, y, bins = 10L)
  expect_equal(m$reliability - m$resolution + m$uncertainty + m$within_bin_variance - 2 * m$within_bin_covariance,
               mean((p - y)^2), tolerance = 1e-12)
  expect_equal(m$bins, 10L)
  pd <- sample(c(0.2, 0.4, 0.6, 0.8), 3000, replace = TRUE)
  yd <- stats::rbinom(3000, 1, pd)
  md <- v5s$vvf_murphy(pd, yd, bins = "value")
  expect_equal(md$within_bin_variance, 0)
  expect_equal(md$within_bin_covariance, 0)
  expect_equal(md$reliability - md$resolution + md$uncertainty, mean((pd - yd)^2), tolerance = 1e-12)
  sharp <- v5s$vvf_murphy(p, y); flat <- v5s$vvf_murphy(rep(mean(y), 3000), y, bins = "value")
  expect_gt(sharp$resolution, flat$resolution)
})

test_that("the calibration label calls an overconfident forecast overconfident", {
  set.seed(2)
  lp <- stats::rnorm(4000, 0, 1)
  y <- stats::rbinom(4000, 1, stats::plogis(lp))
  expect_identical(v5s$vvf_calibration_label(stats::plogis(lp), y)$label, "slope consistent with 1")
  expect_identical(v5s$vvf_calibration_label(stats::plogis(2 * lp), y)$label, "overconfident (slope < 1)")
  expect_identical(v5s$vvf_calibration_label(stats::plogis(0.5 * lp), y)$label, "underconfident (slope > 1)")
})

test_that("MSE is bias squared plus variance, exactly", {
  set.seed(3)
  pred <- stats::rnorm(500, 3, 7); obs <- pred + stats::rnorm(500, 1.5, 13)
  bv <- v5s$vvf_bias_variance(pred, obs)
  expect_equal(bv$mse, bv$bias^2 + bv$variance, tolerance = 1e-12)
  expect_equal(bv$bias, mean(obs - pred))
  expect_equal(bv$n, 500L)
})

test_that("CRPS: a point mass scores |y - m|; the NB sum equals the kernel form; samples converge", {
  expect_equal(v5s$vvf_crps_probs(7L, c(rep(0, 10), 1)), 3)       # all mass at 10
  expect_equal(v5s$vvf_crps_probs(12L, c(rep(0, 10), 1)), 2)      # y beyond the support
  mu <- 23; size <- 9; y <- 17L
  k <- 0:400; pk <- stats::dnbinom(k, size = size, mu = mu)
  kernel <- sum(pk * abs(k - y)) - 0.5 * sum(outer(pk, pk) * abs(outer(k, k, "-")))
  expect_equal(v5s$vvf_crps_nb(y, mu, size), kernel, tolerance = 1e-8)
  set.seed(4)
  expect_equal(v5s$vvf_crps_sample(y, stats::rnbinom(20000, size = size, mu = mu)), kernel, tolerance = 0.02)
  expect_length(v5s$vvf_crps_nb(c(10L, 30L), c(20, 25), size), 2L)
})

test_that("the randomized PIT is uniform for the right NB and U-shaped for an overconfident one", {
  set.seed(5)
  y <- stats::rnbinom(5000, size = 4, mu = 22)
  ok <- v5s$vvf_pit_histogram(v5s$vvf_pit_nb(y, 22, 4))
  expect_gt(ok$p, 0.01)
  expect_equal(sum(ok$counts), 5000L)
  bad <- v5s$vvf_pit_histogram(v5s$vvf_pit_nb(y, 22, 50))         # far too little dispersion
  expect_lt(bad$p, 1e-6)
  expect_gt(bad$counts[1] + bad$counts[10], bad$counts[5] + bad$counts[6])
  expect_identical(v5s$vvf_pit_nb(y[1:5], 22, 4), v5s$vvf_pit_nb(y[1:5], 22, 4))
})

test_that("effective degrees of freedom: all columns without a penalty, the unpenalized ones under a huge one", {
  set.seed(6)
  X <- cbind(1, matrix(stats::rnorm(600 * 4), 600))
  w <- stats::runif(600, 0.1, 0.25)
  expect_equal(v5s$vvf_edf_ridge(X, w, 0), 5, tolerance = 1e-8)
  expect_equal(v5s$vvf_edf_ridge(X, w, 1e10, unpenalized = 1L), 1, tolerance = 1e-4)
  e <- v5s$vvf_edf_ridge(X, w, 100, unpenalized = 1L)
  expect_true(e > 1 && e < 5)
  fit <- stats::glm(rbinom(600, 1, 0.5) ~ X[, -1], family = stats::binomial())
  expect_equal(v5s$vvf_edf(fit), 5L)
})
