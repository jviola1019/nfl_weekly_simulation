# =============================================================================
# Kalshi provider: game and player-prop contracts, hourly candles (roadmap D1)
# =============================================================================
# Public market data, no key (see docs/odds-sources.md):
#   /historical/cutoff                                         the date after which settled markets leave /historical
#   /markets?event_ticker=E                                    live markets of an event
#   /historical/markets?event_ticker=E                         markets settled before the cutoff
#   /series/S/markets/T/candlesticks?...&period_interval=60    live candles
#   /historical/markets/T/candlesticks?...                     historical candles
# The cutoff moves (2026-07-31 on 2026-09-29, 2026-08-14 on 2026-10-13), so it is read at
# run time. Each event tries the side of the cutoff it falls on first and falls back to
# the other side on a 404 or an empty list. The two candle forms differ in field names
# (price.close vs price.close_dollars), and both are parsed.
# One row per candle: captured_at is the candle's end, bid/ask/last are the yes-side
# close in dollars, volume is the candle volume. The Kalshi close is the mid of the last
# pre-kickoff candle (kalshi_mid), chosen by select_closing_snapshots().
# Supported contracts: KXNFLGAME (moneyline) and the player series below. Spread and total
# series are not mapped yet; a market that cannot be mapped is counted, never guessed.
#
# Status (roadmap rule R5: partial data is stale), as in the ESPN core provider:
#   ok           every game was found and read, with no gap
#   stale        partial data; the detail names each gap: a game without a kickoff or without a
#                Kalshi event, a request that failed (with its real error text), a response with
#                schema drift (a field the parser needs is absent), a list longer than the 20-page
#                cap, an unreadable cutoff, a candle without a readable time or with an unreadable
#                price, a run stopped by a block. Unsupported markets, markets without pre-kickoff
#                candles (a market that opened after kickoff has none) and price-less candle rows
#                are counted in the detail and are NOT a gap (R6)
#   unavailable  no snapshot at all for what was requested
#   failed       an error escaped the provider (its message is in detail). A failed result carries
#                NO snapshots (R7); its `fetches` still list the requests that completed
# A block is a 401, 403 or 429, or a 2xx response whose body is not JSON (a captcha, challenge or
# geo-fence page served as 200). The run stops at the first one and makes no further request.
# The block and error helpers (odds_is_html_block, odds_fetch_problem, ...) are in provider.R.
# =============================================================================

KALSHI_GAME_SERIES <- "KXNFLGAME"
KALSHI_SERIES_MARKETS <- c(
  KXNFLGAME = "moneyline", KXNFLANYTD = "anytime_td", KXNFL2TD = "td_2plus", KXNFLFIRSTTD = "first_td",
  KXNFLRECYDS = "receiving_yards", KXNFLRSHYDS = "rushing_yards", KXNFLPASSYDS = "passing_yards",
  KXNFLREC = "receptions"
)
# KXNFLTD holds 1+/2+/3+/4+ touchdown strikes as separate markets; only 1+ and 2+ map to a market
KALSHI_TD_LADDER <- c("0.5" = "anytime_td", "1.5" = "td_2plus")
KALSHI_PROP_SERIES <- c("KXNFLANYTD", "KXNFLTD", "KXNFL2TD", "KXNFLFIRSTTD", "KXNFLRECYDS", "KXNFLRSHYDS",
                        "KXNFLPASSYDS", "KXNFLREC")
KALSHI_PAGE_LIMIT <- 1000L
KALSHI_MAX_PAGES <- 20L
KALSHI_MONTHS <- c("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")

kalshi_cutoff_url <- function() paste0(KALSHI_BASE, "/historical/cutoff")

kalshi_event_markets_url <- function(event_ticker, historical, cursor = NULL) {
  url <- sprintf("%s/%smarkets?event_ticker=%s&limit=%d", KALSHI_BASE, if (historical) "historical/" else "",
                 utils::URLencode(event_ticker, reserved = TRUE), KALSHI_PAGE_LIMIT)
  if (!is.null(cursor) && nzchar(cursor)) url <- paste0(url, "&cursor=", utils::URLencode(cursor, reserved = TRUE))
  url
}

kalshi_candles_url <- function(series, ticker, start_ts, end_ts, historical, period_minutes = 60L) {
  path <- if (historical) sprintf("historical/markets/%s", ticker) else sprintf("series/%s/markets/%s", series, ticker)
  sprintf("%s/%s/candlesticks?start_ts=%d&end_ts=%d&period_interval=%d", KALSHI_BASE, path,
          as.integer(start_ts), as.integer(end_ts), as.integer(period_minutes))
}

# Kalshi writes Jacksonville as JAC, and the Rams as LA (2025 tickers) or LAR (2026 tickers)
kalshi_spellings <- function(team) {
  switch(team, JAX = c("JAX", "JAC"), JAC = c("JAX", "JAC"), LA = c("LA", "LAR"), LAR = c("LA", "LAR"), team)
}

kalshi_date_code <- function(date) {
  sprintf("%s%s%02d", format(date, "%y"), KALSHI_MONTHS[as.integer(format(date, "%m"))], as.integer(format(date, "%d")))
}

#' Candidate event tickers for a game: SERIES-YYMONDD + AWAY + HOME, over every spelling
#' of the two teams and every date offset (days from the ET game day)
kalshi_candidate_events <- function(series, game, date_offsets = 0L) {
  base_date <- as.Date(game$gameday)
  away <- kalshi_spellings(game$away_team)
  home <- kalshi_spellings(game$home_team)
  suffixes <- as.vector(outer(away, home, paste0))
  unlist(lapply(date_offsets, function(d) paste0(series, "-", kalshi_date_code(base_date + d), suffixes)))
}

kalshi_parse_event_ticker <- function(event_ticker) {
  m <- regmatches(event_ticker, regexpr("-[0-9]{2}[A-Z]{3}[0-9]{2}", event_ticker))
  if (length(m) == 0) return(list(date = as.Date(NA), suffix = NA_character_))
  code <- sub("^-", "", m)
  month <- match(substr(code, 3, 5), KALSHI_MONTHS)
  list(date = as.Date(sprintf("20%s-%02d-%s", substr(code, 1, 2), month, substr(code, 6, 7))),
       suffix = sub("^.*-[0-9]{2}[A-Z]{3}[0-9]{2}", "", event_ticker))
}

kalshi_num <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else suppressWarnings(as.numeric(x))

#' How one Kalshi market maps to (market_id, side, line, player_key).
#' @return list(ok = TRUE, market_id, side, line, player_key) or list(ok = FALSE, reason)
kalshi_market_meta <- function(market, game, series) {
  no <- function(reason, drift = FALSE) list(ok = FALSE, reason = reason, drift = drift)
  ticker <- market$ticker %||% ""
  if (series == KALSHI_GAME_SERIES) {
    code <- sub("^.*-", "", ticker)
    side <- if (code %in% kalshi_spellings(game$home_team)) "home" else if (code %in% kalshi_spellings(game$away_team)) "away" else NA_character_
    if (is.na(side)) return(no(sprintf("team code %s matches neither side of %s", code, game$game_id)))
    return(list(ok = TRUE, market_id = "moneyline", side = side, line = NA_real_, player_key = NA_character_))
  }
  player <- market$custom_strike$football_player
  if (is.null(player)) return(no(sprintf("%s has no player in custom_strike", ticker)))
  strike <- kalshi_num(market$floor_strike)
  if (series == "KXNFLTD") {
    market_id <- unname(KALSHI_TD_LADDER[format(strike, nsmall = 1)])
    if (is.na(market_id)) return(no(sprintf("strike %s is not mapped for KXNFLTD", strike)))
  } else {
    market_id <- unname(KALSHI_SERIES_MARKETS[series])
    if (is.na(market_id)) return(no(sprintf("series %s is not supported", series)))
  }
  # a touchdown market's strike is its definition: anytime = more than 0.5, 2+ = more than 1.5
  # a yards or receptions market without its strike has no line to store: schema drift, never a NA line
  if (is.na(strike) && market_id %in% c("passing_yards", "rushing_yards", "receiving_yards", "receptions")) {
    return(no(sprintf("%s has no floor_strike", ticker), drift = TRUE))
  }
  if (is.na(strike)) strike <- switch(market_id, anytime_td = 0.5, td_2plus = 1.5, NA_real_)
  list(ok = TRUE, market_id = market_id, side = "yes", line = strike, player_key = paste0("kalshi:", player))
}

#' Mid price from a genuine two-sided quote (0 < bid <= ask < 1); otherwise NA
kalshi_mid <- function(bid, ask) {
  ok <- !is.na(bid) & !is.na(ask) & bid > 0 & ask < 1 & bid <= ask
  ifelse(ok, (bid + ask) / 2, NA_real_)
}

#' Normalize a candlesticks response (either endpoint form) into snapshots. A candle is kept
#' unless its time cannot be read. Every class of candle that is not kept whole is counted, never
#' dropped silently, in attributes of the result:
#'   no_time      candles without a readable end time (skipped)
#'   bad_fields   candles with a price or volume that is present but unreadable, a dollar price
#'                outside [0, 1], or a crossed quote (bid above ask); the bad values are stored as NA
#'   price_less   candles with no bid, ask or last at all (kept; a candle with no trade has none)
parse_kalshi_candles <- function(parsed, meta, game_id, sha256, source) {
  candles <- parsed$candlesticks %||% list()
  no_time <- 0L
  bad_fields <- 0L
  price_less <- 0L
  rows <- list()
  for (cd in candles) {
    if (!is.list(cd)) {
      no_time <- no_time + 1L
      next
    }
    bad <- FALSE
    num <- function(raw, dollars = FALSE) {
      if (is.null(raw) || length(raw) == 0) return(NA_real_)
      v <- if (length(raw) == 1) suppressWarnings(as.numeric(raw)) else NA_real_
      if (is.na(v) || !is.finite(v) || (dollars && (v < 0 || v > 1))) {
        bad <<- TRUE
        return(NA_real_)
      }
      v
    }
    field <- function(obj, name) {
      if (is.null(obj)) return(NA_real_)
      if (!is.list(obj)) {          # a bare value where a quote object belongs: unreadable, counted
        bad <<- TRUE
        return(NA_real_)
      }
      num(obj[[name]] %||% obj[[paste0(name, "_dollars")]], dollars = TRUE)
    }
    ts <- kalshi_num(if (length(cd$end_period_ts) == 1) cd$end_period_ts else NULL)
    if (is.na(ts) || !is.finite(ts)) {
      no_time <- no_time + 1L
      next
    }
    bid <- field(cd$yes_bid, "close")
    ask <- field(cd$yes_ask, "close")
    last <- field(cd$price, "close")
    if (!is.na(bid) && !is.na(ask) && bid > ask) {
      bid <- NA_real_
      ask <- NA_real_
      bad <- TRUE
    }
    volume <- num(cd$volume_fp %||% cd$volume)
    if (bad) bad_fields <- bad_fields + 1L else if (is.na(bid) && is.na(ask) && is.na(last)) price_less <- price_less + 1L
    rows[[length(rows) + 1]] <- data.frame(
      game_id = game_id, market_id = meta$market_id, venue_id = "kalshi", player_key = meta$player_key,
      side = meta$side, line = meta$line, bid = bid, ask = ask, last = last, volume = volume,
      captured_at = as.POSIXct(ts, origin = "1970-01-01", tz = "UTC"),
      snapshot_kind = "candle", source = source, raw_sha256 = sha256, stringsAsFactors = FALSE
    )
  }
  out <- if (length(rows)) new_odds_snapshots(do.call(rbind, rows)) else odds_snapshots_empty()
  attr(out, "no_time") <- no_time
  attr(out, "bad_fields") <- bad_fields
  attr(out, "price_less") <- price_less
  out
}

# The condition that stops a run at a block (never retried or worked around)
kalshi_block_condition <- function(note) {
  structure(class = c("kalshi_block", "error", "condition"), list(message = note, call = NULL))
}

# "3 games" / "1 game"
kalshi_count <- function(n, noun) sprintf("%d %s%s", n, noun, if (n == 1) "" else "s")

provider_kalshi <- function(cfg = odds_http_config(), fetch_fn = odds_http_get, log_path = NULL,
                            now_fn = Sys.time, sleep_fn = Sys.sleep) {
  get <- function(url, source) {
    odds_fetch(url, cfg, fetch_fn = fetch_fn, log_path = log_path, source = source, now_fn = now_fn, sleep_fn = sleep_fn)
  }

  # snapshots_for() builds these as it goes; they are per call
  snapshots_for <- function(games, series_vec, hours_before, max_markets_per_event, date_offsets, on_raw, source_name) {
    parts <- list()
    fetches <- list()
    failures <- character()
    drift <- character()
    capped <- character()
    n_no_kickoff <- 0L
    n_not_found <- 0L
    n_unsupported <- 0L
    unsupported <- character()
    n_no_candles <- 0L
    n_no_time <- 0L
    n_bad_fields <- 0L
    n_price_less <- 0L
    cutoff <- NULL
    cutoff_note <- NULL
    blocked <- NULL
    never_attempted <- 0L
    thrown <- NULL
    log_fetch <- function(rec, key) fetches[[length(fetches) + 1]] <<- odds_fetch_row(rec, key)
    note_failure <- function(rec, what) {
      if (isTRUE(rec$status == 404L)) return(invisible(NULL))
      failures <<- c(failures, sprintf("%s (%s)", what, odds_fetch_problem(rec)))
    }
    # The body as JSON, or NULL when there is none. A 2xx body that is not JSON (a captcha,
    # challenge or geo-fence page served as 200) and a 401/403/429 stop the whole run at once.
    read_json <- function(rec, where) {
      parsed <- odds_json(rec)
      if (!is.null(parsed)) {
        if (is.list(parsed) && (length(parsed) == 0 || !is.null(names(parsed)))) return(parsed)
        drift <<- c(drift, sprintf("%s returned JSON that is not an object", where))    # valid JSON, wrong shape: not a block
        return(list())
      }
      valid_json <- odds_is_html_block(rec) && !is.null(rec$body) &&
        tryCatch({ jsonlite::fromJSON(rawToChar(rec$body), simplifyVector = FALSE); TRUE }, error = function(e) FALSE)
      if (valid_json) {            # JSON null: valid JSON, wrong shape
        drift <<- c(drift, sprintf("%s returned JSON null, not an object", where))
        return(list())
      }
      if (odds_is_html_block(rec)) stop(kalshi_block_condition(odds_html_block_note(rec, where)))
      if (isTRUE(rec$blocked)) {
        stop(kalshi_block_condition(sprintf("blocked: HTTP %s at %s; run stopped", rec$status, where)))
      }
      NULL
    }

    # All markets of one event on one endpoint (paged to the cap); empty when there are none
    list_markets <- function(event_ticker, historical) {
      markets <- list()
      cursor <- NULL
      done <- FALSE
      for (page in seq_len(KALSHI_MAX_PAGES)) {
        rec <- get(kalshi_event_markets_url(event_ticker, historical, cursor), "kalshi_markets")
        log_fetch(rec, sprintf("%s_%s_p%d", event_ticker, if (historical) "hist" else "live", page))
        parsed <- read_json(rec, event_ticker)
        if (is.null(parsed)) {
          note_failure(rec, event_ticker)
          done <- TRUE
          break
        }
        if (!"markets" %in% names(parsed)) {      # an absent key is drift; null or [] means no markets
          drift <<- c(drift, sprintf("%s has no markets field", event_ticker))
          done <- TRUE
          break
        }
        got <- parsed$markets %||% list()
        usable <- vapply(got, function(m) is.list(m) && is.character(m$ticker) && length(m$ticker) == 1 && nzchar(m$ticker), logical(1))
        if (!all(usable)) drift <<- c(drift, sprintf("%s has %s without a ticker", event_ticker, kalshi_count(sum(!usable), "market")))
        markets <- c(markets, got[usable])
        cursor <- parsed$cursor
        if (is.null(cursor) || !nzchar(cursor)) {
          done <- TRUE
          break
        }
      }
      if (!done) capped <<- c(capped, sprintf("%s has more than %d pages, read the first %d", event_ticker, KALSHI_MAX_PAGES, KALSHI_MAX_PAGES))
      markets
    }

    # The event of a game: every spelling on the endpoint on the cutoff side of the kickoff
    # first, and only if none exists there, every spelling on the other endpoint
    find_event <- function(series, g, historical_first) {
      for (historical in c(historical_first, !historical_first)) {
        for (event_ticker in kalshi_candidate_events(series, g, date_offsets)) {
          markets <- list_markets(event_ticker, historical)
          if (length(markets)) return(list(markets = markets, historical = historical))
        }
      }
      NULL
    }

    tryCatch({
      for (i in seq_len(nrow(games))) {
        g <- games[i, , drop = FALSE]
        if (is.na(g$kickoff_utc)) {
          n_no_kickoff <- n_no_kickoff + 1L
          next
        }
        if (is.null(cutoff)) {
          rec <- get(kalshi_cutoff_url(), "kalshi_cutoff")
          log_fetch(rec, "cutoff")
          parsed <- read_json(rec, "the historical cutoff")
          ts <- parsed$market_settled_ts
          cutoff <- if (is.character(ts) && length(ts) == 1) as.POSIXct(ts, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else as.POSIXct(NA, tz = "UTC")
          if (is.na(cutoff)) {
            cutoff_note <- sprintf("historical cutoff unreadable (%s); live endpoints tried first",
                                   if (is.null(parsed)) odds_fetch_problem(rec) else "no market_settled_ts")
          }
        }
        historical_first <- !is.na(cutoff) && g$kickoff_utc < cutoff
        ko <- as.integer(as.numeric(g$kickoff_utc))
        for (series in series_vec) {
          found <- find_event(series, g, historical_first)
          if (is.null(found)) {
            n_not_found <- n_not_found + 1L
            next
          }
          markets <- found$markets
          markets <- markets[order(vapply(markets, function(m) m$ticker, ""))]
          if (is.finite(max_markets_per_event)) markets <- utils::head(markets, max_markets_per_event)
          for (m in markets) {
            meta <- kalshi_market_meta(m, g, series)
            if (!meta$ok) {
              if (isTRUE(meta$drift)) {
                drift <- c(drift, meta$reason)
              } else {
                n_unsupported <- n_unsupported + 1L
                unsupported <- c(unsupported, meta$reason)
              }
              next
            }
            got <- NULL
            outcome <- "none"       # rows | empty (no pre-kickoff candles, or a 404 on both endpoints) | unreadable
            for (historical in c(found$historical, !found$historical)) {
              rec <- get(kalshi_candles_url(series, m$ticker, ko - hours_before * 3600L, ko, historical), "kalshi_candles")
              log_fetch(rec, sprintf("%s_%s", m$ticker, if (historical) "hist" else "live"))
              parsed <- read_json(rec, m$ticker)
              if (is.null(parsed)) {
                note_failure(rec, m$ticker)
                if (isTRUE(rec$status == 404L)) {
                  outcome <- "empty"
                  next
                }
                outcome <- "unreadable"
                break
              }
              if (is.null(parsed$candlesticks)) {
                drift <- c(drift, sprintf("%s has no candlesticks field", m$ticker))
                outcome <- "unreadable"
                break
              }
              if (length(parsed$candlesticks) == 0) {   # an empty 200 is an answer: no pre-kickoff candles
                outcome <- "empty"
                break
              }
              if (!is.null(on_raw)) on_raw(m$ticker, rec$body, rec)
              got <- parse_kalshi_candles(parsed, meta, g$game_id, rec$sha256,
                                          if (historical) "kalshi_historical" else "kalshi_live")
              n_no_time <- n_no_time + attr(got, "no_time")
              n_bad_fields <- n_bad_fields + attr(got, "bad_fields")
              n_price_less <- n_price_less + attr(got, "price_less")
              outcome <- "rows"
              break
            }
            if (outcome == "empty") n_no_candles <- n_no_candles + 1L
            if (!is.null(got)) parts[[length(parts) + 1]] <- got
          }
        }
      }
    }, kalshi_block = function(b) {
      blocked <<- conditionMessage(b)
      never_attempted <<- nrow(games) - i       # i is the game the block stopped
    },
       error = function(e) thrown <<- e)

    all_fetches <- do.call(rbind, c(list(odds_fetches_empty()), fetches))
    if (!is.null(thrown)) {
      # R7: a failed result carries no snapshots; the requests that completed stay in the lineage
      return(odds_result(source = source_name, status = "failed", fetches = all_fetches,
                         detail = paste0(sprintf("%d request(s) completed; stopped by an error: ", nrow(all_fetches)),
                                         odds_one_line(conditionMessage(thrown)))))
    }
    snaps <- bind_odds_snapshots(parts)
    shown <- function(x, n = 5) paste0(paste(utils::head(unique(x), n), collapse = " | "),
                                       if (length(unique(x)) > n) sprintf(" (+%d more)", length(unique(x)) - n) else "")
    gaps <- c(
      if (n_no_kickoff) sprintf("%s without a kickoff", kalshi_count(n_no_kickoff, "game")),
      if (n_not_found) sprintf("%d game-series with no Kalshi event", n_not_found),
      if (length(failures)) paste0("failed: ", shown(failures)),
      if (!is.null(cutoff_note)) cutoff_note,
      if (length(drift)) paste0("schema drift: ", shown(drift)),
      if (length(capped)) paste0("more pages than the ", KALSHI_MAX_PAGES, "-page cap: ", shown(capped)),
      if (!is.null(blocked)) paste0(blocked, if (never_attempted > 0) paste0("; ", kalshi_count(never_attempted, "game"), " never attempted")),
      if (n_no_time) sprintf("%d candle without a readable time skipped", n_no_time),
      if (n_bad_fields) sprintf("%d candle(s) with an unreadable price or crossed quote (stored as NA)", n_bad_fields)
    )
    info <- c(
      if (n_unsupported) sprintf("%s (%s)", sprintf("%d unsupported market%s", n_unsupported, if (n_unsupported == 1) "" else "s"), shown(unsupported, 3)),
      if (n_no_candles) sprintf("%d market%s without candles", n_no_candles, if (n_no_candles == 1) "" else "s"),
      if (n_price_less) sprintf("%d price-less candle row(s) kept (no bid, ask or last)", n_price_less)
    )
    detail <- paste(c(sprintf("%d snapshot rows", nrow(snaps)), gaps, info), collapse = "; ")
    status <- if (nrow(snaps) == 0) "unavailable" else if (length(gaps)) "stale" else "ok"
    odds_result(snaps, source = source_name, status = status, detail = detail, fetches = all_fetches)
  }

  game_snapshots <- function(games, hours_before = 48L, date_offsets = 0L, on_raw = NULL, ...) {
    snapshots_for(games, KALSHI_GAME_SERIES, hours_before, Inf, date_offsets, on_raw, "kalshi_games")
  }

  # One candle request per market: an event has hundreds, so cap them with max_markets_per_event
  prop_snapshots <- function(games, series = KALSHI_PROP_SERIES, hours_before = 48L, date_offsets = 0L,
                             max_markets_per_event = Inf, on_raw = NULL, ...) {
    snapshots_for(games, series, hours_before, max_markets_per_event, date_offsets, on_raw, "kalshi_props")
  }

  #' Forward capture: the open markets of every per-game NFL series. A body that is not JSON
  #' (a challenge or geo-fence page served as 200) stops the pass at once and returns FALSE;
  #' a series with more than KALSHI_MAX_PAGES pages is read to the cap and the gap is printed.
  capture <- function(fetch, now, cfg) {
    block <- function(key) {
      message(sprintf("Kalshi capture: blocked: body is not JSON (a challenge or geo-fence page) at %s; run stopped", key))
      invisible(FALSE)
    }
    series_text <- fetch("kalshi_series", "sports", kalshi_series_url())
    if (is.null(series_text)) return(invisible(FALSE))
    as_object <- function(text) {       # list(ok, value): ok FALSE when the text is not JSON at all
      v <- tryCatch(list(value = jsonlite::fromJSON(text, simplifyVector = FALSE)), error = function(e) NULL)
      if (is.null(v)) return(list(ok = FALSE))
      list(ok = TRUE, object = is.list(v$value) && (length(v$value) == 0 || !is.null(names(v$value))), value = v$value)
    }
    series_json <- as_object(series_text)
    if (!series_json$ok) return(block("sports"))
    if (!series_json$object) {
      message("Kalshi capture: the series response is not a JSON object; nothing read")
      return(invisible(FALSE))
    }
    if (!"series" %in% names(series_json$value)) {
      message("Kalshi capture: schema drift, the series response has no series field; nothing read")
      return(invisible(FALSE))
    }
    series <- series_json$value$series %||% list()
    tickers <- vapply(series, function(s) as.character(s$ticker %||% NA_character_), character(1))
    if (anyNA(tickers)) message(sprintf("Kalshi: %s without a ticker skipped", kalshi_count(sum(is.na(tickers)), "series entry")))
    tickers <- sort(tickers[!is.na(tickers)])
    tickers <- tickers[is_nfl_game_series(tickers)]
    message(sprintf("Kalshi: %d per-game NFL series", length(tickers)))
    for (ticker in tickers) {
      cursor <- NULL
      page <- 1L
      repeat {
        key <- sprintf("%s_p%d", ticker, page)
        text <- fetch("kalshi_markets", key, kalshi_open_markets_url(ticker, cursor))
        if (is.null(text)) break
        page_json <- as_object(text)
        if (!page_json$ok) return(block(key))
        if (!page_json$object) {
          message(sprintf("Kalshi: %s is not a JSON object (schema drift), series skipped", key))
          break
        }
        cursor <- page_json$value$cursor
        if (is.null(cursor) || !nzchar(cursor)) break
        if (page >= KALSHI_MAX_PAGES) {
          message(sprintf("Kalshi: %s has more than %d pages, read the first %d", ticker, KALSHI_MAX_PAGES, KALSHI_MAX_PAGES))
          break
        }
        page <- page + 1L
      }
    }
    invisible(TRUE)
  }

  new_odds_provider("kalshi", "kalshi", game_snapshots = game_snapshots, prop_snapshots = prop_snapshots,
                    capture = capture)
}
