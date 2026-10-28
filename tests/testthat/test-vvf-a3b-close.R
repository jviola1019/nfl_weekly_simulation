# The committed close-anchored A3b run (backtest/vvf/run_a3b_close.R,
# reports/2026-10-28/vvf-a3b-close): its hash holds, each S4 status follows its
# gating set, and its S3 and S5 tables have the shape the ledger reads.

out <- file.path(PROJECT_ROOT, "reports", "2026-10-28", "vvf-a3b-close")
va <- vvf_test_env(c("common.R", "s4_controls.R"))

test_that("the committed run matches its result hash, and each S4 status follows its gating set", {
  meta <- jsonlite::read_json(file.path(out, "run_meta.json"))
  expect_identical(va$vvf_result_sha256(file.path(out, unlist(meta$result_files))), meta$result_sha256)
  ctl <- data.table::fread(file.path(out, "s4_controls.csv"))
  expect_setequal(ctl$control, c("canary", "placebo", "shuffled_labels", "anchor_null", "permuted_x", "anchor_copy",
                                 "reproducibility"))
  status <- function(gating) if (all(ctl[control %in% gating, passed])) "complete" else "void"
  expect_identical(meta$s4_status, status(va$VVF_S4_GATING_SPEC))
  expect_identical(meta$s4_status_amended, status(va$VVF_S4_GATING_AMENDED))
  expect_identical(meta$s4_amendment, "proposed 2026-10-28, unsigned")
  expect_false(ctl[control == "shuffled_labels", passed])     # fails by construction (disclosure S4-NULL)
  expect_true(all(ctl[control %in% c("canary", "placebo", "anchor_copy", "reproducibility"), passed]))
  expect_gte(meta$placebo_rate, 0.020); expect_lte(meta$placebo_rate, 0.080)
  expect_lte(max(unlist(meta$seasons_scored)), 2022L)
})

test_that("S3 covers the 36 features in v2's order, against the close", {
  s3 <- data.table::fread(file.path(out, "s3_skill.csv"))
  reg <- vvf_test_env("registry.R")
  expect_equal(s3$feature, reg$VVF_V2_FEATURES)
  expect_true(all(s3$anchor == "close"))
  expect_true(all(s3$skill_lo <= s3$skill_hi))
})

test_that("the S5 tables are complete", {
  m <- data.table::fread(file.path(out, "s5_murphy.csv"))
  expect_setequal(m$model, c("C0", "C1", "C2", "E1"))
  expect_true(all(abs(m$reliability - m$resolution + m$uncertainty + m$within_bin_variance -
                        2 * m$within_bin_covariance - m$brier) < 1e-5))
  cv <- data.table::fread(file.path(out, "s5_curve_c2_halflife.csv"))
  expect_equal(cv$value, c(16, 8, 4))
  expect_equal(sum(cv$chosen), 1L)
  for (f in c("s5_calibration.csv", "s5_bias_variance.csv", "s5_team_effects.csv", "s5_loss_anova.csv")) {
    expect_gt(nrow(data.table::fread(file.path(out, f))), 0L)
  }
})

test_that("the learning curve and the fit gap score the joint model beside the anchor on the same games", {
  lc <- data.table::fread(file.path(out, "s5_learning_curve.csv"))
  expect_equal(lc$n_train_seasons, 2:8)
  expect_true(all(is.finite(lc$logloss) & is.finite(lc$logloss_anchor)))
  expect_equal(length(unique(lc$n)), 1L)                      # the same games at every training length
  expect_equal(length(unique(lc$logloss_anchor)), 1L)
  fg <- data.table::fread(file.path(out, "s5_fit_gap.csv"))
  expect_equal(fg$season, 2018:2022)
  expect_true(all(is.finite(fg$gap) & is.finite(fg$logloss_anchor)))
  expect_equal(fg$gap, fg$logloss_wf - fg$logloss_in, tolerance = 1e-5)
})
