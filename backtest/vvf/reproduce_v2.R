#!/usr/bin/env Rscript
# =============================================================================
# Known-answer test of the port (design 2026-10-20 §4): rerun v2's
# close-anchored screen (PR #205, reports/2026-09-30/validation-sprint §1) with
# the VVF on the ported inputs, Tune 2018-22 only, and compare every number
# with v2's committed screen CSVs (tests/testthat/fixtures/vvf/).
#
#   Rscript backtest/vvf/reproduce_v2.R --out reports/2026-10-22/vvf-v2-repro
#
# The v1 games are cut at 2022 before the base models run, so nothing later
# reaches a feature or a test, and every loader guards the sealed season.
# =============================================================================

VVF_V2_TUNE <- 2018:2022
VVF_V2_MAX_SEASON <- 2022L
VVF_V2_FAMILY_MAP <- c(ml = "outcome", ats = "spread", tot = "total")
VVF_V2_FIXTURES <- file.path("tests", "testthat", "fixtures", "vvf")
VVF_V2_RESULT_FILES <- c("s1_features.csv", "s1_joint.csv", "s2_vif.csv", "s2_stability.csv")

#' The close-anchored Tune table: v1 base predictions and features through 2022.
#' The input checks (input_schema.R) run first and stop on any violation.
vvf_v2_table <- function(inp_v1 = vvf_load_v1_inputs(max_season = VVF_V2_MAX_SEASON), inp = vvf_load_inputs()) {
  vvf_assert_inputs(vvf_schema_tables(inp_v1, inp, VVF_V2_MAX_SEASON))
  base <- vvf_base_predictions(inp_v1, VVF_V2_MAX_SEASON)
  d <- vvf_anchor_features(vvf_build_features(base, inp, VVF_V2_MAX_SEASON), "close")
  x <- d[season %in% VVF_V2_TUNE]
  setattr(x, "vvf_anchor", "close")
  list(d = x, base = base)
}

#' The regenerated base predictions against v1's committed Tune predictions
vvf_v2_base_check <- function(base, path = file.path("reports", "2026-09-29", "backtest-games-v1", "predictions.csv")) {
  v1 <- vvf_read_csv(path)[window == "tune" & candidate %in% c("C1", "C2", "E1")]
  v1 <- dcast(v1, game_id ~ candidate, value.var = "p")
  m <- merge(base$pred[, .(game_id, p_c1, p_c2, p_e1)], v1, by = "game_id")
  list(games_compared = nrow(m),
       max_abs_diff = c(C1 = max(abs(m$p_c1 - m$C1)), C2 = max(abs(m$p_c2 - m$C2)), E1 = max(abs(m$p_e1 - m$E1))))
}

vvf_v2_run <- function(x) {
  list(s1 = vvf_s1_screen(x, VVF_V2_FEATURES, "close", VVF_FAMILIES_CLOSE,
                          joint_sets = list(situational = VVF_V2_SITUATIONAL, all = VVF_V2_FEATURES)),
       s2 = vvf_s2_structure(x, VVF_V2_FEATURES, "close", VVF_FAMILIES_CLOSE))
}

#' Largest relative difference per column between S1 and v2's committed screen
vvf_v2_compare <- function(s1, fixture_dir = VVF_V2_FIXTURES) {
  fx <- vvf_read_csv(file.path(fixture_dir, "v2_screen_features.csv"))[posthoc == FALSE]
  fx[, `:=`(family = unname(VVF_V2_FAMILY_MAP[family]), feature = fifelse(feature == "lp_c0", "lp_anchor", feature))]
  m <- merge(s1$features, fx, by = c("family", "feature"), suffixes = c("", "_v2"))
  cols <- c("n", "sd_x", "stat", "p_test", "estimate", "se_robust", "ci_lo", "ci_hi", "p_robust", "q_bh")
  rel <- vapply(cols, function(cc) max(abs(m[[cc]] - m[[paste0(cc, "_v2")]]) / pmax(abs(m[[paste0(cc, "_v2")]]), 1e-12)),
                numeric(1))
  list(rows = nrow(m), max_rel_diff = rel)
}

#' The numbers v2's REPORT.md §1 quotes, recomputed
vvf_v2_headline <- function(res) {
  f <- res$s1$features
  j <- res$s1$joint[family == "outcome" & set == "situational"]
  o <- f[family == "outcome"][order(q_bh, p)]
  tz <- f[family == "spread" & feature == "abs_tz_away"]
  list(outcome_joint_stat = j$stat, outcome_joint_k_entered = j$k_entered, outcome_joint_df = j$df,
       outcome_joint_p = j$p_test, outcome_joint_p_v2_df = stats::pchisq(j$stat, j$k_entered, lower.tail = FALSE),
       outcome_min_q = o$q_bh[1], outcome_min_q_feature = o$feature[1],
       spread_tz_estimate = tz$estimate, spread_tz_ci_lo = tz$ci_lo, spread_tz_ci_hi = tz$ci_hi,
       spread_tz_p = tz$p_test, spread_tz_q = tz$q_bh)
}

vvf_v2_write <- function(res, out_dir, base_check, fidelity) {
  rnd <- function(x) x[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)]
  tabs <- list(res$s1$features, res$s1$joint, res$s2$vif, res$s2$stability)
  paths <- file.path(out_dir, VVF_V2_RESULT_FILES)
  for (k in seq_along(tabs)) vvf_write_csv(rnd(tabs[[k]]), paths[k])
  meta <- list(
    generated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    purpose = "VVF port fidelity: v2's close-anchored screen (PR #205) rerun on the ported inputs",
    tune_seasons = VVF_V2_TUNE, max_season_loaded = VVF_V2_MAX_SEASON, anchor = "close", decision = "close",
    n = res$s1$n, base_check_vs_v1 = base_check, fidelity_vs_v2 = fidelity, headline = vvf_v2_headline(res),
    r_version = R.version.string,
    packages = lapply(setNames(nm = c("data.table", "sandwich", "car")), function(p) as.character(utils::packageVersion(p))),
    result_files = VVF_V2_RESULT_FILES, result_sha256 = vvf_result_sha256(paths))
  vvf_write_json(meta, file.path(out_dir, "run_meta.json"))
  invisible(meta)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 2L || args[1] != "--out") stop("usage: Rscript backtest/vvf/reproduce_v2.R --out <dir>", call. = FALSE)
  e <- environment()
  for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R", "blends.R",
              "calibrators.R", "metrics.R", "controls.R")) sys.source(file.path("backtest", f), envir = e)
  for (f in c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s2_structure.R", "input_schema.R")) {
    sys.source(file.path("backtest", "vvf", f), envir = e)
  }
  tab <- vvf_v2_table()
  res <- vvf_v2_run(tab$d)
  bc <- vvf_v2_base_check(tab$base)
  fid <- vvf_v2_compare(res$s1)
  if (any(bc$max_abs_diff > 1e-9)) stop("base predictions do not reproduce v1", call. = FALSE)
  if (any(fid$max_rel_diff > 1e-5)) stop("S1 does not reproduce v2: ", paste(names(fid$max_rel_diff)[fid$max_rel_diff > 1e-5], collapse = ", "), call. = FALSE)
  meta <- vvf_v2_write(res, args[2], bc, fid)
  h <- meta$headline
  cat(sprintf("base vs v1: %d games, max |diff| %.2e\n", bc$games_compared, max(bc$max_abs_diff)))
  cat(sprintf("S1 vs v2: %d rows, max relative difference %.2e\n", fid$rows, max(fid$max_rel_diff)))
  cat(sprintf("outcome joint (situational): chi2 %.4f, %d entered, df %d, p %.4f (v2's df %d: p %.4f)\n",
              h$outcome_joint_stat, h$outcome_joint_k_entered, h$outcome_joint_df, h$outcome_joint_p,
              h$outcome_joint_k_entered, h$outcome_joint_p_v2_df))
  cat(sprintf("outcome min q: %.4f (%s)\n", h$outcome_min_q, h$outcome_min_q_feature))
  cat(sprintf("spread abs_tz_away: %.4f [%.4f, %.4f], p %.4f, q %.4f\n", h$spread_tz_estimate, h$spread_tz_ci_lo,
              h$spread_tz_ci_hi, h$spread_tz_p, h$spread_tz_q))
  cat(sprintf("result_sha256: %s\n", meta$result_sha256))
}
