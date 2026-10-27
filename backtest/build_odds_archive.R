#!/usr/bin/env Rscript
# =============================================================================
# Decision-time archive: ESPN game openers and closes, 2023-2024 (roadmap D1)
# =============================================================================
#   Rscript backtest/build_odds_archive.R <raw_dir>                  # fetch ~570 games at 1 request/second
#   Rscript backtest/build_odds_archive.R <raw_dir> --from-raw       # rebuild offline from <raw_dir>
#   options: --seasons=2023,2024   --out=backtest/data/odds_archive
#
# <raw_dir> receives one gzipped ESPN response per game (not committed) and a fetch log
# (fetch_log.ndjson). The derived CSVs and SOURCES.json (the sha256 of every raw response
# and every derived file) go to the output directory and are committed, as
# backtest/build_inputs.R does for backtest/data/.
#
# THE 2025 HOLDOUT IS SEALED: any season after 2024 stops the script before it loads a
# schedule or makes a request (R/odds/archive.R). Exit status 1 when any game could not be
# fetched; the files are still written, with the failures listed in SOURCES.json.
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default) {
  hit <- grep(sprintf("^--%s=", name), args, value = TRUE)
  if (length(hit) == 0) default else sub(sprintf("^--%s=", name), "", hit[[1]])
}
positional <- args[!startsWith(args, "--")]
if (length(positional) != 1L) {
  stop("usage: Rscript backtest/build_odds_archive.R <raw_dir> [--seasons=2023,2024] [--from-raw] [--out=DIR]")
}
raw_dir <- positional[[1]]
from_raw <- "--from-raw" %in% args

if (!file.exists("config.R") || !dir.exists("R/odds")) {
  stop("Run from the repository root (config.R and R/odds not found)")
}
cfg_env <- new.env()
sys.source("config.R", envir = cfg_env)
source("R/capture_raw.R")
for (f in sort(list.files("R/odds", pattern = "\\.R$", full.names = TRUE))) source(f)

seasons <- as.integer(strsplit(arg_value("seasons", "2023,2024"), ",", fixed = TRUE)[[1]])
odds_archive_assert_seasons(seasons)   # before any schedule is loaded or any request is made
out_dir <- arg_value("out", ODDS_ARCHIVE_DIR)

if (from_raw) {
  games <- odds_archive_read_event_map(file.path(out_dir, "event_map.csv"))
  games <- games[games$season %in% seasons, , drop = FALSE]
  fetch_fn <- odds_replay_fetch(raw_dir)
} else {
  games <- odds_archive_games(nflreadr::load_schedules(seasons), seasons)
  fetch_fn <- odds_http_get
}
message(sprintf("Odds archive: %d games, seasons %s, %s", nrow(games), paste(seasons, collapse = ", "),
                if (from_raw) "replaying stored raw responses" else "fetching at 1 request/second"))

# a replay reads local files, so it is not throttled (the 1 request/second floor protects hosts)
# and writes no fetch log, which records only the requests that reached ESPN
provider <- provider_espn_core(cfg = odds_http_config(env = cfg_env), fetch_fn = fetch_fn,
                               log_path = if (from_raw) NULL else file.path(raw_dir, "fetch_log.ndjson"),
                               sleep_fn = if (from_raw) function(s) invisible(NULL) else Sys.sleep)
res <- odds_archive_build(games, provider, out_dir, raw_dir)

cat("\nCoverage (games with a complete open and close):\n")
print(res$coverage[res$coverage$venue_id == "any", ], row.names = FALSE)
cat("\n", res$status$source, ": ", res$status$status, " - ", res$status$detail, "\n", sep = "")
verify <- odds_archive_verify(out_dir, raw_dir)
if (length(verify)) stop("odds archive: verification failed: ", paste(verify, collapse = "; "))
if (odds_archive_exit_status(res$sources) > 0L) {
  message(sprintf("INCOMPLETE: %d game(s) could not be fetched; see fetch_failures in SOURCES.json",
                  length(res$sources$fetch_failures)))
  quit(status = 1)
}
if (!identical(res$status$status, "ok")) {
  message("Every game was fetched; the gaps above are in what ESPN serves (source_detail in SOURCES.json)")
}
