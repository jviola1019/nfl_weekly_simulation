# =============================================================================
# nfl_preclose_v1: v1's Elo (backtest/candidates/elo.R) on both information sets.
#   p_elo_b  ratings before each game, as v1's bt_elo_run (IS-B)
#   p_elo_a  the ratings as they stood after week w-2 of the same season, or at the
#            season's start for weeks 1-2 (IS-A: games before the first kickoff of w-1)
# The rating updates are v1's; IS-A only reads an older snapshot. The same as
# reports/2026-10-29/hypotheses/opener_timing_elo.R.
# =============================================================================

pc_elo <- function(games, K, hfa, regress) {
  n <- nrow(games); teams <- sort(unique(c(games$home_franchise, games$away_franchise)))
  R <- setNames(rep(BT_ELO_MEAN, length(teams)), teams)
  pB <- pA <- numeric(n); snaps <- list(); s_now <- games$season[1]; w_now <- games$week[1]
  snaps[[sprintf("%d_0", s_now)]] <- R
  for (i in seq_len(n)) {
    if (games$season[i] != s_now) {
      snaps[[sprintf("%d_%d", s_now, w_now)]] <- R
      R <- (1 - regress) * R + regress * BT_ELO_MEAN; s_now <- games$season[i]; w_now <- games$week[i]
      snaps[[sprintf("%d_0", s_now)]] <- R
    } else if (games$week[i] != w_now) {
      snaps[[sprintf("%d_%d", s_now, w_now)]] <- R; w_now <- games$week[i]
    }
    h <- games$home_franchise[i]; a <- games$away_franchise[i]; hf <- if (games$neutral[i]) 0 else hfa
    pB[i] <- 1 / (1 + 10^(-(R[[h]] - R[[a]] + hf) / 400))
    have <- as.integer(sub("^[0-9]+_", "", grep(sprintf("^%d_", s_now), names(snaps), value = TRUE)))
    RA <- snaps[[sprintf("%d_%d", s_now, max(have[have <= games$week[i] - 2L], 0L))]]
    pA[i] <- 1 / (1 + 10^(-(RA[[h]] - RA[[a]] + hf) / 400))
    if (is.na(games$home_score[i]) || is.na(games$away_score[i])) next
    margin <- games$home_score[i] - games$away_score[i]; result <- if (margin > 0) 1 else if (margin < 0) 0 else 0.5
    elo_diff <- R[[h]] - R[[a]] + hf
    denom <- if (result == 0.5) 1 else ((if (result == 1) elo_diff else -elo_diff) * 0.001 + 2.2)
    shift <- K * log(max(abs(margin), 1) + 1) * (2.2 / denom) * (result - pB[i])
    R[[h]] <- R[[h]] + shift; R[[a]] <- R[[a]] - shift
  }
  data.table(game_id = games$game_id, p_elo_b = pB, p_elo_a = pA)
}
