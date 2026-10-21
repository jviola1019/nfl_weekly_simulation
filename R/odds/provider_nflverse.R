# =============================================================================
# nflverse provider: the consensus closing line (roadmap D1)
# =============================================================================
# nflreadr::load_schedules() carries one closing moneyline, spread and total per
# game since 1999. It is a consensus close, with no open and no timestamp, so
# every row is snapshot_kind "close" with captured_at NA. Sign convention: nflverse
# `spread_line` is positive when the HOME team is favoured, so the home handicap is
# -spread_line and the away handicap is +spread_line.
# `load_schedules_fn(seasons)` is the seam: tests pass a fixture reader.
#
# Status (roadmap rule R5: partial data is stale):
#   ok           every requested game is in the schedule, every price and line column is
#                present, every price and line was stored, and every requested game has a
#                moneyline, a spread and a total
#   stale        partial data. The detail names each gap: a requested game missing from the
#                schedule; a price or line column absent; a requested game with no market rows,
#                or missing a moneyline, spread or total; a spread or total price with no line
#                (dropped and counted); a price that cannot be read (counted; a moneyline drops
#                both of its sides)
#   unavailable  the load returned no rows, or no requested game has a snapshot
#   failed       the loader threw (its message is in detail)
# A requested game the schedule leaves without a moneyline is a gap; the count of such
# games also stays in detail ("N without a moneyline"). Loader warnings and errors are
# copied into detail on one line, on every path.
#
# raw_sha256 is a CONTENT hash of the loaded nflverse rows (game_id and the price and
# line columns, sorted with a radix order so the locale does not matter), not a file
# hash: nflreadr does not expose the release file. It covers every loaded row, so it
# does not change with the games requested. The fetches row carries it, and so does
# every snapshot.
# =============================================================================

NFLVERSE_PRICE_COLUMNS <- c("home_moneyline", "away_moneyline", "spread_line", "home_spread_odds",
                            "away_spread_odds", "total_line", "over_odds", "under_odds")
NFLVERSE_MARKETS <- c("moneyline", "spread", "total")

# Run the loader. An error and any warnings come back as values, never as a crash.
nflverse_load <- function(load_fn, seasons) {
  warnings_seen <- character()
  value <- tryCatch(
    withCallingHandlers(load_fn(seasons), warning = function(w) {
      warnings_seen <<- c(warnings_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    }),
    error = function(e) e
  )
  list(value = value, warnings = warnings_seen)
}

# A message on one line: each run of whitespace, newlines included, becomes one space.
nflverse_one_line <- function(text) trimws(gsub("[[:space:]]+", " ", text))

# The loader's warnings as a detail suffix; "" when there were none.
nflverse_warning_note <- function(warnings_seen) {
  if (!length(warnings_seen)) return("")
  paste0("; nflreadr warning(s): ",
         paste(nflverse_one_line(utils::head(unique(warnings_seen), 3)), collapse = " | "))
}

provider_nflverse <- function(load_schedules_fn = NULL) {
  load_fn <- load_schedules_fn %||% function(seasons) nflreadr::load_schedules(seasons)

  game_snapshots <- function(games, ...) {
    source <- "nflverse_schedules"
    seasons <- sort(unique(games$season))
    season_label <- paste(seasons, collapse = ", ")
    loaded <- nflverse_load(load_fn, seasons)
    warn_note <- nflverse_warning_note(loaded$warnings)
    if (inherits(loaded$value, "error")) {
      return(odds_result(source = source, status = "failed",
                         detail = paste0("load failed: ", nflverse_one_line(conditionMessage(loaded$value)), warn_note)))
    }
    sched <- tryCatch(as.data.frame(loaded$value, stringsAsFactors = FALSE), error = function(e) e)
    if (inherits(sched, "error")) {
      return(odds_result(source = source, status = "failed",
                         detail = paste0("load returned no usable table: ",
                                         nflverse_one_line(conditionMessage(sched)), warn_note)))
    }
    if (!"game_id" %in% names(sched) || nrow(sched) == 0) {
      return(odds_result(source = source, status = "unavailable",
                         detail = paste0("nflreadr returned no schedule rows for ", season_label, warn_note)))
    }
    requested <- unique(games$game_id)
    present <- intersect(NFLVERSE_PRICE_COLUMNS, names(sched))
    absent <- setdiff(NFLVERSE_PRICE_COLUMNS, names(sched))

    # The content hash covers every loaded row, not the request, in a locale-free order.
    hash_frame <- sched[, c("game_id", present), drop = FALSE]
    hash_frame <- hash_frame[do.call(order, c(unname(as.list(hash_frame)), list(method = "radix"))), , drop = FALSE]
    hash_text <- paste(utils::capture.output(utils::write.csv(hash_frame, row.names = FALSE)), collapse = "\n")
    sha <- digest::digest(hash_text, algo = "sha256", serialize = FALSE)

    for (nm in absent) sched[[nm]] <- NA
    n <- nrow(sched)
    in_req <- sched$game_id %in% requested
    not_found <- setdiff(requested, sched$game_id)
    has_ml <- !is.na(sched$home_moneyline) & !is.na(sched$away_moneyline)

    # The rows for the games flagged in keep.
    market_rows <- function(market_id, side, line, price_int, keep) {
      if (!any(keep)) return(NULL)
      data.frame(
        game_id = sched$game_id[keep], market_id = market_id, venue_id = "nflverse_consensus",
        side = side, line = as.numeric(line[keep]), price_american = price_int[keep],
        snapshot_kind = "close", source = source, raw_sha256 = sha, stringsAsFactors = FALSE
      )
    }

    # Moneyline: both sides or neither. A requested game with both prices present keeps both
    # sides when both read. If either does not read, the whole pair is dropped, and each price
    # that does not read is counted.
    home_ml <- american_to_int(sched$home_moneyline)
    away_ml <- american_to_int(sched$away_moneyline)
    ml_base <- in_req & has_ml
    ml_pair <- ml_base & !is.na(home_ml) & !is.na(away_ml)
    unreadable_ml <- sum(ml_base & is.na(home_ml)) + sum(ml_base & is.na(away_ml))
    no_line <- rep(NA_real_, n)

    # Spread and total: a row needs its line. A price with no line cannot be stored, so it is
    # dropped and counted (price_only). A line with no price is kept, and a price that does not
    # read on a kept row is counted (unreadable).
    line_part <- function(market_id, side, line, price) {
      price_int <- american_to_int(price)
      raw_present <- !is.na(price)
      keep <- in_req & !is.na(line)
      list(
        rows = market_rows(market_id, side, line, price_int, keep),
        price_only = sum(in_req & is.na(line) & raw_present),
        unreadable = sum(keep & raw_present & is.na(price_int))
      )
    }
    line_parts <- list(
      line_part("spread", "home", -as.numeric(sched$spread_line), sched$home_spread_odds),
      line_part("spread", "away", as.numeric(sched$spread_line), sched$away_spread_odds),
      line_part("total", "over", as.numeric(sched$total_line), sched$over_odds),
      line_part("total", "under", as.numeric(sched$total_line), sched$under_odds)
    )
    rows <- do.call(rbind, Filter(Negate(is.null), c(
      list(market_rows("moneyline", "home", no_line, home_ml, ml_pair),
           market_rows("moneyline", "away", no_line, away_ml, ml_pair)),
      lapply(line_parts, `[[`, "rows")
    )))
    snaps <- new_odds_snapshots(rows %||% odds_snapshots_empty())
    price_only <- sum(vapply(line_parts, `[[`, integer(1), "price_only"))
    unreadable <- unreadable_ml + sum(vapply(line_parts, `[[`, integer(1), "unreadable"))

    # The requested games the schedule has, and how many of the three markets each has rows for.
    found <- requested[requested %in% sched$game_id]
    market_count <- vapply(found, function(g) {
      sum(NFLVERSE_MARKETS %in% snaps$market_id[snaps$game_id == g])
    }, integer(1))
    games_none <- sum(market_count == 0L)
    games_partial <- sum(market_count > 0L & market_count < length(NFLVERSE_MARKETS))

    gaps <- c(
      if (length(absent)) paste0("column(s) absent: ", paste(absent, collapse = ", ")),
      if (length(not_found)) paste0("not in the schedule: ", paste(utils::head(not_found, 5), collapse = ", ")),
      if (games_none) sprintf("%d requested game(s) in the schedule with no market rows", games_none),
      if (games_partial) sprintf("%d requested game(s) missing a moneyline, spread or total", games_partial),
      if (price_only) sprintf("%d price-only spread/total row(s) dropped (no line)", price_only),
      if (unreadable) sprintf("%d unreadable price(s) not stored (for example a moneyline of 0)", unreadable)
    )
    base <- sprintf("%d of %d requested games in the schedule; %d without a moneyline",
                    length(found), length(requested), sum(in_req & !has_ml))
    status <- if (nrow(snaps) == 0) "unavailable" else if (length(gaps)) "stale" else "ok"
    detail <- paste0(paste(c(base, gaps), collapse = "; "), warn_note)
    fetches <- odds_fetch_row(
      list(url = sprintf("nflreadr::load_schedules(seasons = c(%s))", season_label), source = source,
           status = NA_integer_, sha256 = sha, bytes = nchar(hash_text, type = "bytes"), tries = 1L,
           blocked = FALSE, fetched_at = as.POSIXct(Sys.time(), tz = "UTC")),
      key = paste0("nflverse_schedules_", paste(seasons, collapse = "_"))
    )
    odds_result(snaps, source = source, status = status, detail = detail, fetches = fetches)
  }

  new_odds_provider("nflverse", "nflverse_consensus", game_snapshots = game_snapshots)
}
