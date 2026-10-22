# =============================================================================
# Venues by nflverse stadium_id (audit M21/S3; output audit F6, 2026-10-21)
# =============================================================================
# The engine used to join a hand-typed table of 29 venues by name. nflverse renames venues
# (Heinz Field -> Acrisure Stadium) and keeps the id, so every renamed, missing (Atlanta's
# Mercedes-Benz Stadium) or international venue fell back to league-average weather in Kansas
# and lost its roof. data/reference/stadiums.csv holds every id nflverse used in 2006-2026.

STADIUM_ROOF_TYPES <- c("outdoors", "dome", "retractable")

#' The stadium reference: stadium_id, name, city, lat, lon, roof_type, note. Stops on a
#' malformed file rather than returning a partial table.
load_stadium_reference <- function(path = file.path("data", "reference", "stadiums.csv")) {
  if (!file.exists(path)) stop("load_stadium_reference: no stadium reference at ", path, call. = FALSE)
  ref <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = "", encoding = "UTF-8")
  need <- c("stadium_id", "name", "lat", "lon", "roof_type")
  miss <- setdiff(need, names(ref))
  if (length(miss)) stop("load_stadium_reference: missing column(s) ", paste(miss, collapse = ", "), call. = FALSE)
  bad <- ref$stadium_id[is.na(ref$stadium_id) | !is.finite(ref$lat) | !is.finite(ref$lon) |
                          !ref$roof_type %in% STADIUM_ROOF_TYPES | duplicated(ref$stadium_id)]
  if (length(bad)) stop("load_stadium_reference: bad or duplicate row(s): ", paste(bad, collapse = ", "), call. = FALSE)
  ref
}

#' Is a game indoors? `roof` is nflverse's per-game value (dome, closed, open, outdoors; NA
#' before a retractable roof's status is known); `roof_type` comes from the reference.
#' A venue without a roof is never indoors, whatever nflverse says (it marks some open-air
#' international venues "dome"); a retractable roof counts as closed until it is reported open.
stadium_is_indoor <- function(roof, roof_type) {
  roof <- tolower(as.character(roof))
  has_roof <- roof_type %in% c("dome", "retractable")
  reported_closed <- !is.na(roof) & roof %in% c("closed", "dome")
  has_roof & (reported_closed | is.na(roof))
}

#' Join a slate (game_id, stadium_id, roof) to the reference: adds lat, lon, roof_type and dome.
#' A game whose stadium_id is not in the reference keeps NA coordinates, takes its roof from
#' nflverse alone, and is named in a message (the weather step then logs its fallback).
attach_stadiums <- function(slate, ref) {
  if (!"stadium_id" %in% names(slate)) stop("attach_stadiums: the slate has no stadium_id column", call. = FALSE)
  if (!"roof" %in% names(slate)) slate$roof <- NA_character_
  idx <- match(slate$stadium_id, ref$stadium_id)
  slate$lat <- ref$lat[idx]
  slate$lon <- ref$lon[idx]
  slate$roof_type <- ref$roof_type[idx]
  unknown <- is.na(idx)
  if (any(unknown)) {
    message(sprintf("Stadium reference: %d game(s) with a stadium_id not in data/reference/stadiums.csv: %s",
                    sum(unknown), paste(sprintf("%s (%s)", slate$game_id[unknown], slate$stadium_id[unknown]), collapse = ", ")))
  }
  nflverse_indoor <- tolower(as.character(slate$roof)) %in% c("closed", "dome")
  slate$dome <- ifelse(unknown, nflverse_indoor, stadium_is_indoor(slate$roof, slate$roof_type))
  slate
}
