# =============================================================================
# PROP ODDS: point-in-time quote cache, CSV loader, ScoresAndOdds parser (off by default)
# =============================================================================
# File: R/prop_odds_api.R
# Purpose: Load prop quotes from keyless sources and look them up by game and player id.
# The keyed The Odds API client was retired (audit P4, P5; keyless data only).
# =============================================================================


# =============================================================================
# SCORESANDODDS MARKET-COMPARISON SCRAPER
# =============================================================================

scoresandodds_market_map <- c(
  passing_yards = "passing yards",
  rushing_yards = "rushing yards",
  receiving_yards = "receiving yards",
  receptions = "receptions",
  anytime_td = "touchdowns"
)

scoresandodds_user_agent <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

scoresandodds_endpoint_map <- c(
  passing_yards = "https://www.scoresandodds.com/nfl/props/passing-yards",
  rushing_yards = "https://www.scoresandodds.com/nfl/props/rushing-yards",
  receiving_yards = "https://www.scoresandodds.com/nfl/props/receiving-yards",
  receptions = "https://www.scoresandodds.com/nfl/props/receptions",
  anytime_td = "https://www.scoresandodds.com/nfl/props/touchdowns"
)

extract_scoresandodds_events <- function(html_text) {
  if (!requireNamespace("xml2", quietly = TRUE)) return(character(0))
  doc <- tryCatch(xml2::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(character(0))
  nodes <- xml2::xml_find_all(doc, "//*[@data-event]")
  events <- unique(xml2::xml_attr(nodes, "data-event"))
  events <- events[!is.na(events) & nzchar(events)]
  events
}

fetch_scoresandodds_market <- function(event_id, market) {
  if (!requireNamespace("httr", quietly = TRUE) ||
      !requireNamespace("jsonlite", quietly = TRUE)) return(NULL)

  base_url <- "https://rga51lus77.execute-api.us-east-1.amazonaws.com/prod/market-comparison"
  url <- sprintf("%s?event=%s&market=%s",
                 base_url,
                 utils::URLencode(event_id, reserved = TRUE),
                 utils::URLencode(market, reserved = TRUE))

  ua <- scoresandodds_user_agent %||% "Mozilla/5.0"
  resp <- tryCatch({
    httr::GET(url, httr::timeout(15), httr::user_agent(ua))
  }, error = function(e) NULL)

  if (is.null(resp) || httr::status_code(resp) != 200) return(NULL)

  content <- tryCatch({
    jsonlite::fromJSON(
      httr::content(resp, "text", encoding = "UTF-8"),
      simplifyVector = FALSE
    )
  }, error = function(e) NULL)

  content
}

parse_scoresandodds_market_json <- function(payload, prop_type) {
  if (is.null(payload) || !is.list(payload) || is.null(payload$markets)) {
    return(tibble::tibble())
  }

  home_team <- payload$event$home$key %||% NA_character_
  away_team <- payload$event$away$key %||% NA_character_
  event_id <- if (!is.null(payload$event) && !is.null(payload$event$sport)) {
    sprintf("%s/%s", payload$event$sport, payload$event$home$id %||% payload$event$away$id %||% "")
  } else {
    NA_character_
  }

  rows <- lapply(payload$markets, function(mkt) {
    if (is.null(mkt) || !is.list(mkt)) return(NULL)
    if (is.null(mkt$comparison)) return(NULL)
    player_name <- NA_character_
    if (!is.null(mkt$player$first_name)) {
      player_name <- paste(mkt$player$first_name, mkt$player$last_name)
    } else if (!is.null(mkt$player$last_name)) {
      player_name <- mkt$player$last_name
    }

    team_key <- mkt$player$team$key %||% NA_character_

    book_rows <- lapply(names(mkt$comparison), function(book_key) {
      bk <- mkt$comparison[[book_key]]
      if (is.null(bk)) return(NULL)
      available <- bk$available
      if (isFALSE(available)) return(NULL)
      tibble::tibble(
        player = player_name,
        prop_type = prop_type,
        line = suppressWarnings(as.numeric(bk$value)),
        line_over = suppressWarnings(as.numeric(bk$value)),
        line_under = suppressWarnings(as.numeric(bk$value)),
        over_odds = suppressWarnings(as.numeric(bk$over)),
        under_odds = suppressWarnings(as.numeric(bk$under)),
        book = book_key,
        event_id = payload$event$id %||% NA_character_,
        home_team = home_team,
        away_team = away_team,
        team = team_key,
        source = "scoresandodds"
      )
    })
    dplyr::bind_rows(book_rows)
  })

  dplyr::bind_rows(rows)
}

#' Load prop odds from ScoresAndOdds market-comparison API
#'
#' @param prop_types Vector of prop types to fetch
#' @param allow_remote Logical to allow remote scraping
#' @param sleep_sec Delay between requests
#' @return Tibble of prop odds or NULL
load_prop_odds_scoresandodds <- function(prop_types = NULL,
                                         allow_remote = FALSE,
                                         sleep_sec = NULL) {

  if (!isTRUE(allow_remote)) {
    message("INFO: ScoresAndOdds scraping disabled (PROP_ODDS_ALLOW_REMOTE_HTML=FALSE)")
    return(NULL)
  }

  if (!requireNamespace("httr", quietly = TRUE) ||
      !requireNamespace("jsonlite", quietly = TRUE) ||
      !requireNamespace("xml2", quietly = TRUE)) {
    warning("httr/jsonlite/xml2 packages required for ScoresAndOdds scraping")
    return(NULL)
  }

  if (is.null(prop_types)) prop_types <- names(scoresandodds_market_map)
  prop_types <- intersect(prop_types, names(scoresandodds_market_map))
  if (!length(prop_types)) return(NULL)

  if (is.null(sleep_sec) && exists("PROP_ODDS_SCRAPE_DELAY_SEC")) {
    sleep_sec <- PROP_ODDS_SCRAPE_DELAY_SEC
  }
  if (is.null(sleep_sec) || !is.finite(sleep_sec)) sleep_sec <- 0.4

  all_rows <- list()

  for (prop_type in prop_types) {
    endpoint <- scoresandodds_endpoint_map[[prop_type]]
    market <- scoresandodds_market_map[[prop_type]]
    if (is.null(endpoint) || is.null(market)) next

    html <- tryCatch({
      resp <- httr::GET(endpoint, httr::timeout(15), httr::user_agent(scoresandodds_user_agent))
      if (httr::status_code(resp) != 200) return(NULL)
      httr::content(resp, "text", encoding = "UTF-8")
    }, error = function(e) NULL)

    if (is.null(html)) next
    event_ids <- extract_scoresandodds_events(html)
    if (!length(event_ids)) next

    for (event_id in event_ids) {
      payload <- fetch_scoresandodds_market(event_id, market)
      parsed <- parse_scoresandodds_market_json(payload, prop_type)
      if (!is.null(parsed) && nrow(parsed) > 0) {
        all_rows[[length(all_rows) + 1]] <- parsed
      }
      if (sleep_sec > 0) Sys.sleep(sleep_sec)
    }
  }

  if (!length(all_rows)) return(NULL)
  dplyr::bind_rows(all_rows)
}


# =============================================================================
# POINT-IN-TIME PROP QUOTES (audit P14 and P9)
# =============================================================================
# The quote cache has one row per (player, market, book, capture); see the table in the
# P1 plan, Task 3. A quote is used for a game only when it was captured at or before that
# game's kickoff and before now, and only when it is fresh. Players are matched by id,
# never by name. Anything else leaves the prop unpriced with a reason (rule M11).

PROP_CACHE_REQUIRED <- c("player_id", "prop_type", "game_id", "captured_at", "book")

#' Kickoff instant (UTC) from nflverse gameday and gametime (US Eastern)
#'
#' NA when either input is missing or blank: no default kickoff time is invented.
prop_kickoff_utc <- function(gameday, gametime) {
  gameday <- as.character(gameday)
  gametime <- as.character(gametime)
  ok <- !is.na(gameday) & nzchar(gameday) & !is.na(gametime) & nzchar(gametime)
  secs <- rep(NA_real_, length(gameday))
  if (any(ok)) {
    secs[ok] <- as.numeric(as.POSIXct(paste(gameday[ok], gametime[ok]),
                                      format = "%Y-%m-%d %H:%M", tz = "America/New_York"))
  }
  as.POSIXct(secs, origin = "1970-01-01", tz = "UTC")
}

#' Quotes usable for one player's prop in one game at the decision time
#'
#' @param prop_odds_data Quote cache (see PROP_CACHE_REQUIRED)
#' @param player_id gsis id
#' @param prop_type Market, e.g. "passing_yards"
#' @param game_id nflverse game id
#' @param kickoff POSIXct kickoff of that game
#' @param now POSIXct of the run; the decision time is min(kickoff, now)
#' @param max_age_min A quote older than this many minutes at the decision time is stale
#' @return list(quotes = tibble or NULL, reason = chr). quotes holds the latest capture per
#'   (venue, book) captured at or before the decision time; reason is "" when quotes is set.
get_market_prop_quotes <- function(prop_odds_data, player_id, prop_type, game_id, kickoff,
                                   now = Sys.time(),
                                   max_age_min = get0("PROP_QUOTE_MAX_AGE_MIN", ifnotfound = NULL)) {
  if (is.null(max_age_min) || length(max_age_min) != 1 || !is.finite(max_age_min)) {
    stop("get_market_prop_quotes: PROP_QUOTE_MAX_AGE_MIN is not set (config.R)", call. = FALSE)
  }
  none <- function(reason) list(quotes = NULL, reason = reason)

  if (is.null(prop_odds_data) || nrow(prop_odds_data) == 0) return(none("No prop lines loaded"))
  absent <- setdiff(PROP_CACHE_REQUIRED, names(prop_odds_data))
  if (length(absent)) {
    return(none(sprintf("Prop lines lack %s (cannot be placed in time)", paste(absent, collapse = ", "))))
  }
  if (!inherits(prop_odds_data$captured_at, "POSIXct")) return(none("captured_at is not a timestamp"))
  player_id <- as.character(player_id)
  if (length(player_id) != 1 || is.na(player_id) || !nzchar(player_id)) return(none("Player id unresolved"))
  game_id <- as.character(game_id)
  if (length(game_id) != 1 || is.na(game_id) || !nzchar(game_id)) return(none("Game id missing"))
  if (length(kickoff) != 1 || is.na(kickoff)) return(none("Kickoff unknown"))

  q <- prop_odds_data[prop_odds_data$prop_type %in% prop_type &
                        prop_odds_data$game_id %in% game_id &
                        prop_odds_data$player_id %in% player_id, , drop = FALSE]
  if (nrow(q) == 0) return(none("No line for this player and game"))
  if (all(is.na(q$captured_at))) return(none("Line capture time missing or without a time zone"))

  asof <- min(kickoff, as.POSIXct(now))
  q <- q[!is.na(q$captured_at) & q$captured_at <= asof, , drop = FALSE]
  if (nrow(q) == 0) return(none("No line captured before kickoff"))

  # Each book's latest capture, with every line it offered then: a Kalshi strike ladder or a
  # book's alternate lines are separate quotes, and a line the book has since moved is
  # superseded (final review I2)
  q$venue <- if ("venue" %in% names(q)) ifelse(is.na(q$venue), "book", q$venue) else "book"
  book_key <- paste(q$venue, q$book)
  latest <- stats::ave(as.numeric(q$captured_at), book_key, FUN = max)
  q <- q[as.numeric(q$captured_at) == latest, , drop = FALSE]
  line_col <- function(nm) if (nm %in% names(q)) q[[nm]] else rep(NA_real_, nrow(q))
  q <- q[!duplicated(paste(q$venue, q$book, line_col("line_over"), line_col("line_under"))), , drop = FALSE]

  age_min <- as.numeric(difftime(asof, q$captured_at, units = "mins"))
  fresh <- age_min <= max_age_min
  if (!any(fresh)) {
    return(none(sprintf("Newest line is stale (%.0f min before the decision time, limit %.0f)",
                        min(age_min), max_age_min)))
  }
  list(quotes = q[fresh, , drop = FALSE], reason = "")
}

#' Best sportsbook quote for a player's prop in a game at the decision time
#'
#' Replaces the name-keyed lookup (audit P14, P9). Returns NULL, after calling
#' `on_unpriced(reason)`, when nothing usable exists.
#'
#' @param player_id gsis id
#' @param prop_type Market, e.g. "passing_yards"
#' @param prop_odds_data Quote cache
#' @param game_id nflverse game id
#' @param kickoff POSIXct kickoff
#' @param now POSIXct of the run
#' @param preferred_books Optional books to prefer (used only if any of them has a quote)
#' @param sim_values Simulated stat values: pick the best-EV quote across books and Kalshi
#'   (see select_best_quote) instead of the lowest-vig book
#' @param p_yes Model probability of Yes for a one-way market (anytime TD); same selection
#' @param on_unpriced Optional function(reason) called when the prop stays unpriced
#' @return list(player, prop_type, line, line_over, line_under, over_odds, under_odds, book,
#'   books, n_books, captured_at, venue) or NULL
#' @export
get_market_prop_line <- function(player_id, prop_type, prop_odds_data, game_id, kickoff,
                                 now = Sys.time(), preferred_books = NULL, on_unpriced = NULL,
                                 sim_values = NULL, p_yes = NULL) {
  unpriced <- function(reason) {
    if (is.function(on_unpriced)) on_unpriced(reason)
    NULL
  }

  res <- get_market_prop_quotes(prop_odds_data, player_id, prop_type, game_id, kickoff, now)
  if (is.null(res$quotes)) return(unpriced(res$reason))
  matches <- res$quotes

  # With the model's distribution: EV at the best fresh price for the side the model likes (P12)
  if (!is.null(sim_values) || !is.null(p_yes)) {
    best <- select_best_quote(matches, sim_values = sim_values, p_yes = p_yes)
    if (is.null(best)) return(unpriced("Market odds missing"))
    best$player <- player_id
    best$prop_type <- prop_type
    return(best)
  }

  # Apply preferred book filter if available
  if (!is.null(preferred_books)) {
    preferred_books <- tolower(preferred_books)
    matches$book <- tolower(matches$book)
    preferred_matches <- matches[matches$book %in% preferred_books, , drop = FALSE]
    if (nrow(preferred_matches) > 0) matches <- preferred_matches
  }

  priced <- matches[is.finite(suppressWarnings(as.numeric(matches$over_odds))), , drop = FALSE]
  if (nrow(priced) == 0) return(unpriced("Market odds missing"))
  matches <- priced

  # Choose best book row (min vig for two-way, max price for one-way)
  is_one_way <- all(is.na(matches$under_odds) | !is.finite(matches$under_odds))

  score_row <- function(df) {
    if (nrow(df) == 1) return(df)
    if (is_one_way) {
      dec <- american_to_decimal_odds(df$over_odds)
      df[which.max(dec), , drop = FALSE]
    } else {
      over_p <- american_odds_to_implied_prob(df$over_odds)
      under_p <- american_odds_to_implied_prob(df$under_odds)
      vig <- over_p + under_p
      df[which.min(vig), , drop = FALSE]
    }
  }

  best_row <- score_row(matches)

  as_scalar_num <- function(x) {
    if (is.null(x)) return(NA_real_)
    if (is.list(x)) x <- unlist(x, recursive = TRUE, use.names = FALSE)
    x <- suppressWarnings(as.numeric(x))
    if (!length(x)) return(NA_real_)
    x[1]
  }

  line_over <- if ("line_over" %in% names(best_row)) best_row$line_over else best_row$line
  line_under <- if ("line_under" %in% names(best_row)) best_row$line_under else best_row$line
  line_over <- as_scalar_num(line_over)
  line_under <- as_scalar_num(line_under)

  # Use average line when over/under lines are very close
  line_value <- if (is.finite(line_over) && is.finite(line_under) &&
                    abs(line_over - line_under) <= 0.25) {
    mean(c(line_over, line_under), na.rm = TRUE)
  } else if (is.finite(line_over)) {
    line_over
  } else {
    line_under
  }

  list(
    player = player_id,
    prop_type = prop_type,
    line = as_scalar_num(line_value),
    line_over = line_over,
    line_under = line_under,
    over_odds = as_scalar_num(best_row$over_odds),
    under_odds = as_scalar_num(best_row$under_odds),
    book = best_row$book[1],
    books = unique(matches$book),
    n_books = length(unique(matches$book)),
    captured_at = best_row$captured_at[1],
    venue = best_row$venue[1]
  )
}

#' Fill missing player ids in a quote cache, exactly (Task 2 resolver)
#'
#' Rows that already carry a player_id keep it. Others are resolved from `player` and `team`;
#' what cannot be resolved stays NA and can never match a player (the count is logged).
attach_player_ids <- function(cache, xwalk) {
  if (is.null(cache) || nrow(cache) == 0) return(cache)
  if (!"player_id" %in% names(cache)) cache$player_id <- NA_character_
  cache$player_id <- as.character(cache$player_id)
  need <- is.na(cache$player_id) | !nzchar(cache$player_id)
  if (any(need)) {
    nm <- if ("player" %in% names(cache)) cache$player else rep(NA_character_, nrow(cache))
    tm <- if ("team" %in% names(cache)) cache$team else rep(NA_character_, nrow(cache))
    resolved <- resolve_player_ids(nm[need], tm[need], xwalk)
    cache$player_id[need] <- resolved$player_id
  }
  cache
}

# =============================================================================
# PROP ODDS FALLBACK UTILITIES
# =============================================================================

# Team abbreviation to full name map (for odds providers using full names)
TEAM_ABBR_TO_NAME <- c(
  "ARI" = "Arizona Cardinals",
  "ATL" = "Atlanta Falcons",
  "BAL" = "Baltimore Ravens",
  "BUF" = "Buffalo Bills",
  "CAR" = "Carolina Panthers",
  "CHI" = "Chicago Bears",
  "CIN" = "Cincinnati Bengals",
  "CLE" = "Cleveland Browns",
  "DAL" = "Dallas Cowboys",
  "DEN" = "Denver Broncos",
  "DET" = "Detroit Lions",
  "GB"  = "Green Bay Packers",
  "HOU" = "Houston Texans",
  "IND" = "Indianapolis Colts",
  "JAX" = "Jacksonville Jaguars",
  "KC"  = "Kansas City Chiefs",
  "LAC" = "Los Angeles Chargers",
  "LAR" = "Los Angeles Rams",
  "LV"  = "Las Vegas Raiders",
  "MIA" = "Miami Dolphins",
  "MIN" = "Minnesota Vikings",
  "NE"  = "New England Patriots",
  "NO"  = "New Orleans Saints",
  "NYG" = "New York Giants",
  "NYJ" = "New York Jets",
  "PHI" = "Philadelphia Eagles",
  "PIT" = "Pittsburgh Steelers",
  "SEA" = "Seattle Seahawks",
  "SF"  = "San Francisco 49ers",
  "TB"  = "Tampa Bay Buccaneers",
  "TEN" = "Tennessee Titans",
  "WAS" = "Washington Commanders"
)

probability_to_american_safe <- function(p) {
  if (exists("probability_to_american", mode = "function")) {
    return(probability_to_american(p))
  }
  p <- suppressWarnings(as.numeric(p))
  if (!is.finite(p) || p <= 0 || p >= 1) return(NA_real_)
  if (p == 0.5) return(100)
  if (p > 0.5) {
    return(-as.numeric(round(100 * p / (1 - p))))
  }
  as.numeric(round(100 * (1 - p) / p))
}

round_to_half <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  if (!is.finite(x)) return(NA_real_)
  round(x * 2) / 2
}

apply_two_way_vig <- function(p_over, p_under, vig = 0.045) {
  p_over <- suppressWarnings(as.numeric(p_over))
  p_under <- suppressWarnings(as.numeric(p_under))
  if (!is.finite(p_over) || !is.finite(p_under) || p_over <= 0 || p_under <= 0) {
    return(list(p_over = NA_real_, p_under = NA_real_))
  }
  scale <- (1 + vig) / (p_over + p_under)
  list(
    p_over = pmin(p_over * scale, 0.99),
    p_under = pmin(p_under * scale, 0.99)
  )
}

derive_two_way_odds_from_probs <- function(p_over, p_under, vig = 0.045) {
  vigged <- apply_two_way_vig(p_over, p_under, vig = vig)
  list(
    over_odds = probability_to_american_safe(vigged$p_over),
    under_odds = probability_to_american_safe(vigged$p_under)
  )
}

derive_one_way_odds_from_prob <- function(p, vig = 0.045) {
  p <- suppressWarnings(as.numeric(p))
  if (!is.finite(p) || p <= 0 || p >= 1) return(NA_real_)
  p_vig <- pmin(p * (1 + vig), 0.99)
  probability_to_american_safe(p_vig)
}

derive_prop_market_from_sim <- function(sim_values,
                                        line_quantile = NULL,
                                        vig = NULL) {
  sim_values <- suppressWarnings(as.numeric(sim_values))
  sim_values <- sim_values[is.finite(sim_values)]
  if (!length(sim_values)) {
    return(list(line = NA_real_, over_odds = NA_real_, under_odds = NA_real_))
  }

  if (is.null(line_quantile) && exists("PROP_FALLBACK_LINE_QUANTILE")) {
    line_quantile <- PROP_FALLBACK_LINE_QUANTILE
  }
  if (is.null(line_quantile) || !is.finite(line_quantile)) {
    line_quantile <- 0.50
  }

  if (is.null(vig) && exists("PROP_MARKET_VIG")) {
    vig <- PROP_MARKET_VIG
  }
  if (is.null(vig) || !is.finite(vig)) {
    vig <- 0.045
  }

  line_raw <- stats::quantile(sim_values, probs = line_quantile, names = FALSE, na.rm = TRUE)
  line <- round_to_half(line_raw)

  p_over <- mean(sim_values > line)
  p_under <- mean(sim_values < line)
  p_push <- pmax(1 - p_over - p_under, 0)

  vigged <- apply_two_way_vig(p_over, p_under, vig = vig)
  over_odds <- probability_to_american_safe(vigged$p_over)
  under_odds <- probability_to_american_safe(vigged$p_under)

  list(
    line = line,
    over_odds = over_odds,
    under_odds = under_odds,
    p_over = p_over,
    p_under = p_under,
    p_push = p_push
  )
}

#' Parse ISO 8601 instants that state their zone: a trailing Z or an offset (+HH:MM, +HHMM).
#' A time without a zone is NA, never assumed UTC (final review C2: a quote seen at 16:30
#' Eastern, written without a zone, was read as 16:30 UTC and priced an 18:00 UTC kickoff).
parse_utc_instant <- function(x) {
  s <- sub("T", " ", trimws(as.character(x)), fixed = TRUE)
  s <- sub("Z$", "+0000", s)
  s <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", s)
  s <- sub("^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2})([+-][0-9]{4})$", "\\1:00\\2", s)
  s <- sub("(:[0-9]{2})[.][0-9]+([+-][0-9]{4})$", "\\1\\2", s)
  ok <- !is.na(s) & grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$", s)
  out <- as.POSIXct(rep(NA_real_, length(s)), origin = "1970-01-01", tz = "UTC")
  out[ok] <- as.POSIXct(s[ok], format = "%Y-%m-%d %H:%M:%S%z", tz = "UTC")
  out
}

load_prop_odds_csv <- function(path = NULL) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NULL)
  if (!requireNamespace("readr", quietly = TRUE)) {
    warning("readr package required to load prop odds CSV")
    return(NULL)
  }
  # Every column is read as text: the prices are converted below, and captured_at is parsed
  # strictly (readr's guess would take a time without a zone as UTC)
  raw <- tryCatch(readr::read_csv(path, show_col_types = FALSE,
                                  col_types = readr::cols(.default = readr::col_character())),
                  error = function(e) NULL)
  if (is.null(raw) || nrow(raw) == 0) return(NULL)

  # The cache contract (P1 Task 3): a prop type, a player by gsis id or by name, and a price,
  # as American odds (books) or a bid and an ask (Kalshi). Legacy files without game_id or
  # captured_at still load, so every prop can say why it stays unpriced.
  has_player <- "player_id" %in% names(raw) || "player" %in% names(raw)
  has_price <- "over_odds" %in% names(raw) || all(c("yes_bid", "yes_ask") %in% names(raw))
  if (!"prop_type" %in% names(raw) || !has_player || !has_price) {
    warning("Prop odds CSV needs prop_type, a player (player_id or player) and a price (over_odds, or yes_bid and yes_ask): ", path)
    return(NULL)
  }
  num_cols <- intersect(c("line", "line_over", "line_under", "over_odds", "under_odds", "yes_bid", "yes_ask"), names(raw))
  for (cc in num_cols) raw[[cc]] <- suppressWarnings(as.numeric(raw[[cc]]))
  if (!"source" %in% names(raw)) raw$source <- "csv"
  if ("captured_at" %in% names(raw)) {
    text <- raw$captured_at
    raw$captured_at <- parse_utc_instant(text)
    no_zone <- !is.na(text) & nzchar(trimws(text)) & is.na(raw$captured_at)
    if (any(no_zone)) {
      message(sprintf("  %d prop line(s) in %s have a captured_at with no time zone; they are not used (write ISO 8601 with Z or an offset)",
                      sum(no_zone), basename(path)))
    }
  }
  raw
}

resolve_prop_odds_cache <- function(source = NULL,
                                    csv_path = NULL,
                                    source_order = NULL,
                                    xwalk = NULL) {
  if (is.null(source) && exists("PROP_ODDS_SOURCE")) source <- PROP_ODDS_SOURCE
  if (is.null(csv_path) && exists("PROP_ODDS_CSV_PATH")) csv_path <- PROP_ODDS_CSV_PATH
  if (is.null(source_order) && exists("PROP_ODDS_SOURCE_ORDER")) {
    source_order <- PROP_ODDS_SOURCE_ORDER
  }

  source <- tolower(source %||% "auto")
  if (is.null(source_order) || !length(source_order)) {
    source_order <- c("csv", "model")
  }
  source_order <- tolower(source_order)
  cache <- NULL
  cache_source <- "model"

  allow_remote <- if (exists("PROP_ODDS_ALLOW_REMOTE_HTML")) isTRUE(PROP_ODDS_ALLOW_REMOTE_HTML) else FALSE

  # If a single source is specified, override order
  if (!is.null(source) && !identical(source, "auto")) {
    source_order <- c(source)
  }

  for (src in source_order) {
    src <- tolower(src %||% "")
    if (!nzchar(src)) next

    if (src %in% c("scoresandodds", "sao")) {
      cache <- load_prop_odds_scoresandodds(allow_remote = allow_remote)
      if (!is.null(cache) && nrow(cache) > 0) {
        cache_source <- "scoresandodds"
        break
      }
    }


    if (src %in% c("csv", "file", "local")) {
      cache <- load_prop_odds_csv(csv_path)
      if (!is.null(cache) && nrow(cache) > 0) {
        cache_source <- "csv"
        break
      }
    }
  }

  if (is.null(cache) || nrow(cache) == 0) {
    cache <- NULL
    cache_source <- "model"
  }

  if (!is.null(cache)) {
    needs_ids <- !"player_id" %in% names(cache) || anyNA(cache$player_id) || any(!nzchar(cache$player_id))
    if (needs_ids) {
      if (is.null(xwalk)) {
        xwalk <- tryCatch(build_player_xwalk(), error = function(e) {
          message(sprintf("  Player id crosswalk unavailable (%s): no quote can be matched to a player", e$message))
          NULL
        })
      }
      cache <- if (is.null(xwalk)) {
        if (!"player_id" %in% names(cache)) cache$player_id <- NA_character_
        cache
      } else {
        attach_player_ids(cache, xwalk)
      }
    }
    attr(cache, "source") <- cache_source
  }
  cache
}

# NULL-coalescing operator
if (!exists("%||%")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

#' Get default prop odds when API unavailable
#'
#' Returns position-based realistic odds for props when no market data exists.
#'
#' @param prop_type Type of prop ("passing_yards", "rushing_yards", etc.)
#' @param position Player position ("QB", "RB", "WR", "TE")
#' @param baseline Player's projected baseline value
#'
#' @return List with line, over_odds, under_odds
#'
#' @export
get_default_prop_odds <- function(prop_type, position, baseline) {
  allow_model_odds <- isTRUE(if (exists("PROP_ALLOW_MODEL_ODDS")) PROP_ALLOW_MODEL_ODDS else FALSE)

  if (prop_type == "anytime_td") {
    # Position-based TD odds (realistic market ranges)
    odds <- switch(position,
      QB = 350,    # QBs score in ~15% of games → +350
      RB = -110,   # RB1s score in ~45% of games → -110
      WR = 140,    # WR1s score in ~35% of games → +140
      TE = 200,    # TE1s score in ~25% of games → +200
      200          # Default
    )

    return(list(
      line = NA_real_,
      over_odds = if (allow_model_odds) odds else NA_real_,     # "Yes" odds
      under_odds = NA_real_ # TD props don't have "No" lines typically
    ))
  }

  # Yard props: line at 95% of baseline (typical market placement)
  # -110 both sides is industry standard when synthetic odds are enabled
  list(
    line = round(baseline * 0.95, 0) + 0.5,
    over_odds = if (allow_model_odds) -110 else NA_real_,
    under_odds = if (allow_model_odds) -110 else NA_real_
  )
}

#' Format American odds for display
#'
#' @param odds Numeric American odds value
#' @return Character string with + prefix for positive odds
#'
#' @export
format_american_odds <- function(odds) {
  odds <- suppressWarnings(as.numeric(odds))
  out <- rep("N/A", length(odds))
  valid <- is.finite(odds)
  pos <- valid & odds >= 0
  neg <- valid & odds < 0
  out[pos] <- sprintf("+%d", round(odds[pos]))
  out[neg] <- sprintf("%d", round(odds[neg]))
  if (length(out) == 1) return(out[1])
  out
}

#' Calculate implied probability from American odds
#'
#' @param odds American odds (positive or negative)
#' @return Implied probability (0-1)
#'
#' @export
american_odds_to_implied_prob <- function(odds) {
  odds <- suppressWarnings(as.numeric(odds))
  out <- rep(NA_real_, length(odds))
  valid <- is.finite(odds)
  pos <- valid & odds >= 0
  neg <- valid & odds < 0
  out[pos] <- 100 / (odds[pos] + 100)
  out[neg] <- abs(odds[neg]) / (abs(odds[neg]) + 100)
  out
}

#' Calculate decimal odds from American odds
#'
#' @param odds American odds
#' @return Decimal odds
#'
#' @export
american_to_decimal_odds <- function(odds) {
  odds <- suppressWarnings(as.numeric(odds))
  out <- rep(NA_real_, length(odds))
  valid <- is.finite(odds)
  pos <- valid & odds >= 0
  neg <- valid & odds < 0
  out[pos] <- 1 + odds[pos] / 100
  out[neg] <- 1 + 100 / abs(odds[neg])
  out
}
