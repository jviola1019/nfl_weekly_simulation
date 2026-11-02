# =============================================================================
# VVF stage S2, structure (design 2026-10-20 §4).
#   Collinearity: VIF <= 5 among features entered together (car::vif). VIF
#   depends only on the design, so it is computed from lm(target ~ features).
#   When features exceed it, the one declared first stays and the later one is
#   dropped and logged; aliased and constant features are logged first.
#   Season stability: the sign of the effect in each period, and a feature x
#   period test: glm(y ~ period + x) against glm(y ~ period * x) with the anchor
#   offset (LR chi2, equal to anova()), or the F test for a linear family.
#   Windows of two seasons or fewer use season halves (weeks <= 9 against
#   later), labelled weak.
# =============================================================================

VVF_VIF_MAX <- 5
VVF_HALF_WEEK <- 9L

vvf_s2_vif <- function(dat, features, response) {
  const <- features[!vapply(features, function(f) length(unique(dat[[f]][is.finite(dat[[f]])])) > 1L, logical(1))]
  keep <- setdiff(features, const)
  log <- list(data.table(feature = const, reason = rep("constant", length(const))))
  x <- dat[stats::complete.cases(dat[, ..keep])]
  x[, r_ := get(response)]
  repeat {
    cf <- stats::coef(stats::lm(stats::reformulate(keep, "r_"), data = x))
    al <- intersect(keep, names(cf)[is.na(cf)])   # lm aliases a column linear in earlier ones
    if (!length(al)) break
    log[[length(log) + 1L]] <- data.table(feature = al, reason = "aliased")
    keep <- setdiff(keep, al)
  }
  v <- NULL
  while (length(keep) >= 2L) {
    v <- car::vif(stats::lm(stats::reformulate(keep, "r_"), data = x))
    if (max(v) <= VVF_VIF_MAX) break
    # the first-declared feature over the limit stays (design §4); its most collinear
    # later-declared partner yields, over the limit or not, and it yields itself only when
    # every partner was declared before it (review I1)
    f <- names(v)[v > VVF_VIF_MAX][1]
    later <- keep[-seq_len(match(f, keep))]
    if (length(later)) {
      r2 <- vapply(later, function(g) stats::cor(x[[f]], x[[g]])^2, numeric(1))
      drop <- later[which.max(r2)]
      why <- sprintf("collinear with %s, declared first (VIF %.3f > %g)", f, v[[f]], VVF_VIF_MAX)
    } else {
      drop <- f
      why <- sprintf("VIF %.3f > %g", v[[f]], VVF_VIF_MAX)
    }
    log[[length(log) + 1L]] <- data.table(feature = drop, reason = why)
    keep <- setdiff(keep, drop)
    v <- NULL
  }
  list(kept = keep, vif = v, dropped = rbindlist(log))
}

vvf_s2_fit <- function(x, family, fml) {
  if (family == "outcome") stats::glm(fml, offset = lp_anchor, family = stats::binomial(), data = x)
  else stats::lm(fml, data = x)
}

vvf_s2_stability <- function(dat, family, feature, response) {
  x <- dat[is.finite(get(feature))]
  x[, fx := get(feature)]
  lhs <- if (family == "outcome") "y" else "r_"
  if (family != "outcome") x[, r_ := get(response)]
  if (uniqueN(x$season) >= 3L) {
    x[, period := as.character(season)]
    label <- "season"
  } else {
    x[, period := paste0(season, fifelse(week <= VVF_HALF_WEEK, " wk<=9", " wk>9"))]
    label <- "season halves (weak)"
  }
  slope <- function(rows) {
    if (length(unique(rows$fx)) < 2L) return(NA_real_)
    unname(stats::coef(vvf_s2_fit(rows, family, stats::as.formula(paste(lhs, "~ 1 + fx"))))[["fx"]])
  }
  pooled <- slope(x)
  periods <- sort(unique(x$period))
  est <- vapply(periods, function(p) slope(x[period == p]), numeric(1))
  m0 <- vvf_s2_fit(x, family, stats::as.formula(paste(lhs, "~ factor(period) + fx")))
  m1 <- vvf_s2_fit(x, family, stats::as.formula(paste(lhs, "~ factor(period) * fx")))
  if (family == "outcome") {
    stat <- m0$deviance - m1$deviance
    df <- as.integer(m0$df.residual - m1$df.residual)
    p <- stats::pchisq(stat, df = df, lower.tail = FALSE)
    test <- "LR chi2"
  } else {
    a <- stats::anova(m0, m1)
    stat <- a$F[2]; df <- as.integer(a$Df[2]); p <- a$`Pr(>F)`[2]
    test <- "F"
  }
  data.table(family = family, feature = feature, periods = label, n_periods = length(periods), pooled = pooled,
             by_period = paste(sprintf("%s: %+.3f", periods, est), collapse = "; "),
             sign_consistent = all(sign(est[is.finite(est)]) == sign(pooled)),
             test = test, int_stat = stat, int_df = df, int_p = p)
}

#' Run S2 for `features` at `decision` on the anchored table `d`
vvf_s2_structure <- function(d, features, decision, families = VVF_FAMILIES_CLOSE, registry = vvf_registry()) {
  anchor <- attr(d, "vvf_anchor")
  if (is.null(anchor)) stop("vvf_s2_structure: the table has no anchor; call vvf_anchor_features() first", call. = FALSE)
  vvf_assert_anchor(anchor, decision)
  vvf_guard_table(d, "the S2 table")
  vvf_assert_known_at(features, decision, registry)
  vif <- list(); stab <- list()
  for (fam in names(families)) {
    resp <- families[[fam]]
    dat <- if (fam == "outcome") d[!is.na(y) & is.finite(lp_anchor)] else d[is.finite(get(resp))]
    v <- vvf_s2_vif(dat, features, resp)
    vif[[fam]] <- data.table(family = fam, kept = paste(v$kept, collapse = " "),
                             dropped = paste(v$dropped$feature, collapse = " "),
                             reasons = paste(sprintf("%s: %s", v$dropped$feature, v$dropped$reason), collapse = "; "),
                             max_vif = if (is.null(v$vif)) NA_real_ else max(v$vif))
    for (f in features) {
      if (length(unique(dat[[f]][is.finite(dat[[f]])])) < 2L) next
      stab[[length(stab) + 1L]] <- vvf_s2_stability(dat, fam, f, resp)
    }
  }
  st <- rbindlist(stab)
  st[, `:=`(anchor = anchor, decision = decision)]
  list(vif = rbindlist(vif), stability = st)
}
