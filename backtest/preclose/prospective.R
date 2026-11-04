# =============================================================================
# nfl_preclose_v1.1's Tuesday track (AMENDMENT_1_1.md): the saved weekly predictions it
# scores, and its closing-line value and taker return. Sourced by run_2026.R and tested
# by tests/testthat/test-preclose.R. Needs backtest/metrics.R (bt_boot_counts,
# bt_quantile_ci) and backtest/preclose/gates.R (PC_TAU, PC_B, PC_SEED).
# =============================================================================

PC_KALSHI_FEE <- function(p) 0.07 * p * (1 - p)

#' The prediction each game is scored on: from the predict run of the game's own week
#' (predictions_wWW_<stamp>.csv, WW the run's week), made before that week's first
#' kickoff, the earliest such run. Returns one row per game and a coverage table.
pc_select_saved <- function(files, games_scored) {
  if (!length(files)) stop("pc_select_saved: no saved predictions", call. = FALSE)
  sp <- rbindlist(lapply(files, function(f) {
    w <- as.integer(sub("^predictions_w([0-9]{2})_.*\\.csv$", "\\1", basename(f)))
    fread(f)[, run_week := w]
  }), fill = TRUE)
  sp <- sp[week == run_week & before_first_kickoff_of_week == TRUE]
  setorder(sp, game_id, made_utc); sp <- sp[, .SD[1], by = game_id]
  stopifnot(!anyDuplicated(sp$game_id))
  cov <- data.table(games = length(games_scored), with_saved_prediction = sum(games_scored %in% sp$game_id),
                    without = sum(!games_scored %in% sp$game_id))
  list(predictions = sp[game_id %in% games_scored], coverage = cov)
}

#' Picks where the model is at least PC_TAU from Kalshi's Tuesday mid, CLV (bps) to
#' Kalshi's close for the side, and a taker's return: the side's YES at its Tuesday ask
#' (the away side at 1 - bid) plus Kalshi's taker fee, held to settlement, a tie paying
#' half. `x` has wk, p_tue, ask_tue, bid_tue, p_kclose, home_score, away_score and `col`;
#' `tue` names the decision price (p_tue, or p_tue_state for the sensitivity).
pc_tuesday_clv <- function(x, col, tue = "p_tue", B = PC_B, seed = PC_SEED) {
  x <- x[is.finite(get(col)) & is.finite(get(tue)) & is.finite(p_kclose) & !is.na(home_score) & !is.na(away_score)]
  edge <- x[[col]] - x[[tue]]
  side <- fifelse(edge >= PC_TAU, "home", fifelse(edge <= -PC_TAU, "away", NA_character_)); k <- !is.na(side)
  if (!any(k)) return(data.table(picks = 0L))
  z <- x[k]; s <- side[k]; pt <- z[[tue]]
  clv <- 10000 * fifelse(s == "home", z$p_kclose - pt, pt - z$p_kclose)
  cost <- fifelse(s == "home", z$ask_tue, 1 - z$bid_tue); cost <- cost + PC_KALSHI_FEE(cost)
  pay <- fifelse(z$home_score == z$away_score, 0.5, fifelse((s == "home") == (z$home_score > z$away_score), 1, 0))
  units <- pay / cost - 1
  wk_f <- factor(z$wk); counts <- bt_boot_counts(nlevels(wk_f), B, seed); n_w <- tabulate(as.integer(wk_f), nlevels(wk_f)); bn <- drop(counts %*% n_w)
  cb <- drop(counts %*% as.numeric(tapply(clv, wk_f, sum))) / bn; rb <- drop(counts %*% as.numeric(tapply(units, wk_f, sum))) / bn
  data.table(picks = nrow(z), ties = sum(z$home_score == z$away_score), mean_clv_bps = mean(clv), clv_lo = bt_quantile_ci(cb)[1],
             clv_hi = bt_quantile_ci(cb)[2], p_one_sided = mean(cb <= 0), roi = mean(units), roi_lo = bt_quantile_ci(rb)[1], roi_hi = bt_quantile_ci(rb)[2])
}
