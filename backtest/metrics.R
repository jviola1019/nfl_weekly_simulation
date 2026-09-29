# =============================================================================
# Metrics and statistics for the game backtest (shootout design "Metrics").
# All comparisons are paired: the same non-tie games for every candidate.
# =============================================================================

BT_BOOT_B <- 10000L

bt_brier_vec <- function(p, y) (p - y)^2
bt_logloss_vec <- function(p, y) { p <- bt_clip(p); -(y * log(p) + (1 - y) * log(1 - p)) }

#' Expected calibration error, 10 equal-mass bins
bt_ece <- function(p, y, bins = 10L) {
  g <- cut(rank(p, ties.method = "first"), breaks = bins, labels = FALSE)
  s <- data.table(g = g, p = p, y = y)[, .(n = .N, p = mean(p), y = mean(y)), by = g]
  sum(s$n / sum(s$n) * abs(s$y - s$p))
}

#' Calibration slope (logistic y ~ 1 + logit p) and intercept-in-the-large
#' (y ~ 1 with offset logit p), each with a Wald 95% CI
bt_calibration <- function(p, y) {
  lp <- bt_logit(bt_clip(p))
  m1 <- stats::glm(y ~ lp, family = stats::binomial())
  m0 <- stats::glm(y ~ 1, offset = lp, family = stats::binomial())
  ci1 <- suppressMessages(stats::confint.default(m1)["lp", ])
  ci0 <- suppressMessages(stats::confint.default(m0)[1, ])
  list(slope = unname(stats::coef(m1)[["lp"]]), slope_ci = unname(ci1),
       intercept = unname(stats::coef(m0)[[1]]), intercept_ci = unname(ci0))
}

#' Diebold-Mariano test with the Harvey-Leybourne-Newbold correction on a loss
#' differential d = loss_candidate - loss_reference in kickoff order (h = 1).
#' p_better is one-sided for H1: candidate loss < reference loss.
bt_dm_hln <- function(d, h = 1L) {
  n <- length(d)
  dbar <- mean(d)
  gamma <- function(k) sum((d[(k + 1):n] - dbar) * (d[1:(n - k)] - dbar)) / n
  v <- gamma(0)
  if (h > 1) for (k in 1:(h - 1)) v <- v + 2 * gamma(k)
  if (!is.finite(v) || v <= 0) return(list(n = n, mean_d = dbar, stat = NA_real_, p_better = 1, p_two_sided = 1))
  stat <- dbar / sqrt(v / n) * sqrt((n + 1 - 2 * h + h * (h - 1) / n) / n)
  list(n = n, mean_d = dbar, stat = stat, p_better = stats::pt(stat, df = n - 1),
       p_two_sided = 2 * stats::pt(-abs(stat), df = n - 1))
}

#' Week-resampling count matrix (B x W), deterministic for a seed
bt_boot_counts <- function(n_weeks, B, seed) {
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv()))
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  idx <- matrix(sample.int(n_weeks, n_weeks * B, replace = TRUE), nrow = B)
  t(apply(idx, 1, tabulate, nbins = n_weeks))
}

bt_quantile_ci <- function(x) unname(stats::quantile(x, c(0.025, 0.975), names = FALSE, type = 7))

#' Score candidates on one window. `d` has y (0/1, no ties), wk, kickoff and one
#' column per candidate; `ref` is the reference column (C0).
bt_score_window <- function(d, cands, ref, B = BT_BOOT_B, seed) {
  if (anyNA(d$y)) stop("bt_score_window: ties/unplayed games must be removed first")
  miss <- vapply(c(ref, cands), function(cc) sum(!is.finite(d[[cc]])), integer(1))
  if (any(miss > 0)) stop("bt_score_window: missing predictions: ",
                          paste(sprintf("%s=%d", names(miss)[miss > 0], miss[miss > 0]), collapse = ", "))
  setorder(d, kickoff, game_id)
  wk_f <- factor(d$wk)
  W <- nlevels(wk_f)
  counts <- bt_boot_counts(W, B, seed)
  n_w <- tabulate(as.integer(wk_f), W)
  week_sum <- function(x) as.numeric(tapply(x, wk_f, sum))
  ref_brier <- bt_brier_vec(d[[ref]], d$y)
  ref_ll <- bt_logloss_vec(d[[ref]], d$y)
  S0 <- week_sum(ref_brier); L0 <- week_sum(ref_ll)
  boot_n <- drop(counts %*% n_w)
  boot_S0 <- drop(counts %*% S0)

  one <- function(cc) {
    p <- d[[cc]]
    br <- bt_brier_vec(p, d$y); ll <- bt_logloss_vec(p, d$y)
    S <- week_sum(br)
    boot_S <- drop(counts %*% S)
    skill_b <- 1 - boot_S / boot_S0
    diff_b <- (boot_S - boot_S0) / boot_n
    ll_b <- (drop(counts %*% week_sum(ll)) - drop(counts %*% L0)) / boot_n
    cal <- bt_calibration(p, d$y)
    dm <- bt_dm_hln(br - ref_brier)
    list(
      n = nrow(d), weeks = W,
      brier = mean(br), logloss = mean(ll), accuracy = mean((p > 0.5) == (d$y == 1)),
      ece = bt_ece(p, d$y),
      slope = cal$slope, slope_ci = cal$slope_ci, intercept = cal$intercept, intercept_ci = cal$intercept_ci,
      skill = 1 - mean(br) / mean(ref_brier), skill_ci = bt_quantile_ci(skill_b),
      brier_diff = mean(br) - mean(ref_brier), brier_diff_ci = bt_quantile_ci(diff_b),
      logloss_diff = mean(ll) - mean(ref_ll), logloss_diff_ci = bt_quantile_ci(ll_b),
      dm_stat = dm$stat, dm_p_better = dm$p_better, dm_p_two_sided = dm$p_two_sided
    )
  }
  cols <- unname(c(ref, cands))
  res <- lapply(setNames(cols, cols), one)
  cands <- unname(cands)
  p_adj <- stats::p.adjust(vapply(setNames(cands, cands), function(cc) res[[cc]]$dm_p_better, numeric(1)), method = "BH")
  for (cc in cands) res[[cc]]$dm_p_better_bh <- unname(p_adj[[cc]])
  res
}

#' Closing-line value of decision-time picks at the ESPN BET opener.
#' Pick the side where model - no-vig open >= tau; CLV (bps) = 10000 * (close - open)
#' for that side, both no-vig at the same venue. Flat 1-unit ROI at the opening price.
bt_clv <- function(d, p_col, tau, B = BT_BOOT_B, seed) {
  d <- d[is.finite(get(p_col)) & is.finite(p_open) & is.finite(p_close_venue)]
  edge <- d[[p_col]] - d$p_open
  side <- ifelse(edge >= tau, "home", ifelse(edge <= -tau, "away", NA_character_))
  x <- d[!is.na(side)]
  side <- side[!is.na(side)]
  if (nrow(x) == 0L) return(list(n = 0L))
  home <- side == "home"
  clv <- 10000 * ifelse(home, x$p_close_venue - x$p_open, x$p_open - x$p_close_venue)
  dec <- ifelse(home, bt_amer_to_dec(x$h_open), bt_amer_to_dec(x$a_open))
  win <- (home & x$home_score > x$away_score) | (!home & x$away_score > x$home_score)
  push <- x$home_score == x$away_score
  units <- ifelse(push, 0, ifelse(win, dec - 1, -1))
  wk_f <- factor(x$wk)
  counts <- bt_boot_counts(nlevels(wk_f), B, seed)
  n_w <- tabulate(as.integer(wk_f), nlevels(wk_f))
  bn <- drop(counts %*% n_w)
  clv_b <- drop(counts %*% as.numeric(tapply(clv, wk_f, sum))) / bn
  roi_b <- drop(counts %*% as.numeric(tapply(units, wk_f, sum))) / bn
  list(n = nrow(x), n_home = sum(home), mean_clv_bps = mean(clv), clv_ci = bt_quantile_ci(clv_b),
       roi = mean(units), roi_ci = bt_quantile_ci(roi_b), hit_rate = mean(win[!push]))
}
