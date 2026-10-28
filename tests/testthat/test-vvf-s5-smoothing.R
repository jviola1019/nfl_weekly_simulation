# VVF stage S5, exponential smoothing (backtest/vvf/s5_smoothing.R and the
# engine's two weight functions; amendment 2026-10-21, item 1). Nothing in
# NFLsimulation.R runs: only the named definitions are evaluated.

v5m <- vvf_test_env("s5_smoothing.R", v1_files = character())
sim_path <- file.path(PROJECT_ROOT, "NFLsimulation.R")

# The definition of `name` inside function `fun`'s body, evaluated in `envir`.
# Safety: only a `name <- function(...)` definition from this repository's own
# tracked NFLsimulation.R is evaluated, as load_script_functions() does.
nested_def <- function(fun, name, envir) {
  for (e in as.list(body(fun))) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(name))) {
      f <- eval(e[[3]], envir)
      return(f)
    }
  }
  stop("no definition of ", name)
}

test_that("recency_weights() gives the newest game weight 1 and halves every half-life", {
  env <- load_script_functions(sim_path, "recency_weights")
  env$USE_RECENCY_DECAY <- TRUE
  w <- env$recency_weights(10, halflife = 3)
  expect_equal(w[1], 1)
  expect_equal(w[4], 0.5)
  expect_equal(w[7], 0.25)
  expect_equal(env$recency_weights(6, halflife = 2.5), 0.5^((0:5) / 2.5))
  env$USE_RECENCY_DECAY <- FALSE
  expect_equal(env$recency_weights(5, halflife = 3), rep(1, 5))
})

test_that("the calibration path's rec_wts() gives the same weights", {
  env <- load_script_functions(sim_path, c("recency_weights", "recent_form_at_sim"))
  env$USE_RECENCY_DECAY <- TRUE
  inner <- new.env(parent = env)
  inner$halflife <- 3
  rec_wts <- nested_def(env$recent_form_at_sim, "rec_wts", inner)
  expect_identical(rec_wts(9), env$recency_weights(9, halflife = 3))
  expect_identical(rec_wts(1), 1)
})

fake_team_games <- function() {
  tibble::tibble(team = "AAA", opponent = "BBB", season = 2023L, week = 1:10,
                 game_date = as.Date("2023-09-10") + 7 * (0:9), points = 10 + 1:10)
}

test_that("both weight functions receive rows newest first, cut before the target week", {
  env <- load_script_functions(sim_path, c("get_recent", "recent_form_at_sim"))
  env$team_games <- fake_team_games()
  env$N_RECENT <- 6L
  for (fn in c("filter", "arrange", "desc", "slice_head")) assign(fn, getExportedValue("dplyr", fn), envir = env)
  g <- env$get_recent("AAA", 2023L, 8L, n_recent = 6L)
  expect_equal(g$week, 7:2)
  inner <- new.env(parent = env)
  inner$cut_season <- 2023L; inner$cut_week <- 8L
  cut <- nested_def(env$recent_form_at_sim, "get_recent_cut", inner)
  expect_equal(cut("AAA")$week, 7:2)
})

test_that("the production points-per-drive tables sort newest first before weighting", {
  exprs <- parse(sim_path, keep.source = FALSE)
  for (nm in c("off_ppd_tbl", "def_ppd_tbl")) {
    hit <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(nm)), exprs)
    txt <- paste(deparse(hit[[1]], width.cutoff = 500L), collapse = " ")
    expect_lt(regexpr("arrange(team, desc(sched_date))", txt, fixed = TRUE), regexpr("recency_weights(", txt, fixed = TRUE))
  }
})

test_that("the recency-weighted mean equals an EWMA with alpha = 1 - 2^(-1/h)", {
  env <- load_script_functions(sim_path, "recency_weights")
  env$USE_RECENCY_DECAY <- TRUE
  set.seed(1)
  y <- stats::rnorm(12, 21, 7)                      # oldest first
  for (h in c(1, 2.5, 3, 8)) {
    wm <- stats::weighted.mean(rev(y), env$recency_weights(length(y), halflife = h))
    ew <- v5m$vvf_ewma(y, v5m$vvf_alpha_for_halflife(h))
    expect_equal(ew[length(y)], wm, tolerance = 1e-12)
  }
  expect_equal(v5m$vvf_alpha_for_halflife(3), 1 - 2^(-1 / 3))
})

test_that("a local-level Kalman filter at its steady state is an EWMA with alpha equal to its gain", {
  K <- v5m$vvf_alpha_for_halflife(3)
  q_over_r <- v5m$vvf_snr_for_gain(K)
  kg <- v5m$vvf_kalman_gain(q_over_r, 1)
  expect_equal(kg$gain, K, tolerance = 1e-12)
  set.seed(2)
  y <- cumsum(stats::rnorm(200, 0, sqrt(q_over_r))) + stats::rnorm(200)
  kf <- v5m$vvf_kalman_local_level(y, q_over_r, 1, m0 = 0)
  ew <- Reduce(function(m, yt) m + K * (yt - m), y, accumulate = TRUE, 0)[-1]
  expect_equal(kf$level, ew, tolerance = 1e-12)
  expect_true(all(abs(kf$gain - K) < 1e-12))
})

test_that("forecast::ets recovers a local level's smoothing constant, per team", {
  K <- 0.3
  q_over_r <- v5m$vvf_snr_for_gain(K)
  set.seed(3)
  d <- data.table::rbindlist(lapply(c("AAA", "BBB"), function(tm) {
    data.table::data.table(team = tm, t = 1:600, value = cumsum(stats::rnorm(600, 0, sqrt(q_over_r))) + stats::rnorm(600))
  }))
  a <- v5m$vvf_team_ets_alpha(d, "team", "value", "t")
  expect_equal(a$team, c("AAA", "BBB"))
  expect_true(all(abs(a$alpha - K) < 0.1))
  short <- v5m$vvf_team_ets_alpha(d[t <= 5], "team", "value", "t")
  expect_true(all(is.na(short$alpha)))
  expect_true(all(short$note == "fewer than 10 observations"))
})
