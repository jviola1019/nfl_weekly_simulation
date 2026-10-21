# =============================================================================
# nflverse provider: the consensus closing line (roadmap D1)
# =============================================================================
# nflreadr::load_schedules() carries one closing moneyline, spread and total per
# game since 1999. It is a consensus close, with no open and no timestamp, so
# every row is snapshot_kind "close" with captured_at NA. Sign convention: nflverse
# `spread_line` is positive when the HOME team is favoured, so the home handicap is
# -spread_line and the away handicap is +spread_line.
# `load_schedules_fn(seasons)` is the seam: tests pass a fixture reader.
# =============================================================================

NFLVERSE_PRICE_COLUMNS <- c("home_moneyline", "away_moneyline", "spread_line", "home_spread_odds",
                            "away_spread_odds", "total_line", "over_odds", "under_odds")

provider_nflverse <- function(load_schedules_fn = NULL) {
  load_fn <- load_schedules_fn %||% function(seasons) nflreadr::load_schedules(seasons)

  game_snapshots <- function(games, ...) {
    source <- "nflverse_schedules"
    sched <- as.data.frame(load_fn(sort(unique(games$season))), stringsAsFactors = FALSE)
    absent <- setdiff(NFLVERSE_PRICE_COLUMNS, names(sched))
    for (nm in absent) sched[[nm]] <- NA
    requested <- unique(games$game_id)
    sched <- sched[sched$game_id %in% requested, , drop = FALSE]
    sched <- sched[order(sched$game_id), , drop = FALSE]
    not_found <- setdiff(requested, sched$game_id)

    raw_cols <- c("game_id", setdiff(NFLVERSE_PRICE_COLUMNS, absent))
    raw_text <- paste(utils::capture.output(utils::write.csv(sched[, raw_cols, drop = FALSE], row.names = FALSE)),
                      collapse = "\n")
    sha <- digest::digest(raw_text, algo = "sha256", serialize = FALSE)

    make <- function(idx, market_id, side, line, price) {
      keep <- !is.na(price) | !is.na(line)
      if (!any(keep)) return(NULL)
      data.frame(
        game_id = sched$game_id[idx][keep], market_id = market_id, venue_id = "nflverse_consensus",
        side = side, line = line[keep], price_american = american_to_int(price[keep]),
        snapshot_kind = "close", source = source, raw_sha256 = sha, stringsAsFactors = FALSE
      )
    }
    all_idx <- seq_len(nrow(sched))
    has_ml <- !is.na(sched$home_moneyline) & !is.na(sched$away_moneyline)
    ml_idx <- which(has_ml)
    parts <- list(
      make(ml_idx, "moneyline", "home", rep(NA_real_, length(ml_idx)), sched$home_moneyline[ml_idx]),
      make(ml_idx, "moneyline", "away", rep(NA_real_, length(ml_idx)), sched$away_moneyline[ml_idx]),
      make(all_idx, "spread", "home", -as.numeric(sched$spread_line), sched$home_spread_odds),
      make(all_idx, "spread", "away", as.numeric(sched$spread_line), sched$away_spread_odds),
      make(all_idx, "total", "over", as.numeric(sched$total_line), sched$over_odds),
      make(all_idx, "total", "under", as.numeric(sched$total_line), sched$under_odds)
    )
    snaps <- new_odds_snapshots(do.call(rbind, Filter(Negate(is.null), parts)) %||% odds_snapshots_empty())

    detail <- sprintf("%d of %d games in the schedule; %d without a moneyline",
                      nrow(sched), length(requested), sum(!has_ml))
    if (length(not_found)) detail <- paste0(detail, "; not in the schedule: ", paste(utils::head(not_found, 5), collapse = ", "))
    if (length(absent)) detail <- paste0(detail, "; column(s) absent: ", paste(absent, collapse = ", "))
    status <- if (nrow(sched) == 0) "unavailable" else if (length(not_found)) "failed" else "ok"
    odds_result(snaps, source = source, status = status, detail = detail)
  }

  new_odds_provider("nflverse", "nflverse_consensus", game_snapshots = game_snapshots)
}
