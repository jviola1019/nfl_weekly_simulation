# =============================================================================
# nfl_preclose_v1's anchored candidates (PROTOCOL.md "Candidates"), walk-forward by week.
# `d` has game_id, kickoff, season, wk, y (NA for ties), p_open, p_close and p_e1a (E1 on
# IS-A); `weeks` has season, week, wk and cutoff, the week's IS-A cutoff. Training rows
# are games that kicked off before the cutoff, never from 2025 (sealed prices).
#   OA[E1]: ridge logistic y ~ 1 + lp_open + logit(E1), intercept unpenalized (v1's B1)
#   LM[E1]: OLS of the move logit(close) - lp_open on logit(E1) - lp_open
# =============================================================================

PC_MIN_TRAIN <- 100L
PC_OA_LAMBDA_GRID <- c(0.1, 1, 10)
PC_SEALED_SEASON <- 2025L

pc_oa_walk_forward <- function(d, weeks, lambda, min_train = PC_MIN_TRAIN) {
  d <- d[is.finite(p_open) & is.finite(p_e1a)]
  setorder(d, kickoff, game_id)
  mk <- function(x) cbind(int = 1, open = bt_logit(bt_clip(x$p_open)), model = bt_logit(bt_clip(x$p_e1a)))
  out <- vector("list", nrow(weeks))
  for (i in seq_len(nrow(weeks))) {
    train <- d[kickoff < weeks$cutoff[i] & !is.na(y) & season != PC_SEALED_SEASON]
    target <- d[wk == weeks$wk[i]]
    if (nrow(target) == 0L || nrow(train) < min_train) next
    beta <- bt_ridge_logistic(mk(train), train$y, lambda, unpenalized = 1L)
    out[[i]] <- data.table(game_id = target$game_id, p_oa = drop(bt_expit(mk(target) %*% beta)), oa_b_open = beta[["open"]], oa_b_model = beta[["model"]],
                           oa_train = nrow(train))
  }
  rbindlist(out)
}

pc_lm_walk_forward <- function(d, weeks, min_train = PC_MIN_TRAIN) {
  d <- d[is.finite(p_open) & is.finite(p_e1a)]
  setorder(d, kickoff, game_id)
  d[, `:=`(move = bt_logit(bt_clip(p_close)) - bt_logit(bt_clip(p_open)), lean = bt_logit(bt_clip(p_e1a)) - bt_logit(bt_clip(p_open)))]
  out <- vector("list", nrow(weeks))
  for (i in seq_len(nrow(weeks))) {
    train <- d[kickoff < weeks$cutoff[i] & is.finite(move) & season != PC_SEALED_SEASON]
    target <- d[wk == weeks$wk[i]]
    if (nrow(target) == 0L || nrow(train) < min_train) next
    f <- stats::lm(move ~ lean, data = train)
    mh <- drop(stats::predict(f, newdata = target))
    out[[i]] <- data.table(game_id = target$game_id, move_hat = mh, p_lm = drop(bt_expit(bt_logit(bt_clip(target$p_open)) + mh)),
                           lm_a = unname(stats::coef(f)[1]), lm_b = unname(stats::coef(f)[2]), lm_train = nrow(train))
  }
  rbindlist(out)
}
