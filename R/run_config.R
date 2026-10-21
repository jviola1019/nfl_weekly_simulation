# =============================================================================
# Run configuration: CLI week/season -> R options read by config.R (audit M1)
# =============================================================================

#' Parse `Rscript run_week.R [week] [season]` arguments
parse_run_args <- function(args) {
  out <- list(week = NA_integer_, season = NA_integer_)
  if (length(args) >= 1) {
    wk <- suppressWarnings(as.integer(args[[1]]))
    if (is.na(wk) || wk < 1L || wk > 22L) stop("Invalid week number: must be 1-22 (got '", args[[1]], "')", call. = FALSE)
    out$week <- wk
  }
  if (length(args) >= 2) {
    ss <- suppressWarnings(as.integer(args[[2]]))
    if (is.na(ss) || ss < 2011L || ss > 2030L) stop("Invalid season: must be 2011-2030 (got '", args[[2]], "')", call. = FALSE)
    out$season <- ss
  }
  out
}

#' Publish parsed values as options so every source("config.R") derives from them
set_run_options <- function(parsed) {
  if (!is.na(parsed$week)) options(nfl.week = parsed$week)
  if (!is.na(parsed$season)) options(nfl.season = parsed$season)
  invisible(parsed)
}

# -----------------------------------------------------------------------------
# Which week to run (C1, 2026-10-20). config.R used to default to 2025 week 22. A run with no
# week now takes the upcoming week from the nflverse schedule; base R only, because run_week.R
# resolves before config.R and the engine load.
# -----------------------------------------------------------------------------

NFL_TZ <- "America/New_York"

#' The season a date belongs to: January and February are the previous season's playoffs
nfl_season_of <- function(now = Sys.time()) {
  d <- as.POSIXlt(now, tz = NFL_TZ)
  y <- d$year + 1900L
  as.integer(if (d$mon < 2L) y - 1L else y)   # $mon is 0-based: 0 = January, 1 = February
}

#' Calendar estimate of the week, with no network: weeks run Tuesday to Monday, and week 1 is
#' the week of the opener, the Thursday after Labor Day (the first Monday of September). It is
#' clamped to 1-22: before the season it is week 1, and from the bye week before the Super Bowl
#' until March it is 22. config.R uses it only when run_week.R has not set the week.
nfl_calendar_week <- function(now = Sys.time()) {
  season <- nfl_season_of(now)
  day <- as.Date(format(now, "%Y-%m-%d", tz = NFL_TZ))
  sep1 <- as.Date(sprintf("%d-09-01", season))
  labor_day <- sep1 + (8L - as.integer(format(sep1, "%u"))) %% 7L   # %u: Monday = 1
  week1_tuesday <- labor_day + 1L
  week <- as.integer(floor(as.numeric(day - week1_tuesday) / 7)) + 1L
  list(season = season, week = min(max(week, 1L), 22L))
}

#' The week a forward-looking run simulates: the earliest week of the schedule that still has a
#' game to kick off (regular season and playoffs). Kickoffs are nflverse `gameday` and `gametime`
#' in Eastern time; a game without a date is not counted, one without a time counts from midnight.
#' Stops when nothing is left to kick off, so a run never falls back to a default week.
resolve_target_week <- function(schedule, now = Sys.time()) {
  dated <- schedule[!is.na(schedule$gameday), , drop = FALSE]
  kickoff <- as.POSIXct(paste(dated$gameday, ifelse(is.na(dated$gametime), "00:00", dated$gametime)),
                        format = "%Y-%m-%d %H:%M", tz = NFL_TZ)
  ahead <- !is.na(kickoff) & kickoff > now
  if (!any(ahead)) {
    stop("No game in the schedule is still to kick off (the season is over or not yet published): ",
         "pass a week and season, e.g. Rscript run_week.R 15 2024", call. = FALSE)
  }
  week <- min(dated$week[ahead])
  in_week <- dated$week == week
  list(season = as.integer(dated$season[in_week][1]), week = as.integer(week),
       n_games = sum(in_week), first_kickoff = min(kickoff[in_week]))
}

#' Fill a missing week or season. An explicit week and season are kept as given (the schedule is
#' not loaded); a week alone means the season in progress; with no week, the upcoming week comes
#' from the schedule, and a schedule that cannot load stops the run with the command to use.
resolve_run_target <- function(parsed, now = Sys.time(),
                               load_schedule = function(season) nflreadr::load_schedules(seasons = season)) {
  season <- if (is.na(parsed$season)) nfl_season_of(now) else parsed$season
  if (!is.na(parsed$week)) return(list(week = parsed$week, season = as.integer(season)))
  schedule <- tryCatch(load_schedule(season), error = function(e) {
    stop(sprintf("Cannot resolve the week: the %d schedule did not load (%s). Pass a week and season: Rscript run_week.R <week> <season>",
                 season, conditionMessage(e)), call. = FALSE)
  })
  target <- resolve_target_week(schedule, now)
  first <- as.POSIXlt(target$first_kickoff, tz = NFL_TZ)
  day_name <- c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")[first$wday + 1L]
  message(sprintf("Auto-resolved %d week %d (%d games, first kickoff %s %s ET)", target$season, target$week,
                  target$n_games, day_name, format(target$first_kickoff, "%Y-%m-%d %H:%M", tz = NFL_TZ)))
  list(week = target$week, season = target$season)
}
