#!/usr/bin/env Rscript
# =============================================================================
# F11 diagnosis (output audit 2026-10-21, "F11 resolved"): which mean term is
# NA for the calibration games that simulate_game_nb() silently replaces with
# 21.5. It edits nothing in the engine.
#
#   HOME=<empty dir> Rscript scripts/diagnose_mu_na.R <week> <season> <out_dir>
#
# A fresh HOME is required: a cached calibration (~/.cache/nfl_sim_calib_cache)
# skips week_inputs_and_sim_2w() and hides the NA, so the script refuses to run
# with one. It runs run_week.R in this process. A calling handler catches each
# "simulate_game_nb: invalid mu_" warning, finds the frame of
# week_inputs_and_sim_2w() (it holds g, cut_season and cut_week) and the
# lapply() closure below it that holds i, and records that game's mean terms.
# The warning is not muffled, so the run behaves as production does.
# Seal: a week of season S calibrates on seasons S-5 to S-1
# (NFLsimulation.R calib_seasons), so a 2024 week reads no 2025 game. A sealed
# season is refused as the target, and rows whose cut season is sealed are
# counted but never written.
# Writes <out_dir>/mu_na_terms.csv (one row per game), mu_na_summary.csv (how
# often each term is NA) and mu_na_teams.csv (teams in those games).
# =============================================================================

DMN_TERMS <- c("game_id", "home_team", "away_team", "neutral_site", "home_hfa", "away_hfa", "home_rest_points",
               "away_rest_points", "home_off_drives_pg", "home_def_drives_pg", "away_off_drives_pg", "away_def_drives_pg",
               "home_off_ppd", "home_def_ppd", "away_off_ppd", "away_def_ppd", "exp_drives_home", "exp_drives_away",
               "exp_ppd_home", "exp_ppd_away", "mu_home_base", "mu_away_base", "margin_shift", "mu_home", "mu_away")
DMN_PATTERN <- "^simulate_game_nb: invalid mu_(home|away)="

#' The calibration game being simulated, from the call frames: the innermost
#' frame holding g, cut_season and cut_week, and the lapply() closure under it
#' that holds i
dmn_find_game <- function(frames) {
  k <- NA_integer_
  for (j in seq_along(frames)) {
    if (all(vapply(c("g", "cut_season", "cut_week"), exists, logical(1), envir = frames[[j]], inherits = FALSE))) k <- j
  }
  if (is.na(k)) return(NULL)
  for (j in rev(seq_along(frames))) {
    if (j > k && exists("i", envir = frames[[j]], inherits = FALSE) && identical(parent.env(frames[[j]]), frames[[k]])) {
      g <- as.data.frame(get("g", envir = frames[[k]]))
      miss <- setdiff(DMN_TERMS, names(g))           # a renamed engine column stops the run (review I7)
      if (length(miss)) {
        stop("diagnose_mu_na: the engine's g has no column ", paste(miss, collapse = ", "), "; update DMN_TERMS",
             call. = FALSE)
      }
      row <- g[get("i", envir = frames[[j]]), DMN_TERMS, drop = FALSE]
      return(cbind(data.frame(cut_season = get("cut_season", envir = frames[[k]]),
                              cut_week = get("cut_week", envir = frames[[k]])), row))
    }
  }
  NULL
}

#' Run `run()` and record every game whose simulated mean is invalid
dmn_capture <- function(run, sealed) {
  rows <- list()
  n_sealed <- 0L
  n_unlocated <- 0L
  withCallingHandlers(run(), warning = function(w) {
    if (!grepl(DMN_PATTERN, conditionMessage(w))) return(invisible(NULL))
    r <- dmn_find_game(sys.frames())
    if (is.null(r)) {
      n_unlocated <<- n_unlocated + 1L
    } else if (r$cut_season %in% sealed) {
      n_sealed <<- n_sealed + 1L
    } else {
      rows[[length(rows) + 1L]] <<- r
    }
    invisible(NULL)
  })
  x <- if (length(rows)) unique(data.table::rbindlist(rows, fill = TRUE)) else data.table::data.table()
  list(rows = x, warnings_sealed = n_sealed, warnings_unlocated = n_unlocated)
}

#' How often each recorded term is NA, over the recorded games
dmn_summarise <- function(rows) {
  terms <- setdiff(intersect(DMN_TERMS, names(rows)), c("game_id", "home_team", "away_team"))
  data.table::data.table(term = terms, n_na = vapply(terms, function(t) sum(is.na(rows[[t]])), integer(1)),
                         n_games = nrow(rows))
}

#' Stop if the target season is sealed
dmn_check_target <- function(season, sealed) {
  if (as.integer(season) %in% sealed) stop("diagnose_mu_na: season ", season, " is sealed", call. = FALSE)
  invisible(TRUE)
}

#' Stop if a calibration is cached under `home`: it would skip week_inputs_and_sim_2w() and hide F11
dmn_check_cache <- function(home = path.expand("~")) {
  cache <- file.path(home, ".cache", "nfl_sim_calib_cache")
  if (length(list.files(cache, pattern = "\\.rds$"))) {
    stop("diagnose_mu_na: ", cache, " holds a cached calibration, which would hide F11; run with HOME=<empty dir>", call. = FALSE)
  }
  invisible(TRUE)
}

dmn_main <- function(args) {
  if (length(args) < 3L) stop("usage: HOME=<empty dir> Rscript scripts/diagnose_mu_na.R <week> <season> <out_dir>", call. = FALSE)
  out_dir <- args[3]
  vvf <- new.env()
  sys.source(file.path("backtest", "common.R"), envir = vvf)
  sys.source(file.path("backtest", "vvf", "common.R"), envir = vvf)
  sealed <- vvf$vvf_sealed_seasons()
  dmn_check_target(args[2], sealed)
  dmn_check_cache()
  options(warn = 1)
  res <- dmn_capture(function() source("run_week.R"), sealed)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  rows <- res$rows
  vvf$vvf_write_csv(rows, file.path(out_dir, "mu_na_terms.csv"))
  vvf$vvf_write_csv(dmn_summarise(rows), file.path(out_dir, "mu_na_summary.csv"))
  teams <- if (nrow(rows)) data.table::as.data.table(table(team = c(rows$home_team, rows$away_team)))[order(-N)] else
    data.table::data.table(team = character(), N = integer())
  vvf$vvf_write_csv(teams, file.path(out_dir, "mu_na_teams.csv"))
  cat(sprintf("\nF11 diagnosis: %d calibration games with an invalid mean (%s); %d warnings in sealed seasons; %d unlocated\n",
              nrow(rows), if (nrow(rows)) paste(sort(unique(rows$cut_season)), collapse = ", ") else "none",
              res$warnings_sealed, res$warnings_unlocated))
  print(dmn_summarise(rows))
  invisible(res)
}

if (sys.nframe() == 0L) dmn_main(commandArgs(trailingOnly = TRUE))
