# §9 of HYPOTHESES.md: which markets Kalshi's Liquidity Incentive Program pays resting orders on. One keyless pass over
# GET /incentive_programs?status=active&type=liquidity (one request a second, up to 40 pages of 1,000), through the
# capture layer's GET; --offline re-reads the saved pages. period_reward is in centi-cents (10,000 = $1), per Kalshi's
# SDK docs (IncentiveProgram). Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/kalshi_incentives.R <out_dir> <raw_dir> [--offline]
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE); offline <- "--offline" %in% args
args <- grep("^--", args, value = TRUE, invert = TRUE); out <- args[1]; raw <- args[2]
dir.create(out, recursive = TRUE, showWarnings = FALSE); dir.create(raw, recursive = TRUE, showWarnings = FALSE)
cfg <- new.env(); sys.source("config.R", envir = cfg); source("R/capture_raw.R")
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))   # PLAYER: the player-prop series
`%||%` <- function(a, b) if (is.null(a)) b else a
page_text <- function(pg, cursor) {
  f <- file.path(raw, sprintf("lip_p%02d.body.gz", pg))
  if (offline) { if (!file.exists(f)) return(NULL); con <- gzfile(f, "r"); on.exit(close(con)); return(paste(readLines(con, warn = FALSE), collapse = "\n")) }
  u <- paste0(KALSHI_BASE, "/incentive_programs?status=active&type=liquidity&limit=1000", if (nzchar(cursor)) paste0("&cursor=", utils::URLencode(cursor, reserved = TRUE)) else "")
  r <- capture_http_get(u, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC, cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
  if (is.null(r$body)) stop(sprintf("kalshi_incentives: page %d failed (%s)", pg, r$error), call. = FALSE)
  con <- gzfile(f, "wb"); writeBin(r$body, con); close(con); rawToChar(r$body)
}
rows <- list(); cursor <- ""
for (pg in 1:40) {
  txt <- page_text(pg, cursor); if (is.null(txt)) break
  j <- jsonlite::parse_json(txt)
  rows[[pg]] <- rbindlist(lapply(j$incentive_programs, function(x) data.table(ticker = x$market_ticker %||% NA_character_, reward_usd = as.numeric(x$period_reward %||% NA) / 1e4,
    target_contracts = as.numeric(x$target_size_fp %||% NA), discount_bps = as.numeric(x$discount_factor_bps %||% NA), start = x$start_date %||% NA_character_,
    end = x$end_date %||% NA_character_)))
  cursor <- j$next_cursor %||% ""; if (!nzchar(cursor)) break
}
fetched <- file.info(file.path(raw, "lip_p01.body.gz"))$mtime
ip <- unique(rbindlist(rows))
ip[, `:=`(series = sub("-.*$", "", ticker), nfl = startsWith(ticker, "KXNFL"))]
ip[, nfl_kind := fifelse(!nfl, NA_character_, fifelse(series %in% c("KXNFLGAME", "KXNFLSPREAD", "KXNFLTOTAL", "KXNFLTEAMTOTAL"), "game line",
                                                      fifelse(series %in% PLAYER, "player prop", "other NFL")))]
summ <- data.table(pages = length(rows), programs = nrow(ip), nfl_programs = sum(ip$nfl), nfl_game_line = sum(ip$nfl_kind == "game line", na.rm = TRUE),
                   nfl_player_prop = sum(ip$nfl_kind == "player prop", na.rm = TRUE), nfl_reward_usd_per_period = sum(ip[nfl == TRUE, reward_usd]),
                   saved_at = format(fetched, "%Y-%m-%dT%H:%MZ", tz = "UTC"))
nfl <- ip[nfl == TRUE, .(programs = .N, reward_usd_per_period = sum(reward_usd), median_target_contracts = stats::median(target_contracts),
                         first_start = min(start), last_end = max(end)), by = .(series, nfl_kind)][order(-programs)]
fwrite(summ, file.path(out, "kalshi_incentives_summary.csv")); fwrite(nfl, file.path(out, "kalshi_incentives_nfl.csv"))
options(width = 200); print(summ); print(nfl)
