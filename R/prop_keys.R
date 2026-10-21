# =============================================================================
# FILE: R/prop_keys.R
# PURPOSE: Keys for joining prop quotes to games and players (audit P9).
#   Teams: one canonical spelling (the nflverse schedule's: LA for the Rams).
#   Players: gsis ids resolved once, exactly, through a crosswalk. No fuzzy matching.
# =============================================================================

# The schedule's spelling (nflreadr::load_schedules): 32 teams
CANONICAL_TEAMS <- c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", "DET",
                     "GB", "HOU", "IND", "JAX", "KC", "LA", "LAC", "LV", "MIA", "MIN", "NE", "NO",
                     "NYG", "NYJ", "PHI", "PIT", "SEA", "SF", "TB", "TEN", "WAS")

# ffverse (load_ff_playerids), legacy and provider spellings -> canonical
TEAM_ALIAS_TO_CANONICAL <- c(
  LAR = "LA", RAM = "LA", STL = "LA", OAK = "LV", LVR = "LV", SD = "LAC", SDC = "LAC",
  WSH = "WAS", JAC = "JAX", ARZ = "ARI", GBP = "GB", KCC = "KC", NEP = "NE", NOS = "NO",
  SFO = "SF", TBB = "TB"
)

TEAM_NAME_TO_CANONICAL <- c(
  "Arizona Cardinals" = "ARI", "Atlanta Falcons" = "ATL", "Baltimore Ravens" = "BAL",
  "Buffalo Bills" = "BUF", "Carolina Panthers" = "CAR", "Chicago Bears" = "CHI",
  "Cincinnati Bengals" = "CIN", "Cleveland Browns" = "CLE", "Dallas Cowboys" = "DAL",
  "Denver Broncos" = "DEN", "Detroit Lions" = "DET", "Green Bay Packers" = "GB",
  "Houston Texans" = "HOU", "Indianapolis Colts" = "IND", "Jacksonville Jaguars" = "JAX",
  "Kansas City Chiefs" = "KC", "Los Angeles Chargers" = "LAC", "Los Angeles Rams" = "LA",
  "Las Vegas Raiders" = "LV", "Miami Dolphins" = "MIA", "Minnesota Vikings" = "MIN",
  "New England Patriots" = "NE", "New Orleans Saints" = "NO", "New York Giants" = "NYG",
  "New York Jets" = "NYJ", "Philadelphia Eagles" = "PHI", "Pittsburgh Steelers" = "PIT",
  "Seattle Seahawks" = "SEA", "San Francisco 49ers" = "SF", "Tampa Bay Buccaneers" = "TB",
  "Tennessee Titans" = "TEN", "Washington Commanders" = "WAS"
)

#' Canonical team abbreviation
#'
#' @param x Character: abbreviation in any case, alias, or full team name
#' @return Character of the same length: canonical abbreviation, or NA for blanks,
#'   free agents ("FA") and anything unknown. Never "".
normalize_team_abbr <- function(x) {
  out <- toupper(trimws(as.character(x)))
  out[!nzchar(out)] <- NA_character_
  by_name <- match(out, toupper(names(TEAM_NAME_TO_CANONICAL)))
  out[!is.na(by_name)] <- unname(TEAM_NAME_TO_CANONICAL)[by_name[!is.na(by_name)]]
  by_alias <- match(out, names(TEAM_ALIAS_TO_CANONICAL))
  out[!is.na(by_alias)] <- unname(TEAM_ALIAS_TO_CANONICAL)[by_alias[!is.na(by_alias)]]
  out[!(out %in% CANONICAL_TEAMS)] <- NA_character_
  out
}

#' Comparable key for a person's name
#'
#' Lower-case ASCII; periods and apostrophes removed; other punctuation becomes a space;
#' a trailing generational suffix (jr, sr, ii, iii, iv, v) is dropped.
normalize_person_name <- function(x) {
  out <- iconv(as.character(x), to = "ASCII//TRANSLIT")
  out <- tolower(out)
  out <- gsub("[.']", "", out)
  out <- gsub("[^a-z ]", " ", out)
  out <- trimws(gsub("[[:space:]]+", " ", out))
  out <- sub(" (jr|sr|ii|iii|iv|v)$", "", out)
  out[is.na(out) | !nzchar(out)] <- NA_character_
  out
}

#' Player crosswalk from the ffverse id table
#'
#' @param ff Table with gsis_id, name, team, position (default: nflreadr::load_ff_playerids())
#' @return Tibble player_id (gsis), name, team (canonical), position
build_player_xwalk <- function(ff = nflreadr::load_ff_playerids()) {
  need <- c("gsis_id", "name", "team", "position")
  if (!all(need %in% names(ff))) {
    stop(sprintf("build_player_xwalk: missing columns: %s", paste(setdiff(need, names(ff)), collapse = ", ")),
         call. = FALSE)
  }
  out <- tibble::tibble(
    player_id = as.character(ff$gsis_id),
    name = as.character(ff$name),
    team = normalize_team_abbr(ff$team),
    position = as.character(ff$position)
  )
  out <- out[!is.na(out$player_id) & !is.na(out$name) & !is.na(out$team), , drop = FALSE]
  unique(out)
}

#' Resolve provider player names to gsis ids, exactly
#'
#' A (normalized name, canonical team) pair must match exactly one player in the crosswalk.
#' With no team given, the name alone must match exactly one player. Anything else stays
#' unresolved (NA id) with a status, and the count is logged.
#'
#' @param names Provider player names
#' @param teams Provider team (abbreviation or name) per name; NA allowed
#' @param xwalk Output of build_player_xwalk()
#' @return Tibble player_id, id_status (matched | no_match | ambiguous | bad_team)
resolve_player_ids <- function(names, teams, xwalk) {
  n <- length(names)
  out <- tibble::tibble(player_id = rep(NA_character_, n), id_status = rep("no_match", n))
  if (n == 0) return(out)
  if (length(teams) != n) stop("resolve_player_ids: names and teams must have the same length", call. = FALSE)

  key_name <- normalize_person_name(names)
  raw_team_present <- !is.na(teams) & nzchar(trimws(as.character(teams)))
  key_team <- normalize_team_abbr(teams)
  xw_name <- normalize_person_name(xwalk$name)
  xw_team <- normalize_team_abbr(xwalk$team)

  pair <- paste(key_name, key_team, raw_team_present, sep = "|")
  for (p in unique(pair[!duplicated(pair)])) {
    i <- which(pair == p)
    first <- i[1]
    if (is.na(key_name[first])) next
    if (raw_team_present[first] && is.na(key_team[first])) {
      out$id_status[i] <- "bad_team"
      next
    }
    hit <- !is.na(xw_name) & xw_name == key_name[first]
    if (!is.na(key_team[first])) hit <- hit & !is.na(xw_team) & xw_team == key_team[first]
    ids <- unique(xwalk$player_id[hit])
    if (length(ids) == 1) {
      out$player_id[i] <- ids
      out$id_status[i] <- "matched"
    } else if (length(ids) > 1) {
      out$id_status[i] <- "ambiguous"
    }
  }

  bad <- out$id_status != "matched"
  if (any(bad)) {
    counts <- table(out$id_status[bad])
    message(sprintf("  Player ids: %d matched, %d unresolved (%s)", sum(!bad), sum(bad),
                    paste(sprintf("%s=%d", names(counts), as.integer(counts)), collapse = ", ")))
  }
  out
}
