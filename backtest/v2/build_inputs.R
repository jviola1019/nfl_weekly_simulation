#!/usr/bin/env Rscript
# =============================================================================
# Game backtest v2: build the extra point-in-time inputs for the validation
# sprint, from keyless sources only, into backtest/data_v2/ (new files; the v1
# inputs in backtest/data/ are hash-locked and untouched).
#
#   Rscript backtest/v2/build_inputs.R
#
# Sources (all keyless):
#   - nflreadr::load_schedules(2009:2024): closing total/spread prices, surface,
#     roof, observed temp/wind, referee, stadium. nflreadr downloads the single
#     nflverse schedule file and filters it to the requested seasons in memory;
#     nothing after 2024 is returned to this script, and the guard below stops
#     the build if it were. The nflreadr cache is switched off (no disk copy).
#   - nflreadr::load_injuries(2009:2024): one nflverse file per season, so no
#     file for 2025 or later is requested.
#   - Open-Meteo geocoding API: venue city coordinates, elevation, time zone.
#
# Outputs (sha256 in backtest/data_v2/SOURCES.json):
#   game_context.csv     one row per game (2009-2024)
#   injuries_team.csv    one row per (game, team): final-report counts by group
#   injuries_qb.csv      QB rows of the final report (for the starter-out flag)
#   venues.csv           one row per stadium_id: lat, lon, elevation, time zone
#
# Point-in-time: an injury-report row is kept only if its date_modified plus a
# 6-hour safety margin is before the team's kickoff (the margin covers the
# uncertain time zone of older stamps). Dropped rows are counted in SOURCES.json.
# =============================================================================

suppressPackageStartupMessages(library(data.table))
options(nflreadr.cache = "off", nflreadr.verbose = FALSE)

bt2_builder_dir <- function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else file.path(getwd(), "backtest", "v2")
}

BT2_SEASONS_BUILD <- 2009:2024
BT2_INJ_MARGIN_SEC <- 6 * 3600
BT2_GEO_URL <- "https://geocoding-api.open-meteo.com/v1/search"

# stadium_id -> geocoding query (city, country code, admin1 used to disambiguate)
BT2_VENUE_QUERY <- data.table::fread(text = "
stadium_id|query|country|admin1
ATL00|Atlanta|US|Georgia
ATL97|Atlanta|US|Georgia
BAL00|Baltimore|US|Maryland
BOS00|Foxborough|US|Massachusetts
BUF00|Orchard Park|US|New York
BUF01|Toronto|CA|Ontario
CAR00|Charlotte|US|North Carolina
CHI98|Chicago|US|Illinois
CIN00|Cincinnati|US|Ohio
CLE00|Cleveland|US|Ohio
DAL00|Arlington|US|Texas
DEN00|Denver|US|Colorado
DET00|Detroit|US|Michigan
FRA00|Frankfurt am Main|DE|Hesse
GER00|Munich|DE|Bavaria
GNB00|Green Bay|US|Wisconsin
HOU00|Houston|US|Texas
IND00|Indianapolis|US|Indiana
JAX00|Jacksonville|US|Florida
KAN00|Kansas City|US|Missouri
LAX01|Inglewood|US|California
LAX97|Carson|US|California
LAX99|Los Angeles|US|California
LON00|London|GB|England
LON01|London|GB|England
LON02|London|GB|England
MEX00|Mexico City|MX|Mexico City
MIA00|Miami Gardens|US|Florida
MIN00|Minneapolis|US|Minnesota
MIN01|Minneapolis|US|Minnesota
MIN98|Minneapolis|US|Minnesota
NAS00|Nashville|US|Tennessee
NOR00|New Orleans|US|Louisiana
NYC00|East Rutherford|US|New Jersey
NYC01|East Rutherford|US|New Jersey
OAK00|Oakland|US|California
PHI00|Philadelphia|US|Pennsylvania
PHO00|Glendale|US|Arizona
PIT00|Pittsburgh|US|Pennsylvania
SAO00|Sao Paulo|BR|
SDG00|San Diego|US|California
SEA00|Seattle|US|Washington
SFO00|San Francisco|US|California
SFO01|Santa Clara|US|California
STL00|St Louis|US|Missouri
TAM00|Tampa|US|Florida
VEG00|Las Vegas|US|Nevada
WAS00|Landover|US|Maryland
", sep = "|", na.strings = "")

# Injury-report position groups (production engine groups, config.R:335-358)
bt2_position_group <- function(pos) {
  pos <- toupper(pos)
  fcase(pos == "QB", "qb",
        pos %in% c("T", "G", "C", "OT", "OG", "OL", "LT", "RT", "LG", "RG"), "ol",
        pos %in% c("WR", "TE", "RB", "FB", "HB"), "skill",
        pos %in% c("DE", "DT", "NT", "DL", "EDGE"), "dl",
        pos %in% c("LB", "ILB", "OLB", "MLB"), "lb",
        pos %in% c("CB", "S", "FS", "SS", "DB", "SAF"), "db",
        default = "other")
}

bt2_geocode <- function(q) {
  url <- sprintf("%s?name=%s&count=10&language=en&format=json&countryCode=%s", BT2_GEO_URL,
                 utils::URLencode(q$query, reserved = TRUE), q$country)
  txt <- paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "")
  js <- jsonlite::fromJSON(txt)
  r <- as.data.table(js$results)
  if (!nrow(r)) stop("geocode: no result for ", q$query)
  if (!is.na(q$admin1)) r <- r[admin1 == q$admin1]
  if (!nrow(r)) stop("geocode: no result for ", q$query, " in ", q$admin1)
  r <- r[1]
  list(row = data.table(stadium_id = q$stadium_id, query = q$query, geo_name = r$name, admin1 = r$admin1 %||% NA_character_,
                        country = r$country_code, latitude = r$latitude, longitude = r$longitude,
                        elevation_m = r$elevation, timezone = r$timezone),
       url = url, sha256 = digest::digest(txt, algo = "sha256", serialize = FALSE))
}


bt2_build_v2 <- function(out_dir = BT2_DATA_DIR) {
  games <- bt_load_inputs("backtest/data")$games       # v1 locked schedule (<= 2024)
  bt2_guard_seasons(games$season, BT2_MAX_INPUT_SEASON, "v1 games.csv")
  sources <- list()

  # ---- schedule context -------------------------------------------------------
  sch <- as.data.table(nflreadr::load_schedules(seasons = BT2_SEASONS_BUILD))
  bt2_guard_seasons(sch$season, BT2_MAX_INPUT_SEASON, "load_schedules result")
  sch <- sch[season %in% BT2_SEASONS_BUILD]
  sources$schedules <- list(call = "nflreadr::load_schedules(seasons = 2009:2024)",
                            url = "https://github.com/nflverse/nfldata/raw/master/data/games.rds",
                            nflverse_timestamp = format(attr(sch, "nflverse_timestamp")), rows = nrow(sch),
                            note = "all-season file filtered to 2009-2024 by nflreadr in memory; cache off")
  miss <- setdiff(sch$game_id, games$game_id)
  if (length(miss)) stop("schedule: game_ids not in v1 games.csv: ", paste(head(miss), collapse = ", "))
  chk <- merge(sch[, .(game_id, s_spread = spread_line, s_home = home_team, s_hs = home_score)],
               games[, .(game_id, spread_line, home_team, home_score)], by = "game_id")
  sources$schedules$consistency_vs_v1 <- list(
    games_matched = nrow(chk),
    home_team_mismatch = chk[s_home != home_team, .N],
    home_score_mismatch = chk[!is.na(home_score) & (is.na(s_hs) | s_hs != home_score), .N],
    spread_line_mismatch = chk[!is.na(spread_line) & (is.na(s_spread) | s_spread != spread_line), .N])
  ctx <- sch[, .(game_id, season, week, weekday, total_line, over_odds, under_odds,
                 home_spread_odds, away_spread_odds, surface = tolower(trimws(surface)),
                 temp_obs = temp, wind_obs = wind, referee, home_coach, away_coach, stadium_id, stadium,
                 espn = as.character(espn))]
  setorder(ctx, game_id)

  # ---- venues -----------------------------------------------------------------
  ids <- sort(unique(ctx$stadium_id[!is.na(ctx$stadium_id)]))
  unmapped <- setdiff(ids, BT2_VENUE_QUERY$stadium_id)
  if (length(unmapped)) stop("venues: unmapped stadium_id: ", paste(unmapped, collapse = ", "))
  geo <- lapply(ids, function(id) bt2_geocode(BT2_VENUE_QUERY[stadium_id == id]))
  venues <- rbindlist(lapply(geo, `[[`, "row"))
  sources$venues <- list(api = BT2_GEO_URL, requests = lapply(geo, function(g) list(url = g$url, sha256 = g$sha256)))

  # ---- injuries ----------------------------------------------------------------
  inj <- as.data.table(nflreadr::load_injuries(seasons = BT2_SEASONS_BUILD))
  bt2_guard_seasons(inj$season, BT2_MAX_INPUT_SEASON, "load_injuries result")
  sources$injuries <- list(call = "nflreadr::load_injuries(seasons = 2009:2024)",
                           url = "https://github.com/nflverse/nflverse-data/releases/download/injuries/injuries_{season}.rds",
                           nflverse_timestamp = format(attr(inj, "nflverse_timestamp")), rows_raw = nrow(inj),
                           date_modified_tzone = attr(inj$date_modified, "tzone") %||% "")
  inj[, team := bt2_franchise(team)]
  inj[, `:=`(season = as.integer(season), week = as.integer(week))]
  tw <- rbind(games[, .(game_id, season, week, team = home_franchise, kickoff)],
              games[, .(game_id, season, week, team = away_franchise, kickoff)])
  inj <- merge(inj, tw, by = c("season", "week", "team"), all.x = TRUE)
  sources$injuries$rows_unmatched_team_week <- inj[is.na(game_id), .N]
  inj <- inj[!is.na(game_id)]
  dm <- as.POSIXct(inj$date_modified, tz = "UTC")
  late <- is.na(dm) | !(dm + BT2_INJ_MARGIN_SEC < inj$kickoff)
  sources$injuries$rows_dropped_not_before_kickoff <- sum(late)
  sources$injuries$rows_kept <- sum(!late)
  sources$injuries$point_in_time_rule <- "date_modified (as UTC) + 6 h < team kickoff"
  inj <- inj[!late]
  inj[, status := fcase(report_status %in% c("Out"), "out", report_status %in% c("Doubtful"), "doubtful",
                        report_status %in% c("Questionable"), "questionable", default = "other")]
  inj[, grp := bt2_position_group(position)]
  agg <- inj[status != "other", .(n = .N), by = .(game_id, team, grp, status)]
  agg <- dcast(agg, game_id + team ~ paste0(grp, "_", status), value.var = "n", fill = 0L)
  keys <- CJ(grp = c("qb", "ol", "skill", "dl", "lb", "db", "other"), status = c("out", "doubtful", "questionable"))
  for (cc in keys[, paste0(grp, "_", status)]) if (!cc %in% names(agg)) set(agg, j = cc, value = 0L)
  reported <- unique(inj[, .(game_id, team)])
  agg <- merge(reported, agg, by = c("game_id", "team"), all.x = TRUE)
  for (cc in setdiff(names(agg), c("game_id", "team"))) set(agg, which(is.na(agg[[cc]])), cc, 0L)
  setcolorder(agg, c("game_id", "team", keys[, paste0(grp, "_", status)]))
  agg <- merge(agg, games[, .(game_id, season)], by = "game_id")
  setcolorder(agg, c("game_id", "season"))
  setorder(agg, game_id, team)
  qbi <- inj[grp == "qb" & status != "other", .(game_id, season, team, gsis_id, status)]
  setorder(qbi, game_id, team, gsis_id)

  # ---- write --------------------------------------------------------------------
  files <- list(game_context = ctx, injuries_team = agg, injuries_qb = qbi, venues = venues)
  derived <- list()
  for (nm in names(files)) {
    if ("season" %in% names(files[[nm]])) bt2_guard_seasons(files[[nm]]$season, BT2_MAX_INPUT_SEASON, nm)
    path <- file.path(out_dir, paste0(nm, ".csv"))
    bt2_write_csv(files[[nm]], path)
    derived[[nm]] <- list(file = basename(path), rows = nrow(files[[nm]]), sha256 = bt2_sha256(path))
  }
  meta <- list(built_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), max_season = BT2_MAX_INPUT_SEASON,
               seasons = range(BT2_SEASONS_BUILD), builder = "backtest/v2/build_inputs.R",
               nflreadr_version = as.character(utils::packageVersion("nflreadr")),
               r_version = R.version.string, sources = sources, derived = derived)
  bt2_write_json(meta, file.path(out_dir, "SOURCES.json"))
  invisible(meta)
}

if (sys.nframe() == 0L) {
  d <- bt2_builder_dir()
  sys.source(file.path(d, "..", "common.R"), envir = environment())
  sys.source(file.path(d, "common.R"), envir = environment())
  m <- bt2_build_v2()
  str(m$derived)
}
