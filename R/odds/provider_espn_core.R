# =============================================================================
# ESPN core provider: game open/close lines and live DraftKings prop lines
# =============================================================================
# Keyless endpoints (see docs/odds-sources.md):
#   .../events/{id}/competitions/{id}/odds           game odds per provider. ESPN BET (58)
#       carries an open and a close block for every game from 2023; DraftKings (100)
#       replaces it late in 2025. The blocks have NO timestamp, so these rows are
#       snapshot_kind "open" / "close" with captured_at NA.
#   .../odds/100/propBets                            DraftKings prop LINES, live only
#       (404 after the game), no prices. Rows are line-only observations at fetch time.
# A provider item that is not in ESPN_GAME_VENUES or has neither an open nor a close
# moneyline block (Bet 365) is skipped and named in attr(, "skipped_providers"); a phase
# whose block is absent produces no rows for that phase; a prop type that
# is not mapped is named in attr(, "unmapped_types"). Nothing is guessed.
# A market block that is present but cannot be stored whole (a side missing, a line missing,
# a moneyline price that does not read) is dropped and counted in attr(, "dropped"). A spread
# or total row with a line and no price is kept and counted in attr(, "line_only") (R6).
# URL builders and the scoreboard parser come from R/capture_raw.R.
#
# Status (roadmap rule R5: partial data is stale), for game_snapshots and prop_snapshots:
#   ok           every requested game was fetched and read, with no gap
#   stale        partial data; the detail names each gap: a game without an ESPN event id, a game
#                or a prop page that failed or was refused, a fetched game with no ESPN BET or
#                DraftKings line or without a moneyline, spread or total, a market block dropped,
#                a run stopped by a refusal (HTTP 401, 403, 429). Line-only rows are counted in
#                the detail and are NOT a gap: ESPN publishes lines without prices
#   unavailable  no snapshot at all for what was requested
#   failed       an error was thrown while fetching or parsing (its message is in detail); the
#                rows read before it are kept
# =============================================================================

ESPN_GAME_VENUES <- c("58" = "espn_bet", "100" = "draftkings")
ESPN_GAME_MARKETS <- c("moneyline", "spread", "total")
ESPN_PROP_PROVIDER_ID <- 100L
ESPN_PROP_MARKETS <- c(
  "Total Passing Yards (incl. overtime)" = "passing_yards",
  "Total Rushing Yards (incl. overtime)" = "rushing_yards",
  "Total Receiving Yards (incl. overtime)" = "receiving_yards",
  "Total Receptions (incl. overtime)" = "receptions"
)

# "-6.5", "+7", "o48", "PK" -> number (a pick'em is a handicap of 0); NA when unreadable
espn_number <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  txt <- toupper(trimws(as.character(x)))
  if (txt %in% c("PK", "PICK", "EVEN")) return(0)
  suppressWarnings(as.numeric(gsub("[^0-9.+-]", "", txt)))
}

# An error message on one line, for a detail string
espn_one_line <- function(text) trimws(gsub("[[:space:]]+", " ", text))

#' Normalize one ESPN game-odds response (parsed JSON) into snapshots
parse_espn_game_odds <- function(parsed, game_id, sha256) {
  rows <- list()
  skipped <- character()
  dropped <- 0L
  add <- function(venue, market, side, kind, line, price) {
    rows[[length(rows) + 1]] <<- data.frame(
      game_id = game_id, market_id = market, venue_id = venue, side = side, line = line,
      price_american = american_to_int(price %||% NA_character_), snapshot_kind = kind, source = "espn_core",
      raw_sha256 = sha256, stringsAsFactors = FALSE
    )
  }
  for (it in parsed$items %||% list()) {
    pid <- as.character(it$provider$id %||% NA)
    label <- paste(pid, it$provider$name %||% "")
    venue <- unname(ESPN_GAME_VENUES[pid])
    h <- it$homeTeamOdds
    a <- it$awayTeamOdds
    # a block that is absent yields no rows for that phase (ESPN BET has a close but no open
    # for 80 of the 285 games of 2023); only an item with neither is skipped
    has_blocks <- !is.null(h$open$moneyLine$american) || !is.null(h$close$moneyLine$american)
    if (is.na(venue) || !has_blocks) {
      skipped <- c(skipped, trimws(label))
      next
    }
    for (phase in c("open", "close")) {
      hp <- h[[phase]]
      ap <- a[[phase]]
      # Each market below is stored whole or not at all. A block that is present but cannot be
      # stored (a side missing, a line missing, a moneyline price that does not read) is counted.
      h_ml <- hp$moneyLine$american
      a_ml <- ap$moneyLine$american
      if (!is.null(h_ml) || !is.null(a_ml)) {
        if (!is.na(american_to_int(h_ml %||% NA_character_)) && !is.na(american_to_int(a_ml %||% NA_character_))) {
          add(venue, "moneyline", "home", phase, NA_real_, h_ml)
          add(venue, "moneyline", "away", phase, NA_real_, a_ml)
        } else {
          dropped <- dropped + 1L
        }
      }
      h_pt <- hp$pointSpread$american
      a_pt <- ap$pointSpread$american
      if (!is.null(h_pt) || !is.null(a_pt)) {
        if (!is.na(espn_number(h_pt)) && !is.na(espn_number(a_pt))) {
          add(venue, "spread", "home", phase, espn_number(h_pt), hp$spread$american)
          add(venue, "spread", "away", phase, espn_number(a_pt), ap$spread$american)
        } else {
          dropped <- dropped + 1L
        }
      }
      tb <- it[[phase]]
      if (!is.null(tb$total$american) || !is.null(tb$over$american) || !is.null(tb$under$american)) {
        total_line <- espn_number(tb$total$american)
        if (!is.na(total_line)) {
          add(venue, "total", "over", phase, total_line, tb$over$american)
          add(venue, "total", "under", phase, total_line, tb$under$american)
        } else {
          dropped <- dropped + 1L
        }
      }
    }
  }
  out <- if (length(rows)) new_odds_snapshots(do.call(rbind, rows)) else odds_snapshots_empty()
  attr(out, "skipped_providers") <- skipped
  attr(out, "dropped") <- dropped
  attr(out, "line_only") <- sum(out$market_id %in% c("spread", "total") & !is.na(out$line) & is.na(out$price_american))
  out
}

#' Normalize one page of ESPN propBets (parsed JSON): current and open lines
parse_espn_prop_bets <- function(parsed, game_id, fetched_at, sha256) {
  rows <- list()
  unmapped <- character()
  for (it in parsed$items %||% list()) {
    type_name <- it$type$name %||% NA_character_
    market <- unname(ESPN_PROP_MARKETS[type_name])
    casino <- sub("^.*/casinos/([0-9]+).*$", "\\1", it$provider$`$ref` %||% "")
    venue <- unname(ESPN_GAME_VENUES[casino])
    if (is.na(market) || is.na(venue)) {
      if (is.na(market)) unmapped <- c(unmapped, type_name)
      next
    }
    athlete <- sub("^.*/athletes/([0-9]+).*$", "\\1", it$athlete$`$ref` %||% "")
    if (!grepl("^[0-9]+$", athlete)) next
    for (phase in c("current", "open")) {
      value <- it[[phase]]$target$value
      if (is.null(value)) next
      rows[[length(rows) + 1]] <- data.frame(
        game_id = game_id, market_id = market, venue_id = venue, player_key = paste0("espn:", athlete),
        side = "line", line = as.numeric(value),
        captured_at = if (phase == "current") fetched_at else as.POSIXct(NA, tz = "UTC"),
        snapshot_kind = if (phase == "current") "observed" else "open",
        source = "espn_core", raw_sha256 = sha256, stringsAsFactors = FALSE
      )
    }
  }
  out <- if (length(rows)) new_odds_snapshots(do.call(rbind, rows)) else odds_snapshots_empty()
  attr(out, "unmapped_types") <- unique(unmapped)
  out
}

provider_espn_core <- function(cfg = odds_http_config(), fetch_fn = odds_http_get, log_path = NULL,
                               now_fn = Sys.time, sleep_fn = Sys.sleep) {
  get <- function(url, source) {
    odds_fetch(url, cfg, fetch_fn = fetch_fn, log_path = log_path, source = source, now_fn = now_fn, sleep_fn = sleep_fn)
  }
  no_event_note <- function(ids) {
    sprintf("%d game%s without an ESPN event id", length(ids), if (length(ids) == 1) "" else "s")
  }
  game_list <- function(ids) paste(utils::head(ids, 5), collapse = ", ")

  game_snapshots <- function(games, on_raw = NULL, ...) {
    parts <- list()
    fetches <- list()
    failed <- character()
    no_event <- character()
    no_lines <- character()
    missing_market <- character()
    dropped <- 0L
    line_only <- 0L
    blocked <- FALSE
    thrown <- NULL
    tryCatch({
      for (i in seq_len(nrow(games))) {
        g <- games[i, , drop = FALSE]
        if (i %% 50L == 0L) message(sprintf("ESPN game odds: %d/%d games", i, nrow(games)))
        if (is.na(g$espn) || !nzchar(g$espn)) {
          no_event <- c(no_event, g$game_id)
          next
        }
        rec <- get(espn_game_odds_url(g$espn), "espn_game_odds")
        fetches[[length(fetches) + 1]] <- odds_fetch_row(rec, g$espn)
        parsed <- odds_json(rec)
        if (is.null(parsed)) {
          failed <- c(failed, sprintf("%s (%s)", g$game_id, rec$error %||% "not JSON"))
          if (rec$blocked) {
            blocked <- TRUE
            break
          }
          next
        }
        if (!is.null(on_raw)) on_raw(g$espn, rec$body, rec)
        snap <- parse_espn_game_odds(parsed, g$game_id, rec$sha256)
        parts[[length(parts) + 1]] <- snap
        dropped <- dropped + attr(snap, "dropped")
        line_only <- line_only + attr(snap, "line_only")
        if (nrow(snap) == 0) {
          no_lines <- c(no_lines, g$game_id)
        } else if (!all(ESPN_GAME_MARKETS %in% snap$market_id)) {
          missing_market <- c(missing_market, g$game_id)
        }
      }
    }, error = function(e) thrown <<- e)
    snaps <- bind_odds_snapshots(parts)
    gaps <- c(
      if (length(no_event)) no_event_note(no_event),
      if (length(failed)) paste0("failed: ", game_list(failed)),
      if (blocked) "blocked by the server, run stopped",
      if (length(no_lines)) sprintf("%d game(s) fetched with no ESPN BET or DraftKings line: %s", length(no_lines), game_list(no_lines)),
      if (length(missing_market)) sprintf("%d game(s) missing a moneyline, spread or total: %s", length(missing_market), game_list(missing_market)),
      if (dropped) sprintf("%d market block(s) dropped (a side, a line or a readable price missing)", dropped),
      if (!is.null(thrown)) paste0("stopped by an error: ", espn_one_line(conditionMessage(thrown)))
    )
    info <- if (line_only) sprintf("%d line-only row(s) kept (a spread or total line with no price)", line_only)
    detail <- paste(c(sprintf("%d of %d games fetched", length(parts), nrow(games)), gaps, info), collapse = "; ")
    status <- if (!is.null(thrown)) "failed" else if (nrow(snaps) == 0) "unavailable" else if (length(gaps)) "stale" else "ok"
    odds_result(snaps, source = "espn_core_game_odds", status = status, detail = detail,
                fetches = do.call(rbind, c(list(odds_fetches_empty()), fetches)))
  }

  prop_snapshots <- function(games, provider_id = ESPN_PROP_PROVIDER_ID, ...) {
    parts <- list()
    fetches <- list()
    gone <- character()
    no_event <- character()
    unmapped <- character()
    blocked <- FALSE
    thrown <- NULL
    tryCatch({
      for (i in seq_len(nrow(games))) {
        g <- games[i, , drop = FALSE]
        if (is.na(g$espn) || !nzchar(g$espn)) {
          no_event <- c(no_event, g$game_id)
          next
        }
        page <- 1L
        n_pages <- 1L
        while (page <= n_pages) {
          rec <- get(espn_prop_bets_url(g$espn, provider_id, page), "espn_propbets")
          fetches[[length(fetches) + 1]] <- odds_fetch_row(rec, sprintf("%s_%s_p%d", g$espn, provider_id, page))
          parsed <- odds_json(rec)
          if (is.null(parsed)) {
            if (rec$blocked) {
              blocked <- TRUE
            } else {
              gone <- c(gone, sprintf("%s page %d (%s)", g$game_id, page, rec$error %||% "not JSON"))
            }
            break
          }
          if (page == 1L) n_pages <- max(1L, as.integer(parsed$pageCount %||% 1L))
          snap <- parse_espn_prop_bets(parsed, g$game_id, rec$fetched_at, rec$sha256)
          parts[[length(parts) + 1]] <- snap
          unmapped <- c(unmapped, attr(snap, "unmapped_types"))
          page <- page + 1L
        }
        if (blocked) break
      }
    }, error = function(e) thrown <<- e)
    snaps <- bind_odds_snapshots(parts)
    gaps <- c(
      if (length(no_event)) no_event_note(no_event),
      if (length(gone)) paste0("no propBets for: ", game_list(gone),
                               " (DraftKings propBets are live only; they return 404 after the game)"),
      if (blocked) "blocked by the server, run stopped",
      if (!is.null(thrown)) paste0("stopped by an error: ", espn_one_line(conditionMessage(thrown)))
    )
    info <- if (length(unmapped)) sprintf("%d prop type(s) not mapped, skipped: %s", length(unique(unmapped)), game_list(unique(unmapped)))
    detail <- paste(c(sprintf("%d prop line row(s), lines only (ESPN publishes no prop prices)", nrow(snaps)), gaps, info),
                    collapse = "; ")
    status <- if (!is.null(thrown)) "failed" else if (nrow(snaps) == 0) "unavailable" else if (length(gaps)) "stale" else "ok"
    odds_result(snaps, source = "espn_core_prop_lines", status = status, detail = detail,
                fetches = do.call(rbind, c(list(odds_fetches_empty()), fetches)))
  }

  #' Forward capture: the scoreboard (and the coming week's), then odds for every game inside the
  #' game horizon and propBets for the games inside the prop horizon (owner A0, 2026-10-19).
  #' `fetch(source, key, url)` stores the raw response and returns its text, or NULL.
  #' ESPN's default scoreboard lists the week just played until ESPN rolls it over, so the next week
  #' is asked for by number as well (R4); this mirrors run_capture() in R/capture_raw.R.
  capture <- function(fetch, now, cfg) {
    if (is.null(cfg$game_horizon_hours)) {
      stop("provider_espn_core capture: cfg$game_horizon_hours is missing (config.R CAPTURE_ESPN_GAME_HORIZON_HOURS)",
           call. = FALSE)
    }
    sb_text <- fetch("espn_scoreboard", "scoreboard", espn_scoreboard_url())
    if (is.null(sb_text)) return(invisible(FALSE))
    events <- parse_espn_scoreboard(sb_text)
    sb_week <- parse_espn_scoreboard_week(sb_text)
    next_week <- if (is.null(sb_week)) NULL else espn_next_week(sb_week)
    if (!is.null(next_week)) {
      next_text <- fetch("espn_scoreboard",
                         sprintf("scoreboard_%d_t%d_w%02d", next_week$year, next_week$type, next_week$week),
                         espn_scoreboard_url(next_week))
      if (!is.null(next_text)) {
        upcoming <- parse_espn_scoreboard(next_text)
        events <- rbind(events, upcoming[!upcoming$event_id %in% events$event_id, , drop = FALSE])
      }
    }
    targets <- capture_targets(events, now, cfg$game_horizon_hours, cfg$horizon_hours)
    message(sprintf("ESPN: %d game(s) within %sh (game odds), %d within %sh (props)",
                    length(targets$game), cfg$game_horizon_hours, length(targets$props), cfg$horizon_hours))
    for (event_id in targets$game) {
      fetch("espn_game_odds", event_id, espn_game_odds_url(event_id))
      if (!event_id %in% targets$props) next
      for (provider_id in cfg$espn_prop_providers) {
        first <- fetch("espn_propbets", sprintf("%s_%s_p1", event_id, provider_id),
                       espn_prop_bets_url(event_id, provider_id, 1))
        if (is.null(first)) next
        for (page in seq_len(espn_page_count(first))[-1]) {
          fetch("espn_propbets", sprintf("%s_%s_p%d", event_id, provider_id, page),
                espn_prop_bets_url(event_id, provider_id, page))
        }
      }
    }
    invisible(TRUE)
  }

  new_odds_provider("espn_core", unname(ESPN_GAME_VENUES), game_snapshots = game_snapshots,
                    prop_snapshots = prop_snapshots, capture = capture)
}
