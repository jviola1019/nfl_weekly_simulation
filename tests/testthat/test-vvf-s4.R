# VVF stage S4, controls (backtest/vvf/s4_controls.R): each control passes on a
# sound harness and fails on a broken one. Any gating failure voids a run.

v4 <- vvf_test_env(c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s3_skill.R", "s4_controls.R"),
                   v1_files = VVF_TEST_V1_FILES)

sim_s4 <- function(seasons = 2016:2020, weeks = 17L, per_week = 14L, beta = 0, seed = 1) {
  set.seed(seed)
  g <- data.table::CJ(season = seasons, week = seq_len(weeks), k = seq_len(per_week))
  g[, game_id := sprintf("%d_%02d_%02d", season, week, k)]
  g[, kickoff := as.POSIXct(sprintf("%d-09-01 17:00:00", season), tz = "UTC") + (week - 1) * 7 * 86400 + k * 60]
  g[, wk := season * 100L + week]
  g[, lp_anchor := stats::rnorm(.N, 0.2, 0.8)]
  g[, p_anchor := stats::plogis(lp_anchor)]
  g[, rest_diff := stats::rnorm(.N)]
  g[, y := stats::rbinom(.N, 1, stats::plogis(lp_anchor + beta * rest_diff))]
  data.table::setattr(g, "vvf_anchor", "open")
  g
}

test_that("the leak canary passes on the real feature builder and catches a leaky column", {
  withr::local_dir(PROJECT_ROOT)
  inputs <- list(v1 = v4$vvf_load_v1_inputs(max_season = 2011L), v2 = v4$vvf_load_inputs(), max_season = 2011L)
  build <- function(inp) v4$vvf_build_features(v4$vvf_base_predictions(inp$v1, inp$max_season), inp$v2, inp$max_season)
  ok <- v4$vvf_control_canary(build, inputs, v4$vvf_canary_append)
  expect_true(ok$passed)
  expect_equal(ok$added, 1L)
  expect_length(ok$changed, 0L)
  leaky <- function(inp) {
    d <- build(inp)
    d[, season_margin := mean(home_score - away_score, na.rm = TRUE), by = season][]
  }
  bad <- v4$vvf_control_canary(leaky, inputs, v4$vvf_canary_append)
  expect_false(bad$passed)
  expect_identical(bad$changed, "season_margin")
})

test_that("200 placebo features reject inside [0.020, 0.080], and a liberal test fails the band", {
  d <- sim_s4(seed = 2)
  pl <- v4$vvf_control_placebo(d)
  expect_equal(pl$k, 200L)
  expect_true(pl$passed)
  expect_gte(pl$rate, 0.020); expect_lte(pl$rate, 0.080)
  expect_identical(pl$p, v4$vvf_control_placebo(d)$p)
  expect_false(v4$vvf_control_placebo(d, alpha = 0.5)$passed)
})

test_that("labels are shuffled within week by default, reproducibly, without touching the caller's RNG", {
  d <- sim_s4(seed = 3)
  set.seed(9); before <- stats::runif(1); set.seed(9)
  s <- v4$vvf_shuffle_y(d)
  expect_equal(stats::runif(1), before)
  expect_equal(s[, sum(y), by = wk]$V1, d[, sum(y), by = wk]$V1)
  expect_false(identical(s$y, d$y))
  expect_identical(s$y, v4$vvf_shuffle_y(d)$y)
  expect_identical(attr(s, "vvf_anchor"), "open")
  g <- v4$vvf_shuffle_y(d, within = "all")
  expect_equal(sum(g$y), sum(d$y))
  expect_false(isTRUE(all.equal(g[, sum(y), by = wk]$V1, d[, sum(y), by = wk]$V1)))
})

test_that("a planted effect has skill until its labels are shuffled; then every interval includes 0", {
  withr::local_dir(PROJECT_ROOT)
  d <- sim_s4(beta = 0.5, seed = 4)
  real <- v4$vvf_s3_screen(d, "rest_diff", "open_isa", 2019:2020, B = 2000L)
  expect_gt(real$skill$skill_lo, 0)
  sh <- v4$vvf_control_shuffle(d, "rest_diff", "open_isa", 2019:2020, B = 2000L)
  expect_true(sh$passed)
  expect_identical(sh$within, "wk")
})

test_that("the anchor copy scores exactly 0, and the reproducibility control compares result hashes", {
  d <- sim_s4(seed = 5)
  ac <- v4$vvf_control_anchor_copy(d, 2019:2020, B = 2000L)
  expect_true(ac$passed)
  expect_identical(ac$skill, 0)
  stable <- function(out) { v4$vvf_write_csv(data.table::data.table(a = 1:3), file.path(out, "x.csv")); v4$vvf_result_sha256(file.path(out, "x.csv")) }
  expect_true(v4$vvf_control_repro(stable)$passed)
  noisy <- function(out) { v4$vvf_write_csv(data.table::data.table(a = stats::runif(3)), file.path(out, "x.csv")); v4$vvf_result_sha256(file.path(out, "x.csv")) }
  expect_false(v4$vvf_control_repro(noisy)$passed)
})

test_that("the S4 report voids the run when any control fails", {
  r <- v4$vvf_s4_report(list(canary = list(passed = TRUE), placebo = list(passed = FALSE, rate = 0.1)))
  expect_false(r$all_passed)
  expect_identical(r$status, "void")
  expect_equal(r$table$control, c("canary", "placebo"))
  expect_identical(v4$vvf_s4_report(list(canary = list(passed = TRUE)))$status, "complete")
})

# The researched nulls (reports/2026-10-28/a3-research/RESEARCH.md): y drawn from the anchor, and x
# permuted within week, each judged by S3's own claim rule.

test_that("the anchor null redraws y from the anchor and keeps everything else", {
  d <- sim_s4(per_week = 20L, seed = 6)
  d[c(3, 50), y := NA_integer_]
  set.seed(9); before <- stats::runif(1); set.seed(9)
  r <- v4$vvf_resample_y(d)
  expect_equal(stats::runif(1), before)
  for (cc in setdiff(names(d), "y")) expect_identical(r[[cc]], d[[cc]], info = cc)
  expect_identical(attr(r, "vvf_anchor"), "open")
  expect_true(all(is.na(r$y[c(3, 50)])))
  expect_false(identical(r$y, d$y))
  expect_identical(r$y, v4$vvf_resample_y(d)$y)
  i <- which(!is.na(d$y))
  p <- d$p_anchor[i]
  expect_lt(abs(mean(r$y[i]) - mean(p)), 3 * sqrt(sum(p * (1 - p))) / length(i))
})

test_that("under a calibrated anchor neither null claims a feature that only tracks it, and the spec's shuffle does", {
  withr::local_dir(PROJECT_ROOT)
  # a control at level 0.05 fails 5% of the time on a sound pipeline, so the rate over five draws is tested
  d <- sim_s4(per_week = 20L, seed = 7)
  d[, rest_diff := lp_anchor + stats::rnorm(.N, 0, 0.3)]
  seeds <- v4$VVF_NULL_SEED + 1:5
  an <- lapply(seeds, function(s) v4$vvf_control_null(d, "rest_diff", "open_isa", 2019:2020, null = "anchor", B = 1000L, seed = s))
  px <- lapply(seeds, function(s) v4$vvf_control_null(d, "rest_diff", "open_isa", 2019:2020, null = "permuted_x", B = 1000L, seed = s))
  expect_lte(sum(vapply(an, `[[`, 0L, "claims")), 1L)
  expect_lte(sum(vapply(px, `[[`, 0L, "claims")), 1L)
  expect_identical(an[[1]]$null, "anchor"); expect_identical(px[[1]]$null, "permuted_x")
  expect_identical(an[[1]]$passed, an[[1]]$claims == 0L)
  sh <- lapply(seeds, function(s) v4$vvf_control_shuffle(d, "rest_diff", "open_isa", 2019:2020, B = 1000L, seed = s))
  expect_true(all(!vapply(sh, `[[`, TRUE, "passed")))
  expect_true(all(vapply(sh, function(r) r$skill$skill_lo > 0, TRUE)))
})

test_that("a planted effect is claimed on the data and removed by both nulls", {
  withr::local_dir(PROJECT_ROOT)
  d <- sim_s4(per_week = 20L, beta = 0.5, seed = 8)
  real <- v4$vvf_s3_screen(d, "rest_diff", "open_isa", 2019:2020, B = 2000L)$skill
  expect_identical(v4$vvf_s3_claims(real)$claims, 1L)
  for (nl in c("anchor", "permuted_x")) {
    r <- v4$vvf_control_null(d, "rest_diff", "open_isa", 2019:2020, null = nl, B = 2000L)
    expect_identical(r$claims, 0L, info = nl)
    expect_identical(r$skill$feature, "rest_diff", info = nl)
  }
  expect_error(v4$vvf_control_null(d, "d_c1", "open_isa", 2020L, null = "permuted_x"), "known-at violation")
})

test_that("the S4 status counts only the gating controls", {
  ctl <- list(canary = list(passed = TRUE), shuffled_labels = list(passed = FALSE))
  a <- v4$vvf_s4_report(ctl, gating = "canary")
  expect_identical(a$status, "complete")
  expect_equal(a$table$gates, c(TRUE, FALSE))
  expect_identical(v4$vvf_s4_report(ctl)$status, "void")
  expect_true("anchor_null" %in% v4$VVF_S4_GATING_AMENDED)
  expect_true("shuffled_labels" %in% v4$VVF_S4_GATING_SPEC)
  expect_false("shuffled_labels" %in% v4$VVF_S4_GATING_AMENDED)
})
