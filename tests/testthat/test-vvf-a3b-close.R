# The committed close-anchored A3b run (backtest/vvf/run_a3b_close.R,
# reports/2026-10-28/vvf-a3b-close): its hash holds, each S4 status follows its
# gating set, its S3 and S5 tables have the shape the ledger reads, and the run
# checks its inputs before any stage.

out <- file.path(PROJECT_ROOT, "reports", "2026-10-28", "vvf-a3b-close")
va <- vvf_test_env(c("common.R", "s4_controls.R"))

test_that("the committed run matches its result hash, and each S4 status follows its gating set", {
  meta <- jsonlite::read_json(file.path(out, "run_meta.json"))
  expect_identical(va$vvf_result_sha256(file.path(out, unlist(meta$result_files))), meta$result_sha256)
  ctl <- data.table::fread(file.path(out, "s4_controls.csv"))
  expect_setequal(ctl$control, c("canary", "placebo", "shuffled_labels", "anchor_null", "permuted_x", "anchor_copy",
                                 "reproducibility"))
  controls <- stats::setNames(lapply(ctl$passed, function(p) list(passed = p)), ctl$control)
  expect_identical(meta$s4_status, va$vvf_s4_report(controls, gating = va$VVF_S4_GATING_SPEC)$status)
  expect_identical(meta$s4_status_amended, va$vvf_s4_report(controls, gating = va$VVF_S4_GATING_AMENDED)$status)
  expect_identical(meta$s4_amendment, "proposed 2026-10-28, unsigned")
  expect_false(ctl[control == "shuffled_labels", passed])     # fails by construction (disclosure S4-NULL)
  expect_true(all(ctl[control %in% c("canary", "placebo", "anchor_copy", "reproducibility"), passed]))
  expect_match(ctl[control == "reproducibility", detail], "results_sha256 of the 9 result files")
  expect_gte(meta$placebo_rate, 0.020); expect_lte(meta$placebo_rate, 0.080)
  expect_lte(max(unlist(meta$seasons_scored)), 2022L)
})

test_that("S3 covers the 36 features in v2's order, against the close, with its fallback counts", {
  s3 <- data.table::fread(file.path(out, "s3_skill.csv"))
  reg <- vvf_test_env("registry.R")
  expect_equal(s3$feature, reg$VVF_V2_FEATURES)
  expect_true(all(s3$anchor == "close"))
  expect_true(all(s3$skill_lo <= s3$skill_hi))
  expect_true(all(c("weeks_skipped_min_train", "weeks_constant") %in% names(s3)))
  expect_true(all(s3$weeks_skipped_min_train >= 0L & s3$weeks_constant >= 0L))
})

test_that("the S5 tables are complete", {
  m <- data.table::fread(file.path(out, "s5_murphy.csv"))
  expect_setequal(m$model, c("C0", "C1", "C2", "E1"))
  expect_true(all(abs(m$reliability - m$resolution + m$uncertainty + m$within_bin_variance -
                        2 * m$within_bin_covariance - m$brier) < 1e-5))
  cv <- data.table::fread(file.path(out, "s5_curve_c2_halflife.csv"))
  expect_equal(cv$value, c(Inf, 16, 8, 6, 4, 3, 2, 1))       # the amendment's half-lives and v1's 16, simplest first
  expect_equal(sum(cv$chosen), 1L)
  la <- data.table::fread(file.path(out, "s5_loss_anova.csv"))
  expect_equal(la$q_bh, stats::p.adjust(la$p, method = "BH"), tolerance = 1e-5)
  for (f in c("s5_calibration.csv", "s5_bias_variance.csv", "s5_team_effects.csv")) {
    expect_gt(nrow(data.table::fread(file.path(out, f))), 0L)
  }
})

test_that("the learning curve and the fit gap score the joint model beside the anchor, with fit diagnostics", {
  lc <- data.table::fread(file.path(out, "s5_learning_curve.csv"))
  expect_equal(lc$n_train_seasons, 2:8)
  expect_true(all(is.finite(lc$logloss) & is.finite(lc$logloss_anchor)))
  expect_equal(length(unique(lc$n)), 1L)                      # the same games at every training length
  expect_equal(length(unique(lc$logloss_anchor)), 1L)
  fg <- data.table::fread(file.path(out, "s5_fit_gap.csv"))
  expect_equal(fg$season, 2018:2022)
  expect_true(all(is.finite(fg$gap) & is.finite(fg$logloss_anchor)))
  expect_equal(fg$gap, fg$logloss_wf - fg$logloss_in, tolerance = 1e-5)
  for (t in list(lc, fg)) {
    expect_true(all(c("fits", "fits_converged", "train_rows_dropped", "target_cells_imputed") %in% names(t)))
    expect_equal(t$fits_converged, t$fits)
  }
})

vr <- vvf_test_env(c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s3_skill.R", "s4_controls.R",
                     "s5_curves.R", "s5_scores.R", "s5_anova.R", "reproduce_v2.R", "input_schema.R", "run_a3b_close.R"),
                   v1_files = VVF_TEST_V1_FILES)

test_that("the run's table build stops on a planted input violation before any stage (review I-1)", {
  withr::local_dir(PROJECT_ROOT)
  v1 <- vr$vvf_load_v1_inputs(max_season = vr$VVF_V2_MAX_SEASON)
  v2 <- vr$vvf_load_inputs()
  v2$venues <- rbind(v2$venues, v2$venues[1])
  expect_error(vr$vvf_a3b_table(inp_v1 = v1, inp = v2), "input check failed: venues key unique")
})

test_that("the joint fit records convergence, dropped training rows and imputed target cells (review I-4)", {
  set.seed(3)
  tr <- data.table::data.table(y = stats::rbinom(300, 1, 0.5), lp_anchor = stats::rnorm(300), a = stats::rnorm(300),
                               b = stats::rnorm(300))
  tr[1:4, a := NA_real_]
  tg <- data.table::data.table(lp_anchor = stats::rnorm(10), a = stats::rnorm(10), b = stats::rnorm(10))
  tg[2, b := NA_real_]
  log <- new.env()
  p <- vr$vvf_a3b_joint_fit(c("a", "b"), log)(tr, tg)
  expect_length(p, 10L)
  expect_true(all(is.finite(p)))
  expect_identical(c(log$fits, log$fits_converged, log$train_rows_dropped, log$target_cells_imputed), c(1L, 1L, 4L, 1L))
})
