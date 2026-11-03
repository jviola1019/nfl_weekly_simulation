#!/usr/bin/env Rscript
# The model gauntlet's drive table (PLAN.md, family F9): one row per team-game of 2006-2022, the team's drives and
# how they ended, from nflverse play-by-play release files (keyless; at most one request per second). Writes
# backtest/data/drive_games.csv and backtest/data/drive_games_sources.json (each raw file's url, sha256 and size).
# Nothing after 2022 is downloaded or read.
#   Rscript reports/2026-11-03/model-gauntlet/build_drives.R <raw cache dir>
suppressPackageStartupMessages(library(data.table))
source(file.path("backtest", "common.R"))
MG_DRIVE_SEASONS <- 2006:2022
MG_PBP_BASE <- "https://github.com/nflverse/nflverse-data/releases/download/pbp"
MG_FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA")   # as backtest/build_inputs.R

#' Drives of one season by team-game: the count and how many ended in a touchdown, a field goal, a touchdown by the
#' defence ("Opp touchdown") or a safety (nflfastR's fixed_drive_result)
mg_drives_one_season <- function(pbp) {
  p <- as.data.table(pbp)[!is.na(posteam) & !is.na(fixed_drive) & season_type %in% c("REG", "POST"),
                          .(game_id, posteam, defteam, fixed_drive, fixed_drive_result)]
  d <- p[, .(result = fixed_drive_result[1], opp = defteam[1]), by = .(game_id, posteam, fixed_drive)]
  d[, .(drives = .N, td = sum(result == "Touchdown", na.rm = TRUE), fg = sum(result == "Field goal", na.rm = TRUE),
        def = sum(result == "Opp touchdown", na.rm = TRUE), safety = sum(result == "Safety", na.rm = TRUE)),
    by = .(game_id, team = posteam, opp)]
}

main <- function() {
  raw <- commandArgs(trailingOnly = TRUE)[1]
  if (is.na(raw)) stop("usage: build_drives.R <raw cache dir>")
  dir.create(raw, recursive = TRUE, showWarnings = FALSE)
  games <- fread(file.path("backtest", "data", "games.csv"), na.strings = c("", "NA"),
                 colClasses = list(character = c("home_qb_id", "away_qb_id", "gametime")))[season <= max(MG_DRIVE_SEASONS)]
  meta <- list(); parts <- list()
  for (s in MG_DRIVE_SEASONS) {
    url <- sprintf("%s/play_by_play_%d.rds", MG_PBP_BASE, s)
    f <- file.path(raw, basename(url))
    if (!file.exists(f)) {
      Sys.sleep(1)
      utils::download.file(url, f, mode = "wb", quiet = TRUE)
    }
    meta[[length(meta) + 1]] <- list(file = basename(f), url = url, sha256 = digest::digest(file = f, algo = "sha256"), bytes = file.size(f))
    parts[[length(parts) + 1]] <- mg_drives_one_season(readRDS(f))
    message(sprintf("%d: %d team-games", s, nrow(parts[[length(parts)]])))
  }
  d <- rbindlist(parts)
  d[, `:=`(team = ifelse(team %in% names(MG_FRANCHISE), MG_FRANCHISE[team], team),
           opp = ifelse(opp %in% names(MG_FRANCHISE), MG_FRANCHISE[opp], opp))]
  g <- games[, .(game_id, kickoff_utc, home_franchise, away_franchise, home_score, away_score)]
  d <- merge(d, g, by = "game_id")
  stopifnot(all(d$team == d$home_franchise | d$team == d$away_franchise))
  d[, home := as.integer(team == home_franchise)]
  # sanity: the points a team's drives produce against its final score (special-teams scores and tries make them differ)
  d[, pts_drives := 7 * td + 3 * fg]
  d[, score := fifelse(home == 1L, home_score, away_score)]
  chk <- d[, .(mae = mean(abs(pts_drives - score)), cor = stats::cor(pts_drives, score), two_rows = all(d[, .N, by = game_id]$N == 2))]
  message(sprintf("drive points against final scores: MAE %.2f, correlation %.3f, every game has two rows: %s", chk$mae, chk$cor, chk$two_rows))
  out <- d[, .(game_id, kickoff_utc, team, opp, home, drives, td, fg, def, safety)]
  setorder(out, kickoff_utc, game_id, team)
  bt_write_csv(out, file.path("backtest", "data", "drive_games.csv"))
  src <- list(built_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), seasons = range(MG_DRIVE_SEASONS),
              rows = nrow(out), sha256 = digest::digest(file = file.path("backtest", "data", "drive_games.csv"), algo = "sha256"),
              check = chk, raw = meta)
  bt_write_text(jsonlite::toJSON(src, auto_unbox = TRUE, pretty = TRUE), file.path("backtest", "data", "drive_games_sources.json"))
  message(sprintf("wrote %d rows", nrow(out)))
}

main()
