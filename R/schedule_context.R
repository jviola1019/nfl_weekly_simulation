# Schedule context for the game model: neutral sites (audit M24) and rest (audit M23).
# Pure functions of nflverse schedule columns, used for the current week and for the
# calibration-history simulator in NFLsimulation.R.

#' Neutral-site flag (audit M24)
#'
#' nflverse marks neutral sites (international games, the Super Bowl) with
#' location == "Neutral". A missing column or an unknown value stops the run.
#' @param sched schedule rows with a `location` column (and `game_id` for messages)
#' @return logical vector, one value per row
neutral_site_flag <- function(sched) {
  if (!"location" %in% names(sched)) {
    stop("neutral_site_flag: schedule has no 'location' column (audit M24)", call. = FALSE)
  }
  loc <- as.character(sched$location)
  bad <- is.na(loc) | !loc %in% c("Home", "Neutral")
  if (any(bad)) {
    ids <- if ("game_id" %in% names(sched)) sched$game_id[bad] else which(bad)
    stop("neutral_site_flag: missing or unknown location for ", paste(utils::head(ids, 10), collapse = ", "),
         call. = FALSE)
  }
  loc == "Neutral"
}

#' Home-field points for the home team (audit M24)
#'
#' Team HFA (the league value when missing) times the playoff multiplier, capped at +/-6,
#' and zero at a neutral site.
home_field_points <- function(home_hfa, league_hfa, playoff_mult, neutral_site) {
  pts <- dplyr::coalesce(home_hfa, league_hfa) * playoff_mult
  pts <- pmin(pmax(pts, -6), 6)
  dplyr::if_else(neutral_site, 0, pts)
}

#' Rest points for each team on a slate (audit M23)
#'
#' Rest days come from the schedule row of the team's own game (nflverse home_rest /
#' away_rest), not from the week's first kickoff. A bye means the team's latest game this
#' season was two or more weeks earlier; it earns the bye bonus instead of the long-rest
#' bonus. nflverse gives week 1 seven days, so week 1 is neutral.
#' @param slate one row per game: game_id, home_team, away_team, home_rest, away_rest
#' @param team_games completed games, one row per team-game: team, season, week
#' @return tibble(team, days_rest, rest_points), one row per slate team
compute_rest_table <- function(slate, team_games, season, week,
                               short_penalty = REST_SHORT_PENALTY, long_bonus = REST_LONG_BONUS,
                               bye_bonus = BYE_BONUS) {
  per_team <- data.frame(game_id = c(slate$game_id, slate$game_id),
                         team = c(slate$home_team, slate$away_team),
                         days_rest = as.numeric(c(slate$home_rest, slate$away_rest)),
                         stringsAsFactors = FALSE)
  if (anyDuplicated(per_team$team)) {
    stop("compute_rest_table: a team appears twice on the slate: ",
         paste(unique(per_team$team[duplicated(per_team$team)]), collapse = ", "), call. = FALSE)
  }
  if (any(!is.finite(per_team$days_rest))) {
    stop("compute_rest_table: no rest days for ",
         paste(unique(per_team$game_id[!is.finite(per_team$days_rest)]), collapse = ", "), call. = FALSE)
  }
  prior <- team_games[team_games$season == season & team_games$week < week, c("team", "week")]
  last_week <- if (nrow(prior)) tapply(prior$week, prior$team, max) else integer()
  prev <- as.vector(last_week[per_team$team])   # tapply returns a 1-d array; drop dim and names
  bye_prev <- !is.na(prev) & (week - prev) >= 2
  rest_points <- ifelse(per_team$days_rest <= 6, short_penalty, 0) +
    ifelse(per_team$days_rest >= 9 & !bye_prev, long_bonus, 0) +
    ifelse(bye_prev, bye_bonus, 0)
  tibble::tibble(team = per_team$team, days_rest = per_team$days_rest, rest_points = rest_points)
}
