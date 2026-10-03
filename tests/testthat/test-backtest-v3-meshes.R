# Blend research v3 (backtest/v3/): leak canary, determinism, chunk invariance and
# shuffled-label sanity for every new family on a synthetic schedule. A week's
# prediction may use only games that kicked off before that week: rewriting every
# later result, feature and level-0 prediction must leave it unchanged.

v3_env <- new.env()
for (f in c("common.R", "calibrators.R", "metrics.R")) sys.source(file.path(PROJECT_ROOT, "backtest", f), envir = v3_env)
for (f in c("common.R", "features.R", "models.R")) sys.source(file.path(PROJECT_ROOT, "backtest", "v2", f), envir = v3_env)
for (f in c("common.R", "meshes.R", "families.R", "score.R")) sys.source(file.path(PROJECT_ROOT, "backtest", "v3", f), envir = v3_env)
v3 <- function(name) get(name, envir = v3_env)

V3_LEVEL0_SYNTH <- c("LR_E1", "GLMNET", "XGB", "GBM")
V3_N1_FIXED <- data.table::data.table(season = 2015L, size = 2L, decay = 10, chosen = TRUE)

synthetic_v3 <- function(seed = 11L) {
  set.seed(seed)
  d <- data.table::CJ(season = 2010:2015, week = 1:17, slot = seq_len(16L))
  d[, `:=`(game_id = sprintf("%d_%02d_%02d", season, week, slot),
           kickoff = as.POSIXct(sprintf("%d-09-01 17:00:00", season), tz = "UTC") + (week - 1) * 7 * 86400 + slot * 60)]
  d[, `:=`(wk = season * 100L + week, lp_c0 = stats::rnorm(.N, 0.2, 0.8))]
  d[, p_c0 := plogis(lp_c0)]
  d[, `:=`(p_c1 = plogis(lp_c0 + stats::rnorm(.N, 0, 0.3)), p_c2 = plogis(lp_c0 + stats::rnorm(.N, 0, 0.3)))]
  d[, p_e1 := plogis((qlogis(p_c1) + qlogis(p_c2)) / 2)]
  for (f in v3("bt2_model_features")()) data.table::set(d, j = f, value = stats::rnorm(nrow(d)))
  teams <- sprintf("T%02d", 1:8)
  d[, `:=`(home_franchise = sample(teams, .N, TRUE), away_franchise = sample(teams, .N, TRUE))]
  d[, y := stats::rbinom(.N, 1, p_c0)]
  # synthetic out-of-fold level-0 predictions, available from 2012 (as v2's start in 2014)
  for (m in V3_LEVEL0_SYNTH) {
    data.table::set(d, j = paste0("p_", m), value = ifelse(d$season >= 2012, plogis(d$lp_c0 + stats::rnorm(nrow(d), 0, 0.1)), NA_real_))
  }
  d[]
}
week_table <- function(d) d[, .(cutoff = min(kickoff)), by = .(season, week, wk)][order(cutoff)]

#' Every later game rewritten: outcomes flipped (the target week's too), and features,
#' prices, level-0 predictions and teams of every later game outside the target week
rewrite_later <- function(d, target) {
  d2 <- data.table::copy(d)
  later <- d2$kickoff >= target$cutoff
  d2[later, y := 1L - y]
  other <- which(later & d2$wk != target$wk)
  for (f in v3("bt2_model_features")()) data.table::set(d2, i = other, j = f, value = 99)
  for (cc in c("p_c1", "p_c2", "p_e1", paste0("p_", V3_LEVEL0_SYNTH))) data.table::set(d2, i = other, j = cc, value = 0.99)
  d2[other, `:=`(lp_c0 = 3, p_c0 = plogis(3), home_franchise = "T01", away_franchise = "T02")]
  d2
}

o1_cols <- c(LR_E1 = "p_LR_E1", GLMNET = "p_GLMNET", XGB = "p_XGB", GBM = "p_GBM", C1 = "p_c1", C2 = "p_c2",
             E1 = "p_e1", C0 = "p_c0")
walk_new <- function(fam, d, weeks) {
  if (fam %in% v3("BT3_MESHES")) return(v3("bt3_walk_meta")(weeks, fam, d)$pred)
  if (fam == "O1") {
    x <- d[season >= 2012L]
    return(v3("bt3_o1_walk")(x, weeks, o1_cols, eta = 4)$pred)
  }
  v3("bt3_walk_family")(weeks, fam, d, n1_params = V3_N1_FIXED)$pred
}
NEW_FAMILIES <- c("S1", "S1_MIN", "R1", "O1", "G2", "G2_GAPS", "T1", "N1", "N1_NARROW")

test_that("rewriting every later result, feature and level-0 prediction leaves a week's predictions unchanged", {
  d <- synthetic_v3()
  target <- week_table(d)[wk == 201510L]
  d2 <- rewrite_later(d, target)
  for (fam in NEW_FAMILIES) {
    a <- walk_new(fam, d, target)
    b <- walk_new(fam, d2, target)
    expect_equal(nrow(a), 16L, info = fam)
    expect_identical(a$p, b$p, info = fam)
  }
})

test_that("the full nesting is point in time: level 0 refit on rewritten data feeds the same S1 and R1 week", {
  d <- synthetic_v3()
  wt <- week_table(d)
  target <- wt[wk == 201510L]
  # level 0 (v2 code) on a few weeks of three seasons up to and including the target week
  lv_weeks <- wt[(season %in% 2013:2014 & week <= 4L) | (season == 2015L & cutoff <= target$cutoff)]
  build <- function(x) {
    lv <- v3("bt2_walk_models")(x, lv_weeks, models = c("LR_E1", "GLMNET"), first_season = 2013L)$pred
    x <- data.table::copy(x)[, c("p_LR_E1", "p_GLMNET") := NULL]
    merge(x, lv, by = "game_id", all.x = TRUE)
  }
  cols <- c(LR_E1 = "p_LR_E1", GLMNET = "p_GLMNET", C1 = "p_c1")
  la <- build(d)
  lb <- build(rewrite_later(d, target))
  for (fam in c("S1", "R1")) {
    a <- v3("bt3_walk_meta")(target, fam, la, cols = cols, min_train = 100L)$pred
    b <- v3("bt3_walk_meta")(target, fam, lb, cols = cols, min_train = 100L)$pred
    expect_equal(nrow(a), 16L, info = fam)
    expect_identical(a$p, b$p, info = fam)
  }
})

test_that("new-family predictions are reproducible run to run", {
  d <- synthetic_v3()
  target <- week_table(d)[wk == 201505L]
  for (fam in NEW_FAMILIES) expect_identical(walk_new(fam, d, target), walk_new(fam, d, target), info = fam)
})

test_that("walking weeks together equals walking them one at a time (parallel chunks give the same result)", {
  d <- synthetic_v3()
  two <- week_table(d)[wk %in% c(201507L, 201512L)]
  for (fam in setdiff(NEW_FAMILIES, "O1")) {
    joint <- walk_new(fam, d, two)
    split1 <- rbind(walk_new(fam, d, two[1]), walk_new(fam, d, two[2]))
    expect_identical(joint, split1, info = fam)
  }
  m <- v3("bt3_map_weeks")(two, "bt3_walk_meta", family = "S1", L = d)
  expect_identical(v3("bt3_combine")(m, d)$pred$p, walk_new("S1", d, two)$p)
})

# 64 games: a family that can reach climatology lands within sampling noise of 0, so the
# bound is 1% Brier skill. The formal control (real data, 1,365 games, bootstrap CI) is
# controls/shuffled_labels.csv from backtest/v3/sprint.R.
test_that("with shuffled outcomes no new family beats climatology", {
  d <- v3("bt3_shuffle_labels")(synthetic_v3(), seed = 20260930L)
  wt <- week_table(d)
  target <- wt[season == 2015L & week %in% 9:12]
  clim <- v3("bt3_climatology")(d, target)
  for (fam in NEW_FAMILIES) {
    p <- merge(walk_new(fam, d, target), d[, .(game_id, wk, y)], by = "game_id")
    p <- merge(p, clim, by = "wk")
    skill <- 1 - mean((p$p - p$y)^2) / mean((p$p_clim - p$y)^2)
    expect_equal(nrow(p), 64L, info = fam)
    expect_lt(skill, 0.01, label = fam)
  }
})

test_that("the shuffled-label permutation is v2's (bt2_control_shuffle) and leaves inputs alone", {
  d <- synthetic_v3()
  x <- v3("bt3_shuffle_labels")(d, seed = 20260930L)
  ref <- data.table::copy(d)
  lab <- which(!is.na(ref$y))
  set.seed(20260930L, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  ref$y[lab] <- ref$y[lab][sample.int(length(lab))]
  expect_identical(x$y, ref$y)
  expect_identical(x[, -"y"], d[, -"y"])
})

test_that("O1 weights use only past losses and its learning rate is chosen before Tune", {
  expect_lt(max(v3("BT3_O1_SELECT_SEASONS")), min(v3("BT2_TUNE_SEASONS")))
  d <- synthetic_v3()[season >= 2012L]
  wt <- week_table(d)
  w <- v3("bt3_o1_walk")(d, wt[wk %in% c(201201L, 201202L)], o1_cols, eta = 4)$weights
  first <- w[wk == 201201L]
  expect_equal(first$weight, rep(1 / length(o1_cols), length(o1_cols)))   # no past losses: uniform
  expect_equal(sum(w[wk == 201202L]$weight), 1)
})

test_that("N1 keeps the skip weight on logit(close) at 1, so a heavily decayed net stays at the market", {
  d <- synthetic_v3()
  target <- week_table(d)[wk == 201516L]
  tr <- d[kickoff < target$cutoff & !is.na(y)]
  tg <- d[wk == 201516L]
  inp <- v3("bt3_n1_inputs")(tr, tg)
  fit <- v3("bt3_n1_fit")(inp$train, tr$y, size = 2L, decay = 1e4)
  k <- 2L * (ncol(inp$train) + 1L) + 1L + 2L + 1L
  expect_equal(fit$wts[k], 1)
  p <- drop(stats::predict(fit, inp$target, type = "raw"))
  expect_lt(max(abs(p - tg$p_c0)), 0.02)
  # contrast: without the fixed weight the same decay shrinks the market term and pulls games toward 0.5
  set.seed(1)
  free <- nnet::nnet(inp$train, tr$y, size = 2L, skip = TRUE, entropy = TRUE, decay = 1e4, maxit = 500, trace = FALSE)
  expect_gt(max(abs(drop(stats::predict(free, inp$target, type = "raw")) - tg$p_c0)), 0.2)
})

test_that("N1 tuning for a season uses only games before the season's first kickoff", {
  d <- synthetic_v3()
  wt <- week_table(d)
  first <- wt[wk == 201501L]
  d2 <- data.table::copy(d)
  d2[kickoff >= first$cutoff, y := 1L - y]
  a <- v3("bt3_n1_params")(first, d, sizes = 1L, decays = c(10, 100))
  b <- v3("bt3_n1_params")(first, d2, sizes = 1L, decays = c(10, 100))
  expect_identical(a[, -"seconds"], b[, -"seconds"])
  expect_equal(sum(a$chosen), 1L)
})

test_that("v3 fits refuse any season after the Tune window", {
  d <- synthetic_v3()
  bad <- data.table::copy(d)[1][, season := 2023L]
  d <- rbind(d, bad)
  target <- week_table(d[season < 2023L])[wk == 201510L]
  expect_error(v3("bt3_walk_meta")(target, "S1", d), "sealed-season guard")
  expect_error(v3("bt3_walk_family")(target, "G2", d), "sealed-season guard")
  expect_error(v3("bt3_o1_walk")(d, target, o1_cols, eta = 1), "sealed-season guard")
})

test_that("scoring a copy of the reference gives zero skill and BH runs over every candidate", {
  set.seed(3)
  ev <- data.table::data.table(game_id = sprintf("g%03d", 1:200), wk = rep(1:20, each = 10L),
                               kickoff = as.POSIXct("2020-09-01", tz = "UTC") + (1:200) * 3600)
  ev[, p_c0 := plogis(stats::rnorm(.N))][, y := stats::rbinom(.N, 1, p_c0)]
  ev[, `:=`(p_copy = p_c0, p_noise = plogis(qlogis(p_c0) + stats::rnorm(.N, 0, 0.5)))]
  tab <- v3("bt3_score_all")(ev, c("p_copy", "p_noise"))
  expect_equal(tab[column == "p_copy", skill], 0)
  expect_equal(tab[column == "p_copy", ll_skill], 0)
  expect_lt(tab[column == "p_noise", skill], 0)
  expect_equal(sort(tab[column != "p_c0", bh_q]), sort(stats::p.adjust(tab[column != "p_c0", dm_p], method = "BH")))
})
