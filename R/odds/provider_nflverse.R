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
# Status: ok when every requested game is in the schedule, every price and line
# column is present and every price and line was stored. stale when any of those
# fails: a requested game is absent, a price or line column is absent, a spread or
# total price has no line (dropped and counted), or a price cannot be read (counted).
# A moneyline the schedule leaves empty for a game (NA) is not a gap; it is counted in
# detail, as before. unavailable when the load returns no rows, or no requested game
# has a snapshot. failed when the loader throws (its message is in detail). Warnings
# from the loader are copied into detail on every path.
#
# raw_sha256 is a CONTENT hash of the loaded nflverse rows (game_id and the price and
# line columns, sorted with a radix order so the locale does not matter), not a file
# hash: nflreadr does not expose the release file. It covers every loaded row, so it
# does not change with the games requested. The fetches row carries it, and so does
# every snapshot.
# =============================================================================

NFLVERSE_PRICE_COLUMNS <- c("home_moneyline", "away_moneyline", "spread_line", "home_spread_odds",
                            "away_spread_odds", "total_line", "over_odds", "under_odds")

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

# The loader's warnings as a detail suffix; "" when there were none.
nflverse_warning_note <- function(warnings_seen) {
  if (!length(warnings_seen)) return("")
  paste0("; nflreadr warning(s): ", paste(utils::head(unique(warnings_seen), 3), collapse = " | "))
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
                         detail = paste0("load failed: ", conditionMessage(loaded$value), warn_note)))
    }
    sched <- tryCatch(as.data.frame(loaded$value, stringsAsFactors = FALSE), error = function(e) e)
    if (inherits(sched, "error")) {
      return(odds_result(source = source, status = "failed",
                         detail = paste0("load returned no usable table: ", conditionMessage(sched), warn_note)))
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

    # One market side. A moneyline row needs a readable price. A spread or total row needs its
    # line: a price with no line cannot be stored, so it is dropped and counted, while a line
    # with no price is kept. Counted: price_only (dropped) and unreadable (a price that is not one).
    part <- function(market_id, side, line, price, eligible) {
      price_int <- american_to_int(price)
      raw_present <- !is.na(price)
      if (market_id == "moneyline") {
        keep <- eligible & !is.na(price_int)
        price_only <- rep(FALSE, n)
        unreadable <- eligible & raw_present & is.na(price_int)
      } else {
        keep <- eligible & !is.na(line)
        price_only <- eligible & is.na(line) & raw_present
        unreadable <- keep & raw_present & is.na(price_int)
      }
      rows <- if (any(keep)) {
        data.frame(
          game_id = sched$game_id[keep], market_id = market_id, venue_id = "nflverse_consensus",
          side = side, line = as.numeric(line[keep]), price_american = price_int[keep],
          snapshot_kind = "close", source = source, raw_sha256 = sha, stringsAsFactors = FALSE
        )
      }
      list(rows = rows, price_only = sum(price_only), unreadable = sum(unreadable))
    }
    ml_eligible <- in_req & has_ml
    no_line <- rep(NA_real_, n)
    parts <- list(
      part("moneyline", "home", no_line, sched$home_moneyline, ml_eligible),
      part("moneyline", "away", no_line, sched$away_moneyline, ml_eligible),
      part("spread", "home", -as.numeric(sched$spread_line), sched$home_spread_odds, in_req),
      part("spread", "away", as.numeric(sched$spread_line), sched$away_spread_odds, in_req),
      part("total", "over", as.numeric(sched$total_line), sched$over_odds, in_req),
      part("total", "under", as.numeric(sched$total_line), sched$under_odds, in_req)
    )
    price_only <- sum(vapply(parts, `[[`, integer(1), "price_only"))
    unreadable <- sum(vapply(parts, `[[`, integer(1), "unreadable"))
    rows <- do.call(rbind, Filter(Negate(is.null), lapply(parts, `[[`, "rows")))
    snaps <- new_odds_snapshots(rows %||% odds_snapshots_empty())

    n_found <- length(requested) - length(not_found)
    gaps <- c(
      if (length(absent)) paste0("column(s) absent: ", paste(absent, collapse = ", ")),
      if (length(not_found)) paste0("not in the schedule: ", paste(utils::head(not_found, 5), collapse = ", ")),
      if (price_only) sprintf("%d price-only spread/total row(s) dropped (no line)", price_only),
      if (unreadable) sprintf("%d unreadable price(s) not stored (for example a moneyline of 0)", unreadable)
    )
    base <- sprintf("%d of %d requested games in the schedule; %d without a moneyline",
                    n_found, length(requested), sum(in_req & !has_ml))
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
