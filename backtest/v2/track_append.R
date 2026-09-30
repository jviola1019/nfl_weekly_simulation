#!/usr/bin/env Rscript
# =============================================================================
# Append graded prospective games to the moneyline tracking file.
#
#   Rscript backtest/v2/track_append.R --bundle <weekly bundle dir> --results <csv> \
#       --out reports/<date>/validation-sprint/tracking/moneyline_prospective.csv
#
# --bundle   a weekly bundle written before kickoff (backtest/prospective.R):
#            manifest.json + game_predictions.json (game_id, candidate,
#            p_home_final, p_home_mkt_novig)
# --results  a CSV with game_id, season, home_score, away_score (for example the
#            nflverse games.csv filtered to the graded week)
# Guards: only seasons >= 2026 are accepted (2018-2024 are the scored windows and
# 2025 is the sealed holdout); only final scores are graded; ties are recorded
# with outcome NA and no score; a (game_id, candidate) already tracked is never
# appended twice; the bundle must have been generated before every graded kickoff
# when the results file carries kickoff_utc.
# =============================================================================

BT2_TRACK_FIRST_SEASON <- 2026L

bt2_track_grade <- function(bundle_dir, results) {
  man <- jsonlite::read_json(file.path(bundle_dir, "manifest.json"), simplifyVector = TRUE)
  if (!identical(man$bundle_kind, "weekly")) stop("track: not a weekly bundle: ", bundle_dir, call. = FALSE)
  pred <- data.table::as.data.table(jsonlite::read_json(file.path(bundle_dir, "game_predictions.json"), simplifyVector = TRUE))
  res <- data.table::as.data.table(results)
  x <- merge(pred, res, by = "game_id")
  if (!nrow(x)) stop("track: no bundle game has a result row", call. = FALSE)
  old <- x[season < BT2_TRACK_FIRST_SEASON]
  if (nrow(old)) stop(sprintf("track: refusing season %d (only seasons >= %d are prospective; 2025 is the sealed holdout)",
                              min(old$season), BT2_TRACK_FIRST_SEASON), call. = FALSE)
  if ("kickoff_utc" %in% names(x)) {
    k <- as.POSIXct(x$kickoff_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    g <- as.POSIXct(man$generated_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    if (any(!is.na(k) & !(g < k))) stop("track: bundle generated after a graded kickoff", call. = FALSE)
  }
  x <- x[!is.na(home_score) & !is.na(away_score)]
  x[, outcome := data.table::fifelse(home_score == away_score, NA_integer_, as.integer(home_score > away_score))]
  x[, `:=`(p_model = p_home_final, p_market = p_home_mkt_novig)]
  eps <- 1e-6
  ll <- function(p, y) { p <- pmin(pmax(p, eps), 1 - eps); -(y * log(p) + (1 - y) * log(1 - p)) }
  x[, `:=`(brier = (p_model - outcome)^2, logloss = ll(p_model, outcome), brier_market = (p_market - outcome)^2,
           bundle_sha256 = digest::digest(file = file.path(bundle_dir, "manifest.json"), algo = "sha256"),
           graded_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))]
  x[, .(game_id, season, week = man$week, candidate, p_model, p_market, outcome, brier, logloss, brier_market,
        bundle_sha256, graded_utc)]
}

bt2_track_append <- function(bundle_dir, results, out_path) {
  new <- bt2_track_grade(bundle_dir, results)
  if (file.exists(out_path)) {
    have <- data.table::fread(out_path, select = c("game_id", "candidate"))
    new <- new[!have, on = c("game_id", "candidate")]
  }
  if (nrow(new)) data.table::fwrite(new, out_path, append = file.exists(out_path), eol = "\n")
  invisible(nrow(new))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag) { i <- match(flag, args); if (is.na(i)) NULL else args[i + 1] }
  b <- get_arg("--bundle"); r <- get_arg("--results"); o <- get_arg("--out")
  if (is.null(b) || is.null(r) || is.null(o)) stop("usage: track_append.R --bundle <dir> --results <csv> --out <csv>")
  suppressPackageStartupMessages(library(data.table))
  n <- bt2_track_append(b, fread(r), o)
  cat(sprintf("appended %d graded rows to %s\n", n, o))
}
