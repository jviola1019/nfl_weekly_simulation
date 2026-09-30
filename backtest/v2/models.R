# =============================================================================
# Validation sprint v2: which blend family and which calibration map is most
# useful? Logistic regression vs penalised logistic (glmnet) vs gradient
# boosting (xgboost, gbm), all fit walk-forward week by week on identical
# inputs, then calibrated with maps fit only on earlier weeks' out-of-fold
# predictions. Scored on the Tune window (2018-2022) only.
#
# Candidates (probability the home team wins; ties dropped):
#   LR_E1     ridge logistic y ~ 1 + logit(close) + logit(E1)            (v1 B1[E1])
#   LR_C1C2   ridge logistic y ~ 1 + logit(close) + logit(C1) + logit(C2)
#   GLMNET    elastic net (alpha 0.25, the engine's BLEND_ALPHA), market term
#             unpenalised, + model-vs-market gaps + 28 situational features;
#             lambda.1se from season-grouped CV on the training weeks only
#   XGB       xgboost anchored on the market (base_margin = logit close),
#             depth-2 trees on the same features; rounds chosen by early
#             stopping on the most recent training season, then refit
#   XGB_FREE  the same xgboost WITHOUT the market anchor (logit close is just a
#             feature) - shows what anchoring is worth
#   GBM       gbm anchored on the market (offset), depth 2, rounds by a
#             time-ordered validation split, then refit
# Calibration maps per candidate: none, platt, isotonic, spline (mgcv GAM,
# 4 knots, on the logit scale), each nested walk-forward.
# =============================================================================

BT2_BLEND_FIRST_PRED_SEASON <- 2014L   # out-of-fold blend predictions start here
BT2_BLEND_MIN_TRAIN <- 800L
BT2_CAL_MIN_TRAIN <- 500L
BT2_INNER_VALID <- 267L                 # about one season of games, most recent first
BT2_SEED <- 20260930L
BT2_XGB_PARAMS <- list(objective = "binary:logistic", eval_metric = "logloss", eta = 0.02, max_depth = 2,
                       min_child_weight = 30, subsample = 0.8, colsample_bytree = 0.8, lambda = 10,
                       nthread = 1, base_score = 0.5)
BT2_GBM_ARGS <- list(n.trees = 1500, interaction.depth = 2, shrinkage = 0.01, n.minobsinnode = 30, bag.fraction = 0.8)
BT2_CAL_METHODS <- c("none", "platt", "isotonic", "spline")

bt2_model_features <- function(screen = BT2_SCREEN) {
  sit <- screen[(!posthoc) & !group %in% c("model vs market", "market shape"), feature]
  c("d_c1", "d_c2", setdiff(sit, "inj_diff_all"))
}

bt2_fill <- function(m) { m[!is.finite(m)] <- 0; m }

#' Standardise training columns; apply the same centring/scaling to the target
bt2_scale <- function(train, target) {
  mu <- colMeans(train); s <- apply(train, 2, stats::sd); s[!is.finite(s) | s == 0] <- 1
  list(train = sweep(sweep(train, 2, mu), 2, s, "/"), target = sweep(sweep(target, 2, mu), 2, s, "/"))
}

bt2_fit_predict <- function(model, tr, tg, feats) {
  set.seed(BT2_SEED)
  lp_tr <- tr$lp_c0; lp_tg <- tg$lp_c0
  if (model == "LR_E1") {
    X <- cbind(int = 1, mkt = lp_tr, e1 = bt_logit(bt_clip(tr$p_e1)))
    b <- bt_ridge_logistic(X, tr$y, 0.1, unpenalized = 1L)
    return(drop(bt_expit(cbind(1, lp_tg, bt_logit(bt_clip(tg$p_e1))) %*% b)))
  }
  if (model == "LR_C1C2") {
    X <- cbind(int = 1, mkt = lp_tr, c1 = bt_logit(bt_clip(tr$p_c1)), c2 = bt_logit(bt_clip(tr$p_c2)))
    b <- bt_ridge_logistic(X, tr$y, 1, unpenalized = 1L)
    return(drop(bt_expit(cbind(1, lp_tg, bt_logit(bt_clip(tg$p_c1)), bt_logit(bt_clip(tg$p_c2))) %*% b)))
  }
  Xtr <- bt2_fill(as.matrix(tr[, ..feats])); Xtg <- bt2_fill(as.matrix(tg[, ..feats]))
  if (model == "GLMNET") {
    sc <- bt2_scale(Xtr, Xtg)
    Xa <- cbind(mkt = lp_tr, sc$train); Xt <- cbind(mkt = lp_tg, sc$target)
    fold <- as.integer(factor(tr$season))
    cv <- glmnet::cv.glmnet(Xa, tr$y, family = "binomial", alpha = 0.25, foldid = fold,
                            penalty.factor = c(0, rep(1, ncol(sc$train))), type.measure = "deviance")
    return(drop(stats::predict(cv, newx = Xt, s = "lambda.1se", type = "response")))
  }
  if (model %in% c("XGB", "XGB_FREE")) {
    anchor <- model == "XGB"
    if (!anchor) { Xtr <- cbind(mkt = lp_tr, Xtr); Xtg <- cbind(mkt = lp_tg, Xtg) }
    n <- nrow(Xtr); iv <- seq.int(n - BT2_INNER_VALID + 1L, n); it <- seq_len(n - BT2_INNER_VALID)
    mk <- function(X, y, lp) if (anchor) xgboost::xgb.DMatrix(X, label = y, base_margin = lp, nthread = 1) else
      xgboost::xgb.DMatrix(X, label = y, nthread = 1)
    params <- do.call(xgboost::xgb.params, BT2_XGB_PARAMS)
    fit <- xgboost::xgb.train(params, mk(Xtr[it, , drop = FALSE], tr$y[it], lp_tr[it]), nrounds = 1000,
                              evals = list(val = mk(Xtr[iv, , drop = FALSE], tr$y[iv], lp_tr[iv])),
                              early_stopping_rounds = 50, verbose = 0)
    best <- as.integer(xgboost::xgb.attr(fit, "best_iteration")) + 1L
    set.seed(BT2_SEED)
    full <- xgboost::xgb.train(params, mk(Xtr, tr$y, lp_tr), nrounds = best, verbose = 0)
    dt <- if (anchor) xgboost::xgb.DMatrix(Xtg, base_margin = lp_tg, nthread = 1) else xgboost::xgb.DMatrix(Xtg, nthread = 1)
    p <- stats::predict(full, dt)
    attr(p, "rounds") <- best
    return(p)
  }
  if (model == "GBM") {
    df <- data.frame(y = tr$y, lp = lp_tr, Xtr)
    fml <- stats::as.formula(paste("y ~ offset(lp) +", paste(colnames(Xtr), collapse = " + ")))
    args <- c(list(formula = fml, data = df, distribution = "bernoulli", verbose = FALSE,
                   train.fraction = 1 - BT2_INNER_VALID / nrow(df), keep.data = FALSE), BT2_GBM_ARGS)
    fit <- do.call(gbm::gbm, args)
    best <- max(1L, suppressWarnings(gbm::gbm.perf(fit, method = "test", plot.it = FALSE)))
    set.seed(BT2_SEED)
    args$train.fraction <- 1; args$n.trees <- best
    full <- do.call(gbm::gbm, args)
    # predict.gbm leaves the offset out (and warns so); it is added back explicitly
    eta <- withCallingHandlers(
      stats::predict(full, newdata = data.frame(lp = lp_tg, Xtg), n.trees = best, type = "link"),
      warning = function(w) if (grepl("does not add the offset", conditionMessage(w))) invokeRestart("muffleWarning"))
    p <- bt_expit(eta + lp_tg)
    attr(p, "rounds") <- best
    return(p)
  }
  stop("unknown model ", model)
}

BT2_MODELS <- c("LR_E1", "LR_C1C2", "GLMNET", "XGB", "XGB_FREE", "GBM")

#' Walk-forward predictions for every model. `d` = features (seasons <= 2022).
bt2_walk_models <- function(d, weeks, models = BT2_MODELS, feats = bt2_model_features(),
                            first_season = BT2_BLEND_FIRST_PRED_SEASON) {
  lab <- d[!is.na(y) & is.finite(lp_c0)]
  setorder(lab, kickoff, game_id)
  pw <- weeks[season >= first_season]
  out <- list(); rounds <- list(); secs <- setNames(numeric(length(models)), models)
  for (i in seq_len(nrow(pw))) {
    cut <- pw$cutoff[i]
    tr <- lab[kickoff < cut & season >= BT2_FIRST_PRED_SEASON]
    tg <- d[wk == pw$wk[i] & is.finite(lp_c0)]
    if (!nrow(tg) || nrow(tr) < BT2_BLEND_MIN_TRAIN) next
    row <- data.table(game_id = tg$game_id)
    for (m in models) {
      t0 <- Sys.time()
      p <- bt2_fit_predict(m, tr, tg, feats)
      secs[[m]] <- secs[[m]] + as.numeric(difftime(Sys.time(), t0, units = "secs"))
      if (!is.null(attr(p, "rounds"))) rounds[[length(rounds) + 1L]] <- data.table(wk = pw$wk[i], model = m, rounds = attr(p, "rounds"))
      set(row, j = paste0("p_", m), value = as.numeric(p))
    }
    out[[length(out) + 1L]] <- row
  }
  list(pred = rbindlist(out), rounds = rbindlist(rounds), seconds = secs)
}

#' Calibration map fit on (p, y)
bt2_cal_fit <- function(p, y, method) {
  if (method == "none") return(identity)
  if (method %in% c("platt", "isotonic")) return(bt_calib_fit(p, y, method))
  if (method == "spline") {
    lp <- bt_logit(bt_clip(p))
    g <- mgcv::gam(y ~ s(lp, k = 4, bs = "cr"), family = stats::binomial(), method = "REML")
    return(function(q) as.numeric(stats::predict(g, newdata = data.frame(lp = bt_logit(bt_clip(q))), type = "response")))
  }
  stop("unknown calibration ", method)
}

#' Nested walk-forward calibration of one prediction column
bt2_calibrate <- function(pred, d, weeks, col, method) {
  x <- merge(pred[, .(game_id, p = get(col))], d[, .(game_id, kickoff, season, wk, y)], by = "game_id")
  setorder(x, kickoff, game_id)
  out <- vector("list", nrow(weeks)); nonmono <- 0L; fits <- 0L
  for (i in seq_len(nrow(weeks))) {
    tg <- x[wk == weeks$wk[i]]
    if (!nrow(tg)) next
    tr <- x[kickoff < weeks$cutoff[i] & !is.na(y) & is.finite(p)]
    if (nrow(tr) < BT2_CAL_MIN_TRAIN) next
    f <- bt2_cal_fit(tr$p, tr$y, method)
    if (method == "spline") {
      grid <- seq(0.05, 0.95, by = 0.01); fits <- fits + 1L
      if (any(diff(f(grid)) < -1e-9)) nonmono <- nonmono + 1L
    }
    out[[i]] <- data.table(game_id = tg$game_id, p = pmin(pmax(f(tg$p), 1e-4), 1 - 1e-4))
  }
  r <- rbindlist(out)
  attr(r, "nonmonotone_share") <- if (fits) nonmono / fits else NA_real_
  r
}

#' Reliability table (10 equal-mass bins) for committed CSVs
bt2_reliability <- function(p, y, bins = 10L) {
  g <- cut(rank(p, ties.method = "first"), breaks = bins, labels = FALSE)
  data.table(bin = g, p = p, y = y)[, .(n = .N, mean_p = mean(p), obs_rate = mean(y)), by = bin][order(bin)]
}

#' Shuffled-label control: permute outcomes globally (seeded), refit the blends
#' walk-forward, and score against an expanding-window home-win-rate climatology.
#' A sound harness shows no skill: every skill CI lower bound must be <= 0.
bt2_control_shuffle <- function(d, weeks, models = c("LR_E1", "GLMNET", "XGB"), seed = BT2_SEED) {
  x <- copy(d)
  lab <- which(!is.na(x$y))
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  x$y[lab] <- x$y[lab][sample.int(length(lab))]
  if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv())
  wm <- bt2_walk_models(x, weeks, models = models)
  ev <- merge(wm$pred, x[, .(game_id, season, wk, kickoff, y)], by = "game_id")[season %in% BT2_TUNE_SEASONS & !is.na(y)]
  setorder(ev, kickoff, game_id)
  # climatology: home-win rate of all labelled games before the week's first kickoff
  clim <- rbindlist(lapply(split(weeks, by = "wk"), function(w) {
    prior <- x[kickoff < w$cutoff & !is.na(y)]
    data.table(wk = w$wk, p_clim = if (nrow(prior)) mean(prior$y) else 0.5)
  }))
  ev <- merge(ev, clim, by = "wk")
  cols <- paste0("p_", models)
  sc <- bt_score_window(copy(ev), setNames(cols, cols), c(CLIM = "p_clim"), seed = seed)
  out <- rbindlist(lapply(cols, function(cc) data.table(model = sub("^p_", "", cc), n = sc[[cc]]$n, skill_vs_climatology = sc[[cc]]$skill,
                                                       skill_lo = sc[[cc]]$skill_ci[1], skill_hi = sc[[cc]]$skill_ci[2])))
  out[, passed := skill_lo <= 0]
  out[]
}

bt2_run_models <- function(d, weeks, out_dir) {
  t0 <- Sys.time()
  wm <- bt2_walk_models(d, weeks)
  pred <- wm$pred
  base <- d[, .(game_id, p_c0, p_c1, p_c2, p_e1)]
  pred <- merge(pred, base, by = "game_id", all.x = TRUE)
  cols <- c(paste0("p_", BT2_MODELS), "p_e1")
  cal_share <- list()
  for (cc in cols) for (m in setdiff(BT2_CAL_METHODS, "none")) {
    k <- bt2_calibrate(pred, d, weeks, cc, m)
    nm <- paste0(cc, "__", m)
    pred <- merge(pred, k[, .(game_id, tmp = p)], by = "game_id", all.x = TRUE)
    setnames(pred, "tmp", nm)
    if (m == "spline") cal_share[[cc]] <- attr(k, "nonmonotone_share")
  }
  ev <- merge(pred, d[, .(game_id, season, week, wk, kickoff, y)], by = "game_id")[season %in% BT2_TUNE_SEASONS & !is.na(y)]
  cand_cols <- setdiff(grep("^p_", names(ev), value = TRUE), "p_c0")
  miss <- vapply(cand_cols, function(cc) sum(!is.finite(ev[[cc]])), integer(1))
  if (any(miss > 0)) stop("models: missing Tune predictions: ", paste(names(miss)[miss > 0], collapse = ", "))
  sc <- bt_score_window(copy(ev), setNames(cand_cols, cand_cols), c(C0 = "p_c0"), seed = BT2_SEED)
  tab <- rbindlist(lapply(c("p_c0", cand_cols), function(cc) {
    s <- sc[[cc]]
    base_nm <- sub("__.*$", "", sub("^p_", "", cc))
    cal <- if (grepl("__", cc)) sub("^.*__", "", cc) else "none"
    data.table(candidate = base_nm, calibration = cal, n = s$n, brier = s$brier, logloss = s$logloss, ece = s$ece,
               slope = s$slope, slope_lo = s$slope_ci[1], slope_hi = s$slope_ci[2],
               skill = if (cc == "p_c0") 0 else s$skill, skill_lo = if (cc == "p_c0") 0 else s$skill_ci[1],
               skill_hi = if (cc == "p_c0") 0 else s$skill_ci[2], dm_p = if (cc == "p_c0") NA_real_ else s$dm_p_better,
               dm_p_bh = if (cc == "p_c0") NA_real_ else s$dm_p_better_bh)
  }))
  tab[candidate == "c0", candidate := "C0 (close)"]
  tab[candidate == "e1", candidate := "E1 (v1 ensemble)"]
  setorder(tab, -skill)
  rel <- rbindlist(lapply(c("p_c0", cand_cols), function(cc) bt2_reliability(ev[[cc]], ev$y)[, column := cc]))
  bt2_write_csv(tab[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)], file.path(out_dir, "models", "scores_tune.csv"))
  bt2_write_csv(rel[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)], file.path(out_dir, "models", "reliability_tune.csv"))
  bt2_write_csv(wm$rounds, file.path(out_dir, "models", "boosting_rounds.csv"))
  long <- melt(ev[, c("game_id", "season", "week", "y", "p_c0", cand_cols), with = FALSE],
               id.vars = c("game_id", "season", "week", "y", "p_c0"), variable.name = "column", value.name = "p_model")
  long[, `:=`(candidate = sub("^p_", "", column), brier = (p_model - y)^2,
              logloss = bt_logloss_vec(p_model, y), brier_market = (p_c0 - y)^2)]
  bt2_write_csv(long[, .(game_id, season, week, candidate, p_model = round(p_model, 8), p_market = round(p_c0, 8), outcome = y,
                         brier = round(brier, 8), logloss = round(logloss, 8), brier_market = round(brier_market, 8))],
                file.path(out_dir, "tracking", "moneyline_tune.csv"))
  list(n_tune = nrow(ev), seconds_by_model = as.list(wm$seconds), spline_nonmonotone_share = cal_share,
       rounds_summary = if (nrow(wm$rounds)) wm$rounds[, .(median_rounds = stats::median(rounds), min = min(rounds), max = max(rounds)), by = model] else NULL,
       total_seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))
}
