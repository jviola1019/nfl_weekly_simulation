# VVF registry (backtest/vvf/registry.R) and S0 provenance (backtest/vvf/provenance.R):
# every variable has a well-formed row, the information sets nest, the A3a defect
# table is tracked, and vvf_assert_known_at() refuses what a decision cannot know.

vr <- vvf_test_env(c("registry.R", "provenance.R"))
reg <- vr$vvf_registry()

test_that("every registry row is well formed", {
  expect_false(anyDuplicated(reg$name) > 0)
  expect_true(all(reg$known_at %in% vr$VVF_KNOWN_AT$class))
  expect_true(all(reg$kind %in% c("feature", "engine", "setting", "market")))
  expect_true(all(nzchar(reg$definition) & nzchar(reg$source) & nzchar(reg$unit_test)))
  expect_true(all(reg[kind %in% c("feature", "setting"), n_params] == 1L))
  for (d in unlist(reg$defects, recursive = FALSE)) {
    expect_true(all(c("id", "text", "fix", "phase", "audit", "status") %in% names(d)))
    expect_true(d$status %in% c("open", "closed"))
  }
})

test_that("v2's 36 screened features are registered, with the two post-hoc diagnostics apart", {
  f <- vr$VVF_V2_FEATURES
  expect_length(f, 36L)
  expect_true(all(f %in% reg[kind == "feature" & !posthoc, name]))
  expect_length(vr$VVF_V2_SITUATIONAL, 30L)
  expect_setequal(setdiff(f, vr$VVF_V2_SITUATIONAL), c("d_c1", "d_c2", "d_e1", "lp_anchor", "home_dog", "big_fav"))
  expect_setequal(reg[kind == "feature" & posthoc, name], c("cold_obs", "windy_obs"))
})

test_that("the information sets nest from the opener to the close, and the anchor is in each", {
  d <- vr$VVF_DECISIONS
  expect_equal(names(d), c("open_isa", "open_isb", "tue_18z", "fri_21z", "close"))
  for (k in seq_len(length(d) - 1L)) expect_true(all(d[[k]] %in% d[[k + 1L]]))
  for (s in d) expect_true("anchor" %in% s)
  expect_setequal(d$close, vr$VVF_KNOWN_AT$class)
  expect_setequal(d$open_isa, c("anchor", "schedule", "results_w-2", "qb_prev_start"))
})

test_that("the A3a defect table is tracked on its variables, each with the phase that fixes it", {
  ph <- function(nm) vapply(reg[name == nm, defects][[1]], `[[`, "", "phase")
  ids <- function(nm) vapply(reg[name == nm, defects][[1]], `[[`, "", "id")
  for (nm in c("hfa", "rho_score", "pts_cap")) { expect_true("M5" %in% ids(nm)); expect_true("G1" %in% ph(nm)) }
  expect_true("M9" %in% ids("glmm_prior"))
  expect_true("G1" %in% ph("qb_starter"))
  expect_true("G1" %in% ph("team_tz"))
  expect_true("M18" %in% ids("injury_adj")); expect_true("G2" %in% ph("injury_adj"))
  expect_true(all(c("M21", "S3", "F6") %in% ids("weather")))
  expect_true("G2" %in% ph("neutral_travel"))
  expect_true("M22" %in% ids("turnover_term"))
  expect_true("F11" %in% ids("hfa"))
  expect_true("A3-SAFE" %in% ids("safe_mu_sd")); expect_true("G1" %in% ph("safe_mu_sd"))
  expect_true("P13" %in% ids("dup_loaders")); expect_true("P1" %in% ph("dup_loaders"))
  expect_true("M4" %in% ids("calibrator"))
  for (s in c("RECENCY_HALFLIFE", "GLMM_BLEND_W", "SOS_STRENGTH", "SHRINKAGE", "N_RECENT")) {
    expect_equal(reg[name == s, kind], "setting")
  }
  expect_match(reg[name == "devig", evidence], "4,426")
})

test_that("S0 refuses a feature known after the decision, a post-hoc one, and an unregistered one", {
  sched <- c("rest_diff", "abs_tz_away", "turf", "lp_anchor")
  expect_invisible(vr$vvf_assert_known_at(sched, "open_isa", reg))
  expect_error(vr$vvf_assert_known_at(c(sched, "d_c1"), "open_isa", reg), "known-at violation at open_isa.*d_c1 \\(results_w-1\\)")
  expect_invisible(vr$vvf_assert_known_at(c(sched, "d_c1"), "open_isb", reg))
  expect_error(vr$vvf_assert_known_at("inj_diff_all", "fri_21z", reg), "inj_diff_all \\(gameday\\)")
  expect_invisible(vr$vvf_assert_known_at(vr$VVF_V2_FEATURES, "close", reg))
  expect_error(vr$vvf_assert_known_at("cold_obs", "close", reg), "cold_obs \\(gameday, post-hoc\\)")
  expect_error(vr$vvf_assert_known_at("made_up", "close", reg), "no registry entry for made_up")
  expect_error(vr$vvf_assert_known_at("rest_diff", "kickoff", reg), "unknown decision point")
})

test_that("at the opener (IS-A) only 21 of v2's 36 features are admissible", {
  ok <- vapply(vr$VVF_V2_FEATURES, function(f) {
    tryCatch({ vr$vvf_assert_known_at(f, "open_isa", reg); TRUE }, error = function(e) FALSE)
  }, logical(1))
  expect_equal(sum(ok), 21L)
  expect_false(any(ok[c("d_c1", "d_c2", "d_e1", "roof_closed", "qb_change_diff", "ref_ml_resid")]))
})

test_that("the disclosures name the 2025 reads and the earlier looks", {
  ds <- vr$vvf_disclosures()
  expect_true(all(c("F3", "F11-CALIB", "CLV-POWER", "V1-BUILDER", "V1-CLV-2024") %in% ds$id))
  expect_match(ds[id == "V1-BUILDER", text], "backtest/build_inputs.R")
})
