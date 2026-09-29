# =============================================================================
# C0 market: no-vig closing moneyline (nflverse consensus close), proportional devig.
# C0o market at open: ESPN BET opening moneyline, proportional devig (decision-time
# reference for CLV; 2024 in the Confirm window). Not a scored Brier candidate.
# =============================================================================

bt_market_close <- function(games) games[, .(game_id, p_c0)]

#' ESPN BET open/close no-vig home probabilities and the prices taken
bt_market_open_close <- function(espn) {
  e <- espn[provider_name == "ESPN BET"]
  e[, `:=`(p_open = bt_novig_home(h_open, a_open), p_close_venue = bt_novig_home(h_close, a_close))]
  e[is.finite(p_open) & is.finite(p_close_venue),
    .(game_id, p_open, p_close_venue, h_open, a_open, h_close, a_close)]
}
