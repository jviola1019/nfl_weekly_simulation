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
