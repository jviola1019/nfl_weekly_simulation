# =============================================================================
# VVF stage S5, exponential smoothing (amendment 2026-10-21, item 1).
#   - vvf_ewma(): the normalized EWMA, which equals the engine's recency-weighted
#     mean (weights 2^(-k/h), newest k = 0) when alpha = 1 - 2^(-1/h);
#   - a local-level state-space (Kalman) rating, whose steady-state gain makes
#     it exactly an EWMA: the gain is the smoothing constant implied by the
#     signal-to-noise ratio q/r;
#   - a smoothing constant fitted per team with forecast::ets (model "ANN").
# These are candidate alternatives to RECENCY_HALFLIFE; G2 tests them as C3
# variants once G1's point-in-time walk-forward exists.
# =============================================================================

suppressPackageStartupMessages(library(data.table))

VVF_ETS_MIN_OBS <- 10L

#' Normalized EWMA of y (oldest first): out[t] = sum_k (1 - alpha)^k y[t - k] / sum_k (1 - alpha)^k
vvf_ewma <- function(y, alpha) {
  num <- 0
  den <- 0
  out <- numeric(length(y))
  for (t in seq_along(y)) {
    num <- y[t] + (1 - alpha) * num
    den <- 1 + (1 - alpha) * den
    out[t] <- num / den
  }
  out
}

#' The smoothing constant whose weights halve every h observations
vvf_alpha_for_halflife <- function(h) 1 - 2^(-1 / h)

#' Steady-state gain and prior variance of the local-level model
#' (level_t = level_{t-1} + N(0, q), y_t = level_t + N(0, r))
vvf_kalman_gain <- function(q, r) {
  s <- q / r
  K <- (s + sqrt(s^2 + 4 * s)) / (2 + s + sqrt(s^2 + 4 * s))
  list(gain = K, prior_var = q / K)
}

#' The signal-to-noise ratio q/r whose steady-state gain is K
vvf_snr_for_gain <- function(K) K^2 / (1 - K)

#' Kalman filter of the local-level model; P0 defaults to the steady-state prior variance
vvf_kalman_local_level <- function(y, q, r, m0 = y[1], P0 = vvf_kalman_gain(q, r)$prior_var) {
  m <- m0
  P <- P0
  level <- numeric(length(y))
  gain <- numeric(length(y))
  for (t in seq_along(y)) {
    K <- P / (P + r)
    m <- m + K * (y[t] - m)
    P <- (1 - K) * P + q
    level[t] <- m
    gain[t] <- K
  }
  data.table(t = seq_along(y), level = level, gain = gain)
}

#' forecast::ets smoothing constant (model "ANN") for each team's series, in
#' the order of column `order_col`; NA with a note when a team has too few
#' observations. (The *_col names avoid data.table's column masking.)
vvf_team_ets_alpha <- function(d, team_col, value_col, order_col) {
  teams <- sort(unique(d[[team_col]]))
  rbindlist(lapply(teams, function(tm) {
    x <- d[which(d[[team_col]] == tm)]
    y <- x[[value_col]][order(x[[order_col]])]
    if (length(y) < VVF_ETS_MIN_OBS) {
      return(data.table(team = tm, n = length(y), alpha = NA_real_, note = "fewer than 10 observations"))
    }
    fit <- forecast::ets(stats::ts(y), model = "ANN")
    data.table(team = tm, n = length(y), alpha = unname(fit$par[["alpha"]]), note = "")
  }))
}
