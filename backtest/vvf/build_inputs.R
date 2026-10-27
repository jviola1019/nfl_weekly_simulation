#!/usr/bin/env Rscript
# =============================================================================
# VVF input builder: the extra point-in-time inputs (schedule context, injury
# reports, venues) for seasons 2009-2024, from keyless sources only.
#
#   Rscript backtest/vvf/build_inputs.R <out_dir> [--overwrite]
#
# A directory that already holds locked inputs (SOURCES.json), backtest/vvf/data/
# included, is refused without --overwrite: a rebuild changes the committed sha256s.
#
# Ported with attribution from PR #205 (validation sprint v2,
# backtest/v2/build_inputs.R at 759dd1c; owner decision 2026-10-20). Changes:
#   - the build is split into vvf_build_context(), vvf_build_injuries() and
#     vvf_build_venues(), and the loaders are arguments, so tests run offline;
#   - every requested season is checked against the seal before any request,
#     and every loader result is guarded again;
#   - geocoding follows the project's network rules: config.R's
#     CAPTURE_USER_AGENT, a CAPTURE_TIMEOUT_SEC timeout, at least
#     CAPTURE_MIN_INTERVAL_SEC between requests, and one try (an HTTP error such
#     as 403 or 429 stops the build and is never retried);
#   - the output directory is backtest/vvf/data/.
# The committed backtest/vvf/data/ files were made by v2's builder on
# 2026-09-30. A rebuild writes new files whose sha256s go into SOURCES.json.
#
# Sources (all keyless):
#   - nflreadr::load_schedules(2009:2024): closing total/spread prices, surface,
#     roof, observed temp/wind, referee, stadium (cache off);
#   - nflreadr::load_injuries(2009:2024): one nflverse file per season;
#   - Open-Meteo geocoding: venue coordinates, elevation, time zone.
# Point-in-time rule: an injury-report row is kept only if its date_modified plus
# 6 hours is before the team's kickoff. Dropped rows are counted in SOURCES.json.
# =============================================================================

suppressPackageStartupMessages(library(data.table))

VVF_SEASONS_BUILD <- 2009:2024
VVF_INJ_MARGIN_SEC <- 6 * 3600
VVF_GEO_URL <- "https://geocoding-api.open-meteo.com/v1/search"

# stadium_id -> geocoding query (city, country code, admin1 used to disambiguate)
VVF_VENUE_QUERY <- data.table::fread(text = "
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

# Injury-report position groups (production engine groups, config.R)
vvf_position_group <- function(pos) {
  pos <- toupper(pos)
  fcase(pos == "QB", "qb",
        pos %in% c("T", "G", "C", "OT", "OG", "OL", "LT", "RT", "LG", "RG"), "ol",
        pos %in% c("WR", "TE", "RB", "FB", "HB"), "skill",
        pos %in% c("DE", "DT", "NT", "DL", "EDGE"), "dl",
        pos %in% c("LB", "ILB", "OLB", "MLB"), "lb",
        pos %in% c("CB", "S", "FS", "SS", "DB", "SAF"), "db",
        default = "other")
}

#' One GET with the project user agent and timeout. No retry: an HTTP error stops.
vvf_http_get_text <- function(url, user_agent, timeout_sec) {
  old <- options(timeout = timeout_sec)
  on.exit(options(old), add = TRUE)
  con <- base::url(url, headers = c(`User-Agent` = user_agent), method = "libcurl")
  on.exit(close(con), add = TRUE)
  paste(readLines(con, warn = FALSE, encoding = "UTF-8"), collapse = "")
}

vvf_geocode <- function(q, http_get, user_agent, timeout_sec) {
  url <- sprintf("%s?name=%s&count=10&language=en&format=json&countryCode=%s", VVF_GEO_URL,
                 utils::URLencode(q$query, reserved = TRUE), q$country)
  txt <- http_get(url, user_agent, timeout_sec)
  r <- as.data.table(jsonlite::fromJSON(txt)$results)
  if (!nrow(r)) stop("geocode: no result for ", q$query, call. = FALSE)
  if (!is.na(q$admin1)) r <- r[admin1 == q$admin1]
  if (!nrow(r)) stop("geocode: no result for ", q$query, " in ", q$admin1, call. = FALSE)
  r <- r[1]
  list(row = data.table(stadium_id = q$stadium_id, query = q$query, geo_name = r$name, admin1 = r$admin1 %||% NA_character_,
                        country = r$country_code, latitude = r$latitude, longitude = r$longitude,
                        elevation_m = r$elevation, timezone = r$timezone),
       url = url, sha256 = digest::digest(txt, algo = "sha256", serialize = FALSE))
}

#' Geocode each stadium, at least CAPTURE_MIN_INTERVAL_SEC apart
vvf_build_venues <- function(ids, http_get = vvf_http_get_text, sleep = Sys.sleep) {
  unmapped <- setdiff(ids, VVF_VENUE_QUERY$stadium_id)
  if (length(unmapped)) stop("venues: unmapped stadium_id: ", paste(unmapped, collapse = ", "), call. = FALSE)
  ua <- vvf_config_value("CAPTURE_USER_AGENT")
  timeout_sec <- vvf_config_value("CAPTURE_TIMEOUT_SEC")
  interval <- vvf_config_value("CAPTURE_MIN_INTERVAL_SEC")
  geo <- vector("list", length(ids))
  for (k in seq_along(ids)) {
    if (k > 1L) sleep(interval)
    geo[[k]] <- vvf_geocode(VVF_VENUE_QUERY[stadium_id == ids[k]], http_get, ua, timeout_sec)
  }
  list(venues = rbindlist(lapply(geo, `[[`, "row")),
       meta = list(api = VVF_GEO_URL, user_agent = ua,
                   requests = lapply(geo, function(g) list(url = g$url, sha256 = g$sha256))))
}

#' Schedule context, checked against the v1 locked schedule
vvf_build_context <- function(sch, games) {
  sch <- as.data.table(sch)
  vvf_guard_seasons(sch$season, VVF_MAX_INPUT_SEASON, "load_schedules result")
  sch <- sch[season %in% VVF_SEASONS_BUILD]
  miss <- setdiff(sch$game_id, games$game_id)
  if (length(miss)) stop("schedule: game_ids not in v1 games.csv: ", paste(head(miss), collapse = ", "), call. = FALSE)
  chk <- merge(sch[, .(game_id, s_spread = spread_line, s_home = home_team, s_hs = home_score)],
               games[, .(game_id, spread_line, home_team, home_score)], by = "game_id")
  meta <- list(rows = nrow(sch), consistency_vs_v1 = list(
    games_matched = nrow(chk),
    home_team_mismatch = chk[s_home != home_team, .N],
    home_score_mismatch = chk[!is.na(home_score) & (is.na(s_hs) | s_hs != home_score), .N],
    spread_line_mismatch = chk[!is.na(spread_line) & (is.na(s_spread) | s_spread != spread_line), .N]))
  ctx <- sch[, .(game_id, season, week, weekday, total_line, over_odds, under_odds,
                 home_spread_odds, away_spread_odds, surface = tolower(trimws(surface)),
                 temp_obs = temp, wind_obs = wind, referee, home_coach, away_coach, stadium_id, stadium,
                 espn = as.character(espn))]
  setorder(ctx, game_id)
  list(ctx = ctx, meta = meta)
}

#' Final-report injury counts by team-game, position group and status, plus QB rows
vvf_build_injuries <- function(inj, games) {
  inj <- as.data.table(inj)
  vvf_guard_seasons(inj$season, VVF_MAX_INPUT_SEASON, "load_injuries result")
  meta <- list(rows_raw = nrow(inj), date_modified_tzone = attr(inj$date_modified, "tzone") %||% "")
  inj[, team := vvf_franchise(team)]
  inj[, `:=`(season = as.integer(season), week = as.integer(week))]
  tw <- rbind(games[, .(game_id, season, week, team = home_franchise, kickoff)],
              games[, .(game_id, season, week, team = away_franchise, kickoff)])
  inj <- merge(inj, tw, by = c("season", "week", "team"), all.x = TRUE)
  meta$rows_unmatched_team_week <- inj[is.na(game_id), .N]
  inj <- inj[!is.na(game_id)]
  dm <- as.POSIXct(inj$date_modified, tz = "UTC")
  late <- is.na(dm) | !(dm + VVF_INJ_MARGIN_SEC < inj$kickoff)
  meta$rows_dropped_not_before_kickoff <- sum(late)
  meta$rows_kept <- sum(!late)
  meta$point_in_time_rule <- "date_modified (as UTC) + 6 h < team kickoff"
  inj <- inj[!late]
  inj[, status := fcase(report_status %in% c("Out"), "out", report_status %in% c("Doubtful"), "doubtful",
                        report_status %in% c("Questionable"), "questionable", default = "other")]
  inj[, grp := vvf_position_group(position)]
  keys <- CJ(grp = c("qb", "ol", "skill", "dl", "lb", "db", "other"), status = c("out", "doubtful", "questionable"))
  agg <- inj[status != "other", .(n = .N), by = .(game_id, team, grp, status)]
  agg <- if (nrow(agg)) dcast(agg, game_id + team ~ paste0(grp, "_", status), value.var = "n", fill = 0L) else
    data.table(game_id = character(), team = character())
  for (cc in keys[, paste0(grp, "_", status)]) if (!cc %in% names(agg)) set(agg, j = cc, value = rep(0L, nrow(agg)))
  reported <- unique(inj[, .(game_id, team)])
  agg <- merge(reported, agg, by = c("game_id", "team"), all.x = TRUE)
  for (cc in setdiff(names(agg), c("game_id", "team"))) set(agg, which(is.na(agg[[cc]])), cc, 0L)
  setcolorder(agg, c("game_id", "team", keys[, paste0(grp, "_", status)]))
  agg <- merge(agg, games[, .(game_id, season)], by = "game_id")
  setcolorder(agg, c("game_id", "season"))
  setorder(agg, game_id, team)
  qbi <- inj[grp == "qb" & status != "other", .(game_id, season, team, gsis_id, status)]
  setorder(qbi, game_id, team, gsis_id)
  list(team = agg, qb = qbi, meta = meta)
}

vvf_build_inputs <- function(out_dir = VVF_DATA_DIR, seasons = VVF_SEASONS_BUILD,
                             load_schedules = nflreadr::load_schedules, load_injuries = nflreadr::load_injuries,
                             http_get = vvf_http_get_text, sleep = Sys.sleep, overwrite = FALSE) {
  vvf_guard_seasons(seasons, VVF_MAX_INPUT_SEASON, "requested seasons")
  # a rebuild replaces the locked inputs and their sha256s, so it is never the default (review I8)
  if (file.exists(file.path(out_dir, "SOURCES.json")) && !isTRUE(overwrite)) {
    stop(sprintf("vvf_build_inputs: %s already holds locked inputs (SOURCES.json); a build would overwrite them and their sha256s. Build into another directory, or pass overwrite = TRUE (--overwrite).",
                 out_dir), call. = FALSE)
  }
  games <- vvf_load_v1_inputs(max_season = VVF_MAX_INPUT_SEASON)$games
  old <- options(nflreadr.cache = "off", nflreadr.verbose = FALSE)
  on.exit(options(old), add = TRUE)
  ctx <- vvf_build_context(load_schedules(seasons = seasons), games)
  inj <- vvf_build_injuries(load_injuries(seasons = seasons), games)
  ven <- vvf_build_venues(sort(unique(ctx$ctx$stadium_id[!is.na(ctx$ctx$stadium_id)])), http_get, sleep)
  files <- list(game_context = ctx$ctx, injuries_team = inj$team, injuries_qb = inj$qb, venues = ven$venues)
  for (nm in names(files)) if ("season" %in% names(files[[nm]])) vvf_guard_seasons(files[[nm]]$season, VVF_MAX_INPUT_SEASON, nm)
  derived <- list()
  for (nm in names(files)) {
    path <- file.path(out_dir, paste0(nm, ".csv"))
    vvf_write_csv(files[[nm]], path)
    derived[[nm]] <- list(file = basename(path), rows = nrow(files[[nm]]), sha256 = vvf_sha256(path))
  }
  meta <- list(built_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), max_season = VVF_MAX_INPUT_SEASON,
               seasons = range(seasons), builder = "backtest/vvf/build_inputs.R",
               nflreadr_version = as.character(utils::packageVersion("nflreadr")), r_version = R.version.string,
               sources = list(schedules = ctx$meta, injuries = inj$meta, venues = ven$meta), derived = derived)
  vvf_write_json(meta, file.path(out_dir, "SOURCES.json"))
  invisible(meta)
}

#   Rscript backtest/vvf/build_inputs.R <out_dir> [--overwrite]
# makes live requests. Without --overwrite it refuses a directory that already holds locked
# inputs, backtest/vvf/data/ included: a rebuild there would change the committed sha256s.
if (sys.nframe() == 0L) {
  e <- environment()
  sys.source(file.path("backtest", "common.R"), envir = e)
  sys.source(file.path("backtest", "vvf", "common.R"), envir = e)
  args <- commandArgs(trailingOnly = TRUE)
  pos <- args[!startsWith(args, "--")]
  if (length(pos) != 1L) stop("usage: Rscript backtest/vvf/build_inputs.R <out_dir> [--overwrite]", call. = FALSE)
  m <- vvf_build_inputs(out_dir = pos[[1]], overwrite = "--overwrite" %in% args)
  str(m$derived)
}
