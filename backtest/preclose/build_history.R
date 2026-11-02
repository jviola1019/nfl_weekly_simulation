#!/usr/bin/env Rscript
# =============================================================================
# nfl_preclose_v1: 2025 and 2026 as model history (PROTOCOL.md "Windows"). Builds games,
# team_games and qb_games for 2025-2026 with v1's own functions (backtest/build_inputs.R),
# from nflverse release files (keyless), into a PRIVATE folder: never backtest/data, never
# committed. 2025 enters only as history for 2026's features and fits; nothing here
# predicts or scores a 2025 game.
#   Rscript backtest/preclose/build_history.R <raw_dir> <out_dir>
# <raw_dir> receives games.csv and play_by_play_2025.rds / _2026.rds (fetched when missing
# or older than 12 hours); <out_dir> receives the derived CSVs and SOURCES.json.
# =============================================================================
suppressPackageStartupMessages(library(data.table))
source(file.path("backtest", "build_inputs.R"))   # its main block runs only as a script
source(file.path("backtest", "common.R"))
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
raw <- args[1]; out <- args[2]
if (normalizePath(out, mustWork = FALSE) == normalizePath(file.path("backtest", "data"), mustWork = FALSE)) stop("build_history: never write into backtest/data")
dir.create(raw, recursive = TRUE, showWarnings = FALSE); dir.create(out, recursive = TRUE, showWarnings = FALSE)
SEASONS <- 2025:2026
options(timeout = 900)
get_file <- function(url, f) {
  if (!file.exists(f) || difftime(Sys.time(), file.mtime(f), units = "hours") > 12) utils::download.file(url, f, mode = "wb", quiet = TRUE)
  stopifnot(file.exists(f), file.size(f) > 0)
  f
}
gf <- get_file(sprintf("%s/schedules/games.csv", BT_RELEASE_BASE), file.path(raw, "games.csv"))
g <- fread(gf, na.strings = c("", "NA"))[season %in% SEASONS]
g[, kickoff_utc := bt_kickoff_utc(gameday, gametime)]
g[, `:=`(home_franchise = bt_franchise(home_team), away_franchise = bt_franchise(away_team))]
keep <- c("game_id", "season", "game_type", "week", "gameday", "gametime", "kickoff_utc", "home_team", "away_team", "home_franchise", "away_franchise",
          "home_score", "away_score", "location", "home_rest", "away_rest", "home_moneyline", "away_moneyline", "spread_line", "div_game", "roof",
          "home_qb_id", "away_qb_id")
g <- g[, ..keep]; setorder(g, kickoff_utc, game_id)
tgs <- list(); qbs <- list(); meta <- list()
for (s in SEASONS) {
  f <- get_file(sprintf("%s/pbp/play_by_play_%d.rds", BT_RELEASE_BASE, s), file.path(raw, sprintf("play_by_play_%d.rds", s)))
  parts <- bt_team_games_one_season(readRDS(f))
  tgs[[length(tgs) + 1L]] <- parts$team_games; qbs[[length(qbs) + 1L]] <- parts$qb_games
  meta[[length(meta) + 1L]] <- list(file = basename(f), sha256 = bt_sha256_file(f), bytes = file.size(f), mtime = format(file.mtime(f), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
}
tg <- rbindlist(tgs); qb <- rbindlist(qbs)
tg[, `:=`(team = bt_franchise(team), opp = bt_franchise(opp))]; qb[, team := bt_franchise(team)]
unknown <- setdiff(unique(tg$game_id), g$game_id)
if (length(unknown)) stop("build_history: pbp game_ids not in the schedule: ", paste(head(unknown), collapse = ", "))
setorder(tg, game_id, team); setorder(qb, game_id, team, qb_id)
num_cols <- c("epa_sum", "success_sum", "pass_epa_sum", "rush_epa_sum")
tg[, (num_cols) := lapply(.SD, round, 6), .SDcols = num_cols]; qb[, qb_epa_sum := round(qb_epa_sum, 6)]
files <- list(games = g, team_games = tg, qb_games = qb)
derived <- lapply(names(files), function(nm) { p <- file.path(out, paste0(nm, ".csv")); bt_write_csv(files[[nm]], p)
  list(file = basename(p), rows = nrow(files[[nm]]), sha256 = bt_sha256_file(p)) })
bt_write_text(jsonlite::toJSON(list(built_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), seasons = SEASONS,
                                    use = "history only (nfl_preclose_v1): no 2025 game is predicted or scored",
                                    raw = c(list(list(file = "games.csv", sha256 = bt_sha256_file(gf))), meta), derived = derived),
                               auto_unbox = TRUE, pretty = TRUE), file.path(out, "SOURCES.json"))
cat(sprintf("history: %d games (%d played), %d team-games, %d QB-games\n", nrow(g), g[!is.na(home_score), .N], nrow(tg), nrow(qb)))
