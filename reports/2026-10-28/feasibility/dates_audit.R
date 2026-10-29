# Are the dates right? Every date and time the models and the research rely on, checked against an independent
# derivation. Run from the repository root:
#   Rscript reports/2026-10-28/feasibility/dates_audit.R <out_dir>
# Writes dates_checks.csv (check, n, violations, detail) and dates_violations.csv (every failing row).
suppressPackageStartupMessages(library(data.table))
out <- commandArgs(trailingOnly = TRUE)[1]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
checks <- list(); viol <- list()
add <- function(check, n, bad, detail, rows = NULL) {
  checks[[length(checks) + 1L]] <<- data.table(check = check, n = n, violations = as.integer(bad), detail = detail)
  if (!is.null(rows) && nrow(rows)) viol[[length(viol) + 1L]] <<- cbind(data.table(check = check), rows[, lapply(.SD, as.character)])
  cat(sprintf("%-58s n %5d  violations %4d  %s\n", check, n, bad, detail))
}
g <- fread(file.path("backtest", "data", "games.csv"))
g[, kick := as.POSIXct(kickoff_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]

# 1. kickoff_utc is the ET game day and game time, converted with daylight saving
h <- g[!is.na(gametime) & nzchar(gametime)]
h[, et := as.POSIXct(paste(gameday, gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")]
h[, gap_min := abs(as.numeric(difftime(kick, et, units = "mins")))]
add("kickoff_utc equals the ET game day and time (DST-aware)", nrow(h), sum(!(h$gap_min <= 1), na.rm = TRUE) + sum(is.na(h$gap_min)),
    sprintf("largest gap %.0f min", max(h$gap_min, na.rm = TRUE)), h[!(gap_min <= 1) | is.na(gap_min), .(game_id, gameday, gametime, kickoff_utc)])
nt <- g[is.na(gametime) | !nzchar(gametime)]
nt[, et1 := as.POSIXct(paste(gameday, "13:00"), format = "%Y-%m-%d %H:%M", tz = "America/New_York")]
add("games without a game time sit at 1 p.m. ET on their game day", nrow(nt), sum(nt$kick != nt$et1),
    sprintf("seasons %s; 1 p.m. EDT is 17:00Z, EST 18:00Z", paste(unique(range(nt$season)), collapse = "-")),
    nt[kick != et1, .(game_id, gameday, kickoff_utc)])
dst <- h[format(et, "%m") %in% c("03", "11") & format(et, "%d") <= "14"]
add("games near the DST changes keep their UTC offset", nrow(dst), sum(!(dst$gap_min <= 1), na.rm = TRUE),
    "March and early November games (EDT -4h, EST -5h)", dst[!(gap_min <= 1), .(game_id, gameday, gametime, kickoff_utc)])

# 2. every game sits in its season's window, and no season after 2024 is present (the seal)
g[, in_window := kick >= as.POSIXct(sprintf("%d-08-01", season), tz = "UTC") & kick < as.POSIXct(sprintf("%d-03-01", season + 1L), tz = "UTC")]
add("each game falls between August 1 and March 1 of its season", nrow(g), sum(!g$in_window, na.rm = TRUE),
    "January and February games belong to the season before", g[in_window == FALSE, .(game_id, season, kickoff_utc)])
add("no season after 2024 (the 2025 holdout is sealed)", nrow(g), sum(g$season > 2024L), sprintf("seasons %d-%d", min(g$season), max(g$season)),
    g[season > 2024L, .(game_id, season)])

# 3. weeks run in order: a game of week w + 1 never kicks off before the last game of week w
wk <- g[, .(first = min(kick), last = max(kick)), by = .(season, week)][order(season, week)]
wk[, next_first := shift(first, type = "lead"), by = season]
ov <- wk[!is.na(next_first) & next_first < last]
add("weeks are ordered: week w + 1 starts after week w ends", nrow(wk), nrow(ov),
    "a rescheduled game (2020 COVID, 2022 BUF-CIN) can end its week late",
    ov[, .(season, week, last = format(last, "%Y-%m-%dT%H:%MZ"), next_first = format(next_first, "%Y-%m-%dT%H:%MZ"))])
late <- g[wk, on = .(season, week), nomatch = 0][!is.na(next_first) & kick > next_first]
add("games played after the next week's cutoff (walk-forward excludes them from that week's training)", nrow(g), nrow(late),
    "S3 and S5 train on kickoff < cutoff, so a late game is never seen early; listed, not an error", late[, .(game_id, season, week, kickoff_utc)])

# 4. rest days: nflverse's home_rest and away_rest against days since each team's previous game (ET dates)
long <- rbind(g[, .(game_id, season, team = home_franchise, day = as.Date(gameday), rest = home_rest)],
              g[, .(game_id, season, team = away_franchise, day = as.Date(gameday), rest = away_rest)])
setorder(long, team, day)
long[, prev := shift(day), by = .(team, season)]
r <- long[!is.na(prev) & !is.na(rest)]
r[, mine := as.integer(day - prev)]
add("rest days equal the days since the team's previous game", nrow(r), sum(r$mine != r$rest),
    "within a season; a season's first game has no previous game", r[mine != rest, .(game_id, team, gameday = day, rest, mine)])

# 5. venue time zones are valid Olson names
v <- fread(file.path("backtest", "vvf", "data", "venues.csv"))
add("every venue's time zone is a valid Olson name", nrow(v), sum(!v$timezone %in% OlsonNames()),
    paste(v[!grepl("^America/", timezone), sprintf("%s %s", stadium_id, timezone)], collapse = "; "), v[!timezone %in% OlsonNames(), .(stadium_id, timezone)])

# 6. the late-change research's kickoffs are the schedule's
fg <- fread(file.path("reports", "2026-10-28", "a3-research", "data", "flex-games.csv"))
fg[, k2 := as.POSIXct(kickoff, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]
mm <- merge(fg[, .(game_id, k2)], g[, .(game_id, kick)], by = "game_id", all.x = TRUE)
add("late-change rows carry the schedule's kickoff", nrow(mm), sum(is.na(mm$kick) | mm$k2 != mm$kick), "flex-games.csv against games.csv",
    mm[is.na(kick) | k2 != kick, .(game_id, k2, kick)])

ch <- rbindlist(checks)
fwrite(ch, file.path(out, "dates_checks.csv"))
fwrite(if (length(viol)) rbindlist(viol, fill = TRUE) else data.table(check = character()), file.path(out, "dates_violations.csv"))
cat(sprintf("\n%d checks; %d with violations\n", nrow(ch), sum(ch$violations > 0)))
