# =============================================================================
# Spike: ESPN BET prop archive, priced share and selection-bias test
# (measurement, not production)
# =============================================================================
# Usage (from the repo root):
#   Rscript scripts/spike/espn_bet_bias.R [--sample] [--out=DIR] [--max-minutes=55]
#                                         [--cache=DIR]
#
# For every 2024 regular-season game and every 2025 week 1-13 game, fetch all
# pages of .../odds/58/propBets (ESPN BET). For four markets, classify each row
# as priced (an American price on over or under, open or current) or unpriced
# (line only), join the athlete to nflverse weekly stats, and run bias_test()
# on the over/TD hit rate of priced versus unpriced rows, per market.
#
# Outcomes: anytime TD = rushing_tds + receiving_tds >= the rung (1 for the
# 1+ rung; passing TDs excluded); over/unders = stat > open$target$value.
# Athletes without a gsis match, or without a weekly stat row, are counted and
# excluded, never dropped silently. Every failed request is written to
# espn_bet_failures.csv. Page bodies are cached (gitignored) so a rerun does not
# refetch.
# =============================================================================

if (!file.exists("config.R")) stop("Run from the repo root (config.R not found)")
source("R/capture_raw.R")
source("scripts/spike/spike_helpers.R")
cfg <- new.env()
sys.source("config.R", envir = cfg)

args <- commandArgs(trailingOnly = TRUE)
arg_val <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[1]) else default
}
SAMPLE <- "--sample" %in% args
OUT_DIR <- arg_val("out", "reports/2026-09-29/spike")
MAX_MINUTES <- as.numeric(arg_val("max-minutes", "55"))
CACHE_DIR <- arg_val("cache", file.path(cfg$CAPTURE_ROOT, "spike_cache", "espn_propbets"))
PROVIDER <- 58L
MARKETS <- c(
  anytime_td = "Anytime Touchdown Scorer",
  receiving_yards = "Total Receiving Yards (incl. overtime)",
  receptions = "Total Receptions (incl. overtime)",
  rushing_yards = "Total Rushing Yards (incl. overtime)"
)
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CACHE_DIR, recursive = TRUE, showWarnings = FALSE)

started <- Sys.time()
deadline <- started + MAX_MINUTES * 60
log_msg <- function(...) message(format(Sys.time(), "%H:%M:%S "), sprintf(...))

# ---- HTTP with failure ledger and body cache ---------------------------------
ledger <- new.env()
ledger$fail <- list()
ledger$network <- 0L
ledger$cached <- 0L
fetch_page <- function(event_id, page) {
  cache_file <- file.path(CACHE_DIR, sprintf("%s_p%d.json.gz", event_id, page))
  if (file.exists(cache_file)) {
    ledger$cached <- ledger$cached + 1L
    con <- gzfile(cache_file, "rb")
    on.exit(close(con))
    text <- paste(readLines(con, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    return(jsonlite::fromJSON(text, simplifyVector = FALSE))
  }
  url <- espn_prop_bets_url(event_id, PROVIDER, page)
  res <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC,
                          cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
  ledger$network <- ledger$network + 1L
  err <- res$error
  parsed <- NULL
  if (!is.null(res$body)) {
    parsed <- tryCatch(
      jsonlite::fromJSON(rawToChar(res$body), simplifyVector = FALSE),
      error = function(e) {
        err <<- paste("JSON parse error:", conditionMessage(e))
        NULL
      }
    )
  }
  if (is.null(parsed)) {
    ledger$fail[[length(ledger$fail) + 1]] <- data.frame(
      stage = "propbets", key = sprintf("%s_p%d", event_id, page), url = url,
      status = res$status %||% NA_integer_, error = err %||% NA_character_,
      stringsAsFactors = FALSE
    )
    return(NULL)
  }
  con <- gzfile(cache_file, "wb")
  writeBin(res$body, con)
  close(con)
  parsed
}

# ---- Games ---------------------------------------------------------------------
sched <- as.data.frame(nflreadr::load_schedules(2024:2025))
games <- sched[sched$game_type == "REG" &
                 (sched$season == 2024 | (sched$season == 2025 & sched$week <= 13)), ]
games$kickoff_utc <- as.POSIXct(paste(games$gameday, games$gametime),
                                format = "%Y-%m-%d %H:%M", tz = "America/New_York")
attr(games$kickoff_utc, "tzone") <- "UTC"
games <- games[order(games$season, games$week, games$game_id), ]
if (SAMPLE) games <- games[c(1, 150, nrow(games)), ]
log_msg("games planned: %d", nrow(games))

side_american <- function(side) {
  if (is.null(side) || is.null(side$american) || !nzchar(side$american)) NA_character_ else side$american
}
athlete_id <- function(item) {
  ref <- item$athlete$`$ref`
  if (is.null(ref)) return(NA_character_)
  sub("\\?.*$", "", sub("^.*/athletes/", "", ref))
}

# ---- Scan -----------------------------------------------------------------------
row_list <- list()
game_rows <- list()
type_counts <- list()
completed <- 0L
for (g in seq_len(nrow(games))) {
  if (Sys.time() >= deadline) break
  gm <- games[g, ]
  first <- fetch_page(gm$espn, 1)
  pages_total <- if (is.null(first)) NA_integer_ else max(1L, as.integer(first$pageCount %||% 1L))
  items <- if (is.null(first)) list() else first$items %||% list()
  failed_pages <- if (is.null(first)) 1L else 0L
  if (!is.na(pages_total) && pages_total > 1) {
    for (p in 2:pages_total) {
      nxt <- fetch_page(gm$espn, p)
      if (is.null(nxt)) failed_pages <- failed_pages + 1L else items <- c(items, nxt$items %||% list())
    }
  }
  types <- vapply(items, function(i) i$type$name %||% NA_character_, character(1))
  priced <- vapply(items, espn_row_is_priced, logical(1))
  if (length(items)) {
    type_counts[[length(type_counts) + 1]] <- data.frame(
      season = gm$season, market = types, priced = priced, stringsAsFactors = FALSE
    )
  }
  keep <- which(types %in% MARKETS)
  if (length(keep)) {
    row_list[[length(row_list) + 1]] <- data.frame(
      season = gm$season, week = gm$week, game_id = gm$game_id, espn_event = gm$espn,
      kickoff_utc = gm$kickoff_utc,
      market = names(MARKETS)[match(types[keep], MARKETS)],
      athlete_espn_id = vapply(items[keep], athlete_id, character(1)),
      open_target = vapply(items[keep], function(i) as.numeric(i$open$target$value %||% NA_real_), numeric(1)),
      current_target = vapply(items[keep], function(i) as.numeric(i$current$target$value %||% NA_real_), numeric(1)),
      priced = priced[keep],
      open_over_american = vapply(items[keep], function(i) side_american(i$open$over), character(1)),
      open_under_american = vapply(items[keep], function(i) side_american(i$open$under), character(1)),
      last_updated = vapply(items[keep], function(i) i$lastUpdated %||% NA_character_, character(1)),
      stringsAsFactors = FALSE
    )
  }
  game_rows[[length(game_rows) + 1]] <- data.frame(
    season = gm$season, week = gm$week, game_id = gm$game_id, espn_event = gm$espn,
    pages = pages_total, failed_pages = failed_pages, items_total = length(items),
    items_priced = sum(priced), items_4_markets = length(keep),
    status = if (is.null(first)) "failed" else if (failed_pages > 0) "partial" else
      if (length(items) == 0) "empty" else "ok",
    stringsAsFactors = FALSE
  )
  completed <- completed + 1L
  if (completed %% 25 == 0) {
    log_msg("scanned %d/%d games (network %d, cache %d, failed %d)", completed, nrow(games),
            ledger$network, ledger$cached, length(ledger$fail))
  }
}
scan_complete <- completed == nrow(games)
log_msg("scan %s: %d/%d games", if (scan_complete) "complete" else "STOPPED at time cap (PARTIAL)",
        completed, nrow(games))

rows <- do.call(rbind, row_list)
game_tbl <- do.call(rbind, game_rows)
types_all <- do.call(rbind, type_counts)
if (is.null(rows)) {
  if (length(ledger$fail)) {
    utils::write.csv(do.call(rbind, ledger$fail), file.path(OUT_DIR, "espn_bet_failures.csv"), row.names = FALSE)
  }
  stop("No prop rows collected for the four markets; see espn_bet_failures.csv")
}
saveRDS(rows, file.path(CACHE_DIR, "..", if (SAMPLE) "espn_bet_rows_sample.rds" else "espn_bet_rows.rds"))

# ---- Joins ----------------------------------------------------------------------
ids <- as.data.frame(nflreadr::load_ff_playerids())
ids <- ids[!is.na(ids$espn_id) & !is.na(ids$gsis_id) & nzchar(ids$espn_id), c("espn_id", "gsis_id")]
ambiguous_espn <- unique(ids$espn_id[duplicated(ids$espn_id)])
ids <- ids[!duplicated(ids$espn_id), ]
rows$gsis_id <- ids$gsis_id[match(rows$athlete_espn_id, ids$espn_id)]

stats <- as.data.frame(nflreadr::load_player_stats(2024:2025))
stats <- stats[stats$season_type == "REG",
               c("player_id", "season", "week", "rushing_tds", "receiving_tds",
                 "receiving_yards", "receptions", "rushing_yards")]
key_rows <- paste(rows$gsis_id, rows$season, rows$week)
key_stats <- paste(stats$player_id, stats$season, stats$week)
st <- stats[match(key_rows, key_stats), ]
rows$has_stat_row <- !is.na(rows$gsis_id) & !is.na(st$player_id)

zero_na <- function(x) ifelse(is.na(x), 0, x)
tds <- zero_na(st$rushing_tds) + zero_na(st$receiving_tds)
stat_value <- ifelse(rows$market == "receiving_yards", st$receiving_yards,
              ifelse(rows$market == "receptions", st$receptions,
              ifelse(rows$market == "rushing_yards", st$rushing_yards, NA_real_)))
rows$hit <- ifelse(
  rows$market == "anytime_td",
  tds >= pmax(1, ceiling(rows$open_target)),
  zero_na(stat_value) > rows$open_target
)
rows$hit[!rows$has_stat_row | is.na(rows$open_target)] <- NA
rows$last_updated_utc <- as.POSIXct(rows$last_updated, format = "%Y-%m-%dT%H:%MZ", tz = "UTC")
rows$updated_after_kickoff <- rows$last_updated_utc > rows$kickoff_utc
rows$open_priced <- !is.na(rows$open_over_american) | !is.na(rows$open_under_american)
rows$player_game <- paste(rows$game_id, rows$athlete_espn_id, rows$market)
pg_has_priced <- tapply(rows$priced, rows$player_game, any)
rows$in_priced_player_game <- pg_has_priced[rows$player_game]

# ---- Tables ---------------------------------------------------------------------
market_season <- do.call(rbind, lapply(split(rows, list(rows$market, rows$season), drop = TRUE), function(d) {
  pg <- split(d, d$player_game)
  pg_priced <- vapply(pg, function(x) any(x$priced), logical(1))
  pg_open <- vapply(pg, function(x) any(x$open_priced), logical(1))
  pg_settled <- vapply(pg, function(x) any(x$has_stat_row), logical(1))
  data.frame(
    market = d$market[1], season = d$season[1],
    games_with_market = length(unique(d$game_id)),
    rows = nrow(d), priced_rows = sum(d$priced),
    priced_share_rows = round(mean(d$priced), 4),
    player_games = length(pg), priced_player_games = sum(pg_priced),
    priced_share_player_games = round(mean(pg_priced), 4),
    open_priced_player_games = sum(pg_open),
    open_priced_settled_player_games = sum(pg_open & pg_settled),
    rows_athlete_unmatched = sum(is.na(d$gsis_id)),
    rows_no_stat_row = sum(!is.na(d$gsis_id) & !d$has_stat_row),
    share_rows_updated_after_kickoff = round(mean(d$updated_after_kickoff, na.rm = TRUE), 4),
    stringsAsFactors = FALSE
  )
}))

bias_rows <- function(d, label) {
  ok <- d[!is.na(d$hit), ]
  p <- ok[ok$priced, ]
  u <- ok[!ok$priced, ]
  res <- if (nrow(p) > 0 && nrow(u) > 0) bias_test(sum(p$hit), nrow(p), sum(u$hit), nrow(u)) else
    list(diff = NA_real_, p_value = NA_real_)
  verdict <- if (is.na(res$p_value)) "UNTESTABLE (no priced or no unpriced rows)" else
    if (res$p_value >= 0.05 && abs(res$diff) < 0.03) "USABLE" else "LINE-MOVEMENT ONLY"
  data.frame(
    market = d$market[1], scope = label,
    rows = nrow(d),
    excluded_athlete_unmatched = sum(is.na(d$gsis_id)),
    excluded_no_stat_row = sum(!is.na(d$gsis_id) & !d$has_stat_row),
    excluded_no_open_target = sum(d$has_stat_row & is.na(d$open_target)),
    priced_n = nrow(p), priced_hits = sum(p$hit),
    unpriced_n = nrow(u), unpriced_hits = sum(u$hit),
    priced_hit_rate = if (nrow(p)) round(mean(p$hit), 4) else NA_real_,
    unpriced_hit_rate = if (nrow(u)) round(mean(u$hit), 4) else NA_real_,
    diff = round(res$diff, 4), p_value = signif(res$p_value, 4), verdict = verdict,
    mean_open_target_priced = if (nrow(p)) round(mean(p$open_target), 2) else NA_real_,
    mean_open_target_unpriced = if (nrow(u)) round(mean(u$open_target), 2) else NA_real_,
    share_unpriced_integer_target = if (nrow(u)) round(mean(u$open_target %% 1 == 0), 4) else NA_real_,
    share_unpriced_in_priced_player_game = if (nrow(u)) round(mean(u$in_priced_player_game), 4) else NA_real_,
    stringsAsFactors = FALSE
  )
}
bias <- do.call(rbind, lapply(split(rows, rows$market), bias_rows, label = "2024 + 2025 wk1-13"))
bias_season <- do.call(rbind, lapply(split(rows, list(rows$market, rows$season), drop = TRUE),
                                     function(d) bias_rows(d, as.character(d$season[1]))))

# Structure behind the row-level test: unpriced rows are mostly alternate-ladder
# rungs. A "stripped main line" would show up as an unpriced player-game that
# still has a half-point target row (2024 ladders use whole-number targets;
# 2025 ladders also use half points, so the 2025 count is an upper bound).
rows$half_point <- (rows$open_target %% 1) == 0.5
structure_tbl <- do.call(rbind, lapply(split(rows, list(rows$market, rows$season), drop = TRUE), function(d) {
  pg_priced <- tapply(d$priced, d$player_game, any)
  pg_half <- tapply(d$half_point %in% TRUE, d$player_game, any)
  u <- d[!d$priced, ]
  data.frame(
    market = d$market[1], season = d$season[1],
    player_games = length(pg_priced), priced_player_games = sum(pg_priced),
    unpriced_player_games = sum(!pg_priced),
    unpriced_player_games_with_half_point_row = sum(!pg_priced & pg_half),
    unpriced_rows = nrow(u),
    share_unpriced_rows_in_priced_player_game = if (nrow(u)) round(mean(u$in_priced_player_game), 4) else NA_real_,
    share_unpriced_rows_integer_target = if (nrow(u)) round(mean(u$open_target %% 1 == 0, na.rm = TRUE), 4) else NA_real_,
    priced_rows_per_priced_player_game = round(sum(d$priced) / max(1, sum(pg_priced)), 2),
    stringsAsFactors = FALSE
  )
}))
by_week <- do.call(rbind, lapply(split(rows, list(rows$market, rows$season, rows$week), drop = TRUE), function(d) {
  pg_priced <- tapply(d$priced, d$player_game, any)
  data.frame(market = d$market[1], season = d$season[1], week = d$week[1],
             games = length(unique(d$game_id)), player_games = length(pg_priced),
             priced_share_player_games = round(mean(pg_priced), 4),
             priced_share_rows = round(mean(d$priced), 4), stringsAsFactors = FALSE)
}))
by_week <- by_week[order(by_week$market, by_week$season, by_week$week), ]

all_markets <- do.call(rbind, lapply(split(types_all, list(types_all$market, types_all$season), drop = TRUE), function(d) {
  data.frame(market = d$market[1], season = d$season[1], rows = nrow(d),
             priced_rows = sum(d$priced), priced_share = round(mean(d$priced), 4),
             stringsAsFactors = FALSE)
}))
all_markets <- all_markets[order(all_markets$season, -all_markets$rows), ]

unmatched_athletes <- data.frame(
  scope = c("distinct athletes in 4 markets", "distinct athletes without gsis match",
            "rows without gsis match", "espn_ids mapping to >1 gsis (first kept)"),
  count = c(length(unique(rows$athlete_espn_id)),
            length(unique(rows$athlete_espn_id[is.na(rows$gsis_id)])),
            sum(is.na(rows$gsis_id)), length(ambiguous_espn))
)

failures <- if (length(ledger$fail)) do.call(rbind, ledger$fail) else
  data.frame(stage = character(), key = character(), url = character(),
             status = integer(), error = character())
finished <- Sys.time()
meta <- data.frame(
  script = "espn_bet_bias.R", sample_mode = SAMPLE,
  started_utc = format_utc_iso(started), finished_utc = format_utc_iso(finished),
  minutes = round(as.numeric(difftime(finished, started, units = "mins")), 1),
  games_planned = nrow(games), games_scanned = completed,
  status = if (scan_complete) "COMPLETE" else "PARTIAL",
  requests_network = ledger$network, pages_from_cache = ledger$cached,
  failed_requests = nrow(failures), stringsAsFactors = FALSE
)

utils::write.csv(game_tbl, file.path(OUT_DIR, "espn_bet_games.csv"), row.names = FALSE)
utils::write.csv(market_season, file.path(OUT_DIR, "espn_bet_market_season.csv"), row.names = FALSE)
utils::write.csv(bias, file.path(OUT_DIR, "espn_bet_bias.csv"), row.names = FALSE)
utils::write.csv(bias_season, file.path(OUT_DIR, "espn_bet_bias_by_season.csv"), row.names = FALSE)
utils::write.csv(all_markets, file.path(OUT_DIR, "espn_bet_all_markets.csv"), row.names = FALSE)
utils::write.csv(unmatched_athletes, file.path(OUT_DIR, "espn_bet_athlete_matching.csv"), row.names = FALSE)
utils::write.csv(structure_tbl, file.path(OUT_DIR, "espn_bet_unpriced_structure.csv"), row.names = FALSE)
utils::write.csv(by_week, file.path(OUT_DIR, "espn_bet_priced_by_week.csv"), row.names = FALSE)
# Failed pages are never cached, so a rerun retries them and logs them again.
utils::write.csv(failures, file.path(OUT_DIR, "espn_bet_failures.csv"), row.names = FALSE)
# Run meta is appended, so a network run and later re-analyses from cache stay on record.
meta_path <- file.path(OUT_DIR, "espn_bet_run_meta.csv")
utils::write.table(meta, meta_path, sep = ",", row.names = FALSE,
                   col.names = !file.exists(meta_path), append = file.exists(meta_path))
log_msg("done: %s, %d/%d games, %d network requests, %d failed, %.1f min", meta$status,
        completed, nrow(games), ledger$network, nrow(failures), meta$minutes)
