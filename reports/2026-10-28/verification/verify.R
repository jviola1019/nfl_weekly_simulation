# =============================================================================
# Independent verification of A3b's numbers (plan Task 15; the owner's request of 2026-10-28): the model
# p-values, Brier and log loss, the research's key results and the blends' scores, recomputed with code paths
# independent of backtest/vvf's statistics: base R (glm, lm, anova, t.test, p.adjust, oneway.test, ks.test,
# binom.test), hand-written cluster-robust sandwiches, lmtest, car and nlme, all locked in renv. The data come
# from the committed inputs through the VVF loaders, which the input checks and the v2 reproduction verify.
#
#   Rscript reports/2026-10-28/verification/verify.R <out_dir> <git ref of #205> <git ref of #209>
#
# The blends' committed files are read with `git show <ref>:<path>`, and each ref's commit is recorded.
# Writes checks.csv (one row per check), pvalue_calibration.csv, blends.csv and research_replication.csv,
# and exits 1 if any check fails. Nothing after 2022 is scored; 2025 is never read.
# =============================================================================
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L) stop("usage: Rscript verify.R <out_dir> <ref #205> <ref #209>", call. = FALSE)
out <- args[1]; ref205 <- args[2]; ref209 <- args[3]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
t0 <- Sys.time()
e <- environment()
for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R", "blends.R", "calibrators.R",
            "metrics.R", "controls.R")) sys.source(file.path("backtest", f), envir = e)
for (f in c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s2_structure.R", "s3_skill.R",
            "s4_controls.R", "s5_curves.R", "s5_scores.R", "s5_anova.R", "reproduce_v2.R", "input_schema.R")) {
  sys.source(file.path("backtest", "vvf", f), envir = e)
}
source(file.path("backtest", "vvf", "run_a3b_close.R"), local = e)
TUNE <- 2018:2022
# VERIFY_FAST=1 is a smoke test of every code path (tiny loops, 3 S4 features); its checks are not evidence
FAST <- identical(Sys.getenv("VERIFY_FAST"), "1")
n_of <- function(full_n, fast_n) if (FAST) fast_n else full_n
S4_FEATURES <- if (FAST) VVF_V2_FEATURES[1:3] else VVF_V2_FEATURES
RUN <- file.path("reports", "2026-10-28", "vvf-a3b-close")
REPRO <- file.path("reports", "2026-10-22", "vvf-v2-repro")

checks <- list()
#' One check: `value` against `reference`, passing when every |value - reference| <= abs_tol + rel_tol |reference|
#' (committed CSVs hold 6 significant digits, so rel_tol 1e-5 covers their rounding)
check <- function(section, name, value, reference, rel_tol = 1e-5, abs_tol = 1e-9, detail = "") {
  value <- as.numeric(value); reference <- as.numeric(reference)
  d <- abs(value - reference)
  ok <- length(d) > 0L && !anyNA(d) && all(d <= abs_tol + rel_tol * abs(reference))
  checks[[length(checks) + 1L]] <<- data.table(section = section, check = name, n = length(d),
                                               max_abs_diff = if (anyNA(d)) NA_real_ else signif(max(d), 4),
                                               tolerance = sprintf("%g + %g x |ref|", abs_tol, rel_tol), passed = ok, detail = detail)
  cat(sprintf("[%s] %-62s %s  n %4d  max|diff| %.3g  %s\n", section, name, if (ok) "PASS" else "FAIL", length(d),
              if (anyNA(d)) NA else max(d), detail))
  invisible(ok)
}
#' One check of a condition that is not a recomputation (a rate in a band, a count)
check_true <- function(section, name, ok, detail) {
  checks[[length(checks) + 1L]] <<- data.table(section = section, check = name, n = 1L, max_abs_diff = NA_real_,
                                               tolerance = "condition", passed = isTRUE(ok), detail = detail)
  cat(sprintf("[%s] %-62s %s  %s\n", section, name, if (isTRUE(ok)) "PASS" else "FAIL", detail))
  invisible(isTRUE(ok))
}
logloss <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
lg <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
#' Cluster-robust covariance by hand: bread (X'WX)^-1, meat sum over clusters of U_g U_g', times G / (G - 1)
#' (sandwich::vcovCL's HC0 with its cluster adjustment), for a logit (u = y - p, w = p(1 - p)) or OLS (u = e, w = 1)
cr_vcov <- function(X, u, w, cluster) {
  bread <- solve(crossprod(X, X * w))
  Ug <- rowsum(X * u, cluster)
  G <- nrow(Ug)
  V <- bread %*% crossprod(Ug) %*% bread * G / (G - 1)
  dimnames(V) <- list(colnames(X), colnames(X))
  V
}
#' The diagonal restricted wild cluster score bootstrap, written as a plain loop over the bootstrap draws
wild_diag_loop <- function(X, resid, w, cluster, W) {
  Xc <- sweep(X, 2, colSums(X * w) / sum(w))
  Sg <- rowsum(Xc * resid, cluster)
  dg <- colSums(Sg^2); ok <- dg > 0
  t0 <- sum(colSums(Sg)[ok]^2 / dg[ok])
  hits <- 0L
  for (b in seq_len(ncol(W))) hits <- hits + (sum(colSums(Sg[, ok, drop = FALSE] * W[, b])^2 / dg[ok]) >= t0)
  (hits + 1) / (ncol(W) + 1)
}
git_csv <- function(ref, path) fread(text = system2("git", c("show", shQuote(sprintf("%s:%s", ref, path))), stdout = TRUE))
git_sha <- function(ref) system2("git", c("rev-parse", "--short", shQuote(ref)), stdout = TRUE)

cat("Loading the close-anchored tables (the input checks run first)\n")
tab <- vvf_a3b_table()
full <- tab$full
v2t <- vvf_v2_table()$d

# ---------------------------------------------------------------------------------------------------------
# A. S1 per-feature p-values (the v2 reproduction, 108 rows)
fam <- c(outcome = "y", spread = "ats_resid", total = "tot_resid")
s1c <- fread(file.path(REPRO, "s1_features.csv"))
rows <- list()
for (fm in names(fam)) {
  base <- if (fm == "outcome") v2t[!is.na(y) & is.finite(lp_anchor)] else v2t[is.finite(get(fam[[fm]]))]
  for (f in VVF_V2_FEATURES) {
    x <- base[is.finite(get(f))]
    if (uniqueN(x[[f]]) < 2L) next
    X <- cbind(`(Intercept)` = 1, fx = x[[f]])
    if (fm == "outcome") {
      m0 <- stats::glm(x$y ~ 1, offset = x$lp_anchor, family = stats::binomial())
      m1 <- stats::glm(x$y ~ 1 + X[, "fx"], offset = x$lp_anchor, family = stats::binomial())
      pt <- stats::anova(m0, m1, test = "LRT")[2, "Pr(>Chi)"]
      p1 <- stats::fitted(m1); V <- cr_vcov(X, x$y - p1, p1 * (1 - p1), x$wk)
      ct <- lmtest::coeftest(m1, vcov. = sandwich::vcovCL(m1, cluster = x$wk, type = "HC0"), df = Inf)
    } else {
      r <- x[[fam[[fm]]]]
      m0 <- stats::lm(r ~ 1); m1 <- stats::lm(r ~ 1 + X[, "fx"])
      pt <- stats::anova(m0, m1)[2, "Pr(>F)"]
      V <- cr_vcov(X, stats::residuals(m1), rep(1, nrow(x)), x$wk)
      ct <- lmtest::coeftest(m1, vcov. = sandwich::vcovCL(m1, cluster = x$wk, type = "HC0"), df = Inf)
    }
    est <- unname(stats::coef(m1)[2]); se <- sqrt(V["fx", "fx"])
    rows[[length(rows) + 1L]] <- data.table(family = fm, feature = f, p_test = pt, estimate = est, se = se,
                                            p_robust = 2 * stats::pnorm(-abs(est / se)), p_coeftest = ct[2, 4])
  }
}
a <- rbindlist(rows)
a[, q := stats::p.adjust(pmax(p_test, p_robust), method = "BH"), by = family]
m <- merge(a, s1c[, .(family, feature, p_test_c = p_test, est_c = estimate, se_c = se_robust, p_robust_c = p_robust, q_c = q_bh)],
           by = c("family", "feature"))
check("A. S1", "rows recomputed against the reproduction", nrow(m), sum(is.finite(s1c$p_test)), rel_tol = 0)
check("A. S1", "p_test (anova LR or F)", m$p_test, m$p_test_c)
check("A. S1", "estimate", m$estimate, m$est_c)
# The hand sandwich is evaluated at glm's converged probabilities; sandwich::vcovCL uses glm's stored IRLS working
# weights from the last iteration, so the two differ by glm's convergence error (up to 1.6e-5 relative here, at
# 3 IRLS iterations). The linear families have no iteration and must agree to the CSVs' 6 digits.
lin <- m$family != "outcome"
check("A. S1", "robust SE, spread and total (hand-written sandwich)", m$se[lin], m$se_c[lin])
check("A. S1", "robust SE, moneyline (hand sandwich; glm convergence)", m$se[!lin], m$se_c[!lin], rel_tol = 5e-5,
      detail = "vcovCL's bread uses the last IRLS weights")
check("A. S1", "p_robust, spread and total (z on the hand sandwich)", m$p_robust[lin], m$p_robust_c[lin])
check("A. S1", "p_robust, moneyline (z on the hand sandwich)", m$p_robust[!lin], m$p_robust_c[!lin], rel_tol = 0, abs_tol = 1e-5,
      detail = "absolute 1e-5 on the p scale")
check("A. S1", "p_robust (lmtest::coeftest on sandwich::vcovCL)", m$p_coeftest, m$p_robust_c)
check("A. S1", "BH q within family (p.adjust)", m$q, m$q_c)

# ---------------------------------------------------------------------------------------------------------
# B. Joint tests (the v2 reproduction, 6 rows)
jc <- fread(file.path(REPRO, "s1_joint.csv"))
sets <- list(situational = VVF_V2_SITUATIONAL, all = VVF_V2_FEATURES)
jr <- list()
for (i in seq_len(nrow(jc))) {
  fm <- jc$family[i]; st <- jc$set[i]
  base <- if (fm == "outcome") v2t[!is.na(y) & is.finite(lp_anchor)] else v2t[is.finite(get(fam[[fm]]))]
  keep <- sets[[st]][vapply(sets[[st]], function(f) uniqueN(base[[f]][is.finite(base[[f]])]) > 1L, logical(1))]
  x <- base[stats::complete.cases(base[, ..keep])]
  q <- qr(cbind(1, as.matrix(x[, ..keep])))
  est <- keep[setdiff(q$pivot[seq_len(q$rank)], 1L) - 1L]
  X <- as.matrix(x[, ..est])
  if (fm == "outcome") {
    m0 <- stats::glm(x$y ~ 1, offset = x$lp_anchor, family = stats::binomial())
    m1 <- stats::glm(x$y ~ X, offset = x$lp_anchor, family = stats::binomial())
    pt <- stats::anova(m0, m1, test = "LRT")[2, "Pr(>Chi)"]
    p1 <- stats::fitted(m1); V <- cr_vcov(cbind(`(Intercept)` = 1, X), x$y - p1, p1 * (1 - p1), x$wk)
    p0 <- stats::fitted(m0); resid <- x$y - p0; wt <- p0 * (1 - p0)
  } else {
    r <- x[[fam[[fm]]]]
    m0 <- stats::lm(r ~ 1); m1 <- stats::lm(r ~ X)
    pt <- stats::anova(m0, m1)[2, "Pr(>F)"]
    V <- cr_vcov(cbind(`(Intercept)` = 1, X), stats::residuals(m1), rep(1, nrow(x)), x$wk)
    resid <- r - mean(r); wt <- rep(1, nrow(x))
  }
  b <- stats::coef(m1)[-1]; names(b) <- est
  Vb <- V[est, est]
  lh <- car::linearHypothesis(m1, diag(length(est)), coef. = unname(b), vcov. = unname(Vb), test = "Chisq")
  W <- vvf_rademacher(uniqueN(x$wk), VVF_WILD_B, VVF_WILD_SEED)
  jr[[i]] <- data.table(family = fm, set = st, same_features = setequal(est, strsplit(jc$features[i], " ")[[1]]),
                        p_test = pt, wald = lh$Chisq[2], p_wild = wild_diag_loop(X, resid, wt, x$wk, W))
}
jv <- merge(rbindlist(jr), jc[, .(family, set, p_test_c = p_test, wald_c = wald_robust, p_wild_c = p_joint_wild, p_joint_c = p_joint)],
            by = c("family", "set"))
check_true("B. Joint", "estimable feature sets match (QR, independent of glm)", all(jv$same_features), sprintf("%d of %d", sum(jv$same_features), nrow(jv)))
check("B. Joint", "p_test (anova LR or F)", jv$p_test, jv$p_test_c)
check("B. Joint", "Wald statistic (car::linearHypothesis, hand sandwich)", jv$wald, jv$wald_c)
check("B. Joint", "p_joint_wild (loop implementation, same weights)", jv$p_wild, jv$p_wild_c, rel_tol = 0, abs_tol = 1e-9)
check("B. Joint", "p_joint = max(p_test, p_joint_wild)", pmax(jv$p_test, jv$p_wild), jv$p_joint_c)

# ---------------------------------------------------------------------------------------------------------
# C. S3 incremental skill (36 rows): an independent walk-forward refit, Brier skill, the DM-HLN p as the
# paired one-sided t-test (exactly equal at h = 1), BH, and the week-block bootstrap CI's arithmetic
s3c <- fread(file.path(RUN, "s3_skill.csv"))
weeks <- full[season %in% TUNE, .(cutoff = min(kickoff)), by = .(season, week, wk)][order(cutoff)]
pool <- full[is.finite(lp_anchor)]
ev <- full[season %in% TUNE & !is.na(y), .(game_id, kickoff, wk, y, p_anchor)]
pmax_diff <- 0
for (f in VVF_V2_FEATURES) {
  x <- pool[is.finite(get(f))]
  pr <- rbindlist(lapply(seq_len(nrow(weeks)), function(i) {
    tg <- x[wk == weeks$wk[i]]
    tr <- x[kickoff < weeks$cutoff[i] & !is.na(y)]
    if (!nrow(tg) || nrow(tr) < VVF_S3_MIN_TRAIN) return(NULL)
    mu <- mean(tr[[f]]); sdv <- stats::sd(tr[[f]])
    if (!is.finite(sdv) || sdv == 0) return(data.table(game_id = tg$game_id, p = tg$p_anchor))
    z <- (tr[[f]] - mu) / sdv
    bh <- unname(stats::coef(stats::glm(tr$y ~ 0 + z, offset = tr$lp_anchor, family = stats::binomial()))[1])
    data.table(game_id = tg$game_id, p = stats::plogis(tg$lp_anchor + bh * (tg[[f]] - mu) / sdv))
  }))
  vv <- vvf_s3_refit(full, f, bt_week_schedule(full, TUNE))
  mm <- merge(pr, vv[, .(game_id, p_v = p)], by = "game_id")
  pmax_diff <- max(pmax_diff, abs(mm$p - mm$p_v), abs(nrow(pr) - nrow(vv)))
  ev <- merge(ev, pr[, .(game_id, p)], by = "game_id", all.x = TRUE)
  setnames(ev, "p", paste0("p_", f))
}
check("C. S3", "walk-forward predictions against vvf_s3_refit (36 features)", pmax_diff, 0, rel_tol = 0, abs_tol = 1e-10)
cols <- paste0("p_", VVF_V2_FEATURES)
ev <- ev[Reduce(`&`, lapply(c("p_anchor", cols), function(cc) is.finite(ev[[cc]])))]
setorder(ev, kickoff, game_id)
br0 <- (ev$p_anchor - ev$y)^2; ll0 <- logloss(ev$p_anchor, ev$y)
wkf <- factor(ev$wk)
cnt <- bt_boot_counts(nlevels(wkf), VVF_S3_B, VVF_S3_SEED)
S0 <- as.numeric(tapply(br0, wkf, sum))
s3v <- rbindlist(lapply(VVF_V2_FEATURES, function(f) {
  p <- ev[[paste0("p_", f)]]; br <- (p - ev$y)^2
  sk_b <- 1 - drop(cnt %*% as.numeric(tapply(br, wkf, sum))) / drop(cnt %*% S0)
  ci <- stats::quantile(sk_b, c(0.025, 0.975), names = FALSE, type = 7)
  data.table(feature = f, n = length(p), skill = 1 - mean(br) / mean(br0), skill_lo = ci[1], skill_hi = ci[2],
             brier_diff = mean(br) - mean(br0), logloss_diff = mean(logloss(p, ev$y)) - mean(ll0),
             dm_p = stats::t.test(br, br0, paired = TRUE, alternative = "less")$p.value)
}))
s3v[, dm_p_bh := stats::p.adjust(dm_p, method = "BH")]
s3m <- merge(s3v, s3c, by = "feature", suffixes = c("", "_c"))
check("C. S3", "scored games", s3m$n, s3m$n_c, rel_tol = 0)
check("C. S3", "Brier skill 1 - Brier/Brier(anchor)", s3m$skill, s3m$skill_c)
check("C. S3", "Brier difference", s3m$brier_diff, s3m$brier_diff_c)
check("C. S3", "log-loss difference", s3m$logloss_diff, s3m$logloss_diff_c)
check("C. S3", "skill CI, week-block bootstrap (own arithmetic)", c(s3m$skill_lo, s3m$skill_hi), c(s3m$skill_lo_c, s3m$skill_hi_c))
check("C. S3", "DM-HLN p = paired one-sided t-test p (t.test)", s3m$dm_p, s3m$dm_p_better)
check("C. S3", "BH over the 36 DM p (p.adjust)", s3m$dm_p_bh, s3m$dm_p_better_bh)
check_true("C. S3", "no feature claimed (CI above 0 and BH p < 0.05)", !any(s3m$skill_lo > 0 & s3m$dm_p_bh < 0.05),
           sprintf("%d intervals wholly above 0; smallest BH p %.3f", sum(s3m$skill_lo > 0), min(s3m$dm_p_bh)))

# ---------------------------------------------------------------------------------------------------------
# D. S5: Brier and log loss of each model, Murphy, calibration, loss ANOVA, team effects, E1, bias-variance
x <- full[season %in% TUNE]
y <- x[!is.na(y)]
mods <- c(C0 = "p_c0", C1 = "p_c1", C2 = "p_c2", E1 = "p_e1")
mur <- fread(file.path(RUN, "s5_murphy.csv"))
cal <- fread(file.path(RUN, "s5_calibration.csv"))
md <- rbindlist(lapply(names(mods), function(mn) {
  p <- y[[mods[[mn]]]]; yy <- y$y
  g <- cut(rank(p, ties.method = "first"), breaks = 10L, labels = FALSE)
  t <- data.table(g, p, yy)[, .(n = .N, pb = mean(p), yb = mean(yy)), by = g]
  m1 <- stats::glm(yy ~ lg(p), family = stats::binomial()); m0 <- stats::glm(yy ~ 1, offset = lg(p), family = stats::binomial())
  data.table(model = mn, brier = mean((p - yy)^2), logloss = mean(logloss(p, yy)), uncertainty = mean(yy) * (1 - mean(yy)),
             reliability = sum(t$n * (t$pb - t$yb)^2) / length(p), resolution = sum(t$n * (t$yb - mean(yy))^2) / length(p),
             slope = unname(stats::coef(m1)[2]), slope_lo = stats::confint.default(m1)[2, 1], slope_hi = stats::confint.default(m1)[2, 2],
             intercept = unname(stats::coef(m0)[1]), intercept_lo = stats::confint.default(m0)[1, 1], intercept_hi = stats::confint.default(m0)[1, 2])
}))
mm <- merge(md, merge(mur, cal, by = "model"), by = "model", suffixes = c("", "_c"))
check("D. S5", "Brier of C0, C1, C2, E1", mm$brier, mm$brier_c)
check("D. S5", "Murphy reliability, resolution, uncertainty", c(mm$reliability, mm$resolution, mm$uncertainty),
      c(mm$reliability_c, mm$resolution_c, mm$uncertainty_c))
check("D. S5", "calibration slope and Wald CI", c(mm$slope, mm$slope_lo, mm$slope_hi), c(mm$slope_c, mm$slope_lo_c, mm$slope_hi_c))
check("D. S5", "calibration-in-the-large and Wald CI", c(mm$intercept, mm$intercept_lo, mm$intercept_hi),
      c(mm$intercept_c, mm$intercept_lo_c, mm$intercept_hi_c))
lc <- fread(file.path(RUN, "s5_learning_curve.csv")); fg <- fread(file.path(RUN, "s5_fit_gap.csv"))
check("D. S5", "the anchor's Tune log loss (learning curve column)", md[model == "C0", logloss], unique(lc$logloss_anchor))
check("D. S5", "the anchor's log loss by season (fit-gap column)", y[, mean(logloss(p_anchor, y)), keyby = season]$V1, fg[order(season), logloss_anchor])
la <- fread(file.path(RUN, "s5_loss_anova.csv"))
part <- function(week, phase) ifelse(phase == "POST", "playoffs", ifelse(week <= 6L, "weeks 1-6", ifelse(week <= 12L, "weeks 7-12", "weeks 13-18")))
lav <- rbindlist(lapply(seq_len(nrow(la)), function(i) {
  d <- if (la$loss[i] == "brier") (y$p_e1 - y$y)^2 - (y$p_c0 - y$y)^2 else logloss(y$p_e1, y$y) - logloss(y$p_c0, y$y)
  grp <- if (la$by[i] == "season") as.character(y$season) else part(y$week, y$phase)
  o <- stats::oneway.test(d ~ grp, var.equal = TRUE)
  data.table(F = unname(o$statistic), p = o$p.value)
}))
check("D. S5", "loss ANOVA F and p (oneway.test)", c(lav$F, lav$p), c(la$F, la$p))
check("D. S5", "loss ANOVA BH q over the four tests", stats::p.adjust(lav$p, method = "BH"), la$q_bh)
te <- fread(file.path(RUN, "s5_team_effects.csv"))
o <- y[is.finite(lp_anchor)]
lr <- stats::anova(stats::glm(y ~ 1, offset = lp_anchor, family = stats::binomial(), data = o),
                   stats::glm(y ~ factor(home_franchise) + factor(away_franchise), offset = lp_anchor, family = stats::binomial(), data = o),
                   test = "LRT")
s <- x[is.finite(ats_resid)]
fs <- stats::anova(stats::lm(ats_resid ~ 1, data = s), stats::lm(ats_resid ~ factor(home_franchise) + factor(away_franchise), data = s))
check("D. S5", "team effects: LR and F statistics (treatment contrasts)", c(lr$Deviance[2], fs$F[2]), te[order(family), stat])
check("D. S5", "team effects: p-values", c(lr$`Pr(>Chi)`[2], fs$`Pr(>F)`[2]), te[order(family), p])
ee <- full[is.finite(p_c1) & is.finite(p_c2) & is.finite(p_e1)]
check("D. S5", "E1 = logit mean of C1 and C2, every game", ee$p_e1, stats::plogis((stats::qlogis(ee$p_c1) + stats::qlogis(ee$p_c2)) / 2),
      rel_tol = 0, abs_tol = 1e-9)
bv <- fread(file.path(RUN, "s5_bias_variance.csv"))
em <- (x$margin - x$spread_line)[is.finite(x$margin - x$spread_line)]
et <- (x$total - x$total_line)[is.finite(x$total - x$total_line)]
check("D. S5", "the closing lines' error bias and variance", c(mean(em), mean((em - mean(em))^2), mean(et), mean((et - mean(et))^2)),
      c(bv$bias[1], bv$variance[1], bv$bias[2], bv$variance[2]))

# ---------------------------------------------------------------------------------------------------------
# E. Are the p-values calibrated under the null? Rejection rates in the binomial 99% band, and KS against U(0, 1)
cal_rows <- list()
calib <- function(name, p, alpha = 0.05) {
  R <- length(p); band <- stats::qbinom(c(0.005, 0.995), R, alpha) / R
  rate <- mean(p < alpha); ks <- stats::ks.test(p, "punif")$p.value
  cal_rows[[length(cal_rows) + 1L]] <<- data.table(test = name, draws = R, rate_05 = rate, rate_01 = mean(p < 0.01),
                                                   band_lo = band[1], band_hi = band[2], ks_p = ks)
  check_true("E. Null calibration", name, rate >= band[1] && rate <= band[2],
             sprintf("rejection %.3f at 0.05 (99%% band %.3f-%.3f), %.3f at 0.01, KS p %.3f", rate, band[1], band[2], mean(p < 0.01), ks))
}
set.seed(20261101L)
dref <- (ev$p_rest_diff - ev$y)^2 - br0
d0 <- dref - mean(dref)
calib("S3 DM p, sign-flipped real loss differences", replicate(n_of(2000L, 50L), stats::t.test(d0 * sample(c(-1, 1), length(d0), TRUE),
                                                                                    alternative = "less")$p.value))
o <- v2t[!is.na(y) & is.finite(lp_anchor)]
X1 <- function(z) cbind(`(Intercept)` = 1, fx = z)
pl <- t(vapply(seq_len(n_of(500L, 20L)), function(i) {
  z <- stats::rnorm(nrow(o))
  m0 <- stats::glm(o$y ~ 1, offset = o$lp_anchor, family = stats::binomial())
  m1 <- stats::glm(o$y ~ z, offset = o$lp_anchor, family = stats::binomial())
  p1 <- stats::fitted(m1); se <- sqrt(cr_vcov(X1(z), o$y - p1, p1 * (1 - p1), o$wk)["fx", "fx"])
  c(lr = stats::pchisq(m0$deviance - m1$deviance, 1, lower.tail = FALSE), robust = unname(2 * stats::pnorm(-abs(stats::coef(m1)[2] / se))))
}, numeric(2)))
calib("S1 LR p, 500 placebo features on the Tune design", pl[, "lr"])
calib("S1 robust p (cluster sandwich z), 500 placebos", pl[, "robust"])
calib("S1 p = max(LR, robust), 500 placebos (conservative)", pmax(pl[, "lr"], pl[, "robust"]))
xs <- o[stats::complete.cases(o[, ..VVF_V2_SITUATIONAL])]
keep <- VVF_V2_SITUATIONAL[vapply(VVF_V2_SITUATIONAL, function(f) uniqueN(xs[[f]]) > 1L, logical(1))]
qq <- qr(cbind(1, as.matrix(xs[, ..keep]))); keep <- keep[setdiff(qq$pivot[seq_len(qq$rank)], 1L) - 1L]
XS <- as.matrix(xs[, ..keep]); G <- uniqueN(xs$wk)
jn <- t(vapply(seq_len(n_of(300L, 10L)), function(i) {
  ys <- stats::rbinom(nrow(xs), 1, xs$p_anchor)
  m0 <- stats::glm(ys ~ 1, offset = xs$lp_anchor, family = stats::binomial())
  m1 <- stats::glm(ys ~ XS, offset = xs$lp_anchor, family = stats::binomial())
  p1 <- stats::fitted(m1); V <- cr_vcov(cbind(`(Intercept)` = 1, XS), ys - p1, p1 * (1 - p1), xs$wk)[-1, -1]
  b <- stats::coef(m1)[-1]
  wald <- car::linearHypothesis(m1, diag(length(b)), coef. = unname(b), vcov. = unname(V), test = "Chisq")$Chisq[2]
  p0 <- stats::fitted(m0)
  W <- matrix(sample(c(-1, 1), G * 999L, replace = TRUE), G)
  c(lr = stats::pchisq(m0$deviance - m1$deviance, length(b), lower.tail = FALSE), wald = stats::pchisq(wald, length(b), lower.tail = FALSE),
    wild = wild_diag_loop(XS, ys - p0, p0 * (1 - p0), xs$wk, W))
}, numeric(3)))
calib(sprintf("joint wild p, 300 null draws (k = %d, G = %d)", length(keep), G), jn[, "wild"])
calib(sprintf("joint LR p, the same draws (k = %d)", length(keep)), jn[, "lr"])
fwrite(rbindlist(cal_rows), file.path(out, "pvalue_calibration.csv"))

# ---------------------------------------------------------------------------------------------------------
# F. The research, replicated independently
rep_rows <- list()
wr <- mean(jn[, "wald"] < 0.05); se_w <- sqrt(0.399 * 0.601 / nrow(jn))
rep_rows[[1]] <- data.table(item = "CR Wald size, situational, 107 clusters (car::linearHypothesis, hand sandwich)",
                            research = 0.399, replication = wr, tolerance = 3 * se_w)
check_true("F. Research", "CR Wald null size replicates the research's 0.399", abs(wr - 0.399) <= 3 * se_w,
           sprintf("%.3f over %d draws (research 0.399; 3 SE %.3f)", wr, nrow(jn), 3 * se_w))
icc <- function(r, g) {
  dd <- data.frame(r = r, g = factor(g))
  # a variance at its boundary (0) can stop nlminb; optim is nlme's documented alternative. A failure stays visible (NA).
  fit <- tryCatch(nlme::lme(r ~ 1, random = ~ 1 | g, data = dd, method = "REML"),
                  error = function(err) tryCatch(nlme::lme(r ~ 1, random = ~ 1 | g, data = dd, method = "REML",
                                                           control = nlme::lmeControl(opt = "optim")), error = function(err2) NULL))
  if (is.null(fit)) return(NA_real_)
  vc <- as.numeric(nlme::VarCorr(fit)[, "Variance"]); vc[1] / sum(vc)
}
yy <- v2t[!is.na(y)]
iccs <- c(e_out = icc(yy$y - yy$p_anchor, yy$wk), ats_resid = icc(v2t[is.finite(ats_resid), ats_resid], v2t[is.finite(ats_resid), wk]),
          tot_resid = icc(v2t[is.finite(tot_resid), tot_resid], v2t[is.finite(tot_resid), wk]))
for (nm in names(iccs)) rep_rows[[length(rep_rows) + 1L]] <- data.table(item = paste("season-week ICC (nlme REML), ", nm), research = 0,
                                                                        replication = iccs[[nm]], tolerance = 0.01)
check_true("F. Research", "season-week ICC by REML random intercept is about 0", !anyNA(iccs) && all(iccs < 0.01),
           paste(sprintf("%s %.5f", names(iccs), iccs), collapse = "; "))
fg2 <- fread(file.path("reports", "2026-10-28", "a3-research", "data", "flex-games.csv"))
bul <- rbindlist(lapply(jsonlite::read_json(file.path("reports", "2026-10-28", "a3-research", "data", "flex-bullets.json")),
                        function(b) data.table(season = b$season, text = substr(b$text, 1, 300), teams = paste(unlist(b$teams), collapse = "|"))))
bul <- unique(bul, by = c("season", "text"))
NAME <- c(Arizona = "ARI", Atlanta = "ATL", Baltimore = "BAL", Buffalo = "BUF", Carolina = "CAR", Chicago = "CHI", Cincinnati = "CIN",
          Cleveland = "CLE", Dallas = "DAL", Denver = "DEN", Detroit = "DET", `Green Bay` = "GB", Houston = "HOU", Indianapolis = "IND",
          Jacksonville = "JAX", `Kansas City` = "KC", `Las Vegas` = "LV", Oakland = "LV", `Los Angeles Chargers` = "LAC",
          `Los Angeles Rams` = "LA", Miami = "MIA", Minnesota = "MIN", `New England` = "NE", `New Orleans` = "NO", `New York Giants` = "NYG",
          `New York Jets` = "NYJ", Philadelphia = "PHI", Pittsburgh = "PIT", `San Francisco` = "SF", Seattle = "SEA", `Tampa Bay` = "TB",
          Tennessee = "TEN", Washington = "WAS")
code_of <- function(team) {
  if (is.na(team) || !nzchar(team)) return(NA_character_)
  k <- names(NAME)[vapply(names(NAME), function(n) startsWith(team, n), logical(1))]
  if (length(k)) NAME[[k[which.max(nchar(k))]]] else NA_character_
}
games <- tab$inp_v1$games
gm <- fread(file.path("backtest", "data", "games.csv"), select = c("game_id", "season", "week", "home_franchise", "away_franchise"))
fm2 <- merge(fg2[, .(game_id, season, week, text)], gm, by = "game_id", all.x = TRUE, suffixes = c("", "_g"))
fm2 <- merge(fm2, bul, by = c("season", "text"), all.x = TRUE)
fm2[, ok := !is.na(home_franchise) & season == season_g & week == week_g & !is.na(teams) &
         mapply(function(tm, h, a) {
           if (is.na(tm)) return(FALSE)
           cs <- vapply(strsplit(tm, "|", fixed = TRUE)[[1]], code_of, "")
           h %in% cs && a %in% cs
         }, teams, home_franchise, away_franchise)]
check_true("F. Research", "late changes: each row's game, week and both teams match its bullet", nrow(fm2) == nrow(fg2) && all(fm2$ok),
           sprintf("%d of %d rows", sum(fm2$ok), nrow(fm2)))
rep_rows[[length(rep_rows) + 1L]] <- data.table(item = "late-change rows matched to their game and bullet", research = nrow(fg2),
                                                replication = sum(fm2$ok), tolerance = 0)
nul <- rbindlist(lapply(c(101L, 102L), function(k) rbindlist(lapply(c("anchor", "permuted_x"), function(nl) {
  r <- vvf_control_null(full, S4_FEATURES, "close", TUNE, null = nl, B = n_of(1000L, 50L), seed = VVF_NULL_SEED + k)
  data.table(null = nl, seed = VVF_NULL_SEED + k, claims = r$claims, above = r$above, below = r$below)
}))))
sh <- vvf_control_shuffle(full, S4_FEATURES, "close", TUNE, B = n_of(1000L, 50L), seed = VVF_SHUFFLE_SEED + 101L)
sh_above <- sum(sh$skill$skill_lo > 0)
check_true("F. Research", "S4: the anchor and permuted-x nulls claim nothing on new seeds", all(nul$claims == 0L),
           paste(sprintf("%s seed +%d: %d claims, %d above 0", nul$null, nul$seed - VVF_NULL_SEED, nul$claims, nul$above), collapse = "; "))
check_true("F. Research", "S4: the spec's shuffle still fails on a new seed", sh_above > 0L, sprintf("%d of %d intervals wholly above 0", sh_above, nrow(sh$skill)))
for (i in seq_len(nrow(nul))) rep_rows[[length(rep_rows) + 1L]] <- data.table(item = sprintf("S4 %s null claims, seed +%d", nul$null[i], nul$seed[i] - VVF_NULL_SEED),
                                                                         research = 0, replication = nul$claims[i], tolerance = 0)
fwrite(rbindlist(rep_rows), file.path(out, "research_replication.csv"))

# ---------------------------------------------------------------------------------------------------------
# G. The blends: #205's 30 and #209's 9 candidates recomputed from their committed per-game files
tr205 <- git_csv(ref205, "reports/2026-09-30/validation-sprint/tracking/moneyline_tune.csv")
sc205 <- git_csv(ref205, "reports/2026-09-30/validation-sprint/models/scores_tune.csv")
tr209 <- git_csv(ref209, "reports/2026-10-01/blend-research/tracking/moneyline_tune_v3.csv")
sc209 <- git_csv(ref209, "reports/2026-10-01/blend-research/scores/scores_tune.csv")
trk <- rbind(tr205[, src := "#205"], tr209[, src := "#209"])
check("G. Blends", "per-game Brier and log loss in the tracking files", c(trk$brier, trk$logloss, trk$brier_market),
      c((trk$p_model - trk$outcome)^2, logloss(trk$p_model, trk$outcome), (trk$p_market - trk$outcome)^2), rel_tol = 1e-6, abs_tol = 1e-7)
mk <- merge(unique(trk[, .(game_id, p_market)]), ev[, .(game_id, p_anchor)], by = "game_id")
check("G. Blends", "their market probability is VVF's no-vig close", mk$p_market, mk$p_anchor, rel_tol = 0, abs_tol = 1e-7,
      detail = sprintf("%d games", nrow(mk)))
agg <- trk[, .(n = .N, brier = mean((p_model - outcome)^2), logloss = mean(logloss(p_model, outcome)),
               skill = 1 - mean((p_model - outcome)^2) / mean((p_market - outcome)^2),
               dm_p = stats::t.test((p_model - outcome)^2, (p_market - outcome)^2, paired = TRUE, alternative = "less")$p.value),
           by = .(src, candidate)]
agg[, `:=`(base = sub("__.*$", "", candidate), calibration = fifelse(grepl("__", candidate), sub("^.*__", "", candidate), "none"))]
agg[base == "e1", base := "E1 (v1 ensemble)"]
c205 <- merge(agg[src == "#205"], sc205, by.x = c("base", "calibration"), by.y = c("candidate", "calibration"), suffixes = c("", "_c"))
check("G. Blends", "#205: Brier, log loss and skill of its 30 candidates", c(c205$brier, c205$logloss, c205$skill),
      c(c205$brier_c, c205$logloss_c, c205$skill_c), detail = sprintf("%d candidates", nrow(c205)))
check("G. Blends", "#205: DM p as the paired t-test", c205$dm_p, c205$dm_p_c)
c209 <- merge(agg[src == "#209"], sc209, by = "candidate", suffixes = c("", "_c"))
check("G. Blends", "#209: Brier, log loss and skill of its 9 new candidates", c(c209$brier, c209$logloss, c209$skill),
      c(c209$brier_c, c209$logloss_c, c209$skill_c), detail = sprintf("%d candidates", nrow(c209)))
check("G. Blends", "#209: DM p as the paired t-test", c209$dm_p, c209$dm_p_c)
ml <- sc209[is.finite(dm_p)]
check("G. Blends", "#209: BH q over its 39 moneyline candidates", stats::p.adjust(ml$dm_p, method = "BH"), ml$bh_q,
      detail = sprintf("%d candidates", nrow(ml)))
base4 <- merge(md[, .(model, brier, logloss)], sc209[column %in% c("p_c0", "p_c1", "p_c2", "p_e1"),
                                                     .(model = toupper(sub("^p_", "", column)), brier_c = brier, logloss_c = logloss)], by = "model")
check("G. Blends", "#209's C0, C1, C2, E1 against VVF's own base predictions", c(base4$brier, base4$logloss), c(base4$brier_c, base4$logloss_c))
# #209 reports two intercepts: the recalibration model's (y ~ a + b logit p) and calibration-in-the-large (offset);
# VVF's s5_calibration intercept is the latter
c0 <- sc209[column == "p_c0"]
check("G. Blends", "the close's slope and calibration-in-the-large: VVF against #209", unlist(md[model == "C0", .(slope, slope_lo, slope_hi, intercept, intercept_lo, intercept_hi)]),
      unlist(c0[, .(slope, slope_lo, slope_hi, citl, citl_lo, citl_hi)]), detail = sprintf("#209's recalibration intercept is %.4f", c0$recal_intercept))
best <- agg[order(-skill)][1]
check_true("G. Blends", "no blend beats the close after BH (every q > 0.05)", all(ml$bh_q > 0.05),
           sprintf("best skill %s %+.5f; smallest DM p %.3f; smallest q %.3f", best$candidate, best$skill, min(agg$dm_p), min(ml$bh_q)))
fwrite(agg[, .(src, candidate, n, brier = signif(brier, 6), logloss = signif(logloss, 6), skill = signif(skill, 6), dm_p = signif(dm_p, 6))],
       file.path(out, "blends.csv"))

# ---------------------------------------------------------------------------------------------------------
ch <- rbindlist(checks)
ch[, provenance := sprintf("#205 %s, #209 %s", git_sha(ref205), git_sha(ref209))]
fwrite(ch, file.path(out, "checks.csv"))
cat(sprintf("\n%d of %d checks passed (%.0f s)\n", sum(ch$passed), nrow(ch), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
if (!all(ch$passed)) quit(status = 1L)
