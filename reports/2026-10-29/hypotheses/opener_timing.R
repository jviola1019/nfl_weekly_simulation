# The opener-timing question that nflverse_preclose_v1 leaves open (design §2: IS-B "may not be executable until the
# opener-timing study shows openers post after w-1's games"). From the A0 capture archive (ESPN's game odds, saved
# Tuesday, Thursday, Saturday and Sunday): for each game, the first capture whose DraftKings odds already carry an opening
# moneyline, against the kickoffs of both teams' previous games. If an opener is captured before a team's previous game
# was played, the opener did not know that game's result, and a model that uses it (v1's C2, IS-B) looked ahead.
# ESPN keeps no line history for 2023-2024 (its movement endpoint returns nothing), so this measures 2026 DraftKings,
# not ESPN BET's 2023-2024 openers. Run from the repository root, with each extracted capture archive in its own directory:
#   Rscript reports/2026-10-29/hypotheses/opener_timing.R <out_dir> <archive_dir> [<archive_dir> ...]
suppressPackageStartupMessages(library(data.table))
a <- commandArgs(trailingOnly = TRUE); out <- a[1]; dirs <- a[-1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
`%||%` <- function(x, y) if (is.null(x)) y else x
files <- list.files(dirs, pattern = "^[0-9]+__[0-9]{8}T[0-9]{6}Z\\.json\\.gz$", recursive = TRUE, full.names = TRUE)
files <- files[grepl("espn_game_odds", files, fixed = TRUE)]
stopifnot(length(files) > 0)
cap <- rbindlist(lapply(files, function(f) {
  j <- tryCatch(jsonlite::parse_json(paste(readLines(gzfile(f), warn = FALSE), collapse = "\n")), error = function(e) NULL)
  dk <- if (is.null(j)) NULL else Filter(function(it) identical(it$provider$id %||% "", "100"), j$items %||% list())
  has_open <- length(dk) > 0 && !is.null(dk[[1]]$homeTeamOdds$open$moneyLine %||% dk[[1]]$homeTeamOdds$open$moneyLine$american %||% NULL)
  data.table(espn = sub("__.*$", "", basename(f)), captured = as.POSIXct(sub("^.*__([0-9]{8}T[0-9]{6}Z)\\.json\\.gz$", "\\1", basename(f)), format = "%Y%m%dT%H%M%SZ", tz = "UTC"),
             has_dk = length(dk) > 0, has_open = has_open)
}))
sched <- as.data.table(nflreadr::load_schedules(2026))[game_type == "REG"]
stopifnot(all(sched$season == 2026))
sched[, kick := as.POSIXct(paste(gameday, gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")]; attr(sched$kick, "tzone") <- "UTC"
tg <- rbind(sched[, .(game_id, week, team = home_team, kick)], sched[, .(game_id, week, team = away_team, kick)])
setorder(tg, team, kick); tg[, prev_kick := shift(kick), by = team]
pk <- tg[, .(prev_kick_latest = max(prev_kick)), by = game_id]           # the later of the two teams' previous games
g <- merge(sched[, .(game_id, week, espn = as.character(espn), kick)], pk, by = "game_id")
first <- cap[has_open == TRUE, .(first_open_capture = min(captured)), by = espn]
g <- merge(g, first, by = "espn")
g[, opener_before_prev := first_open_capture < prev_kick_latest]
# the archive's own limit: when it first captured any odds for the week's games, against when the previous week ended. If it
# first looks after the previous week's games, it cannot see an opener posted before them, and a 0 below says nothing
seen <- merge(cap[has_dk == TRUE, .(first_capture = min(captured)), by = espn], sched[, .(espn = as.character(espn), week)], by = "espn")[, .(first_capture_of_week = min(first_capture)), by = week]
prev_end <- sched[, .(last_kick = max(kick)), by = week][, .(week = week + 1L, previous_week_last_kickoff = last_kick)]
res <- g[, .(games = .N, opener_captured_before_a_previous_game = sum(opener_before_prev),
             median_hours_open_before_kickoff = stats::median(as.numeric(difftime(kick, first_open_capture, units = "hours")))), by = week][order(week)]
res <- merge(merge(res, seen, by = "week"), prev_end, by = "week")
res[, archive_could_see_an_earlier_opener := first_capture_of_week < previous_week_last_kickoff]
fwrite(res, file.path(out, "opener_timing.csv")); fwrite(g[order(week, kick), .(game_id, week, first_open_capture, prev_kick_latest, opener_before_prev)], file.path(out, "opener_timing_games.csv"))
options(width = 200); print(res); cat(sprintf("\ncaptures read %d; games with a captured DraftKings opener %d; of them captured before a team's previous game %d\n",
                                            nrow(cap), nrow(g), sum(g$opener_before_prev)))
