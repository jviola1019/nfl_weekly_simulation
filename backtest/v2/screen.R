# =============================================================================
# Validation sprint v2: Tune-window significance screen.
#
# Question for every feature: does it predict the outcome BEYOND the no-vig close?
#   ML  (home win, ties dropped):  glm(y ~ 1 + x, offset = logit(p_close), binomial)
#                                  vs glm(y ~ 1, offset = logit(p_close)); likelihood-ratio test
#   ATS (home margin - spread_line): lm(resid ~ x) vs lm(resid ~ 1); ANOVA F test
#   TOT (total - total_line):        lm(resid ~ x) vs lm(resid ~ 1); ANOVA F test
# Each coefficient also gets a week-clustered robust test (sandwich::vcovCL), and
# Benjamini-Hochberg q-values are computed within each family over the
# point-in-time features (post-hoc weather diagnostics are reported separately).
# A joint test of all point-in-time situational features per family answers
# "does the set as a whole add anything beyond the market?".
# Data: Tune seasons 2018-2022 only. Nothing here reads Confirm or Holdout seasons.
# =============================================================================

bt2_robust_row <- function(fit, term, cluster) {
  V <- sandwich::vcovCL(fit, cluster = cluster, type = "HC0")
  est <- stats::coef(fit)[[term]]
  se <- sqrt(V[term, term])
  z <- est / se
  c(estimate = est, se_robust = se, ci_lo = est - 1.96 * se, ci_hi = est + 1.96 * se,
    p_robust = 2 * stats::pnorm(-abs(z)))
}

bt2_screen_one <- function(dat, family, feature) {
  x <- dat[is.finite(get(feature))]
  if (length(unique(x[[feature]])) < 2L) return(NULL)
  sdx <- stats::sd(x[[feature]])
  x[, fx := get(feature)]
  if (family == "ml") {
    m0 <- stats::glm(y ~ 1, offset = lp_c0, family = stats::binomial(), data = x)
    m1 <- stats::glm(y ~ 1 + fx, offset = lp_c0, family = stats::binomial(), data = x)
    stat <- m0$deviance - m1$deviance
    p_test <- stats::pchisq(stat, df = 1, lower.tail = FALSE)
    test <- "LR chi2"
  } else {
    m0 <- stats::lm(resid ~ 1, data = x)
    m1 <- stats::lm(resid ~ 1 + fx, data = x)
    a <- stats::anova(m0, m1)
    stat <- a$F[2]
    p_test <- a$`Pr(>F)`[2]
    test <- "F"
  }
  r <- bt2_robust_row(m1, "fx", x$wk)
  data.table(family = family, feature = feature, n = nrow(x), mean_x = mean(x$fx), sd_x = sdx,
             test = test, stat = stat, p_test = p_test,
             estimate = r[["estimate"]], se_robust = r[["se_robust"]], ci_lo = r[["ci_lo"]], ci_hi = r[["ci_hi"]],
             p_robust = r[["p_robust"]], effect_per_sd = r[["estimate"]] * sdx)
}

bt2_screen_joint <- function(dat, family, features) {
  keep <- features[vapply(features, function(f) length(unique(dat[[f]][is.finite(dat[[f]])])) > 1L, logical(1))]
  x <- dat[stats::complete.cases(dat[, ..keep])]
  fml <- stats::as.formula(paste(if (family == "ml") "y" else "resid", "~ 1 +", paste(keep, collapse = " + ")))
  if (family == "ml") {
    m0 <- stats::glm(y ~ 1, offset = lp_c0, family = stats::binomial(), data = x)
    m1 <- stats::glm(fml, offset = lp_c0, family = stats::binomial(), data = x)
    stat <- m0$deviance - m1$deviance
    df <- length(stats::coef(m1)) - 1L
    p <- stats::pchisq(stat, df = df, lower.tail = FALSE)
    test <- "LR chi2"
  } else {
    m0 <- stats::lm(resid ~ 1, data = x)
    m1 <- stats::lm(fml, data = x)
    a <- stats::anova(m0, m1)
    stat <- a$F[2]; df <- a$Df[2]; p <- a$`Pr(>F)`[2]
    test <- "F"
  }
  # robust Wald test of all situational coefficients together (week-clustered);
  # aliased (perfectly collinear) terms have NA coefficients and are reported, not tested
  cf <- stats::coef(m1)
  est <- intersect(keep, names(cf)[!is.na(cf)])
  aliased <- setdiff(keep, est)
  b <- cf[est]
  V <- sandwich::vcovCL(m1, cluster = x$wk, type = "HC0")[est, est]
  w <- drop(t(b) %*% solve(V, b))
  data.table(family = family, n = nrow(x), k = length(est), test = test, stat = stat, df = df, p_test = p,
             wald_robust = w, p_wald_robust = stats::pchisq(w, df = length(est), lower.tail = FALSE),
             features = paste(est, collapse = " "), aliased = paste(aliased, collapse = " "))
}

#' Run the screen on Tune seasons. `d` is bt2_build_features() output.
bt2_run_screen <- function(d, tune_seasons = BT2_TUNE_SEASONS, screen = BT2_SCREEN) {
  x <- d[season %in% tune_seasons]
  bt2_guard_seasons(x$season, BT2_MAX_SPRINT_SEASON, "screen rows")
  fams <- list(
    ml = x[!is.na(y) & is.finite(lp_c0)],
    ats = x[is.finite(ats_resid)][, resid := ats_resid],
    tot = x[is.finite(tot_resid)][, resid := tot_resid]
  )
  rows <- list()
  for (fam in names(fams)) {
    for (f in screen$feature) rows[[length(rows) + 1L]] <- bt2_screen_one(fams[[fam]], fam, f)
  }
  res <- merge(rbindlist(rows), screen, by = "feature")
  res[, q_bh := NA_real_]
  for (fam in names(fams)) {
    i <- res[, which(family == fam & !posthoc)]
    res[i, q_bh := stats::p.adjust(pmax(p_test, p_robust), method = "BH")]
  }
  res[, verdict := fcase(posthoc, "post-hoc diagnostic (not point-in-time)",
                         q_bh < 0.05, "signal beyond the close (q < 0.05)",
                         q_bh < 0.20, "weak (q < 0.20)",
                         default = "no evidence")]
  situational <- screen[(!posthoc) & group != "model vs market" & group != "market shape", feature]
  joint <- rbindlist(lapply(names(fams), function(fam) {
    rbind(bt2_screen_joint(fams[[fam]], fam, situational)[, set := "situational (schedule, travel, venue, injuries, QB, officials)"],
          bt2_screen_joint(fams[[fam]], fam, screen[(!posthoc), feature])[, set := "all point-in-time features incl. model-vs-market"])
  }))
  setorder(res, family, q_bh, p_test)
  list(features = res, joint = joint,
       n = lapply(fams, nrow), seasons = sort(unique(x$season)))
}
