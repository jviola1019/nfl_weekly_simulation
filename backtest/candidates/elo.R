# =============================================================================
# C1 Elo (FiveThirtyEight NFL Elo form, public nfl_elo.py):
#   p_home = 1 / (1 + 10^(-(R_home - R_away + HFA * !neutral) / 400))
#   shift  = K * ln(max(|margin|, 1) + 1) * 2.2 / (winner_elo_diff * 0.001 + 2.2) * (result - p_home)
# Between seasons every rating regresses toward the mean: R <- (1 - regress) * R + regress * mean.
# Ratings start in 1999 at the mean. The starting-QB adjustment is off in v1.
# Predictions for a game use only results of games that kicked off earlier.
# =============================================================================

BT_ELO_MEAN <- 1505

#' Run Elo over `games` (ordered by kickoff). `home_score`/`away_score` may be
#' replaced (shuffled-label control). Returns data.table(game_id, p_c1).
bt_elo_run <- function(games, K, hfa, regress, home_score = games$home_score, away_score = games$away_score) {
  n <- nrow(games)
  teams <- sort(unique(c(games$home_franchise, games$away_franchise)))
  R <- setNames(rep(BT_ELO_MEAN, length(teams)), teams)
  p_out <- numeric(n)
  season_now <- games$season[1]
  hf <- games$home_franchise; af <- games$away_franchise
  neutral <- games$neutral; seas <- games$season
  for (i in seq_len(n)) {
    if (seas[i] != season_now) {
      R <- (1 - regress) * R + regress * BT_ELO_MEAN
      season_now <- seas[i]
    }
    h <- hf[i]; a <- af[i]
    elo_diff <- R[[h]] - R[[a]] + if (neutral[i]) 0 else hfa
    p <- 1 / (1 + 10^(-elo_diff / 400))
    p_out[i] <- p
    hs <- home_score[i]; as <- away_score[i]
    if (is.na(hs) || is.na(as)) next
    margin <- hs - as
    result <- if (margin > 0) 1 else if (margin < 0) 0 else 0.5
    denom <- if (result == 0.5) 1 else ((if (result == 1) elo_diff else -elo_diff) * 0.001 + 2.2)
    mult <- log(max(abs(margin), 1) + 1) * (2.2 / denom)
    shift <- K * mult * (result - p)
    R[[h]] <- R[[h]] + shift
    R[[a]] <- R[[a]] - shift
  }
  data.table(game_id = games$game_id, p_c1 = p_out)
}

BT_ELO_GRID <- CJ(K = c(15, 20, 25, 30), hfa = c(20, 30, 40, 55, 70), regress = c(0.20, 1 / 3, 0.45, 0.60))
