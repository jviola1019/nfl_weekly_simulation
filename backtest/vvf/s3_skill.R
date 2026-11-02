# =============================================================================
# VVF stage S3, incremental skill (design 2026-10-20 §4; the only stage that
# can support a claim). For a feature x the base model is
#   logit(p) = lp_anchor + b * x_c,
# where x_c is x centred and scaled on the training rows (so b cannot absorb an
# intercept), refit every week on all earlier weeks (expanding window) and used
# to predict that week. The reference is the anchor alone. Paired Brier and
# log-loss differences, a week-block bootstrap with B = 10,000
# (bt_boot_counts inside bt_score_window), DM-HLN (bt_dm_hln) and BH over the
# declared order of hypotheses, which must be fixed before the run.
# =============================================================================

VVF_S3_B <- 10000L
VVF_S3_SEED <- 20261021L
VVF_S3_MIN_TRAIN <- 200L

#' Walk-forward predictions of anchor + b * x_c for the weeks in `weeks`
#' (bt_week_schedule). Weeks with fewer than `min_train` earlier rows are
#' skipped, and weeks where x is constant in training predict the anchor; both
#' are counted in the attribute "vvf_s3".
vvf_s3_refit <- function(d, feature, weeks, min_train = VVF_S3_MIN_TRAIN) {
  x <- d[is.finite(lp_anchor)]
  x[, fx := get(feature)]
  out <- vector("list", nrow(weeks))
  skipped <- 0L
  constant <- 0L
  for (i in seq_len(nrow(weeks))) {
    tg <- x[wk == weeks$wk[i] & is.finite(fx)]
    if (!nrow(tg)) next
    tr <- x[kickoff < weeks$cutoff[i] & !is.na(y) & is.finite(fx)]
    if (nrow(tr) < min_train) { skipped <- skipped + 1L; next }
    stopifnot(max(tr$kickoff) < weeks$cutoff[i])
    m <- mean(tr$fx)
    s <- stats::sd(tr$fx)
    if (!is.finite(s) || s == 0) {
      constant <- constant + 1L
      b <- 0
      xt <- rep(0, nrow(tg))
    } else {
      tr[, xc := (fx - m) / s]
      b <- unname(stats::coef(stats::glm(y ~ 0 + xc, offset = lp_anchor, family = stats::binomial(), data = tr))[["xc"]])
      xt <- (tg$fx - m) / s
    }
    out[[i]] <- data.table(game_id = tg$game_id, p = stats::plogis(tg$lp_anchor + b * xt), beta = b)
  }
  res <- rbindlist(out)
  setattr(res, "vvf_s3", list(weeks_skipped_min_train = skipped, weeks_constant = constant))
  res
}

#' Skill of each candidate column against `ref` on the same games, in the
#' declared order; BH runs across the candidates (bt_score_window)
vvf_s3_skill <- function(d, cands, order, ref = "p_anchor", B = VVF_S3_B, seed = VVF_S3_SEED) {
  if (!identical(unname(cands), unname(order))) {
    stop(sprintf("S3: the candidates must be exactly the declared order (%s), got (%s)",
                 paste(order, collapse = ", "), paste(cands, collapse = ", ")), call. = FALSE)
  }
  x <- copy(d[!is.na(y)])
  ok <- Reduce(`&`, lapply(c(ref, cands), function(cc) is.finite(x[[cc]])))
  x <- x[ok]
  s <- bt_score_window(x, setNames(cands, cands), ref, B = B, seed = seed)
  res <- rbindlist(lapply(cands, function(cc) {
    r <- s[[cc]]
    data.table(candidate = cc, n = r$n, weeks = r$weeks, skill = r$skill, skill_lo = r$skill_ci[1], skill_hi = r$skill_ci[2],
               brier_diff = r$brier_diff, brier_diff_lo = r$brier_diff_ci[1], brier_diff_hi = r$brier_diff_ci[2],
               logloss_diff = r$logloss_diff, logloss_diff_lo = r$logloss_diff_ci[1], logloss_diff_hi = r$logloss_diff_ci[2],
               dm_stat = r$dm_stat, dm_p_better = r$dm_p_better, dm_p_better_bh = r$dm_p_better_bh,
               slope = r$slope, ece = r$ece)
  }))
  res[, verdict := fifelse(skill_lo > 0 & dm_p_better_bh < 0.05, "incremental skill (CI above 0, BH p < 0.05)",
                           "no incremental skill")]
  setattr(res, "n_dropped", sum(!ok))
  res[]
}

#' S3 for `features` at `decision`: one walk-forward candidate per feature,
#' scored on `eval_seasons` against the anchor, BH over the features' order
vvf_s3_screen <- function(d, features, decision, eval_seasons, registry = vvf_registry(), B = VVF_S3_B, seed = VVF_S3_SEED) {
  anchor <- attr(d, "vvf_anchor")
  if (is.null(anchor)) stop("vvf_s3_screen: the table has no anchor; call vvf_anchor_features() first", call. = FALSE)
  vvf_assert_anchor(anchor, decision)              # A3a review C1: the close only at the close
  vvf_guard_table(d, "the S3 table")               # A3a review I5: the seal at every stage
  vvf_assert_known_at(features, decision, registry)
  vvf_guard_seasons(eval_seasons, VVF_MAX_INPUT_SEASON, "S3 evaluation seasons")
  weeks <- bt_week_schedule(d, eval_seasons)
  x <- d[season %in% eval_seasons, .(game_id, kickoff, season, week, wk, y, p_anchor)]
  meta <- list()
  for (f in features) {
    p <- vvf_s3_refit(d, f, weeks)
    meta[[f]] <- attr(p, "vvf_s3")
    x <- merge(x, p[, .(game_id, p_new = p)], by = "game_id", all.x = TRUE)
    setnames(x, "p_new", paste0("p_", f))
  }
  cols <- paste0("p_", features)
  sk <- vvf_s3_skill(x, cols, order = cols, ref = "p_anchor", B = B, seed = seed)
  sk[, feature := features]
  setcolorder(sk, "feature")
  # the refit's fallbacks go into the table, never only an attribute (review I-3)
  sk[, `:=`(weeks_skipped_min_train = vapply(features, function(f) meta[[f]]$weeks_skipped_min_train, integer(1), USE.NAMES = FALSE),
            weeks_constant = vapply(features, function(f) meta[[f]]$weeks_constant, integer(1), USE.NAMES = FALSE))]
  sk[, `:=`(anchor = anchor, decision = decision)]
  list(skill = sk, predictions = x, meta = meta, anchor = anchor, decision = decision)
}
