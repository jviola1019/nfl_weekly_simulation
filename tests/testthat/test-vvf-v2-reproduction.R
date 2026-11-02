# Known-answer test of the port (design 2026-10-20 §4): the VVF, run with
# anchor = close on the ported inputs (Tune 2018-22), reproduces v2's screen
# (PR #205, reports/2026-09-30/validation-sprint §1). The fixtures are v2's
# committed screen CSVs, copied byte for byte from 759dd1c.

vr2 <- vvf_test_env(c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s2_structure.R", "input_schema.R",
                      "reproduce_v2.R"), v1_files = VVF_TEST_V1_FILES)
fixture_dir <- file.path(PROJECT_ROOT, "tests", "testthat", "fixtures", "vvf")
repro <- withr::with_dir(PROJECT_ROOT, {
  tab <- vr2$vvf_v2_table()
  list(tab = tab, res = vr2$vvf_v2_run(tab$d))
})
f <- repro$res$s1$features

test_that("the regenerated base predictions equal v1's committed Tune predictions", {
  bc <- withr::with_dir(PROJECT_ROOT, vr2$vvf_v2_base_check(repro$tab$base))
  expect_equal(bc$games_compared, 1372L)
  expect_true(all(bc$max_abs_diff < 1e-9))
  expect_lte(max(repro$tab$d$season), 2022L)
  expect_identical(attr(repro$tab$d, "vvf_anchor"), "close")
})

test_that("every S1 row matches v2's committed screen to its 6 significant digits", {
  cmp <- vr2$vvf_v2_compare(repro$res$s1, fixture_dir)
  expect_equal(cmp$rows, 108L)                    # 36 features x 3 families
  expect_true(all(cmp$max_rel_diff < 1e-5))
  expect_equal(unlist(repro$res$s1$n), c(outcome = 1365L, spread = 1372L, total = 1372L))
})

test_that("v2's headline numbers are reproduced (REPORT.md §1)", {
  h <- vr2$vvf_v2_headline(repro$res)
  # moneyline joint test of the situational set: chi2 26.9 on 29 estimable
  # coefficients (inj_diff_all is aliased). v2's p = 0.63 used df 30, which
  # counted the aliased term; the anova() df is 29.
  expect_equal(round(h$outcome_joint_stat, 1), 26.9)
  expect_equal(h$outcome_joint_k_entered, 30L)
  expect_equal(h$outcome_joint_df, 29L)
  expect_equal(round(h$outcome_joint_p_v2_df, 2), 0.63)
  expect_equal(h$outcome_joint_p, stats::pchisq(h$outcome_joint_stat, 29, lower.tail = FALSE))
  expect_equal(round(h$outcome_min_q, 2), 0.49)
  expect_identical(h$outcome_min_q_feature, "abs_tz_away")
  expect_equal(round(h$spread_tz_estimate, 2), -0.88)
  expect_equal(round(c(h$spread_tz_ci_lo, h$spread_tz_ci_hi), 2), c(-1.46, -0.30))
  expect_equal(round(h$spread_tz_p, 3), 0.004)
  expect_equal(round(h$spread_tz_q, 2), 0.15)
})

test_that("the joint tests match v2's, except that df now counts only estimable coefficients", {
  j <- repro$res$s1$joint
  v2j <- data.table::fread(file.path(fixture_dir, "v2_screen_joint.csv"))
  v2j[, `:=`(family = unname(vr2$VVF_V2_FAMILY_MAP[family]), set = ifelse(grepl("^situational", set), "situational", "all"))]
  m <- merge(j, v2j, by = c("family", "set"), suffixes = c("", "_v2"))
  expect_equal(nrow(m), 6L)
  expect_equal(m$stat, m$stat_v2, tolerance = 1e-5)
  expect_equal(m$k, m$k_v2)
  expect_equal(m$wald_robust, m$wald_robust_v2, tolerance = 1e-5)
  expect_equal(m[family != "outcome", df], m[family != "outcome", df_v2])
  expect_equal(m[family == "outcome", df_v2], m[family == "outcome", k_entered])
  expect_setequal(m[family == "outcome" & set == "all", strsplit(aliased, " ")[[1]]], c("d_e1", "inj_diff_all"))
})

test_that("the committed reproduction outputs match their result hash and a fresh run", {
  out <- file.path(PROJECT_ROOT, "reports", "2026-10-22", "vvf-v2-repro")
  meta <- jsonlite::read_json(file.path(out, "run_meta.json"))
  expect_identical(vr2$vvf_result_sha256(file.path(out, unlist(meta$result_files))), meta$result_sha256)
  committed <- data.table::fread(file.path(out, "s1_features.csv"))
  m <- merge(f, committed, by = c("family", "feature"), suffixes = c("", "_c"))
  expect_equal(nrow(m), 108L)
  for (cc in c("estimate", "p_test", "p_robust", "q_bh")) expect_equal(m[[cc]], m[[paste0(cc, "_c")]], tolerance = 1e-5)
})

test_that("the reproduction's table build stops on a planted input violation before S1 (review I-1)", {
  withr::local_dir(PROJECT_ROOT)
  v1 <- vr2$vvf_load_v1_inputs(max_season = vr2$VVF_V2_MAX_SEASON)
  v2 <- vr2$vvf_load_inputs()
  v2$injuries_team <- rbind(v2$injuries_team, v2$injuries_team[1])
  expect_error(vr2$vvf_v2_table(inp_v1 = v1, inp = v2), "input check failed: injuries_team key unique")
})
