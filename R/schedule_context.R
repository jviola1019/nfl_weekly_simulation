# Schedule context for the game model: neutral sites (audit M24) and rest (audit M23).
# Pure functions of nflverse schedule columns, used for the current week and for the
# calibration-history simulator in NFLsimulation.R.

# The franchises that moved since 2015, by their old code (audit F11b). nflverse play-by-play
# uses the current code in every season; its schedules and injuries keep the old one.
TEAM_FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA")

#' Current franchise code for a team code, so pre-move games join the play-by-play (F11b)
#' @param team character team codes (NA stays NA)
#' @return the codes with OAK, SD and STL replaced by LV, LAC and LA
franchise_code <- function(team) {
  team <- as.character(team)
  moved <- !is.na(team) & team %in% names(TEAM_FRANCHISE)
  team[moved] <- unname(TEAM_FRANCHISE[team[moved]])
  team
}

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

#' Home-field points per team (output audit F11)
#'
#' Each team's mean home margin, shrunk toward the league value with weight n / (n + shrink_n),
#' for every team in `teams`: a team with no home game gets the league value, and DEN gets the
#' altitude bonus. The calibration backtest joins this for every team of every past week, so it
#' must not be limited to the teams on the slate being simulated (a bye team got no value, and
#' every one of its calibration games became a 21.5-21.5 coin flip).
#' @param home_margins one row per non-neutral REG home game: team_home, margin (NA if unplayed)
#' @param teams the teams that need a value
#' @return tibble(team, hfa), one row per element of `teams`
team_hfa_table <- function(home_margins, teams, league_hfa, den_bonus = 0, shrink_n = 60) {
  by_team <- home_margins |>
    dplyr::group_by(team_home) |>
    dplyr::summarise(hfa_raw = mean(margin, na.rm = TRUE), n = dplyr::n(), .groups = "drop") |>
    dplyr::mutate(w = n / (n + shrink_n), hfa = w * hfa_raw + (1 - w) * league_hfa) |>
    dplyr::transmute(team = team_home, hfa)
  tibble::tibble(team = teams) |>
    dplyr::left_join(by_team, by = "team") |>
    dplyr::mutate(
      hfa = dplyr::coalesce(hfa, league_hfa),
      hfa = ifelse(team == "DEN", hfa + den_bonus, hfa)
    )
}

#' Stop when a week's simulated means are not finite (output audit F11)
#'
#' simulate_game_nb would otherwise replace them with 21.5 each, a coin flip, without a word.
#' The message names every other column that is missing in those games, with up to three of
#' its games, so the input that broke the mean is in the error itself.
#' @param g one row per game: game_id, mu_home, mu_away, and the inputs of the means
#' @param where label for the message, e.g. "calibration 2024 week 3"
assert_finite_means <- function(g, where) {
  bad <- !is.finite(g$mu_home) | !is.finite(g$mu_away)
  if (any(bad)) {
    rows <- g[bad, setdiff(names(g), c("game_id", "mu_home", "mu_away")), drop = FALSE]
    ids <- g$game_id[bad]
    missing <- names(rows)[vapply(rows, function(x) any(is.na(x)), logical(1))]
    detail <- if (length(missing)) {
      sprintf("; missing inputs: %s", paste(vapply(utils::head(missing, 12), function(col)
        sprintf("%s (%s)", col, paste(utils::head(ids[is.na(rows[[col]])], 3), collapse = ", ")), ""),
        collapse = "; "))
    } else ""
    stop(sprintf("%s: %d game(s) without a finite mean: %s%s", where, sum(bad),
                 paste(utils::head(ids, 10), collapse = ", "), detail), call. = FALSE)
  }
  invisible(g)
}
