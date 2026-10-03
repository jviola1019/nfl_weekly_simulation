# =============================================================================
# Blend research v3: meshes built on the v2 level-0 predictions.
#
# Level 0 (out of fold): the v2 walk-forward predictions of LR_E1, GLMNET, XGB
# and GBM (backtest/v2/models.R, refit weekly on every earlier game from 2010,
# first predicted week 2014-01), plus the walk-forward base models C1 (Elo),
# C2 (EPA GLM) and E1 (their logit average). A week's level-0 prediction uses
# only games that kicked off before that week.
#
#   S1      stacked mesh: ridge logistic (glmnet, alpha 0) of the outcome on the 7
#           level-0 logits with offset logit(close); lambda.1se from season-grouped
#           CV on the training weeks. Fit on earlier weeks' level-0 predictions
#           only (nested walk-forward).
#   S1_MIN  the same with lambda.min (declared sensitivity variant)
#   R1      residual mesh: xgboost with base_margin = the anchored glmnet's
#           out-of-fold logit, so it boosts the residual of the logistic blend;
#           v2 XGB hyperparameters; rounds by early stopping in season-grouped CV
#           on the training weeks, then refit on all of them.
#   O1      online convex blend: exponentially weighted average forecaster over
#           the 7 level-0 models plus the close. Weights exp(-eta * cumulative
#           Brier loss) use only games that kicked off before the week; eta is
#           the grid value (2^-4 to 2^6) with the lowest Brier on 2014-2017
#           (before Tune), then frozen. eta = 1/2 is also the largest rate at
#           which squared loss on [0, 1] is exp-concave, where the summed Brier
#           loss is at most ln(8) / eta = 4.2 above the best expert's.
# Burn-in: level-0 predictions start in 2014, so the meta-learners train on
# 2014-2017 (and earlier Tune weeks) before predicting any Tune week. No Tune
# week is excluded; burn-in weeks are not scored.
# =============================================================================

BT3_O1_ETA_GRID <- 2^(-4:6)
BT3_O1_SELECT_SEASONS <- 2014:2017
BT3_MESHES <- c("S1", "S1_MIN", "R1")

bt3_level0_chunk <- function(weeks, d, models) bt2_walk_models(d, weeks, models = models)

#' Level 0: the v2 families' walk-forward predictions (2014-2022) from the
#' unchanged v2 code (bt2_walk_models), run in week chunks
bt3_level0 <- function(d, weeks, cl = NULL, models = BT2_MODELS) {
  bt3_guard(d$season, "level-0 rows")
  t0 <- Sys.time()
  pw <- weeks[season >= BT2_BLEND_FIRST_PRED_SEASON]
  res <- bt3_map_weeks(pw, "bt3_level0_chunk", d = d, models = models, cl = cl)
  pred <- rbindlist(lapply(res, `[[`, "pred"))[order(match(game_id, d$game_id))]
  rounds <- rbindlist(lapply(res, `[[`, "rounds"))
  if (nrow(rounds)) rounds <- rounds[order(wk, match(model, models))]
  list(pred = pred, rounds = rounds, seconds = Reduce(`+`, lapply(res, `[[`, "seconds")),
       wall = as.numeric(difftime(Sys.time(), t0, units = "secs")))
}

#' Games with every level-0 prediction (and a market price)
bt3_meta_rows <- function(L, cols = BT3_LEVEL0) {
  ok <- is.finite(L$lp_c0)
  for (cc in cols) ok <- ok & is.finite(L[[cc]])
  L[ok]
}

#' S1 / S1_MIN: ridge meta-logistic on the level-0 logits, offset = logit(close)
bt3_s1_fit_predict <- function(tr, tg, cols = BT3_LEVEL0, s = "lambda.1se") {
  set.seed(BT2_SEED)
  X <- bt_logit(bt_clip(as.matrix(tr[, ..cols]))); Xt <- bt_logit(bt_clip(as.matrix(tg[, ..cols])))
  colnames(X) <- colnames(Xt) <- names(cols)
  cv <- glmnet::cv.glmnet(X, tr$y, family = "binomial", alpha = 0, offset = tr$lp_c0,
                          foldid = as.integer(factor(tr$season)), type.measure = "deviance")
  p <- drop(stats::predict(cv, newx = Xt, newoffset = tg$lp_c0, s = s, type = "response"))
  b <- as.matrix(stats::coef(cv, s = s))[, 1]
  attr(p, "diag") <- data.table(term = c(names(b), "lambda"), value = c(unname(b), cv[[s]]))
  p
}

#' R1: xgboost boosting the residual of the anchored glmnet (base_margin = its OOF logit)
bt3_r1_fit_predict <- function(tr, tg, feats = bt2_model_features()) {
  set.seed(BT2_SEED)
  m_tr <- bt_logit(bt_clip(tr$p_GLMNET)); m_tg <- bt_logit(bt_clip(tg$p_GLMNET))
  Xtr <- bt2_fill(as.matrix(tr[, ..feats])); Xtg <- bt2_fill(as.matrix(tg[, ..feats]))
  params <- do.call(xgboost::xgb.params, BT2_XGB_PARAMS)
  dtr <- xgboost::xgb.DMatrix(Xtr, label = tr$y, base_margin = m_tr, nthread = 1)
  folds <- unname(split(seq_len(nrow(tr)), tr$season))
  cv <- xgboost::xgb.cv(params, dtr, nrounds = 1000, folds = folds, early_stopping_rounds = 50, verbose = 0)
  best <- as.integer(cv$early_stop$best_iteration)
  set.seed(BT2_SEED)
  full <- xgboost::xgb.train(params, dtr, nrounds = best, verbose = 0)
  p <- stats::predict(full, xgboost::xgb.DMatrix(Xtg, base_margin = m_tg, nthread = 1))
  attr(p, "diag") <- data.table(term = "rounds", value = best)
  p
}

#' Walk S1 / S1_MIN / R1 over `weeks`. `L` = features joined to level-0 predictions.
bt3_walk_meta <- function(weeks, family, L, cols = BT3_LEVEL0, feats = bt2_model_features(),
                          min_train = BT3_META_MIN_TRAIN) {
  bt3_guard(L$season, "meta rows")
  M <- bt3_meta_rows(L, cols)
  lab <- M[!is.na(y)]
  setorder(lab, kickoff, game_id)
  out <- list(); diag <- list(); secs <- 0
  for (i in seq_len(nrow(weeks))) {
    tr <- lab[kickoff < weeks$cutoff[i]]
    tg <- M[wk == weeks$wk[i]]
    if (!nrow(tg) || nrow(tr) < min_train || data.table::uniqueN(tr$season) < BT3_META_MIN_SEASONS) next
    t0 <- Sys.time()
    p <- switch(family,
                S1 = bt3_s1_fit_predict(tr, tg, cols, "lambda.1se"),
                S1_MIN = bt3_s1_fit_predict(tr, tg, cols, "lambda.min"),
                R1 = bt3_r1_fit_predict(tr, tg, feats),
                stop("unknown mesh ", family))
    secs <- secs + as.numeric(difftime(Sys.time(), t0, units = "secs"))
    out[[length(out) + 1L]] <- data.table(game_id = tg$game_id, p = as.numeric(p))
    diag[[length(diag) + 1L]] <- cbind(data.table(wk = weeks$wk[i], n_train = nrow(tr)), attr(p, "diag"))
  }
  list(pred = rbindlist(out), diag = rbindlist(diag), seconds = setNames(secs, family))
}

#' O1: exponentially weighted average forecaster. `L` has kickoff, wk, y and the
#' expert columns (finite on every row); weights for a week use only the Brier
#' losses of games that kicked off before the week's first kickoff.
bt3_o1_walk <- function(L, weeks, cols, eta) {
  bt3_guard(L$season, "O1 rows")
  x <- L[, c("game_id", "kickoff", "wk", "y", cols), with = FALSE]
  P <- as.matrix(x[, ..cols])
  if (any(!is.finite(P))) stop("bt3_o1_walk: every expert needs a prediction on every row")
  loss <- (P - x$y)^2
  out <- vector("list", nrow(weeks)); wts <- vector("list", nrow(weeks))
  for (i in seq_len(nrow(weeks))) {
    tg <- which(x$wk == weeks$wk[i])
    if (!length(tg)) next
    prior <- which(x$kickoff < weeks$cutoff[i] & !is.na(x$y))
    cum <- if (length(prior)) colSums(loss[prior, , drop = FALSE]) else setNames(numeric(length(cols)), cols)
    w <- exp(-eta * (cum - min(cum)))
    w <- w / sum(w)
    out[[i]] <- data.table(game_id = x$game_id[tg], p = drop(P[tg, , drop = FALSE] %*% w))
    wts[[i]] <- data.table(wk = weeks$wk[i], expert = names(cols), weight = unname(w), n_past = length(prior))
  }
  list(pred = rbindlist(out), weights = rbindlist(wts))
}

#' O1 learning rate: the grid value with the lowest Brier on 2014-2017 (before Tune)
bt3_o1_select_eta <- function(L, weeks, cols, grid = BT3_O1_ETA_GRID, seasons = BT3_O1_SELECT_SEASONS) {
  w <- weeks[season %in% seasons]
  ev <- L[season %in% seasons & !is.na(y), .(game_id, y)]
  rows <- lapply(grid, function(eta) {
    p <- bt3_o1_walk(L, w, cols, eta)$pred
    m <- merge(ev, p, by = "game_id")
    data.table(eta = eta, n = nrow(m), brier = mean((m$p - m$y)^2))
  })
  tab <- rbindlist(rows)
  tab[, chosen := eta == tab$eta[which.min(tab$brier)]]
  tab[]
}

#' O1 end to end: eta selected on 2014-2017, then the online blend walks every week from 2014
bt3_run_o1 <- function(L, weeks, cols = c(BT3_LEVEL0, C0 = "p_c0")) {
  t0 <- Sys.time()
  x <- L[season >= min(BT3_O1_SELECT_SEASONS)]
  ok <- Reduce(`&`, lapply(cols, function(cc) is.finite(x[[cc]])))
  x <- x[ok]
  w <- weeks[season >= min(BT3_O1_SELECT_SEASONS)]
  grid <- bt3_o1_select_eta(x, w, cols)
  eta <- grid[chosen == TRUE, eta]
  o <- bt3_o1_walk(x, w, cols, eta)
  list(pred = o$pred, weights = o$weights, grid = grid, eta = eta,
       seconds = c(O1 = as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
