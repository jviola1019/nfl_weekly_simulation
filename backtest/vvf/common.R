# =============================================================================
# Variable validation framework (VVF, master plan A3): shared constants, seal
# guards, sha256-locked loaders, writers and geometry helpers.
#
# Ported with attribution from PR #205 (validation sprint v2, branch
# feat/validation-sprint-v2, backtest/v2/common.R at 759dd1c; owner decision
# 2026-10-20: port the feature builder, the input builder and the inputs).
# Changes from v2:
#   - names use the vvf_ prefix;
#   - the season guard also refuses every sealed season: VVF_SEALED_SEASONS,
#     joined with config.R's SEALED_SEASONS once PR #218 defines it;
#   - vvf_assert_readable() refuses the 2024-2025 ESPN opener/close file that
#     the A2 power study read (design 2026-10-20 §6, disclosures);
#   - the inputs live in backtest/vvf/data/, byte-identical copies of v2's
#     backtest/data_v2/ (their SOURCES.json still names v2's builder, which
#     made them on 2026-09-30).
# Source after backtest/common.R.
# =============================================================================

suppressPackageStartupMessages(library(data.table))

VVF_MAX_INPUT_SEASON <- 2024L   # no input row may be later (v2's BT2_MAX_INPUT_SEASON)
VVF_SEALED_SEASONS <- 2025L     # the shared 2025 holdout of nfl_games_v2 and nfl_preclose_v1
VVF_FIRST_PRED_SEASON <- 2010L
VVF_DATA_DIR <- file.path("backtest", "vvf", "data")
# 2025 ESPN opener and close prices, read once on 2026-09-29 for the A2 power study
VVF_FORBIDDEN_FILES <- "espn_open_close_2024_2025.csv"
VVF_FORBIDDEN_DIRS <- "reports/2026-09-29/clv-power"

`%||%` <- function(a, b) if (is.null(a)) b else a

# Relocated franchises share one history (the map of backtest/build_inputs.R),
# plus alternative codes seen in some nflverse tables
VVF_FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA", LAR = "LA", JAC = "JAX")
vvf_franchise <- function(team) {
  out <- unname(VVF_FRANCHISE[team])
  ifelse(is.na(out), team, out)
}

#' One top-level assignment from config.R, evaluated on its own: nothing else
#' in config.R runs. NULL when `name` is not assigned and `required` is FALSE.
#' Safety: only the right-hand side of an assignment in this repository's own
#' tracked config.R is evaluated, in baseenv() (as helper-extract.R does).
vvf_config_value <- function(name, config_path = "config.R", required = TRUE) {
  if (!file.exists(config_path)) {
    stop("vvf_config_value: missing ", config_path, " (run from the repository root)", call. = FALSE)
  }
  val <- NULL
  found <- FALSE
  for (e in parse(config_path, keep.source = FALSE)) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(name))) {
      val <- eval(e[[3]], baseenv())
      found <- TRUE
    }
  }
  if (!found && required) stop(sprintf("vvf_config_value: %s is not assigned in %s", name, config_path), call. = FALSE)
  val
}

#' Sealed seasons: VVF's own list joined with config.R's SEALED_SEASONS (PR #218)
vvf_sealed_seasons <- function(config_path = "config.R") {
  extra <- vvf_config_value("SEALED_SEASONS", config_path, required = FALSE)
  sort(unique(c(VVF_SEALED_SEASONS, as.integer(extra))))
}

#' Stop if any season is sealed or exceeds `max_season`
vvf_guard_seasons <- function(seasons, max_season = VVF_MAX_INPUT_SEASON, what = "data",
                              sealed = vvf_sealed_seasons()) {
  s <- suppressWarnings(as.integer(seasons))
  bad <- !is.na(s) & (s > max_season | s %in% sealed)
  if (any(bad)) {
    stop(sprintf("sealed-season guard: %s contains season %d (input ceiling %d; sealed %s)",
                 what, max(s[bad]), max_season, paste(sealed, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

#' Refuse the 2024-2025 opener/close price file, by name or by directory
vvf_assert_readable <- function(path) {
  norm <- paste0("/", gsub("\\\\", "/", path), "/")
  in_dir <- any(vapply(VVF_FORBIDDEN_DIRS, function(d) grepl(paste0("/", d, "/"), norm, fixed = TRUE), logical(1)))
  if (basename(gsub("\\\\", "/", path)) %in% VVF_FORBIDDEN_FILES || in_dir) {
    stop(sprintf("vvf_assert_readable: refused %s (2025 opener/close prices; design 2026-10-20 §6)", path),
         call. = FALSE)
  }
  invisible(path)
}

vvf_read_csv <- function(path, ...) {
  vvf_assert_readable(path)
  fread(path, ...)
}

#' Run fun() under `seed` (Mersenne-Twister, Inversion, Rejection), restoring
#' the caller's RNG afterwards, as bt_boot_counts() does
vvf_seeded <- function(seed, fun) {
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv()))
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  fun()
}

vvf_sha256 <- function(path) digest::digest(file = path, algo = "sha256")

#' sha256 over the files' own sha256s, in the order given
vvf_result_sha256 <- function(paths) {
  digest::digest(paste(vapply(paths, vvf_sha256, character(1)), collapse = ""), algo = "sha256", serialize = FALSE)
}

vvf_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  fwrite(x, path, eol = "\n", na = "NA")
  invisible(path)
}

vvf_write_text <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  bt_write_text(text, path)
}

vvf_write_json <- function(x, path, digits = NA) {
  vvf_write_text(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = digits,
                                               null = "null", na = "null")), path)
}

#' Load the ported inputs, verifying each file's sha256 against SOURCES.json
vvf_load_inputs <- function(data_dir = VVF_DATA_DIR, max_season = VVF_MAX_INPUT_SEASON) {
  src <- jsonlite::read_json(file.path(data_dir, "SOURCES.json"), simplifyVector = FALSE)
  sealed <- vvf_sealed_seasons()
  out <- list()
  for (nm in names(src$derived)) {
    d <- src$derived[[nm]]
    f <- file.path(data_dir, d$file)
    vvf_assert_readable(f)
    got <- vvf_sha256(f)
    if (!identical(got, d$sha256)) {
      stop(sprintf("vvf_load_inputs: %s sha256 %s != SOURCES %s", d$file, got, d$sha256), call. = FALSE)
    }
    x <- fread(f, na.strings = c("", "NA"), colClasses = list(character = intersect(
      c("game_id", "stadium_id", "gsis_id", "espn", "referee"), names(fread(f, nrows = 0)))))
    if ("season" %in% names(x)) vvf_guard_seasons(x$season, max_season, d$file, sealed)
    out[[nm]] <- x
  }
  out
}

#' Stop if a table carries a sealed season, by its season column or else the season in its
#' game_id. The stages check the table they are given, whatever built it (review I5); a table
#' with neither column has nothing to check.
vvf_guard_table <- function(d, what, sealed = NULL) {
  s <- if ("season" %in% names(d)) d$season else if ("game_id" %in% names(d)) substr(d$game_id, 1L, 4L) else NULL
  s <- unique(suppressWarnings(as.integer(s)))
  s <- s[!is.na(s)]
  if (!length(s)) return(invisible(TRUE))
  vvf_guard_seasons(s, max_season = .Machine$integer.max, what = what, sealed = sealed %||% vvf_sealed_seasons())
}

#' Load the v1 inputs against the nfl_games_v1 window's sha256s, then cut the
#' games at `max_season`
vvf_load_v1_inputs <- function(max_season, window_path = file.path("backtest", "eval_windows", "nfl_games_v1.json")) {
  win <- jsonlite::read_json(window_path, simplifyVector = TRUE)
  for (nm in names(win$data_sha256)) vvf_assert_readable(file.path(win$data_dir, paste0(nm, ".csv")))
  inp <- bt_load_inputs(win$data_dir, win$data_sha256)
  vvf_guard_seasons(inp$games$season, VVF_MAX_INPUT_SEASON, "v1 games.csv")
  for (nm in setdiff(names(inp), "games")) {          # the team and QB tables have no season: their game_id
    if (is.data.frame(inp[[nm]])) vvf_guard_table(inp[[nm]], paste("v1", nm))
  }
  inp$games <- inp$games[season <= max_season]
  inp
}

#' Great-circle distance in km (haversine, R = 6371 km)
vvf_haversine_km <- function(lat1, lon1, lat2, lon2) {
  rad <- pi / 180
  dlat <- (lat2 - lat1) * rad
  dlon <- (lon2 - lon1) * rad
  a <- sin(dlat / 2)^2 + cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2)^2
  2 * 6371 * asin(pmin(1, sqrt(a)))
}

#' UTC offset in hours of time zone `tz` at instant `t` (vectorised over both)
vvf_utc_offset_h <- function(t, tz) {
  out <- rep(NA_real_, length(t))
  for (z in unique(tz[!is.na(tz)])) {
    i <- which(tz == z)
    out[i] <- as.POSIXlt(t[i], tz = z)$gmtoff / 3600
  }
  out
}

#' Local clock hour (fractional) of instant `t` in time zone `tz`
vvf_local_hour <- function(t, tz) {
  out <- rep(NA_real_, length(t))
  for (z in unique(tz[!is.na(tz)])) {
    i <- which(tz == z)
    lt <- as.POSIXlt(t[i], tz = z)
    out[i] <- lt$hour + lt$min / 60
  }
  out
}
