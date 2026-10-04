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
