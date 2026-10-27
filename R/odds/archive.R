# =============================================================================
# The decision-time archive: ESPN game openers and closes, 2023-2024 (roadmap D1)
# =============================================================================
# backtest/build_odds_archive.R builds backtest/data/odds_archive/ from the ESPN core
# game-odds responses, the way backtest/build_inputs.R builds backtest/data/: derived
# CSVs are committed, and SOURCES.json records the sha256 of every raw response and
# every derived file. The raw responses are stored gzipped under a raw directory that
# is NOT committed (16.4 MB measured); odds_archive_verify() re-checks them against SOURCES.json.
#
# THE 2025 HOLDOUT IS SEALED. This builder refuses any season after
# ODDS_ARCHIVE_MAX_SEASON before it loads a schedule or makes one request. The 2025 rows
# are appended only by the G3 Holdout build, after the freeze. The constant is not a
# config value on purpose: raising it is a protocol decision, not a setting.
# ESPN has no open line before 2023 (2022 has a close only), so 2023 is the first season.
# =============================================================================

ODDS_ARCHIVE_MIN_SEASON <- 2023L
ODDS_ARCHIVE_MAX_SEASON <- 2024L
ODDS_ARCHIVE_DIR <- file.path("backtest", "data", "odds_archive")
ODDS_ARCHIVE_COLUMNS <- c("game_id", "season", "week", "game_type", "market_id", "venue_id", "side", "line",
                          "price_american", "snapshot_kind", "raw_sha256")

#' Stop unless every season is inside the archive window
odds_archive_assert_seasons <- function(seasons) {
  seasons <- as.integer(seasons)
  if (length(seasons) == 0 || anyNA(seasons)) stop("odds archive: seasons must be integers", call. = FALSE)
  sealed <- seasons[seasons > ODDS_ARCHIVE_MAX_SEASON]
  if (length(sealed)) {
    stop(sprintf(paste0("odds archive: refusing season(s) %s. The 2025 Holdout is sealed; only the G3 Holdout build, ",
                        "after the freeze, may add 2025 game rows (archive window %d-%d)."),
                 paste(sort(unique(sealed)), collapse = ", "), ODDS_ARCHIVE_MIN_SEASON, ODDS_ARCHIVE_MAX_SEASON),
         call. = FALSE)
  }
  early <- seasons[seasons < ODDS_ARCHIVE_MIN_SEASON]
  if (length(early)) {
    stop(sprintf("odds archive: no ESPN opening line before %d (season(s) %s)", ODDS_ARCHIVE_MIN_SEASON,
                 paste(sort(unique(early)), collapse = ", ")), call. = FALSE)
  }
  invisible(sort(unique(seasons)))
}

#' The games of the archive window from a schedule table, in kickoff order. Re-checks
#' the seasons of the result, so a wide schedule can never leak a sealed season through.
odds_archive_games <- function(schedule, seasons) {
  seasons <- odds_archive_assert_seasons(seasons)
  sched <- as.data.frame(schedule, stringsAsFactors = FALSE)
  games <- odds_games_from_schedule(sched[as.integer(sched$season) %in% seasons, , drop = FALSE])
  games <- games[order(games$kickoff_utc, games$game_id), , drop = FALSE]
  if (nrow(games) && max(games$season) > ODDS_ARCHIVE_MAX_SEASON) stop("odds archive: sealed season in the game list", call. = FALSE)
  rownames(games) <- NULL
  games
}

oa_raw_path <- function(raw_dir, key) file.path(raw_dir, sprintf("espn_game_odds__%s.json.gz", key))

oa_write_gz <- function(path, body) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- gzfile(path, "wb")
  on.exit(close(con))
  writeBin(body, con)
  invisible(path)
}

oa_read_gz <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  out <- raw()
  repeat {
    chunk <- readBin(con, "raw", 65536L)
    if (length(chunk) == 0) break
    out <- c(out, chunk)
  }
  out
}

#' A fetch function that serves stored raw responses, so the archive can be rebuilt
#' offline from a raw directory (the `--from-raw` mode). A missing file is a 404.
odds_replay_fetch <- function(raw_dir) {
  function(url, cfg) {
    key <- sub("^.*/events/([0-9]+)/competitions/.*$", "\\1", url)
    path <- oa_raw_path(raw_dir, key)
    if (!grepl("^[0-9]+$", key) || !file.exists(path)) {
      return(list(status = 404L, body = NULL, error = "HTTP 404 (no stored raw response)", retry_after = NA_real_))
    }
    list(status = 200L, body = oa_read_gz(path), error = NA_character_, retry_after = NA_real_)
  }
}

# LF line endings on every platform: the files are hash-locked evidence (.gitattributes)
oa_write_text <- function(text, path) {
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n"))), con)
  invisible(path)
}

oa_write_csv <- function(x, path) {
  oa_write_text(utils::capture.output(utils::write.csv(x, row.names = FALSE, na = "")), path)
}

oa_sha256_file <- function(path) digest::digest(file = path, algo = "sha256")

#' Games per season, market and venue that have a complete open, a complete close, or both.
#' A line is complete when both its sides are present (home and away, over and under).
#' The venue "any" counts a game once if any venue has it.
odds_coverage <- function(snaps, games) {
  markets <- c("moneyline", "spread", "total")
  out <- list()
  complete <- function(d) {
    # (game, venue, market, kind) groups with 2 distinct sides
    if (nrow(d) == 0) return(d[0, c("game_id", "venue_id", "market_id", "snapshot_kind")])
    key <- paste(d$game_id, d$venue_id, d$market_id, d$snapshot_kind, sep = "|")
    n_sides <- tapply(d$side, key, function(x) length(unique(x)))
    keep <- !duplicated(key) & n_sides[key] >= 2
    d[keep, c("game_id", "venue_id", "market_id", "snapshot_kind")]
  }
  cmp <- complete(snaps)
  venues <- c(sort(unique(snaps$venue_id)), "any")
  for (season in sort(unique(games$season))) {
    ids <- games$game_id[games$season == season]
    for (venue in venues) {
      for (market in markets) {
        d <- cmp[cmp$game_id %in% ids & cmp$market_id == market & (venue == "any" | cmp$venue_id == venue), ]
        open <- unique(d$game_id[d$snapshot_kind == "open"])
        close <- unique(d$game_id[d$snapshot_kind == "close"])
        both <- intersect(open, close)
        if (venue != "any" && length(open) + length(close) == 0) next
        out[[length(out) + 1]] <- data.frame(
          season = season, venue_id = venue, market_id = market, games_expected = length(ids),
          games_with_open = length(open), games_with_close = length(close), games_with_open_and_close = length(both),
          pct_open_and_close = round(100 * length(both) / length(ids), 1), stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(out) == 0) {
    return(data.frame(season = integer(), venue_id = character(), market_id = character(), games_expected = integer(),
                      games_with_open = integer(), games_with_close = integer(), games_with_open_and_close = integer(),
                      pct_open_and_close = numeric(), stringsAsFactors = FALSE))
  }
  do.call(rbind, out)
}

#' Games read back from a committed event_map.csv (the offline `--from-raw` input)
odds_archive_read_event_map <- function(path) {
  em <- utils::read.csv(path, colClasses = "character", na.strings = "")
  games <- data.frame(
    game_id = em$game_id, season = as.integer(em$season), week = as.integer(em$week), game_type = em$game_type,
    gameday = em$gameday, kickoff_utc = as.POSIXct(em$kickoff_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    home_team = em$home_team, away_team = em$away_team, espn = em$espn_event_id, stringsAsFactors = FALSE
  )
  odds_archive_assert_seasons(unique(games$season))
  games
}

#' Build the archive: fetch (or replay) the ESPN game odds of `games`, store each raw body,
#' and write the derived CSVs plus SOURCES.json to `out_dir`.
#' @param provider provider_espn_core() with the network (or replay) seam of the caller
#' @return list(snapshots, coverage, sources, status)
odds_archive_build <- function(games, provider, out_dir, raw_dir, built_utc = Sys.time()) {
  odds_archive_assert_seasons(unique(games$season))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  res <- provider$game_snapshots(games, on_raw = function(key, body, rec) oa_write_gz(oa_raw_path(raw_dir, key), body))

  s <- res$snapshots
  meta <- games[match(s$game_id, games$game_id), c("season", "week", "game_type")]
  arch <- cbind(s["game_id"], meta, s[c("market_id", "venue_id", "side", "line", "price_american", "snapshot_kind", "raw_sha256")])
  arch <- arch[order(arch$game_id, arch$venue_id, arch$market_id, arch$side, arch$snapshot_kind), ODDS_ARCHIVE_COLUMNS, drop = FALSE]
  rownames(arch) <- NULL
  event_map <- data.frame(
    game_id = games$game_id, season = games$season, week = games$week, game_type = games$game_type,
    gameday = games$gameday, kickoff_utc = odds_iso(games$kickoff_utc), home_team = games$home_team,
    away_team = games$away_team, espn_event_id = games$espn, stringsAsFactors = FALSE
  )
  coverage <- odds_coverage(s, games)

  paths <- list(odds_archive = file.path(out_dir, "espn_game_odds.csv"),
                event_map = file.path(out_dir, "event_map.csv"),
                coverage = file.path(out_dir, "COVERAGE.csv"))
  oa_write_csv(arch, paths$odds_archive)
  oa_write_csv(event_map, paths$event_map)
  oa_write_csv(coverage, paths$coverage)

  f <- res$fetches
  ok <- !is.na(f$http_status) & f$http_status == 200L & !is.na(f$raw_sha256)
  raw <- lapply(which(ok), function(i) list(file = basename(oa_raw_path(raw_dir, f$key[i])), url = f$url[i],
                                            sha256 = f$raw_sha256[i], bytes = f$bytes[i]))
  failures <- lapply(which(!ok), function(i) list(key = f$key[i], url = f$url[i], http_status = f$http_status[i]))
  derived <- lapply(paths, function(p) list(file = basename(p), rows = nrow(utils::read.csv(p)), sha256 = oa_sha256_file(p)))
  sources <- list(
    built_utc = odds_iso(built_utc), seasons = sort(unique(games$season)), max_season = ODDS_ARCHIVE_MAX_SEASON,
    script = "backtest/build_odds_archive.R", games = nrow(games), source_status = res$source_status$status,
    source_detail = res$source_status$detail, raw = unname(raw), fetch_failures = unname(failures), derived = derived,
    r_version = R.version.string
  )
  oa_write_text(jsonlite::toJSON(sources, auto_unbox = TRUE, pretty = TRUE, na = "null"), file.path(out_dir, "SOURCES.json"))
  invisible(list(snapshots = arch, coverage = coverage, sources = sources, status = res$source_status))
}

#' The build's exit status: 1 only when a game could not be fetched. A stale source status from
#' gaps in what ESPN serves (a market it never posted, a line with no price) is reported in
#' SOURCES.json, not treated as a failure: every game was fetched and stored.
odds_archive_exit_status <- function(sources) if (length(sources$fetch_failures)) 1L else 0L

#' Re-hash the stored raw responses and the derived files against SOURCES.json.
#' With `raw_dir = NULL` only the committed derived files are checked (the raw
#' responses are not committed).
#' @return character vector of mismatches (empty when everything verifies)
odds_archive_verify <- function(out_dir, raw_dir) {
  src <- jsonlite::read_json(file.path(out_dir, "SOURCES.json"), simplifyVector = FALSE)
  bad <- character()
  for (r in if (is.null(raw_dir)) list() else src$raw) {
    path <- file.path(raw_dir, r$file)
    if (!file.exists(path)) {
      bad <- c(bad, paste("missing raw file", r$file))
    } else if (!identical(digest::digest(oa_read_gz(path), algo = "sha256", serialize = FALSE), r$sha256)) {
      bad <- c(bad, paste("raw hash differs", r$file))
    }
  }
  for (d in src$derived) {
    path <- file.path(out_dir, d$file)
    if (!file.exists(path)) {
      bad <- c(bad, paste("missing derived file", d$file))
    } else if (!identical(oa_sha256_file(path), d$sha256)) {
      bad <- c(bad, paste("derived hash differs", d$file))
    }
  }
  if (max(unlist(src$seasons)) > ODDS_ARCHIVE_MAX_SEASON) bad <- c(bad, "SOURCES.json lists a sealed season")
  bad
}
