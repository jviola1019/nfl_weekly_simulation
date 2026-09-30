# Validation sprint v2 blends and calibrators (backtest/v2/models.R): leak canary and
# reproducibility on a synthetic schedule. A week's prediction may use only games
# that kicked off before that week, so rewriting every later result or feature must
# leave it unchanged, for every model family and every calibration map.

mv_env <- new.env()
for (f in c("common.R", "calibrators.R", "metrics.R")) sys.source(file.path(PROJECT_ROOT, "backtest", f), envir = mv_env)
for (f in c("common.R", "features.R", "models.R")) sys.source(file.path(PROJECT_ROOT, "backtest", "v2", f), envir = mv_env)
mv <- function(name) get(name, envir = mv_env)

synthetic_features <- function(seed = 7L) {
  set.seed(seed)
  seasons <- 2010:2015; weeks <- 1:17; per <- 16L
  d <- data.table::CJ(season = seasons, week = weeks, slot = seq_len(per))
  d[, `:=`(game_id = sprintf("%d_%02d_%02d", season, week, slot),
           kickoff = as.POSIXct(sprintf("%d-09-01 17:00:00", season), tz = "UTC") + (week - 1) * 7 * 86400 + slot * 60)]
  d[, `:=`(wk = season * 100L + week, lp_c0 = stats::rnorm(.N, 0.2, 0.8))]
  d[, p_c0 := plogis(lp_c0)]
  d[, `:=`(p_c1 = plogis(lp_c0 + stats::rnorm(.N, 0, 0.3)), p_c2 = plogis(lp_c0 + stats::rnorm(.N, 0, 0.3)))]
  d[, p_e1 := plogis((qlogis(p_c1) + qlogis(p_c2)) / 2)]
  for (f in mv("bt2_model_features")()) data.table::set(d, j = f, value = stats::rnorm(nrow(d)))
  d[, y := stats::rbinom(.N, 1, p_c0)]
  d[]
}
week_table <- function(d) d[, .(cutoff = min(kickoff)), by = .(season, week, wk)][order(cutoff)]

test_that("rewriting every later result and feature leaves a week's blend predictions unchanged", {
  d <- synthetic_features()
  target <- week_table(d)[wk == 201510L]
  models <- c("LR_E1", "LR_C1C2", "GLMNET", "XGB", "XGB_FREE", "GBM")
  a <- mv("bt2_walk_models")(d, target, models = models, first_season = 2015L)$pred
  d2 <- data.table::copy(d)
  later <- d2$kickoff >= target$cutoff
  d2[later, y := 1L - y]
  for (f in mv("bt2_model_features")()) data.table::set(d2, i = which(later & d2$wk != 201510L), j = f, value = 99)
  b <- mv("bt2_walk_models")(d2, target, models = models, first_season = 2015L)$pred
  expect_equal(nrow(a), 16L)
  for (m in models) expect_identical(a[[paste0("p_", m)]], b[[paste0("p_", m)]], info = m)
})

test_that("walk-forward blend predictions are reproducible run to run", {
  d <- synthetic_features()
  target <- week_table(d)[wk == 201505L]
  a <- mv("bt2_walk_models")(d, target, models = c("XGB", "GBM", "GLMNET"), first_season = 2015L)$pred
  b <- mv("bt2_walk_models")(d, target, models = c("XGB", "GBM", "GLMNET"), first_season = 2015L)$pred
  expect_identical(a, b)
})

test_that("calibration maps for a week are fit only on earlier weeks", {
  d <- synthetic_features()
  wt <- week_table(d)
  pred <- d[, .(game_id, p_x = p_c1)]
  for (m in c("platt", "isotonic", "spline")) {
    a <- mv("bt2_calibrate")(pred, d, wt[wk == 201512L], "p_x", m)
    d2 <- data.table::copy(d); d2[kickoff >= wt[wk == 201512L, cutoff], y := 1L - y]
    b <- mv("bt2_calibrate")(pred, d2, wt[wk == 201512L], "p_x", m)
    expect_identical(a$p, b$p, info = m)
  }
})

test_that("an anchored xgboost with no signal stays close to the market", {
  d <- synthetic_features()
  target <- week_table(d)[wk == 201516L]
  a <- mv("bt2_walk_models")(d, target, models = "XGB", first_season = 2015L)$pred
  m <- merge(a, d[, .(game_id, p_c0)], by = "game_id")
  expect_lt(max(abs(m$p_XGB - m$p_c0)), 0.05)
})
