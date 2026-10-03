# =============================================================================
# Blend research v3: other model families, each anchored on the no-vig close
# and fit walk-forward by week on the v2 features (games before the week only).
#
#   G2       mgcv::gam, offset logit(close), REML, shrinkage smooths (bs = "ts") of
#            the Elo and EPA gaps (d_c1, d_c2) and of the v2 moneyline screen's
#            best features (raw p < 0.10 on Tune: abs_tz_away, roof_closed,
#            west_early, inj_diff_lb). The two binary ones enter as ridge-penalised
#            linear terms (bs = "re"). The screen ran on Tune, so G2's Tune score
#            is optimistic; G2_GAPS is the selection-free check.
#   G2_GAPS  the same GAM with the Elo and EPA gap smooths only
#   T1       lme4::glmer, offset logit(close), random intercepts for the home and
#            the away franchise (is a team systematically mispriced?), refit
#            weekly on a rolling window: the current season to date plus the two
#            previous seasons
#   N1       nnet, one hidden layer (size <= 3) with skip-layer connections; the
#            skip weight from logit(close) to the output is fixed at 1 (an
#            offset), the rest is shrunk by weight decay. Size and decay are
#            chosen at each season's first week by season-grouped CV on the
#            training games (decay 1 to 10,000), then the net is refit weekly.
#   N1_NARROW  the development version: decay grid 1 to 100 only. Its CV chose the
#            grid edge (decay 100) in every season, so the grid was widened for
#            N1 after that run's Tune score had been seen; N1_NARROW stays in the
#            table and in the BH family so that choice is visible.
# Training rows: every labelled game from 2010 that kicked off before the week
# (T1: its rolling window). Targets: the week's games with a market price.
# =============================================================================

BT3_G2_FORMULA <- y ~ s(d_c1, bs = "ts") + s(d_c2, bs = "ts") + s(abs_tz_away, bs = "ts", k = 4) +
  s(inj_diff_lb, bs = "ts") + s(roof_closed, bs = "re") + s(west_early, bs = "re") + offset(lp_c0)
BT3_G2_GAPS_FORMULA <- y ~ s(d_c1, bs = "ts") + s(d_c2, bs = "ts") + offset(lp_c0)
BT3_G2_VARS <- c("d_c1", "d_c2", "abs_tz_away", "inj_diff_lb", "roof_closed", "west_early")
BT3_N1_SIZES <- 1:3
BT3_N1_DECAYS <- 10^(0:4)
BT3_N1_DECAYS_NARROW <- c(1, 10, 100)
BT3_N1_MAXIT <- 500L
BT3_FAMILIES <- c("G2", "G2_GAPS", "T1", "N1", "N1_NARROW")
BT3_N1_GRIDS <- list(N1 = BT3_N1_DECAYS, N1_NARROW = BT3_N1_DECAYS_NARROW)

#' Missing feature values -> 0 (as v2's bt2_fill), on the named columns only
bt3_fill_cols <- function(x, cols) {
  x <- copy(x)
  for (cc in cols) set(x, which(!is.finite(x[[cc]])), cc, 0)
  x
}

bt3_g2_fit_predict <- function(tr, tg, formula = BT3_G2_FORMULA) {
  tr <- bt3_fill_cols(tr, BT3_G2_VARS); tg <- bt3_fill_cols(tg, BT3_G2_VARS)
  g <- mgcv::gam(formula, family = stats::binomial(), data = tr, method = "REML")
  p <- as.numeric(stats::predict(g, newdata = tg, type = "response"))
  edf <- vapply(seq_along(g$smooth), function(j) sum(g$edf[g$smooth[[j]]$first.para:g$smooth[[j]]$last.para]), numeric(1))
  attr(p, "diag") <- data.table(term = c(vapply(g$smooth, function(s) s$label, character(1)), "intercept"),
                                value = c(edf, unname(stats::coef(g)[1])))
  p
}

bt3_t1_fit_predict <- function(tr, tg) {
  nwarn <- 0L
  m <- withCallingHandlers(
    lme4::glmer(y ~ 1 + (1 | home_franchise) + (1 | away_franchise) + offset(lp_c0), data = tr, family = stats::binomial(),
                control = lme4::glmerControl(optimizer = "bobyqa", calc.derivs = FALSE)),
    warning = function(w) { nwarn <<- nwarn + 1L; invokeRestart("muffleWarning") },
    message = function(m) invokeRestart("muffleMessage"))
  p <- as.numeric(stats::predict(m, newdata = tg, type = "response", allow.new.levels = TRUE))
  vc <- as.data.frame(lme4::VarCorr(m))
  attr(p, "diag") <- data.table(term = c("sd_home", "sd_away", "intercept", "singular", "warnings"),
                                value = c(vc$sdcor[vc$grp == "home_franchise"], vc$sdcor[vc$grp == "away_franchise"],
                                          unname(lme4::fixef(m)[1]), as.numeric(lme4::isSingular(m)), nwarn))
  p
}

#' N1 design: logit(close) unscaled in column 1, then the v2 features standardised on the training rows
bt3_n1_inputs <- function(tr, tg, feats = bt2_model_features()) {
  sc <- bt2_scale(bt2_fill(as.matrix(tr[, ..feats])), bt2_fill(as.matrix(tg[, ..feats])))
  list(train = cbind(lp = tr$lp_c0, sc$train), target = cbind(lp = tg$lp_c0, sc$target))
}

#' Anchored nnet: the skip weight input 1 (logit close) -> output is fixed at 1.
#' nnet weight order: per hidden unit (bias, inputs), then output (bias, hidden, skip inputs).
bt3_n1_fit <- function(X, y, size, decay) {
  p <- ncol(X)
  nw <- size * (p + 1L) + 1L + size + p
  k <- size * (p + 1L) + 1L + size + 1L
  set.seed(BT2_SEED)
  w0 <- stats::runif(nw, -0.5, 0.5)
  w0[k] <- 1
  mask <- rep(TRUE, nw); mask[k] <- FALSE
  fit <- nnet::nnet(X, y, size = size, skip = TRUE, entropy = TRUE, decay = decay, Wts = w0, mask = mask,
                    maxit = BT3_N1_MAXIT, trace = FALSE)
  if (abs(fit$wts[k] - 1) > 1e-12) stop("bt3_n1_fit: the anchored skip weight moved")
  fit
}

#' Season-grouped CV over size x decay on the training games; returns the CV table
bt3_n1_tune <- function(tr, feats = bt2_model_features(), sizes = BT3_N1_SIZES, decays = BT3_N1_DECAYS) {
  folds <- split(seq_len(nrow(tr)), tr$season)
  grid <- CJ(size = sizes, decay = decays)
  grid[, deviance := NA_real_]
  for (g in seq_len(nrow(grid))) {
    ll <- 0
    for (f in folds) {
      inp <- bt3_n1_inputs(tr[-f], tr[f], feats)
      fit <- bt3_n1_fit(inp$train, tr$y[-f], grid$size[g], grid$decay[g])
      ll <- ll + sum(bt_logloss_vec(drop(stats::predict(fit, inp$target, type = "raw")), tr$y[f]))
    }
    set(grid, g, "deviance", 2 * ll / nrow(tr))
  }
  grid[, chosen := seq_len(.N) == which.min(deviance)]
  grid[]
}

bt3_n1_fit_predict <- function(tr, tg, size, decay, feats = bt2_model_features()) {
  inp <- bt3_n1_inputs(tr, tg, feats)
  fit <- bt3_n1_fit(inp$train, tr$y, size, decay)
  p <- drop(stats::predict(fit, inp$target, type = "raw"))
  attr(p, "diag") <- data.table(term = c("size", "decay", "converged"), value = c(size, decay, as.numeric(fit$convergence == 0)))
  p
}

#' Training rows of a family for a target week
bt3_family_train <- function(lab, family, cut_time, target_season) {
  first_season <- if (family == "T1") target_season - BT3_T1_SEASONS + 1L else BT2_FIRST_PRED_SEASON
  lab[kickoff < cut_time & season >= first_season]
}

#' N1 hyperparameters for each season in `weeks`, chosen at the season's first week
#' on the games that kicked off before it
bt3_n1_params <- function(weeks, d, sizes = BT3_N1_SIZES, decays = BT3_N1_DECAYS) {
  bt3_guard(d$season, "N1 tuning rows")
  lab <- d[!is.na(y) & is.finite(lp_c0)]
  setorder(lab, kickoff, game_id)
  first <- weeks[, .SD[which.min(cutoff)], by = season]
  rbindlist(lapply(seq_len(nrow(first)), function(i) {
    t0 <- Sys.time()
    g <- bt3_n1_tune(lab[kickoff < first$cutoff[i] & season >= BT2_FIRST_PRED_SEASON], sizes = sizes, decays = decays)
    g[, `:=`(season = first$season[i], seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))]
  }))
}

#' Walk G2 / G2_GAPS / T1 / N1 / N1_NARROW over `weeks` on feature table `d`.
#' N1 and N1_NARROW need `n1_params` (bt3_n1_params output) covering the weeks' seasons.
bt3_walk_family <- function(weeks, family, d, n1_params = NULL) {
  bt3_guard(d$season, "family rows")
  lab <- d[!is.na(y) & is.finite(lp_c0)]
  setorder(lab, kickoff, game_id)
  min_train <- if (family == "T1") BT3_T1_MIN_TRAIN else BT3_FAMILY_MIN_TRAIN
  out <- list(); diag <- list(); secs <- 0
  for (i in seq_len(nrow(weeks))) {
    s <- weeks$season[i]
    tr <- bt3_family_train(lab, family, weeks$cutoff[i], s)
    tg <- d[wk == weeks$wk[i] & is.finite(lp_c0)]
    if (!nrow(tg) || nrow(tr) < min_train) next
    t0 <- Sys.time()
    p <- if (family %in% names(BT3_N1_GRIDS)) {
      hp <- n1_params[season == s & chosen == TRUE]
      if (nrow(hp) != 1L) stop(family, ": no tuned size/decay for season ", s)
      bt3_n1_fit_predict(tr, tg, hp$size, hp$decay)
    } else switch(family,
                  G2 = bt3_g2_fit_predict(tr, tg, BT3_G2_FORMULA),
                  G2_GAPS = bt3_g2_fit_predict(tr, tg, BT3_G2_GAPS_FORMULA),
                  T1 = bt3_t1_fit_predict(tr, tg),
                  stop("unknown family ", family))
    secs <- secs + as.numeric(difftime(Sys.time(), t0, units = "secs"))
    out[[length(out) + 1L]] <- data.table(game_id = tg$game_id, p = as.numeric(p))
    diag[[length(diag) + 1L]] <- cbind(data.table(wk = weeks$wk[i], n_train = nrow(tr)), attr(p, "diag"))
  }
  list(pred = rbindlist(out), diag = rbindlist(diag), seconds = setNames(secs, family))
}
