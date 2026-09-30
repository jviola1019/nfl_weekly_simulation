# =============================================================================
# Controls for the game backtest (a failure voids the run). Operational
# definitions are fixed in PROTOCOL.md; functions here only compute them.
# =============================================================================

BT_IMPLAUSIBLE_SKILL <- 0.05    # Brier skill vs the no-vig close above this voids the run
BT_MARKET_COPY_SLOPE <- c(0.85, 1.15)
BT_CANARY_SEED <- 20260929L
BT_SHUFFLE_SEED <- 20260930L

#' Leak canary. (a) A feature equal to the final margin plus N(0, 1) noise, whose
#' source ends 3.5 h after kickoff, must be rejected by bt_assert_asof().
#' (b) If the assertion is bypassed, C2 refit with the canary must show
#' implausible skill, which the implausible-skill guard flags.
bt_control_canary <- function(feats, games, weeks, lambda, eval_ids) {
  d <- merge(feats, games[, .(game_id, margin = home_score - away_score)], by = "game_id")
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv()))
  set.seed(BT_CANARY_SEED, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  d[, canary := margin + stats::rnorm(.N)]
  d[, src_end_canary := pmax(src_end, kickoff + 3.5 * 3600, na.rm = TRUE)]
  rejected <- tryCatch({ bt_assert_asof(d$src_end_canary, d$kickoff, "canary"); FALSE },
                       error = function(e) grepl("as-of violation", conditionMessage(e)))

  # (b) bypass: fit with the canary as an extra feature on the evaluation weeks
  ev_weeks <- weeks[wk %in% games[game_id %in% eval_ids, unique(wk)]]
  d[, margin := NULL]
  p <- bt_epa_walk_forward(d, games, ev_weeks, lambda, features = c(BT_EPA_FEATURES, "canary"))
  s <- merge(p, games[, .(game_id, y, p_c0)], by = "game_id")[game_id %in% eval_ids & !is.na(y)]
  skill <- 1 - mean((s$p_c2 - s$y)^2) / mean((s$p_c0 - s$y)^2)
  list(assertion_rejected = rejected, bypass_skill = skill,
       bypass_flagged = skill > BT_IMPLAUSIBLE_SKILL,
       passed = rejected && skill > BT_IMPLAUSIBLE_SKILL)
}

#' Global permutation of result tuples (home_score, away_score) across all played
#' games. A within-week permutation keeps each week's home-win count, which
#' correlates with the market's weekly mean home probability, so market-anchored
#' candidates would keep real week-level information (PROTOCOL.md, controls).
bt_shuffle_scores <- function(games, seed = BT_SHUFFLE_SEED) {
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv()))
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  g <- copy(games)
  idx <- which(!is.na(g$home_score) & !is.na(g$away_score))
  perm <- idx[sample.int(length(idx))]
  g[idx, `:=`(home_score = games$home_score[perm], away_score = games$away_score[perm])]
  g[, played := !is.na(home_score) & !is.na(away_score)]
  g[, tie := played & home_score == away_score]
  g[, y := fifelse(played & !tie, as.integer(home_score > away_score), NA_integer_)]
  g[]
}

#' Expanding-window home-win rate before each week (climatology forecast)
bt_climatology <- function(games, weeks) {
  played <- games[!is.na(y)]
  rbindlist(lapply(seq_len(nrow(weeks)), function(i) {
    prior <- played[kickoff < weeks$cutoff[i]]
    data.table(wk = weeks$wk[i], p_clim = mean(prior$y))
  }))
}
