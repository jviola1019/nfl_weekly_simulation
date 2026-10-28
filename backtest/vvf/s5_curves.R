# =============================================================================
# VVF stage S5, bias-variance diagnostics: validation curves, nested
# walk-forward validation, learning curves and the in-sample against
# walk-forward gap (amendment 2026-10-21, item 1).
#
# The one-SE rule here works on paired differences: every setting is scored on
# the same games, so the noise that matters is the bootstrap SE of each
# setting's loss minus the best setting's loss (week blocks, bt_boot_counts).
# The chosen setting is the simplest whose mean log loss is within one such SE
# of the best. On the planted half-life test this recovers the truth; the SE of
# the best setting's own mean, the textbook form, chose one step smoother in all
# five dry-run seeds.
# Validation is walk-forward only, never random k-fold, and nested: tune inside
# the tuning seasons, evaluate later seasons (vvf_assert_nested).
# =============================================================================

VVF_S5_B <- 10000L
VVF_S5_SEED <- 20261024L

#' Validation curve over `grid`, ordered from the simplest setting (most
#' smoothing or shrinkage) to the most complex. predict_fun(value, seasons)
#' returns data.table(game_id, p): walk-forward predictions for `seasons`.
#' `d` holds the evaluated games (game_id, wk, y).
vvf_validation_curve <- function(grid, predict_fun, d, seasons, B = VVF_S5_B, seed = VVF_S5_SEED) {
  x <- d[!is.na(y), .(game_id, wk, y)]
  P <- vapply(grid, function(v) {
    p <- predict_fun(v, seasons)
    p$p[match(x$game_id, p$game_id)]
  }, numeric(nrow(x)))
  if (anyNA(P)) stop("validation curve: a setting is missing predictions for some evaluation games", call. = FALSE)
  P <- bt_clip(P)
  LL <- -(x$y * log(P) + (1 - x$y) * log(1 - P))
  BR <- (P - x$y)^2
  wk_f <- factor(x$wk)
  counts <- bt_boot_counts(nlevels(wk_f), B, seed)
  bn <- drop(counts %*% tabulate(as.integer(wk_f), nlevels(wk_f)))
  boot <- function(M) (counts %*% rowsum(M, wk_f)) / bn
  ll_b <- boot(LL)
  br_b <- boot(BR)
  m <- colMeans(LL)
  best <- which.min(m)
  diff_se <- apply(ll_b - ll_b[, best], 2, stats::sd)
  chosen <- which(m - m[best] <= diff_se)[1]
  q <- function(M) apply(M, 2, bt_quantile_ci)
  data.table(value = grid, order = seq_along(grid), n = nrow(x),
             logloss = m, logloss_lo = q(ll_b)[1, ], logloss_hi = q(ll_b)[2, ], logloss_se = apply(ll_b, 2, stats::sd),
             diff_to_best = m - m[best], diff_se = diff_se,
             brier = colMeans(BR), brier_lo = q(br_b)[1, ], brier_hi = q(br_b)[2, ],
             best = seq_along(grid) == best, chosen = seq_along(grid) == chosen)
}

#' Nested validation: every evaluation season follows every tuning season, and
#' none is sealed
vvf_assert_nested <- function(tune_seasons, eval_seasons, sealed = vvf_sealed_seasons()) {
  if (any(eval_seasons <= max(tune_seasons))) {
    stop(sprintf("nested validation: evaluation seasons (%s) must all follow the tuning seasons (%s)",
                 paste(eval_seasons, collapse = ", "), paste(tune_seasons, collapse = ", ")), call. = FALSE)
  }
  vvf_guard_seasons(c(tune_seasons, eval_seasons), VVF_MAX_INPUT_SEASON, "nested validation seasons", sealed)
  invisible(TRUE)
}

#' Walk-forward predictions for the weeks of `eval_seasons`, training on the
#' rows `train_rows(d, week_row)` returns. fit_predict(train, target) -> p.
vvf_walk_forward <- function(d, fit_predict, eval_seasons, train_rows) {
  weeks <- bt_week_schedule(d, eval_seasons)
  rbindlist(lapply(seq_len(nrow(weeks)), function(i) {
    tg <- d[wk == weeks$wk[i]]
    tr <- train_rows(d, weeks[i])
    stopifnot(max(tr$kickoff) < weeks$cutoff[i])
    data.table(game_id = tg$game_id, season = tg$season, y = tg$y, p = fit_predict(tr, tg))
  }))[!is.na(y)]
}

#' Learning curve: for each n, train on the n seasons before the predicted
#' week's season plus that season's earlier weeks, and score the same games
vvf_learning_curve <- function(fit_predict, d, eval_seasons, n_train = 2:10) {
  rbindlist(lapply(n_train, function(n) {
    p <- vvf_walk_forward(d, fit_predict, eval_seasons, function(d, w) {
      d[kickoff < w$cutoff & season >= w$season - n & !is.na(y)]
    })
    data.table(n_train_seasons = n, n = nrow(p), logloss = mean(bt_logloss_vec(p$p, p$y)), brier = mean(bt_brier_vec(p$p, p$y)))
  }))
}

#' Per season: the loss of a fit on that season's own rows (in-sample) against
#' the expanding walk-forward loss on the same rows. gap = walk-forward minus
#' in-sample; a large positive gap is over-fitting.
vvf_fit_gap <- function(d, fit_predict, eval_seasons) {
  wf <- vvf_walk_forward(d, fit_predict, eval_seasons, function(d, w) d[kickoff < w$cutoff & !is.na(y)])
  ins <- rbindlist(lapply(eval_seasons, function(s) {
    tr <- d[season == s & !is.na(y)]
    data.table(season = s, y = tr$y, p = fit_predict(tr, tr))
  }))
  a <- ins[, .(logloss_in = mean(bt_logloss_vec(p, y))), by = season]
  b <- wf[, .(logloss_wf = mean(bt_logloss_vec(p, y))), by = season]
  out <- merge(a, b, by = "season")
  out[, gap := logloss_wf - logloss_in]
  out[]
}
