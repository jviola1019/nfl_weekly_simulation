# VVF stage S5, validation curves (backtest/vvf/s5_curves.R): on synthetic data
# with a planted half-life, the one-SE choice recovers it (amendment 2026-10-21,
# item 3); validation is nested and walk-forward; learning curves and the
# in-sample against walk-forward gap expose over-fitting.

v5c <- vvf_test_env(c("common.R", "s5_curves.R"), v1_files = VVF_TEST_V1_FILES)

# Signal for event t from x[, 1:(t - 1)], weights 2^(-k / h), unit variance
ewma_signal <- function(x, h) {
  out <- matrix(NA_real_, nrow(x), ncol(x))
  for (t in 2:ncol(x)) {
    k <- 0:(t - 2)
    w <- if (is.infinite(h)) rep(1, length(k)) else 2^(-k / h)
    out[, t] <- (x[, (t - 1):1, drop = FALSE] %*% w) / sqrt(sum(w^2))
  }
  out
}

planted <- function(seed, h0 = 3, n_series = 32L, n_t = 300L, c = 1.5) {
  set.seed(seed)
  x <- matrix(stats::rnorm(n_series * n_t), n_series)
  s0 <- ewma_signal(x, h0)
  y <- matrix(NA_integer_, n_series, n_t)
  y[, -1] <- stats::rbinom(n_series * (n_t - 1), 1, stats::plogis(c * s0[, -1]))
  d <- data.table::data.table(series = rep(seq_len(n_series), n_t), t = rep(seq_len(n_t), each = n_series),
                              y = as.vector(y))
  d[, `:=`(game_id = sprintf("s%02d_t%03d", series, t), wk = t, season = 2000L + (t - 1L) %/% 50L)]
  list(x = x, d = d)
}

predict_h <- function(sim) {
  function(h, seasons) {
    s <- ewma_signal(sim$x, h)
    d <- data.table::copy(sim$d)[, sig := as.vector(s)]
    tr <- d[t >= 2 & t <= 150]
    b <- unname(stats::coef(stats::glm(y ~ 0 + sig, family = stats::binomial(), data = tr))[["sig"]])
    ev <- d[season %in% seasons]
    data.table::data.table(game_id = ev$game_id, p = stats::plogis(b * ev$sig))
  }
}

test_that("the one-SE choice of the validation curve recovers a planted half-life of 3", {
  withr::local_dir(PROJECT_ROOT)                    # the curve guards its seasons against config.R's seal
  grid <- c(Inf, 8, 6, 4, 3, 2, 1)                  # simplest (most smoothing) first
  for (seed in 1:2) {
    sim <- planted(seed)
    ev <- sim$d[season %in% 2003:2005]
    cv <- v5c$vvf_validation_curve(grid, predict_h(sim), ev, seasons = 2003:2005, B = 2000L)
    expect_equal(cv[(best), value], 3)
    expect_equal(cv[(chosen), value], 3)
    expect_true(all(cv$logloss_lo <= cv$logloss & cv$logloss <= cv$logloss_hi))
    expect_equal(cv[(best), diff_to_best], 0)
  }
})

test_that("the one-SE rule prefers the simpler setting when two are within one SE", {
  withr::local_dir(PROJECT_ROOT)
  sim <- planted(3)
  ev <- sim$d[season %in% 2003:2005]
  same <- function(h, seasons) predict_h(sim)(3, seasons)   # every setting predicts the same
  cv <- v5c$vvf_validation_curve(c(8, 3), same, ev, seasons = 2003:2005, B = 500L)
  expect_equal(cv[(chosen), value], 8)
  expect_error(v5c$vvf_validation_curve(c(8, 3), function(h, seasons) predict_h(sim)(h, seasons)[-1], ev,
                                        seasons = 2003:2005, B = 500L), "missing predictions")
})

test_that("nested validation tunes on earlier seasons only and never touches a sealed one", {
  withr::local_dir(PROJECT_ROOT)
  expect_invisible(v5c$vvf_assert_nested(2018:2022, 2023:2024))
  expect_error(v5c$vvf_assert_nested(2018:2022, 2022:2023), "must all follow")
  expect_error(v5c$vvf_assert_nested(2018:2022, 2025L), "sealed-season guard")
})

# A weekly anchored outcome with a planted effect, for the learning curve and the fit gap
weekly <- function(seed, seasons = 2008:2020, beta = 0.4, noise_k = 0L) {
  set.seed(seed)
  g <- data.table::CJ(season = seasons, week = 1:17, k = 1:14)
  g[, game_id := sprintf("%d_%02d_%02d", season, week, k)]
  g[, kickoff := as.POSIXct(sprintf("%d-09-01 17:00:00", season), tz = "UTC") + (week - 1) * 7 * 86400 + k * 60]
  g[, wk := season * 100L + week]
  g[, `:=`(lp = stats::rnorm(.N, 0, 0.8), z = stats::rnorm(.N))]
  g[, y := stats::rbinom(.N, 1, stats::plogis(lp + beta * z))]
  for (j in seq_len(noise_k)) data.table::set(g, j = sprintf("n%02d", j), value = stats::rnorm(nrow(g)))
  g
}
fit_z <- function(tr, tg) {
  b <- stats::coef(stats::glm(y ~ 0 + z, offset = lp, family = stats::binomial(), data = tr))
  stats::plogis(tg$lp + b[["z"]] * tg$z)
}
fit_noise <- function(tr, tg) {
  f <- stats::as.formula(paste("y ~ 1 + z +", paste(grep("^n[0-9]", names(tr), value = TRUE), collapse = " + ")))
  m <- stats::glm(f, offset = lp, family = stats::binomial(), data = tr)
  stats::predict(m, newdata = tg, type = "response")
}

test_that("a learning curve runs from 2 to 10 training seasons on the same games, and a 31-parameter model gains", {
  d <- weekly(4, noise_k = 30L)
  lc <- v5c$vvf_learning_curve(fit_noise, d, 2019:2020, n_train = c(2L, 5L, 10L))
  expect_equal(lc$n_train_seasons, c(2L, 5L, 10L))
  expect_equal(length(unique(lc$n)), 1L)
  expect_lt(lc[n_train_seasons == 10L, logloss], lc[n_train_seasons == 2L, logloss])
})

test_that("an over-fitted model shows a larger in-sample against walk-forward gap", {
  d <- weekly(5, seasons = 2016:2020, noise_k = 30L)
  simple <- v5c$vvf_fit_gap(d, fit_z, 2019:2020)
  complex <- v5c$vvf_fit_gap(d, fit_noise, 2019:2020)
  expect_equal(simple$season, 2019:2020)
  expect_true(all(complex$gap > simple$gap))
  expect_true(all(complex$gap > 0))
})

test_that("the validation curve guards its tuning seasons and, given evaluation seasons, requires them to follow (review I-2)", {
  withr::local_dir(PROJECT_ROOT)
  sim <- planted(4)
  ev <- sim$d[season %in% 2003:2005]
  expect_error(v5c$vvf_validation_curve(c(8, 3), predict_h(sim), ev, seasons = c(2005L, 2025L), B = 200L), "sealed-season guard")
  expect_error(v5c$vvf_validation_curve(c(8, 3), predict_h(sim), ev, seasons = 2003:2005, eval_seasons = 2005:2006, B = 200L),
               "must all follow")
  expect_error(v5c$vvf_validation_curve(c(8, 3), predict_h(sim), ev, seasons = 2003:2005, eval_seasons = 2025L, B = 200L),
               "sealed-season guard")
  ok <- v5c$vvf_validation_curve(c(8, 3), predict_h(sim), ev, seasons = 2003:2005, eval_seasons = 2006:2007, B = 200L)
  expect_equal(nrow(ok), 2L)
})
