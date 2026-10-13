# Explicit composition of the simulated mean scores (audit M22, Plan 1b-1).
#
# The adjustment chain in NFLsimulation.R computes many terms, in points per side. Until
# Plan 1b-1 a non-finite turnover term silently reduced the simulated means to drives x
# points per drive (+ home field). The means are now the sum of the terms named in
# config.R MU_TERMS_ADMITTED. Every other term is still computed and logged
# (run_logs/mu_terms_*.rds) so its size stays visible; it enters the means only after the
# pre-registered walk-forward backtest admits it (Plan 1b-3).

MU_TERM_NAMES <- c("base", "hfa", "glmm", "qb", "rest", "injury", "travel", "div_conf",
                   "pressure", "explosive", "location", "special_teams", "situational",
                   "turnover", "weather")

MU_COMPONENT_COLUMNS <- c(
  "game_id", "exp_drives_home", "exp_ppd_home", "exp_drives_away", "exp_ppd_away", "HFA_pts",
  "glmm_w", "mu_home_glmm", "mu_away_glmm", "mu_home_model", "mu_away_model",
  "home_off_points_adj", "away_off_points_adj", "home_rest_points", "away_rest_points",
  "home_injury_off_total", "away_injury_off_total", "home_injury_def_total", "away_injury_def_total",
  "travel_mu_adj_home", "travel_mu_adj_away", "div_conf_adj",
  "home_press_mismatch", "away_press_mismatch", "expl_edge_home", "expl_edge_away",
  "home_location_boost", "away_location_penalty", "st_impact_home", "st_impact_away",
  "rz_impact_home", "rz_impact_away", "third_down_edge_home", "third_down_edge_away",
  "to_edge_home", "to_edge_away", "penalty_edge_home", "penalty_edge_away",
  "situational_home", "situational_away", "momentum_home", "momentum_away",
  "div_adjustment_home", "div_adjustment_away", "home_to_adj", "away_to_adj",
  "env_total_adj", "mu_home_adj", "mu_away_adj",
  "wind_interaction_home", "wind_interaction_away", "cold_interaction_home", "cold_interaction_away")

#' Per-game points for every mean term, home and away (audit M22)
#'
#' Each term repeats the expression the adjustment chain in NFLsimulation.R adds to the
#' legacy mean, so the terms sum to that chain's total exactly where no clamp binds.
#' @param games games_ready after the environment block
#' @param pressure_pts config PRESSURE_MISMATCH_PTS (points per +10% pressure mismatch)
#' @return list(home = , away = ): data frames of game_id plus one column per MU_TERM_NAMES
mu_components <- function(games, pressure_pts) {
  missing <- setdiff(MU_COMPONENT_COLUMNS, names(games))
  if (length(missing)) stop("mu_components: games is missing ", paste(missing, collapse = ", "), call. = FALSE)
  g <- games
  home <- data.frame(
    game_id       = g$game_id,
    base          = g$exp_drives_home * g$exp_ppd_home,   # expected drives x points per drive
    hfa           = g$HFA_pts,
    glmm          = g$glmm_w * (dplyr::coalesce(g$mu_home_glmm, g$mu_home_model) - g$mu_home_model),
    qb            = g$home_off_points_adj,
    rest          = g$home_rest_points,
    injury        = g$home_injury_off_total + g$away_injury_def_total,
    travel        = dplyr::coalesce(g$travel_mu_adj_home, 0),
    div_conf      = g$div_conf_adj,
    pressure      = -pressure_pts * g$home_press_mismatch,
    explosive     = 0.16 * 5 * g$expl_edge_home,
    location      = 0.7 * g$home_location_boost,
    special_teams = 0.7 * g$st_impact_home,
    situational   = 0.7 * (g$rz_impact_home + g$third_down_edge_home + g$to_edge_home +
                           g$penalty_edge_home + g$situational_home + g$momentum_home +
                           g$div_adjustment_home),
    turnover      = g$home_to_adj,
    weather       = g$env_total_adj / 2 + g$mu_home_adj + g$wind_interaction_home + g$cold_interaction_home,
    stringsAsFactors = FALSE
  )
  away <- data.frame(
    game_id       = g$game_id,
    base          = g$exp_drives_away * g$exp_ppd_away,
    hfa           = 0,
    glmm          = g$glmm_w * (dplyr::coalesce(g$mu_away_glmm, g$mu_away_model) - g$mu_away_model),
    qb            = g$away_off_points_adj,
    rest          = g$away_rest_points,
    injury        = g$away_injury_off_total + g$home_injury_def_total,
    travel        = dplyr::coalesce(g$travel_mu_adj_away, 0),
    div_conf      = g$div_conf_adj,
    pressure      = -pressure_pts * g$away_press_mismatch,
    explosive     = 0.16 * 5 * g$expl_edge_away,
    location      = 0.7 * g$away_location_penalty,
    special_teams = 0.7 * g$st_impact_away,
    situational   = 0.7 * (g$rz_impact_away + g$third_down_edge_away + g$to_edge_away +
                           g$penalty_edge_away + g$situational_away + g$momentum_away +
                           g$div_adjustment_away),
    turnover      = g$away_to_adj,
    weather       = g$env_total_adj / 2 + g$mu_away_adj + g$wind_interaction_away + g$cold_interaction_away,
    stringsAsFactors = FALSE
  )
  list(home = home, away = away)
}

#' Simulated means: the sum of the admitted terms (audit M22)
#'
#' Terms are summed in MU_TERM_NAMES order, so the result does not depend on how config
#' lists them. A non-finite admitted term or a mean that is not positive stops the run;
#' nothing is substituted.
#' @param components output of mu_components()
#' @param admitted character vector of term names; must include "base"
#' @return data.frame(game_id, mu_home, mu_away)
compose_mu <- function(components, admitted) {
  unknown <- setdiff(admitted, MU_TERM_NAMES)
  if (length(unknown)) stop("compose_mu: unknown term(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  if (!"base" %in% admitted) stop("compose_mu: 'base' (drives x points per drive) must be admitted", call. = FALSE)
  if (!identical(components$home$game_id, components$away$game_id)) {
    stop("compose_mu: home and away components are not aligned", call. = FALSE)
  }
  terms <- MU_TERM_NAMES[MU_TERM_NAMES %in% admitted]
  side_mu <- function(comp, side) {
    bad <- lapply(terms, function(t) comp$game_id[!is.finite(comp[[t]])])
    names(bad) <- terms
    bad <- bad[lengths(bad) > 0]
    if (length(bad)) {
      stop(sprintf("compose_mu: admitted term not finite (%s): %s", side,
                   paste(sprintf("%s [%s]", names(bad), vapply(bad, paste, character(1), collapse = ", ")),
                         collapse = "; ")), call. = FALSE)
    }
    mu <- Reduce(`+`, lapply(terms, function(t) comp[[t]]))
    if (any(mu <= 0)) {
      stop(sprintf("compose_mu: %s mean not positive for %s", side, paste(comp$game_id[mu <= 0], collapse = ", ")),
           call. = FALSE)
    }
    mu
  }
  data.frame(game_id = components$home$game_id,
             mu_home = side_mu(components$home, "home"),
             mu_away = side_mu(components$away, "away"),
             stringsAsFactors = FALSE)
}
