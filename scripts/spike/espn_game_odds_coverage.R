# =============================================================================
# Spike: ESPN game odds open/close coverage by season (measurement only)
# =============================================================================
# Usage (from the repo root):
#   Rscript scripts/spike/espn_game_odds_coverage.R [--sample] [--out=DIR]
#
# For 5 seeded-random regular-season games per season 2018-2025, fetch
# .../competitions/{id}/odds and record, per provider, whether open and close
# blocks exist and whether a moneyline is present (open, close, current).
# Every failed request is written to espn_game_odds_failures.csv.
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
SEASONS <- if (SAMPLE) c(2018L, 2025L) else 2018:2025
PER_SEASON <- if (SAMPLE) 1L else 5L
SEED <- 20260929L
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
started <- Sys.time()
log_msg <- function(...) message(format(Sys.time(), "%H:%M:%S "), sprintf(...))

fail_rows <- list()
n_requests <- 0L
fetch_json <- function(url, key) {
  res <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC,
                          cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
  n_requests <<- n_requests + 1L
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
    fail_rows[[length(fail_rows) + 1]] <<- data.frame(
      stage = "game_odds", key = key, url = url, status = res$status %||% NA_integer_,
      error = err %||% NA_character_, stringsAsFactors = FALSE
    )
  }
  parsed
}

sched <- as.data.frame(nflreadr::load_schedules(SEASONS))
sched <- sched[sched$game_type == "REG", ]
set.seed(SEED)
games <- do.call(rbind, lapply(SEASONS, function(s) {
  pool <- sched[sched$season == s, ]
  pool[sort(sample.int(nrow(pool), PER_SEASON)), c("season", "week", "game_id", "espn")]
}))

present <- function(x) !is.null(x) && length(x) > 0
ml_in <- function(block) present(block$moneyLine)
out <- list()
for (g in seq_len(nrow(games))) {
  gm <- games[g, ]
  x <- fetch_json(espn_game_odds_url(gm$espn), gm$espn)
  items <- if (is.null(x)) NULL else x$items %||% list()
  if (is.null(items) || length(items) == 0) {
    out[[length(out) + 1]] <- data.frame(
      season = gm$season, week = gm$week, game_id = gm$game_id, espn_event = gm$espn,
      request_ok = !is.null(x), provider_id = NA_character_, provider_name = NA_character_,
      has_open = NA, has_close = NA, has_open_moneyline = NA, has_close_moneyline = NA,
      has_current_moneyline = NA, has_open_total = NA, has_close_total = NA,
      stringsAsFactors = FALSE
    )
    next
  }
  for (it in items) {
    h <- it$homeTeamOdds
    a <- it$awayTeamOdds
    out[[length(out) + 1]] <- data.frame(
      season = gm$season, week = gm$week, game_id = gm$game_id, espn_event = gm$espn,
      request_ok = TRUE,
      provider_id = as.character(it$provider$id %||% NA_character_),
      provider_name = it$provider$name %||% NA_character_,
      has_open = present(it$open) || present(h$open) || present(a$open),
      has_close = present(it$close) || present(h$close) || present(a$close),
      has_open_moneyline = ml_in(h$open) && ml_in(a$open),
      has_close_moneyline = ml_in(h$close) && ml_in(a$close),
      has_current_moneyline = (present(h$moneyLine) && present(a$moneyLine)) ||
        (ml_in(h$current) && ml_in(a$current)),
      has_open_total = present(it$open$total),
      has_close_total = present(it$close$total),
      stringsAsFactors = FALSE
    )
  }
  log_msg("%s %s: %d provider item(s)", gm$season, gm$espn, length(items))
}
providers <- do.call(rbind, out)

season_summary <- do.call(rbind, lapply(split(providers, providers$season), function(d) {
  per_game <- split(d, d$game_id)
  any_true <- function(col) vapply(per_game, function(x) any(x[[col]] %in% TRUE), logical(1))
  data.frame(
    season = d$season[1], games_sampled = length(per_game),
    games_request_ok = sum(vapply(per_game, function(x) all(x$request_ok), logical(1))),
    games_with_any_provider = sum(vapply(per_game, function(x) any(!is.na(x$provider_id)), logical(1))),
    providers_seen = paste(sort(unique(stats::na.omit(d$provider_name))), collapse = "; "),
    games_open_moneyline = sum(any_true("has_open_moneyline")),
    games_close_moneyline = sum(any_true("has_close_moneyline")),
    games_open_and_close_moneyline = sum(vapply(per_game, function(x)
      any(x$has_open_moneyline %in% TRUE & x$has_close_moneyline %in% TRUE), logical(1))),
    games_current_moneyline = sum(any_true("has_current_moneyline")),
    games_open_total = sum(any_true("has_open_total")),
    games_close_total = sum(any_true("has_close_total")),
    stringsAsFactors = FALSE
  )
}))

failures <- if (length(fail_rows)) do.call(rbind, fail_rows) else
  data.frame(stage = character(), key = character(), url = character(),
             status = integer(), error = character())
finished <- Sys.time()
meta <- data.frame(
  script = "espn_game_odds_coverage.R", sample_mode = SAMPLE,
  started_utc = format_utc_iso(started), finished_utc = format_utc_iso(finished),
  minutes = round(as.numeric(difftime(finished, started, units = "mins")), 1),
  games_planned = nrow(games), requests = n_requests, failed_requests = nrow(failures),
  status = "COMPLETE", stringsAsFactors = FALSE
)
utils::write.csv(providers, file.path(OUT_DIR, "espn_game_odds_providers.csv"), row.names = FALSE)
utils::write.csv(season_summary, file.path(OUT_DIR, "espn_game_odds_by_season.csv"), row.names = FALSE)
utils::write.csv(failures, file.path(OUT_DIR, "espn_game_odds_failures.csv"), row.names = FALSE)
utils::write.csv(meta, file.path(OUT_DIR, "espn_game_odds_run_meta.csv"), row.names = FALSE)
log_msg("done: %d games, %d requests, %d failed", nrow(games), n_requests, nrow(failures))
