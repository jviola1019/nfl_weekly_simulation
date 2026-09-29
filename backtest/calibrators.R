# =============================================================================
# K calibrators, fit with nested walk-forward: the calibrator applied to week t
# is fit only on out-of-fold predictions from games that kicked off before
# week t, so it never sees the evaluation fold.
#   platt:    logistic y ~ 1 + logit(p)
#   isotonic: pool-adjacent-violators fit, linearly interpolated, clamped to [0.01, 0.99]
# =============================================================================

BT_K_METHODS <- c("platt", "isotonic")
BT_K_MIN_TRAIN <- 500L
BT_K_FIRST_TRAIN_SEASON <- 2010L

bt_calib_fit <- function(p, y, method) {
  if (method == "platt") {
    X <- cbind(int = 1, lp = bt_logit(bt_clip(p)))
    beta <- bt_ridge_logistic(X, y, lambda = 0)
    return(function(q) drop(bt_expit(cbind(1, bt_logit(bt_clip(q))) %*% beta)))
  }
  if (method == "isotonic") {
    o <- order(p)
    fit <- stats::isoreg(p[o], y[o])
    x <- p[o]; yf <- fit$yf
    ux <- unique(x)
    uy <- vapply(split(yf, factor(x, levels = ux)), mean, numeric(1))
    return(function(q) pmin(pmax(stats::approx(ux, uy, xout = q, rule = 2, ties = "ordered")$y, 0.01), 0.99))
  }
  stop("bt_calib_fit: unknown method ", method)
}

#' `d` has game_id, kickoff, season, wk, y, p (out-of-fold predictions)
bt_calib_walk_forward <- function(d, weeks, method) {
  d <- d[is.finite(p)]
  setorder(d, kickoff, game_id)
  out <- vector("list", nrow(weeks))
  for (i in seq_len(nrow(weeks))) {
    cut <- weeks$cutoff[i]
    train <- d[kickoff < cut & season >= BT_K_FIRST_TRAIN_SEASON & !is.na(y)]
    target <- d[wk == weeks$wk[i]]
    if (nrow(target) == 0L || nrow(train) < BT_K_MIN_TRAIN) next
    f <- bt_calib_fit(train$p, train$y, method)
    out[[i]] <- data.table(game_id = target$game_id, p = f(target$p))
  }
  rbindlist(out)
}
