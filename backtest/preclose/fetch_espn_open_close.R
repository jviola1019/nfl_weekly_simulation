#!/usr/bin/env Rscript
# =============================================================================
# nfl_preclose_v1: 2026 opening and closing moneylines at the venue ESPN reports
# (DraftKings, provider 100), one row per played game, from ESPN's core API: keyless,
# at most one request a second, a truthful user agent. A 403 stops the script (a refusal
# is never worked around); a 429 backs off. Raw responses go to <raw_dir> (private, never
# committed); <out_csv> gets v1's espn_open_close layout with American prices.
#   Rscript backtest/preclose/fetch_espn_open_close.R <raw_dir> <out_csv> [--weeks=1:8]
# 2026 only: a 2025 game stops the script.
# =============================================================================
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
pos <- grep("^--", args, value = TRUE, invert = TRUE); stopifnot(length(pos) == 2L)
raw <- pos[1]; out_csv <- pos[2]; dir.create(raw, recursive = TRUE, showWarnings = FALSE)
wk_arg <- sub("^--weeks=", "", grep("^--weeks=", args, value = TRUE))
weeks <- if (length(wk_arg)) { r <- as.integer(strsplit(wk_arg, ":", fixed = TRUE)[[1]]); r[1]:r[length(r)] } else 1:18
UA <- "nfl-research/1.0 (personal research; contact: repo owner)"
BASE <- "https://sports.core.api.espn.com/v2/sports/football/leagues/nfl"
s <- as.data.table(nflreadr::load_schedules(2026))[game_type == "REG" & week %in% weeks & !is.na(result) & !is.na(espn)]
stopifnot(nrow(s) > 0, all(s$season == 2026))
amer <- function(x) suppressWarnings(as.integer(sub("^\\+", "", as.character(x %||% NA_character_))))
rows <- list(); last <- 0
for (i in seq_len(nrow(s))) {
  f <- file.path(raw, sprintf("odds_%s.json.gz", s$espn[i]))
  if (!file.exists(f)) {
    wait <- 1 - (as.numeric(Sys.time()) - last); if (wait > 0) Sys.sleep(wait)
    for (try in 1:4) {
      last <- as.numeric(Sys.time())
      r <- tryCatch(curl::curl_fetch_memory(sprintf("%s/events/%s/competitions/%s/odds", BASE, s$espn[i], s$espn[i]),
                                            handle = curl::new_handle(useragent = UA, timeout = 20)), error = function(e) NULL)
      code <- if (is.null(r)) NA_integer_ else r$status_code
      if (identical(code, 403L)) stop("fetch_espn_open_close: HTTP 403 (refused); stopping, never worked around", call. = FALSE)
      if (identical(code, 429L) || is.na(code)) { Sys.sleep(5 * try); next }
      break
    }
    if (!identical(code, 200L)) { message(sprintf("%s: HTTP %s", s$game_id[i], code)); next }
    con <- gzfile(f, "wb"); writeBin(r$content, con); close(con)
  }
  txt <- paste(readLines(gzfile(f), warn = FALSE), collapse = "\n")
  j <- jsonlite::parse_json(txt)
  it <- Filter(function(x) identical(as.integer(x$provider$id %||% NA), 100L), j$items %||% list())
  if (!length(it)) next
  h <- it[[1]]$homeTeamOdds; a <- it[[1]]$awayTeamOdds
  rows[[length(rows) + 1L]] <- data.table(game_id = s$game_id[i], season = 2026L, week = s$week[i], provider = 100L, provider_name = "DraftKings",
                                          h_open = amer(h$open$moneyLine$american), a_open = amer(a$open$moneyLine$american),
                                          h_close = amer(h$close$moneyLine$american), a_close = amer(a$close$moneyLine$american))
}
oc <- rbindlist(rows)
stopifnot(!anyDuplicated(oc$game_id), !any(oc$season == 2025))
fwrite(oc, out_csv, eol = "\n")
cat(sprintf("%d of %d played games with a DraftKings open and close (weeks %d-%d)\n", oc[is.finite(h_open) & is.finite(a_open) & is.finite(h_close) & is.finite(a_close), .N],
            nrow(s), min(weeks), max(weeks)))
