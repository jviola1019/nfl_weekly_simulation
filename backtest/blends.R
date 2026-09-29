# =============================================================================
# Ensembles and market blends (shootout design: E1, B1, B2).
#   E1: equal-weight logit average of the model-only candidates.
#   B1: ridge logistic y ~ 1 + logit(C0) + logit(Ci), refit weekly on all earlier
#       games with both inputs (walk-forward); the market weight is learned.
#   B2: (1 - w) * p_model + w * p_market with w fixed from the Tune window.
# =============================================================================

BT_B1_LAMBDA_GRID <- c(0.1, 1, 10)
BT_B2_W_GRID <- seq(0.50, 0.95, by = 0.05)
BT_BLEND_MIN_TRAIN <- 200L
BT_BLEND_FIRST_TRAIN_SEASON <- 2010L

bt_e1 <- function(...) {
  ps <- list(...)
  bt_expit(Reduce(`+`, lapply(ps, function(p) bt_logit(bt_clip(p)))) / length(ps))
}

#' B1 walk-forward. `d` has game_id, kickoff, season, wk, y, p_mkt, p_model.
#' Returns data.table(game_id, p, b_mkt, b_model) with the fitted coefficients.
bt_b1_walk_forward <- function(d, weeks, lambda) {
  d <- d[is.finite(p_mkt) & is.finite(p_model)]
  setorder(d, kickoff, game_id)
  out <- vector("list", nrow(weeks))
  for (i in seq_len(nrow(weeks))) {
    cut <- weeks$cutoff[i]
    train <- d[kickoff < cut & season >= BT_BLEND_FIRST_TRAIN_SEASON & !is.na(y)]
    target <- d[wk == weeks$wk[i]]
    if (nrow(target) == 0L || nrow(train) < BT_BLEND_MIN_TRAIN) next
    X <- cbind(int = 1, mkt = bt_logit(bt_clip(train$p_mkt)), model = bt_logit(bt_clip(train$p_model)))
    beta <- bt_ridge_logistic(X, train$y, lambda, unpenalized = 1L)
    Xt <- cbind(int = 1, mkt = bt_logit(bt_clip(target$p_mkt)), model = bt_logit(bt_clip(target$p_model)))
    out[[i]] <- data.table(game_id = target$game_id, p = drop(bt_expit(Xt %*% beta)),
                           b_mkt = beta[["mkt"]], b_model = beta[["model"]])
  }
  rbindlist(out)
}

bt_b2 <- function(p_model, p_mkt, w) (1 - w) * p_model + w * p_mkt
