#!/usr/bin/env Rscript
# =============================================================================
# Game backtest v1: build the committed, point-in-time inputs from raw nflverse
# release files (docs/superpowers/specs/2026-09-29-model-shootout-design.md).
#
#   Rscript backtest/build_inputs.R <raw_dir>
#
# <raw_dir> holds games.csv (nflverse-data release "schedules") and
# play_by_play_<season>.rds (release "pbp") for 2006-2024. The walk-forward
# reads only the derived files written to backtest/data/, whose sha256 are
# recorded in backtest/data/SOURCES.json together with the raw files' sha256.
# nflverse re-publishes release files, so the derived files (not the URLs) are
# the reproducible snapshot.
#
# The 2025 holdout is sealed: no row with season > MAX_SEASON is written.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

BT_MIN_PBP_SEASON <- 2006L
BT_MAX_SEASON <- 2024L          # holdout (2025) sealed in v1
BT_RELEASE_BASE <- "https://github.com/nflverse/nflverse-data/releases/download"

# Relocated franchises share one Elo/feature history
BT_FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA")

bt_franchise <- function(team) {
  out <- unname(BT_FRANCHISE[team])
  ifelse(is.na(out), team, out)
}

bt_sha256_file <- function(path) digest::digest(file = path, algo = "sha256")

# nflverse gameday/gametime are US Eastern
bt_kickoff_utc <- function(gameday, gametime) {
  gametime[is.na(gametime) | !nzchar(gametime)] <- "13:00"
  lt <- as.POSIXct(paste(gameday, gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")
  format(lt, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

bt_build_games <- function(raw_games) {
  g <- fread(raw_games, na.strings = c("", "NA"))
  g <- g[season <= BT_MAX_SEASON]
  g[, kickoff_utc := bt_kickoff_utc(gameday, gametime)]
  g[, `:=`(home_franchise = bt_franchise(home_team), away_franchise = bt_franchise(away_team))]
  keep <- c("game_id", "season", "game_type", "week", "gameday", "gametime", "kickoff_utc",
            "home_team", "away_team", "home_franchise", "away_franchise", "home_score", "away_score",
            "location", "home_rest", "away_rest", "home_moneyline", "away_moneyline", "spread_line",
            "div_game", "roof", "home_qb_id", "away_qb_id")
  g <- g[, ..keep]
  setorder(g, kickoff_utc, game_id)
  g
}

# One row per (game, offense): play-weighted EPA and success components
bt_team_games_one_season <- function(pbp) {
  p <- as.data.table(pbp)
  p <- p[!is.na(epa) & !is.na(posteam) & play_type %in% c("pass", "run") &
           (pass == 1 | rush == 1) & (is.na(two_point_attempt) | two_point_attempt == 0)]
  tg <- p[, .(
    plays = .N, epa_sum = sum(epa), success_sum = sum(success, na.rm = TRUE),
    pass_plays = sum(pass == 1), pass_epa_sum = sum(epa[pass == 1]),
    rush_plays = sum(rush == 1 & pass == 0), rush_epa_sum = sum(epa[rush == 1 & pass == 0])
  ), by = .(game_id, team = posteam, opp = defteam)]
  db <- p[qb_dropback == 1 & !is.na(qb_epa)]
  db[, qb_id := fifelse(!is.na(passer_player_id), passer_player_id, rusher_player_id)]
  qb <- db[!is.na(qb_id), .(dropbacks = .N, qb_epa_sum = sum(qb_epa)), by = .(game_id, team = posteam, qb_id)]
  list(team_games = tg, qb_games = qb)
}

bt_build_all <- function(raw_dir, out_dir = file.path("backtest", "data")) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  raw_games <- file.path(raw_dir, "games.csv")
  if (!file.exists(raw_games)) stop("build_inputs: missing ", raw_games)
  games <- bt_build_games(raw_games)

  seasons <- BT_MIN_PBP_SEASON:BT_MAX_SEASON
  tgs <- list(); qbs <- list(); raw_meta <- list()
  for (s in seasons) {
    f <- file.path(raw_dir, sprintf("play_by_play_%d.rds", s))
    if (!file.exists(f)) stop("build_inputs: missing ", f)
    parts <- bt_team_games_one_season(readRDS(f))
    tgs[[length(tgs) + 1]] <- parts$team_games
    qbs[[length(qbs) + 1]] <- parts$qb_games
    raw_meta[[length(raw_meta) + 1]] <- list(file = basename(f), url = sprintf("%s/pbp/play_by_play_%d.rds", BT_RELEASE_BASE, s),
                                             sha256 = bt_sha256_file(f), bytes = file.size(f))
    message("pbp ", s, ": ", nrow(parts$team_games), " team-games")
  }
  tg <- rbindlist(tgs); qb <- rbindlist(qbs)
  tg[, `:=`(team = bt_franchise(team), opp = bt_franchise(opp))]
  qb[, team := bt_franchise(team)]

  # Every pbp game must be a known schedule game (joins are by game_id only)
  unknown <- setdiff(unique(tg$game_id), games$game_id)
  if (length(unknown)) stop("build_inputs: pbp game_ids not in schedule: ", paste(head(unknown), collapse = ", "))
  setorder(tg, game_id, team); setorder(qb, game_id, team, qb_id)

  num_cols <- c("epa_sum", "success_sum", "pass_epa_sum", "rush_epa_sum")
  tg[, (num_cols) := lapply(.SD, round, 6), .SDcols = num_cols]
  qb[, qb_epa_sum := round(qb_epa_sum, 6)]

  # Decision-time prices: ESPN BET moneyline open/close (keyless ESPN core API,
  # captured for the A2 power analysis). Only seasons <= BT_MAX_SEASON are kept.
  espn_src <- file.path("reports", "2026-09-29", "clv-power", "espn_open_close_2024_2025.csv")
  if (!file.exists(espn_src)) stop("build_inputs: missing ", espn_src)
  espn <- fread(espn_src, colClasses = list(character = c("h_open", "a_open", "h_close", "a_close", "provider")))
  espn <- espn[season <= BT_MAX_SEASON & game_id %in% games$game_id,
               .(game_id, season, week, provider, provider_name, h_open, a_open, h_close, a_close)]
  setorder(espn, game_id, provider)

  files <- list(games = games, team_games = tg, qb_games = qb, espn_open_close = espn)
  out_meta <- list()
  for (nm in names(files)) {
    path <- file.path(out_dir, paste0(nm, ".csv"))
    bt_write_csv(files[[nm]], path)
    out_meta[[nm]] <- list(file = basename(path), rows = nrow(files[[nm]]), sha256 = bt_sha256_file(path))
  }
  sources <- list(
    built_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    max_season = BT_MAX_SEASON,
    raw = c(list(list(file = "games.csv", url = sprintf("%s/schedules/games.csv", BT_RELEASE_BASE),
                      sha256 = bt_sha256_file(raw_games), bytes = file.size(raw_games))), raw_meta,
            list(list(file = basename(espn_src), url = espn_src, sha256 = bt_sha256_file(espn_src),
                      bytes = file.size(espn_src)))),
    derived = out_meta,
    r_version = R.version.string
  )
  bt_write_text(jsonlite::toJSON(sources, auto_unbox = TRUE, pretty = TRUE), file.path(out_dir, "SOURCES.json"))
  invisible(sources)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 1L) stop("usage: Rscript backtest/build_inputs.R <raw_dir>")
  bt_build_all(args[[1]])
}
