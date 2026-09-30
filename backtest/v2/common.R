# =============================================================================
# Game backtest v2 (validation sprint): shared helpers.
#
# Builds on the v1 helpers in backtest/common.R (sourced first). Everything here
# is season-guarded: v2 code refuses any row from a season after
# BT2_MAX_INPUT_SEASON (the 2025 holdout is sealed), and the sprint's screening
# and candidate evaluation stop at BT2_MAX_SPRINT_SEASON (end of the Tune window).
# All writers emit LF line endings and UTF-8 so that sha256 locks agree across
# Windows and Linux checkouts.
# =============================================================================

suppressPackageStartupMessages(library(data.table))

BT2_MAX_INPUT_SEASON <- 2024L    # no input row may be later (2025 holdout sealed)
BT2_MAX_SPRINT_SEASON <- 2022L   # screening and candidate evaluation: Tune only
BT2_TUNE_SEASONS <- 2018:2022
BT2_BURNIN_SEASONS <- 2010:2017
BT2_FIRST_PRED_SEASON <- 2010L
BT2_DATA_DIR <- file.path("backtest", "data_v2")

`%||%` <- function(a, b) if (is.null(a)) b else a

# Relocated franchises share one history (same map as backtest/build_inputs.R),
# plus alternative codes seen in some nflverse tables
BT2_FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA", LAR = "LA", JAC = "JAX")
bt2_franchise <- function(team) {
  out <- unname(BT2_FRANCHISE[team])
  ifelse(is.na(out), team, out)
}

#' Stop if any season exceeds `max_season` (sealed holdout guard)
bt2_guard_seasons <- function(seasons, max_season = BT2_MAX_INPUT_SEASON, what = "data") {
  s <- suppressWarnings(as.integer(seasons))
  if (any(!is.na(s) & s > max_season)) {
    stop(sprintf("sealed-season guard: %s contains season %d > %d", what, max(s, na.rm = TRUE), max_season),
         call. = FALSE)
  }
  invisible(TRUE)
}

bt2_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  fwrite(x, path, eol = "\n", na = "NA")
  invisible(path)
}

bt2_json_text <- function(x, digits = NA) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = digits, null = "null", na = "null"))
}

bt2_write_text <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n"))), con)
  invisible(path)
}

bt2_write_json <- function(x, path, digits = NA) bt2_write_text(bt2_json_text(x, digits), path)

bt2_sha256 <- function(path) digest::digest(file = path, algo = "sha256")

#' Load the v2 derived inputs, verifying each file's sha256 against SOURCES.json
bt2_load_v2_inputs <- function(data_dir = BT2_DATA_DIR, max_season = BT2_MAX_INPUT_SEASON) {
  src <- jsonlite::read_json(file.path(data_dir, "SOURCES.json"), simplifyVector = FALSE)
  out <- list()
  for (nm in names(src$derived)) {
    d <- src$derived[[nm]]
    f <- file.path(data_dir, d$file)
    got <- bt2_sha256(f)
    if (!identical(got, d$sha256)) stop(sprintf("bt2_load_v2_inputs: %s sha256 %s != SOURCES %s", d$file, got, d$sha256),
                                        call. = FALSE)
    x <- fread(f, na.strings = c("", "NA"), colClasses = list(character = intersect(
      c("game_id", "stadium_id", "gsis_id", "espn", "referee"), names(fread(f, nrows = 0)))))
    if ("season" %in% names(x)) bt2_guard_seasons(x$season, max_season, d$file)
    out[[nm]] <- x
  }
  out
}

#' Great-circle distance in km (haversine, R = 6371 km)
bt2_haversine_km <- function(lat1, lon1, lat2, lon2) {
  rad <- pi / 180
  dlat <- (lat2 - lat1) * rad; dlon <- (lon2 - lon1) * rad
  a <- sin(dlat / 2)^2 + cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2)^2
  2 * 6371 * asin(pmin(1, sqrt(a)))
}

#' UTC offset in hours of time zone `tz` at instant `t` (vectorised over both)
bt2_utc_offset_h <- function(t, tz) {
  out <- rep(NA_real_, length(t))
  for (z in unique(tz[!is.na(tz)])) {
    i <- which(tz == z)
    out[i] <- as.POSIXlt(t[i], tz = z)$gmtoff / 3600
  }
  out
}

#' Local clock hour (fractional) of instant `t` in time zone `tz`
bt2_local_hour <- function(t, tz) {
  out <- rep(NA_real_, length(t))
  for (z in unique(tz[!is.na(tz)])) {
    i <- which(tz == z)
    lt <- as.POSIXlt(t[i], tz = z)
    out[i] <- lt$hour + lt$min / 60
  }
  out
}
