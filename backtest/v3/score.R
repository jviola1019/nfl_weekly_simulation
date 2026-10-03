# =============================================================================
# Blend research v3: scoring and controls (statistics exactly as v2).
#
# Every candidate, new and v2, is scored on the same 1,365 non-tie Tune games
# against the no-vig close: Brier and log-loss skill with week-block bootstrap
# 95% CIs (B = BT_BOOT_B = 10,000, seed BT2_SEED, the same resampling as v2),
# Diebold-Mariano with the HLN correction (one-sided: candidate better), BH
# q-values across ALL moneyline candidates. Probability quality: ECE (10
# equal-count bins), the logistic recalibration fit y ~ a + b * logit(p) (slope b
# and intercept a, Wald 95% CIs; a well-calibrated forecast has a = 0, b = 1),
# calibration-in-the-large (y ~ 1 with offset logit(p)), and a reliability table
# (10 equal-count bins: n, mean predicted, observed rate with a Wilson 95% CI).
# v2 rows are re-scored from v2's committed per-game tracking file, so v2 and
# v3 share one multiplicity family.
# Shuffled-label control: outcomes permuted globally with v2's seed (the same
# permutation as bt2_control_shuffle), every learner refit walk-forward, scored
# against an expanding home-win-rate climatology; a family passes when the
# lower bound of its skill CI is not above 0.
# =============================================================================

#' Log-loss skill vs `ref` with the same week-block bootstrap as bt_score_window,
#' plus a DM-HLN test on the log-loss differential
bt3_ll_skill <- function(d, cands, ref, B = BT_BOOT_B, seed = BT2_SEED) {
  setorder(d, kickoff, game_id)
  wk_f <- factor(d$wk)
  counts <- bt_boot_counts(nlevels(wk_f), B, seed)
  week_sum <- function(x) as.numeric(tapply(x, wk_f, sum))
  ll0 <- bt_logloss_vec(d[[ref]], d$y)
  b0 <- drop(counts %*% week_sum(ll0))
  rbindlist(lapply(cands, function(cc) {
    ll <- bt_logloss_vec(d[[cc]], d$y)
    b <- drop(counts %*% week_sum(ll))
    ci <- bt_quantile_ci(1 - b / b0)
    data.table(column = cc, ll_skill = 1 - sum(ll) / sum(ll0), ll_skill_lo = ci[1], ll_skill_hi = ci[2],
               dm_ll_p = bt_dm_hln(ll - ll0)$p_better)
  }))
}

#' Logistic recalibration fit y ~ a + b * logit(p): intercept a and slope b with Wald 95% CIs
bt3_recalibration <- function(p, y) {
  lp <- bt_logit(bt_clip(p))
  m <- stats::glm(y ~ lp, family = stats::binomial())
  ci <- suppressMessages(stats::confint.default(m))
  list(a = unname(stats::coef(m)[1]), a_ci = unname(ci[1, ]), b = unname(stats::coef(m)[2]), b_ci = unname(ci[2, ]))
}

#' Score `cols` against `ref` on `ev` (non-tie games). BH runs across all `cols`.
bt3_score_all <- function(ev, cols, ref = "p_c0", seed = BT2_SEED) {
  sc <- bt_score_window(copy(ev), setNames(cols, cols), c(REF = ref), seed = seed)
  lls <- bt3_ll_skill(copy(ev), cols, ref, seed = seed)
  lp0 <- bt_logit(bt_clip(ev[[ref]]))
  tab <- rbindlist(lapply(c(ref, cols), function(cc) {
    s <- sc[[cc]]; is_ref <- cc == ref
    rc <- bt3_recalibration(ev[[cc]], ev$y)
    data.table(column = cc, n = s$n, brier = s$brier, logloss = s$logloss, ece = s$ece,
               slope = s$slope, slope_lo = s$slope_ci[1], slope_hi = s$slope_ci[2],
               recal_intercept = rc$a, recal_intercept_lo = rc$a_ci[1], recal_intercept_hi = rc$a_ci[2],
               citl = s$intercept, citl_lo = s$intercept_ci[1], citl_hi = s$intercept_ci[2],
               skill = if (is_ref) 0 else s$skill, skill_lo = if (is_ref) 0 else s$skill_ci[1],
               skill_hi = if (is_ref) 0 else s$skill_ci[2],
               dm_p = if (is_ref) NA_real_ else s$dm_p_better, bh_q = if (is_ref) NA_real_ else s$dm_p_better_bh,
               mean_abs_logit_vs_close = mean(abs(bt_logit(bt_clip(ev[[cc]])) - lp0)))
  }))
  merge(tab, lls, by = "column", all.x = TRUE, sort = FALSE)
}

#' v2's committed per-game Tune predictions, one column per candidate (p_<candidate>)
bt3_v2_tracking_wide <- function(path = file.path(BT3_V2_DIR, "tracking", "moneyline_tune.csv")) {
  v2 <- fread(path)
  bt3_guard(v2$season, "v2 tracking file")
  w <- dcast(v2, game_id ~ candidate, value.var = "p_model")
  setnames(w, setdiff(names(w), "game_id"), paste0("p_", setdiff(names(w), "game_id")))
  w
}

#' Regenerated level-0 Tune predictions must equal v2's committed ones, which v2
#' wrote rounded to 8 decimals: compare raw and rounded values
bt3_check_level0 <- function(pred, v2w, cols) {
  m <- merge(pred[, c("game_id", cols), with = FALSE], v2w[, c("game_id", cols), with = FALSE], by = "game_id",
             suffixes = c("", ".v2"))
  rbindlist(lapply(cols, function(cc) data.table(
    column = cc, games = nrow(m), max_abs_diff = max(abs(m[[cc]] - m[[paste0(cc, ".v2")]])),
    max_abs_diff_rounded = max(abs(round(m[[cc]], 8) - m[[paste0(cc, ".v2")]])))))
}

#' Permute outcomes globally exactly as bt2_control_shuffle does (same seed, same draw)
bt3_shuffle_labels <- function(d, seed = BT2_SEED) {
  x <- copy(d)
  lab <- which(!is.na(x$y))
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  x$y[lab] <- x$y[lab][sample.int(length(lab))]
  if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv())
  x
}

#' Expanding-window home-win rate of all labelled games before each week (as v2)
bt3_climatology <- function(x, weeks) {
  rbindlist(lapply(split(weeks, by = "wk"), function(w) {
    prior <- x[kickoff < w$cutoff & !is.na(y)]
    data.table(wk = w$wk, p_clim = if (nrow(prior)) mean(prior$y) else 0.5)
  }))
}

#' Score shuffled-label predictions against climatology on Tune
bt3_score_control <- function(x, weeks, preds, seed = BT2_SEED) {
  ev <- x[season %in% BT2_TUNE_SEASONS & !is.na(y) & is.finite(lp_c0), .(game_id, season, wk, kickoff, y)]
  for (nm in names(preds)) {
    p <- preds[[nm]][, .(game_id, p)]
    setnames(p, "p", paste0("p_", nm))
    ev <- merge(ev, p, by = "game_id", all.x = TRUE)
  }
  ev <- merge(ev, bt3_climatology(x, weeks), by = "wk")
  cols <- paste0("p_", names(preds))
  miss <- vapply(cols, function(cc) sum(!is.finite(ev[[cc]])), integer(1))
  if (any(miss > 0)) stop("control: missing shuffled-label predictions: ", paste(names(miss)[miss > 0], collapse = ", "))
  sc <- bt_score_window(copy(ev), setNames(cols, cols), c(CLIM = "p_clim"), seed = seed)
  out <- rbindlist(lapply(cols, function(cc) data.table(model = sub("^p_", "", cc), n = sc[[cc]]$n,
                                                       skill_vs_climatology = sc[[cc]]$skill,
                                                       skill_lo = sc[[cc]]$skill_ci[1], skill_hi = sc[[cc]]$skill_ci[2])))
  out[, `:=`(passed = skill_lo <= 0, point_not_positive = skill_vs_climatology <= 0)]
  out[]
}

#' Wilson score interval for k successes in n trials
bt3_wilson <- function(k, n, z = 1.96) {
  p <- k / n; den <- 1 + z^2 / n
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))
  cbind(lo = (p + z^2 / (2 * n) - half) / den, hi = (p + z^2 / (2 * n) + half) / den)
}

#' Reliability: 10 equal-count bins of predicted probability (v2's bt2_reliability),
#' with the observed rate's Wilson 95% CI
bt3_reliability <- function(ev, cols) {
  rbindlist(lapply(cols, function(cc) {
    r <- bt2_reliability(ev[[cc]], ev$y)
    ci <- bt3_wilson(round(r$obs_rate * r$n), r$n)
    r[, `:=`(obs_lo = ci[, "lo"], obs_hi = ci[, "hi"], column = cc)]
  }))
}
