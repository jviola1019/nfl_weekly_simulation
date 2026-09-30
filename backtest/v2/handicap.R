# =============================================================================
# Validation sprint v2: handicapping markets (against the spread, totals).
#
# Targets (pushes dropped): cover = home margin > spread_line; over = total > total_line.
# Market baseline: the nflverse consensus closing spread/total prices, devigged
# proportionally (available for every Tune game). Candidates, walk-forward by week:
#   RESID_GLMNET  gaussian elastic net on (outcome - line) ~ model-vs-market gaps +
#                 situational features; P = Phi(mu / sigma), sigma = training SD
#   LOGIT_GLMNET  binomial elastic net on the cover/over outcome, same features
#   XGB           xgboost anchored on the market's devigged probability (base_margin)
#   TZ_ONLY       logistic cover ~ abs_tz_away (the one feature with q < 0.20 in the
#                 ATS screen). Selected ON the Tune window, so its Tune score is
#                 optimistic and only an out-of-sample test can confirm it.
# Scored on Tune 2018-2022: Brier skill vs the market price with a week-block
# bootstrap CI, and flat 1-unit betting at the actual closing price when the
# model's probability exceeds the market's by >= 3 points, with a Wilson CI on
# the hit rate against the break-even rate implied by the prices taken.
# =============================================================================

BT2_HC_EDGE <- 0.03

bt2_wilson <- function(k, n, z = 1.96) {
  if (n == 0) return(c(NA_real_, NA_real_))
  p <- k / n; den <- 1 + z^2 / n
  c((p + z^2 / (2 * n) - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / den,
    (p + z^2 / (2 * n) + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / den)
}

bt2_hc_fit_predict <- function(model, tr, tg, feats, target, resid_col, pm_col) {
  set.seed(BT2_SEED)
  Xtr <- bt2_fill(as.matrix(tr[, ..feats])); Xtg <- bt2_fill(as.matrix(tg[, ..feats]))
  if (model == "RESID_GLMNET") {
    sc <- bt2_scale(Xtr, Xtg)
    cv <- glmnet::cv.glmnet(sc$train, tr[[resid_col]], family = "gaussian", alpha = 0.25,
                            foldid = as.integer(factor(tr$season)))
    mu <- drop(stats::predict(cv, newx = sc$target, s = "lambda.1se"))
    sig <- stats::sd(tr[[resid_col]])
    return(stats::pnorm(mu / sig))
  }
  if (model == "LOGIT_GLMNET") {
    sc <- bt2_scale(Xtr, Xtg)
    cv <- glmnet::cv.glmnet(sc$train, tr[[target]], family = "binomial", alpha = 0.25,
                            foldid = as.integer(factor(tr$season)))
    return(drop(stats::predict(cv, newx = sc$target, s = "lambda.1se", type = "response")))
  }
  if (model == "XGB") {
    lm_tr <- bt_logit(bt_clip(tr[[pm_col]])); lm_tg <- bt_logit(bt_clip(tg[[pm_col]]))
    n <- nrow(Xtr); iv <- seq.int(n - BT2_INNER_VALID + 1L, n); it <- seq_len(n - BT2_INNER_VALID)
    params <- do.call(xgboost::xgb.params, BT2_XGB_PARAMS)
    fit <- xgboost::xgb.train(params, xgboost::xgb.DMatrix(Xtr[it, , drop = FALSE], label = tr[[target]][it], base_margin = lm_tr[it], nthread = 1),
                              nrounds = 1000, evals = list(val = xgboost::xgb.DMatrix(Xtr[iv, , drop = FALSE], label = tr[[target]][iv],
                                                                                        base_margin = lm_tr[iv], nthread = 1)),
                              early_stopping_rounds = 50, verbose = 0)
    best <- as.integer(xgboost::xgb.attr(fit, "best_iteration")) + 1L
    set.seed(BT2_SEED)
    full <- xgboost::xgb.train(params, xgboost::xgb.DMatrix(Xtr, label = tr[[target]], base_margin = lm_tr, nthread = 1),
                               nrounds = best, verbose = 0)
    return(stats::predict(full, xgboost::xgb.DMatrix(Xtg, base_margin = lm_tg, nthread = 1)))
  }
  if (model == "TZ_ONLY") {
    X <- cbind(int = 1, tz = tr$abs_tz_away)
    b <- bt_ridge_logistic(X, tr[[target]], 0)
    return(drop(bt_expit(cbind(1, tg$abs_tz_away) %*% b)))
  }
  stop("unknown handicap model ", model)
}

bt2_hc_market <- function(d, weeks, target, resid_col, pm_col, models, feats) {
  lab <- d[!is.na(get(target)) & is.finite(get(pm_col))]
  setorder(lab, kickoff, game_id)
  pw <- weeks[season >= BT2_BLEND_FIRST_PRED_SEASON]
  out <- list()
  for (i in seq_len(nrow(pw))) {
    tr <- lab[kickoff < pw$cutoff[i] & season >= BT2_FIRST_PRED_SEASON]
    tg <- d[wk == pw$wk[i] & is.finite(get(pm_col))]
    if (!nrow(tg) || nrow(tr) < BT2_BLEND_MIN_TRAIN) next
    row <- data.table(game_id = tg$game_id)
    for (m in models) set(row, j = paste0("p_", m), value = bt2_hc_fit_predict(m, tr, tg, feats, target, resid_col, pm_col))
    out[[length(out) + 1L]] <- row
  }
  rbindlist(out)
}

bt2_hc_betting <- function(ev, col, pm_col, target, home_odds, away_odds) {
  edge <- ev[[col]] - ev[[pm_col]]
  side <- ifelse(edge >= BT2_HC_EDGE, 1L, ifelse(edge <= -BT2_HC_EDGE, 0L, NA_integer_))
  x <- ev[!is.na(side)]; s <- side[!is.na(side)]
  if (!nrow(x)) return(data.table(picks = 0L))
  dec <- ifelse(s == 1L, bt_amer_to_dec(x[[home_odds]]), bt_amer_to_dec(x[[away_odds]]))
  won <- x[[target]] == s
  units <- ifelse(won, dec - 1, -1)
  be <- mean(1 / dec)
  ci <- bt2_wilson(sum(won), length(won))
  data.table(picks = nrow(x), hits = sum(won), hit_rate = mean(won), hit_lo = ci[1], hit_hi = ci[2],
             breakeven = be, roi = mean(units), p_binom_vs_breakeven = stats::binom.test(sum(won), length(won), be,
                                                                                            alternative = "greater")$p.value)
}

bt2_run_handicap <- function(d, weeks, out_dir) {
  feats <- bt2_model_features()
  specs <- list(
    ats = list(target = "cover", resid = "ats_resid", pm = "p_cover_mkt", ho = "home_spread_odds", ao = "away_spread_odds",
               models = c("RESID_GLMNET", "LOGIT_GLMNET", "XGB", "TZ_ONLY")),
    totals = list(target = "over", resid = "tot_resid", pm = "p_over_mkt", ho = "over_odds", ao = "under_odds",
                  models = c("RESID_GLMNET", "LOGIT_GLMNET", "XGB"))
  )
  res <- list(); bets <- list(); tracks <- list()
  for (mk in names(specs)) {
    s <- specs[[mk]]
    pred <- bt2_hc_market(d, weeks, s$target, s$resid, s$pm, s$models, feats)
    ev <- merge(pred, d[, c("game_id", "season", "week", "wk", "kickoff", s$target, s$pm, s$ho, s$ao), with = FALSE], by = "game_id")
    ev <- ev[season %in% BT2_TUNE_SEASONS & !is.na(get(s$target))]
    setnames(ev, s$target, "y")
    cols <- paste0("p_", s$models)
    sc <- bt_score_window(copy(ev), setNames(cols, s$models), c(MARKET = s$pm), seed = BT2_SEED)
    res[[mk]] <- rbindlist(lapply(c(s$pm, cols), function(cc) {
      z <- sc[[cc]]
      data.table(market = mk, candidate = if (cc == s$pm) "MARKET (devigged close)" else sub("^p_", "", cc), n = z$n,
                 brier = z$brier, logloss = z$logloss,
                 skill = if (cc == s$pm) 0 else z$skill, skill_lo = if (cc == s$pm) 0 else z$skill_ci[1],
                 skill_hi = if (cc == s$pm) 0 else z$skill_ci[2], dm_p_bh = if (cc == s$pm) NA_real_ else z$dm_p_better_bh)
    }))
    setnames(ev, "y", s$target)
    bets[[mk]] <- rbindlist(lapply(s$models, function(m) cbind(market = mk, candidate = m,
                                                                bt2_hc_betting(ev, paste0("p_", m), s$pm, s$target, s$ho, s$ao))))
    lg <- melt(ev[, c("game_id", "season", "week", s$target, s$pm, cols), with = FALSE],
               id.vars = c("game_id", "season", "week", s$target, s$pm), variable.name = "candidate", value.name = "p_model")
    setnames(lg, c(s$target, s$pm), c("outcome", "p_market"))
    lg[, `:=`(market = mk, candidate = sub("^p_", "", candidate))]
    tracks[[mk]] <- lg[, .(game_id, season, week, market, candidate, p_model = round(p_model, 8), p_market = round(p_market, 8),
                           outcome, brier = round((p_model - outcome)^2, 8), brier_market = round((p_market - outcome)^2, 8))]
  }
  scores <- rbindlist(res); betting <- rbindlist(bets, fill = TRUE)
  rnd <- function(x) x[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)]
  bt2_write_csv(rnd(scores), file.path(out_dir, "handicap", "scores_tune.csv"))
  bt2_write_csv(rnd(betting), file.path(out_dir, "handicap", "betting_tune.csv"))
  bt2_write_csv(rbindlist(tracks), file.path(out_dir, "tracking", "handicap_tune.csv"))
  list(n = lapply(tracks, function(x) uniqueN(x$game_id)), edge_threshold = BT2_HC_EDGE)
}
