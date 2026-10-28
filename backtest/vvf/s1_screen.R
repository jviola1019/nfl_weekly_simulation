# =============================================================================
# VVF stage S1, the screen (the "ANOVA" question; design 2026-10-20 §4): does
# feature x predict beyond the anchor, in each family?
#   outcome   glm(y ~ 1 + x, offset = lp_anchor, binomial) against
#             glm(y ~ 1, offset = lp_anchor): a likelihood-ratio chi2(1), equal
#             to anova(m0, m1, test = "Chisq");
#   linear    lm(r ~ 1 + x) against lm(r ~ 1): the F test, where r is the
#             movement target delta (family "movement") or a residual against
#             the anchor's spread or total line ("spread", "total").
# Robust p: week-clustered (sandwich::vcovCL, HC0) with 30 or more week
# clusters. With fewer, a wild cluster bootstrap with the null imposed
# (Rademacher weights, B = 9,999, a fixed seed): the restricted bootstrap-t for
# the linear families, and the restricted score bootstrap (Kline and Santos,
# 2012) for the outcome family, whose 0/1 outcome cannot be redrawn additively.
# p = max(p_model, p_robust); BH within each family (one anchor per call); the
# effect per SD with its week-clustered CI; the MDE per SD at the observed n
# (the formula of reports/2026-10-20/preclose-design/mde.R); and a verdict.
#
# Ports bt2_robust_row(), bt2_screen_one() and bt2_screen_joint() from PR #205
# (backtest/v2/screen.R at 759dd1c) with attribution. Changes: the anchor and
# the decision are parameters and S0 runs first; the wild bootstrap below 30
# clusters; the MDE formula; a constant feature is reported "not testable"
# instead of dropped; and the joint test's degrees of freedom count estimable
# coefficients only (v2 counted aliased ones too, so its moneyline joint test
# used df 30 for 29 estimable features).
# =============================================================================

VVF_ALPHA <- 0.05
VVF_POWER <- 0.80
VVF_Q_SIGNAL <- 0.05
VVF_MIN_CLUSTERS <- 30L
VVF_WILD_B <- 9999L
VVF_WILD_SEED <- 20261020L
VVF_WILD_CHUNK <- 1000L
VVF_FAMILIES_CLOSE <- c(outcome = "y", spread = "ats_resid", total = "tot_resid")

#' G x B matrix of Rademacher weights for a seed; the caller's RNG is restored
vvf_rademacher <- function(G, B, seed) {
  vvf_seeded(seed, function() matrix(sample(c(-1, 1), G * B, replace = TRUE), nrow = G))
}

#' Wild cluster restricted bootstrap-t p-value for H0: b = 0 in lm(r ~ 1 + x);
#' p = (1 + #{|t*| >= |t|}) / (B + 1), so it is never 0
vvf_wild_p_linear <- function(r, x, cluster, B = VVF_WILD_B, seed = VVF_WILD_SEED) {
  cl <- as.integer(factor(cluster))
  G <- max(cl)
  n <- length(r)
  xc <- x - mean(x)
  sxx <- sum(xc^2)
  b <- sum(xc * r) / sxx
  e <- r - mean(r) - b * xc
  t0 <- b / (sqrt(sum(rowsum(xc * e, cl)^2)) / sxx)
  u <- r - mean(r)                       # residuals with the null imposed
  V <- vvf_rademacher(G, B, seed)
  hits <- 0
  for (s in seq(1L, B, by = VVF_WILD_CHUNK)) {
    j <- s:min(B, s + VVF_WILD_CHUNK - 1L)
    U <- u * V[cl, j, drop = FALSE]
    bs <- colSums(xc * U) / sxx
    E <- U - matrix(colMeans(U), n, length(j), byrow = TRUE) - outer(xc, bs)
    ses <- sqrt(colSums(rowsum(xc * E, cl)^2)) / sxx
    hits <- hits + sum(abs(bs / ses) >= abs(t0))
  }
  (hits + 1) / (B + 1)
}

#' Wild cluster restricted score bootstrap p-value (Kline and Santos 2012) for
#' H0: b = 0 in glm(y ~ 1 + x, offset = lp, binomial)
vvf_wild_p_score <- function(y, lp, x, cluster, B = VVF_WILD_B, seed = VVF_WILD_SEED) {
  cl <- as.integer(factor(cluster))
  m0 <- stats::glm(y ~ 1, offset = lp, family = stats::binomial())
  p0 <- stats::fitted(m0)
  w <- p0 * (1 - p0)
  xt <- x - sum(w * x) / sum(w)           # x net of the intercept, in the null model's weights
  S <- as.numeric(rowsum(xt * (y - p0), cl))
  den <- sqrt(sum(S^2))
  t0 <- sum(S) / den
  ts <- colSums(S * vvf_rademacher(length(S), B, seed)) / den
  (sum(abs(ts) >= abs(t0)) + 1) / (B + 1)
}

#' Minimum detectable effect per SD of x (two-sided alpha / k, power): outcome
#' families in log-odds, (z + z) / sqrt(n * mean(p (1 - p))); linear families in
#' the target's units, (z + z) * sigma / sqrt(n)
vvf_mde_per_sd <- function(n, family, v = NULL, sigma = NULL, alpha = VVF_ALPHA, power = VVF_POWER, k = 1L) {
  z <- stats::qnorm(1 - alpha / (2 * k)) + stats::qnorm(power)
  if (family == "outcome") z / sqrt(n * v) else z * sigma / sqrt(n)
}

vvf_s1_one <- function(dat, family, feature, response, B = VVF_WILD_B, seed = VVF_WILD_SEED) {
  x <- dat[is.finite(get(feature))]
  x[, fx := get(feature)]
  base <- data.table(family = family, feature = feature, n = nrow(x), n_clusters = uniqueN(x$wk))
  if (length(unique(x$fx)) < 2L) return(base[, robust_method := "not testable (constant)"])
  sdx <- stats::sd(x$fx)
  if (family == "outcome") {
    m0 <- stats::glm(y ~ 1, offset = lp_anchor, family = stats::binomial(), data = x)
    m1 <- stats::glm(y ~ 1 + fx, offset = lp_anchor, family = stats::binomial(), data = x)
    stat <- m0$deviance - m1$deviance
    p_test <- stats::pchisq(stat, df = 1, lower.tail = FALSE)
    test <- "LR chi2"
    mde <- vvf_mde_per_sd(nrow(x), family, v = mean(stats::plogis(x$lp_anchor) * (1 - stats::plogis(x$lp_anchor))))
  } else {
    x[, r := get(response)]
    m0 <- stats::lm(r ~ 1, data = x)
    m1 <- stats::lm(r ~ 1 + fx, data = x)
    a <- stats::anova(m0, m1)
    stat <- a$F[2]
    p_test <- a$`Pr(>F)`[2]
    test <- "F"
    mde <- vvf_mde_per_sd(nrow(x), family, sigma = stats::sd(x$r))
  }
  V <- sandwich::vcovCL(m1, cluster = x$wk, type = "HC0")
  est <- stats::coef(m1)[["fx"]]
  se <- sqrt(V["fx", "fx"])
  if (base$n_clusters >= VVF_MIN_CLUSTERS) {
    p_robust <- 2 * stats::pnorm(-abs(est / se))
    method <- "vcovCL HC0"
  } else if (family == "outcome") {
    p_robust <- vvf_wild_p_score(x$y, x$lp_anchor, x$fx, x$wk, B, seed)
    method <- sprintf("wild score bootstrap, Rademacher, B = %d", B)
  } else {
    p_robust <- vvf_wild_p_linear(x$r, x$fx, x$wk, B, seed)
    method <- sprintf("wild bootstrap-t, Rademacher, B = %d", B)
  }
  # below the cluster floor the p-value is the bootstrap's; a sandwich SE and CI beside it could
  # contradict it, so none is reported (review I3)
  if (base$n_clusters < VVF_MIN_CLUSTERS) se <- NA_real_
  base[, `:=`(mean_x = mean(x$fx), sd_x = sdx, test = test, stat = stat, p_test = p_test,
              estimate = est, se_robust = se, ci_lo = est - 1.96 * se, ci_hi = est + 1.96 * se,
              p_robust = p_robust, robust_method = method, p = max(p_test, p_robust),
              effect_per_sd = est * sdx, effect_ci_lo = (est - 1.96 * se) * sdx, effect_ci_hi = (est + 1.96 * se) * sdx,
              mde_per_sd = mde)]
  base[]
}

#' Restricted wild cluster score bootstrap p-value for H0: every slope is 0
#' (Kline and Santos, 2012), with diagonal studentization, so it is defined
#' for any number of features. X holds the estimable columns; resid and w are
#' y - p0 and p0 (1 - p0) at the null fit (outcome), or r - mean(r) and 1
#' (linear). With Rademacher weights the bootstrap variance equals the
#' observed one, so the statistic needs no refit. Its size holds where the
#' cluster-robust Wald's does not (reports/2026-10-28/a3-research, section 2).
vvf_wild_p_joint_score <- function(X, resid, w, cluster, B = VVF_WILD_B, seed = VVF_WILD_SEED) {
  Xc <- sweep(X, 2, colSums(X * w) / sum(w))     # the efficient score: the intercept projected out
  Sg <- rowsum(Xc * resid, as.integer(factor(cluster)))
  S <- colSums(Sg)
  dg <- colSums(Sg^2)
  ok <- dg > 0
  t0 <- sum(S[ok]^2 / dg[ok])
  hits <- 0
  W <- vvf_rademacher(nrow(Sg), B, seed)          # G x B
  for (s in seq(1L, B, by = VVF_WILD_CHUNK)) {
    j <- s:min(B, s + VVF_WILD_CHUNK - 1L)
    Ws <- crossprod(W[, j, drop = FALSE], Sg[, ok, drop = FALSE])
    hits <- hits + sum(rowSums(sweep(Ws^2, 2, dg[ok], "/")) >= t0)
  }
  (hits + 1) / (B + 1)
}

#' Joint test of a feature set: the model-based test (p_test), the wild score
#' bootstrap (p_joint_wild) and p_joint = max of the two, the p of record. The
#' week-clustered robust Wald statistic is kept as v2's known answer, NA when
#' its covariance is singular; its chi-square(k) p-value is not reported: it
#' rejects 0.30-0.69 of the time at a nominal 5% under a true null with k 29-34
#' over 107 clusters (reports/2026-10-28/a3-research, section 2).
#' Aliased (perfectly collinear) features are reported and not counted.
vvf_s1_joint <- function(dat, family, features, response, B = VVF_WILD_B, seed = VVF_WILD_SEED) {
  keep <- features[vapply(features, function(f) length(unique(dat[[f]][is.finite(dat[[f]])])) > 1L, logical(1))]
  x <- dat[stats::complete.cases(dat[, ..keep])]
  lhs <- if (family == "outcome") "y" else "r"
  fml <- stats::as.formula(paste(lhs, "~ 1 +", paste(keep, collapse = " + ")))
  if (family == "outcome") {
    m0 <- stats::glm(y ~ 1, offset = lp_anchor, family = stats::binomial(), data = x)
    m1 <- stats::glm(fml, offset = lp_anchor, family = stats::binomial(), data = x)
    stat <- m0$deviance - m1$deviance
    df <- as.integer(m0$df.residual - m1$df.residual)
    p <- stats::pchisq(stat, df = df, lower.tail = FALSE)
    test <- "LR chi2"
  } else {
    x[, r := get(response)]
    m0 <- stats::lm(r ~ 1, data = x)
    m1 <- stats::lm(fml, data = x)
    a <- stats::anova(m0, m1)
    stat <- a$F[2]; df <- as.integer(a$Df[2]); p <- a$`Pr(>F)`[2]
    test <- "F"
  }
  cf <- stats::coef(m1)
  est <- intersect(keep, names(cf)[!is.na(cf)])
  aliased <- setdiff(keep, est)
  b <- cf[est]
  V <- sandwich::vcovCL(m1, cluster = x$wk, type = "HC0")[est, est, drop = FALSE]
  # with an intercept the slopes' cluster-robust covariance has rank at most G - 1
  w <- if (qr(V)$rank == length(est)) drop(t(b) %*% solve(V, b)) else NA_real_
  if (family == "outcome") {
    p0 <- stats::fitted(m0)
    resid <- x$y - p0
    wt <- p0 * (1 - p0)
  } else {
    resid <- x$r - mean(x$r)
    wt <- rep(1, nrow(x))
  }
  p_wild <- vvf_wild_p_joint_score(as.matrix(x[, ..est]), resid, wt, x$wk, B, seed)
  data.table(family = family, n = nrow(x), n_clusters = uniqueN(x$wk), k_entered = length(keep), k = length(est),
             test = test, stat = stat, df = df, p_test = p,
             wald_robust = w,
             p_joint_wild = p_wild, joint_wild_method = sprintf("wild score bootstrap, diagonal, Rademacher, B = %d", B),
             p_joint = max(p, p_wild),
             features = paste(est, collapse = " "), aliased = paste(aliased, collapse = " "))
}

#' Run S1 for `features` at `decision` on the anchored table `d` (from
#' vvf_anchor_features). `families` maps family name -> target column.
vvf_s1_screen <- function(d, features, decision, families = VVF_FAMILIES_CLOSE, joint_sets = list(),
                          registry = vvf_registry(), B = VVF_WILD_B, seed = VVF_WILD_SEED) {
  anchor <- attr(d, "vvf_anchor")
  if (is.null(anchor)) stop("vvf_s1_screen: the table has no anchor; call vvf_anchor_features() first", call. = FALSE)
  vvf_assert_anchor(anchor, decision)
  vvf_guard_table(d, "the S1 table")
  vvf_assert_known_at(unique(c(features, unlist(joint_sets))), decision, registry)
  rows <- list(); joints <- list(); n <- list()
  for (fam in names(families)) {
    resp <- families[[fam]]
    dat <- if (fam == "outcome") d[!is.na(y) & is.finite(lp_anchor)] else d[is.finite(get(resp))]
    n[[fam]] <- nrow(dat)
    for (f in features) rows[[length(rows) + 1L]] <- vvf_s1_one(dat, fam, f, resp, B, seed)
    for (sn in names(joint_sets)) joints[[length(joints) + 1L]] <- vvf_s1_joint(dat, fam, joint_sets[[sn]], resp, B, seed)[, set := sn]
  }
  res <- rbindlist(rows, fill = TRUE)
  res[, q_bh := NA_real_]
  res[, mde_per_sd_family := NA_real_]
  for (fam in names(families)) {
    i <- res[, which(family == fam & is.finite(p))]
    res[i, q_bh := stats::p.adjust(p, method = "BH")]
    k <- length(i)
    res[i, mde_per_sd_family := mde_per_sd * (stats::qnorm(1 - VVF_ALPHA / (2 * k)) + stats::qnorm(VVF_POWER)) /
          (stats::qnorm(1 - VVF_ALPHA / 2) + stats::qnorm(VVF_POWER))]
  }
  res[, verdict := fifelse(!is.finite(p), "not testable (constant)",
                           fifelse(q_bh < VVF_Q_SIGNAL, "signal (q < 0.05)", sprintf("no evidence (MDE = %.3f per SD)", mde_per_sd)))]
  res[, `:=`(anchor = anchor, decision = decision)]
  list(features = res, joint = rbindlist(joints), n = n, anchor = anchor, decision = decision)
}
