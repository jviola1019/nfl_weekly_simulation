# =============================================================================
# VVF stage S5, scoring diagnostics (amendment 2026-10-21, item 1): the Murphy
# decomposition of Brier, calibration slope and intercept with a label, bias and
# variance of margin and total errors, CRPS and randomized PIT for discrete
# score distributions, and effective degrees of freedom.
# =============================================================================

VVF_PIT_SEED <- 20261025L

#' Murphy decomposition of the Brier score. With bins the identity is exact:
#'   Brier = REL - RES + UNC + WBV - 2 * WBC
#' (WBV, WBC: within-bin variance of p and within-bin covariance of p and y).
#' bins = "value" groups identical forecasts, where WBV = WBC = 0.
vvf_murphy <- function(p, y, bins = 10L) {
  g <- if (identical(bins, "value")) match(p, sort(unique(p))) else
    cut(rank(p, ties.method = "first"), breaks = bins, labels = FALSE)
  n <- length(y)
  ybar <- mean(y)
  t <- data.table(g = g, p = p, y = y)[, .(n_k = .N, pbar = mean(p), ybar_k = mean(y),
                                          wbv = sum((p - mean(p))^2), wbc = sum((p - mean(p)) * (y - mean(y)))), by = g]
  list(brier = mean((p - y)^2), reliability = sum(t$n_k * (t$pbar - t$ybar_k)^2) / n,
       resolution = sum(t$n_k * (t$ybar_k - ybar)^2) / n, uncertainty = ybar * (1 - ybar),
       within_bin_variance = sum(t$wbv) / n, within_bin_covariance = sum(t$wbc) / n, bins = nrow(t))
}

#' bt_calibration() with a label: a slope CI below 1 is overconfident, above 1 underconfident
vvf_calibration_label <- function(p, y) {
  cal <- bt_calibration(p, y)
  cal$label <- if (cal$slope_ci[2] < 1) "overconfident (slope < 1)" else
    if (cal$slope_ci[1] > 1) "underconfident (slope > 1)" else "slope consistent with 1"
  cal
}

#' Error decomposition MSE = bias^2 + variance (population variance of the errors)
vvf_bias_variance <- function(pred, obs) {
  e <- obs - pred
  e <- e[is.finite(e)]
  list(n = length(e), mse = mean(e^2), bias = mean(e), variance = mean((e - mean(e))^2))
}

#' CRPS of an integer outcome under a distribution on 0..K given by `probs`:
#' sum over k of (F(k) - 1{y <= k})^2, exact for unit-spaced support
vvf_crps_probs <- function(y, probs) {
  top <- max(length(probs) - 1L, y)
  cdf <- cumsum(c(probs, rep(0, top - (length(probs) - 1L))))
  k <- 0:top
  sum((cdf - (k >= y))^2)
}

#' CRPS under NB(mu, size), vectorised; the support runs to the 1 - 1e-12 quantile
vvf_crps_nb <- function(y, mu, size) {
  mapply(function(yy, m, s) {
    k <- 0:max(yy, stats::qnbinom(1 - 1e-12, size = s, mu = m))
    sum((stats::pnbinom(k, size = s, mu = m) - (k >= yy))^2)
  }, y, mu, size)
}

#' CRPS from draws: mean|X - y| - E|X - X'| / 2, with the sorted-sample form of E|X - X'|
vvf_crps_sample <- function(y, x) {
  x <- sort(x)
  n <- length(x)
  mean(abs(x - y)) - sum((2 * seq_len(n) - n - 1) * x) / n^2
}

#' Randomized PIT for discrete outcomes under NB(mu, size):
#' u = F(y - 1) + v * (F(y) - F(y - 1)), v uniform under a fixed seed
vvf_pit_nb <- function(y, mu, size, seed = VVF_PIT_SEED) {
  lo <- stats::pnbinom(y - 1, size = size, mu = mu)
  hi <- stats::pnbinom(y, size = size, mu = mu)
  v <- vvf_seeded(seed, function() stats::runif(length(y)))
  lo + v * (hi - lo)
}

#' PIT histogram with a chi-square test of uniformity
vvf_pit_histogram <- function(u, bins = 10L) {
  counts <- tabulate(pmin(floor(u * bins) + 1L, bins), bins)
  e <- length(u) / bins
  chi2 <- sum((counts - e)^2 / e)
  list(counts = counts, chi2 = chi2, p = stats::pchisq(chi2, bins - 1L, lower.tail = FALSE))
}

#' Effective degrees of freedom of a weighted ridge fit: trace((X'WX + P)^-1 X'WX)
vvf_edf_ridge <- function(X, w, lambda, unpenalized = integer()) {
  pen <- rep(lambda, ncol(X))
  pen[unpenalized] <- 0
  A <- crossprod(X, X * w)
  sum(diag(solve(A + diag(pen, ncol(X)), A)))
}

#' Effective degrees of freedom of an unpenalized lm or glm: its rank
vvf_edf <- function(fit) as.integer(fit$rank)
