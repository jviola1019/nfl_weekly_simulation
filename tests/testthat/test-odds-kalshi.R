# =============================================================================
# Tests: the Kalshi provider (R/odds/provider_kalshi.R)
# Fixtures in fixtures/odds/ are trimmed REAL responses from the public Kalshi API
# (fetched 2026-10-13): the 2026-10-12 BUF at LA game, its touchdown and receiving
# yards props, an August 2026 preseason market for the historical endpoint form, and
# /historical/cutoff. Every fetch goes through odds_fake_fetch(): no network.
# =============================================================================

KO <- as.POSIXct("2026-10-13 00:15:00", tz = "UTC")      # BUF at LA, Monday night
GAME_K <- data.frame(game_id = "2026_05_BUF_LA", season = 2026L, week = 5L, gameday = "2026-10-12",
                     kickoff_utc = KO, home_team = "LA", away_team = "BUF", espn = "401872994",
                     stringsAsFactors = FALSE)
PRE_KO <- as.POSIXct("2026-08-07 00:00:00", tz = "UTC")  # CAR at ARI, preseason (not an nflverse game)
GAME_PRE <- data.frame(game_id = "pre_2026_08_06_CAR_ARI", season = 2026L, week = 0L, gameday = "2026-08-06",
                       kickoff_utc = PRE_KO, home_team = "ARI", away_team = "CAR", espn = NA_character_,
                       stringsAsFactors = FALSE)
TS <- function(t) as.integer(as.numeric(t))
EV_GAME <- "KXNFLGAME-26OCT12BUFLAR"
empty_markets <- list(text = '{"markets": [], "cursor": ""}')
empty_candles <- list(text = '{"candlesticks": []}')
HTML_200 <- list(status = 200L, text = "<html><body>Just a moment... verify you are human</body></html>")

kalshi_provider <- function(routes, clock = odds_fake_clock()) {
  odds_http_reset()
  fake <- odds_fake_fetch(routes)
  list(provider = provider_kalshi(cfg = odds_http_config(), fetch_fn = fake$fn, now_fn = clock$now, sleep_fn = clock$sleep),
       fake = fake, clock = clock)
}

# A parsed fixture back to a route that serves it as inline text (for tests that edit a fixture)
kalshi_json_route <- function(parsed) {
  list(text = as.character(jsonlite::toJSON(parsed, auto_unbox = TRUE, digits = NA, null = "null")))
}

# The routes of a normal BUF at LA game run: BUFLA is empty, BUFLAR has the two markets
game_routes <- function(buf_candles = "kalshi_candles_game_live.json", lar_candles = empty_candles) {
  win <- function(ticker) kalshi_candles_url("KXNFLGAME", ticker, TS(KO) - 48L * 3600L, TS(KO), FALSE)
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- empty_markets
  b[[kalshi_event_markets_url(EV_GAME, FALSE)]] <- "kalshi_markets_game_live.json"
  b[[win("KXNFLGAME-26OCT12BUFLAR-BUF")]] <- buf_candles
  b[[win("KXNFLGAME-26OCT12BUFLAR-LAR")]] <- lar_candles
  b
}

test_that("Kalshi URLs are built exactly", {
  b <- "https://api.elections.kalshi.com/trade-api/v2"
  expect_equal(kalshi_cutoff_url(), paste0(b, "/historical/cutoff"))
  expect_equal(kalshi_event_markets_url(EV_GAME, historical = FALSE),
               paste0(b, "/markets?event_ticker=", EV_GAME, "&limit=1000"))
  expect_equal(kalshi_event_markets_url(EV_GAME, historical = TRUE, cursor = "a b"),
               paste0(b, "/historical/markets?event_ticker=", EV_GAME, "&limit=1000&cursor=a%20b"))
  expect_equal(kalshi_candles_url("KXNFLGAME", "KXNFLGAME-X-BUF", 10L, 20L, historical = FALSE),
               paste0(b, "/series/KXNFLGAME/markets/KXNFLGAME-X-BUF/candlesticks?start_ts=10&end_ts=20&period_interval=60"))
  expect_equal(kalshi_candles_url("KXNFLGAME", "KXNFLGAME-X-BUF", 10L, 20L, historical = TRUE),
               paste0(b, "/historical/markets/KXNFLGAME-X-BUF/candlesticks?start_ts=10&end_ts=20&period_interval=60"))
})

test_that("event tickers are built from the game, trying each spelling of JAX and LA", {
  expect_equal(kalshi_candidate_events("KXNFLGAME", GAME_K), c("KXNFLGAME-26OCT12BUFLA", "KXNFLGAME-26OCT12BUFLAR"))
  jax <- transform(GAME_K, home_team = "JAX", away_team = "KC", gameday = "2026-09-13")
  expect_equal(kalshi_candidate_events("KXNFLTD", jax), c("KXNFLTD-26SEP13KCJAX", "KXNFLTD-26SEP13KCJAC"))
  expect_equal(kalshi_candidate_events("KXNFLGAME", GAME_K, date_offsets = c(0L, 1L))[3], "KXNFLGAME-26OCT13BUFLA")
  expect_equal(kalshi_parse_event_ticker("KXNFLTD-26SEP28PHICHI")$date, as.Date("2026-09-28"))
  expect_true(is.na(kalshi_parse_event_ticker("KXNFLWINS-NO")$date))
})

test_that("a market maps to a moneyline side, a prop market and a strike, or is named as unsupported", {
  game_markets <- odds_fixture_json("kalshi_markets_game_live.json")$markets
  by_ticker <- setNames(game_markets, vapply(game_markets, `[[`, "", "ticker"))
  away <- kalshi_market_meta(by_ticker[["KXNFLGAME-26OCT12BUFLAR-BUF"]], GAME_K, "KXNFLGAME")
  home <- kalshi_market_meta(by_ticker[["KXNFLGAME-26OCT12BUFLAR-LAR"]], GAME_K, "KXNFLGAME")
  expect_equal(c(away$market_id, away$side), c("moneyline", "away"))
  expect_equal(home$side, "home")                                   # Kalshi spells the Rams LAR; nflverse says LA

  td <- odds_fixture_json("kalshi_markets_td_live.json")$markets
  metas <- lapply(td, kalshi_market_meta, game = GAME_K, series = "KXNFLTD")
  ok <- Filter(function(m) m$ok, metas)
  expect_setequal(vapply(ok, `[[`, "", "market_id"), c("anytime_td", "td_2plus"))
  expect_equal(unique(vapply(ok, `[[`, "", "side")), "yes")
  expect_equal(unique(vapply(ok, `[[`, "", "player_key")), "kalshi:28cbef9d-f049-419b-89d0-5dbf89d38eef")
  bad <- Filter(function(m) !m$ok, metas)
  expect_length(bad, 1)
  expect_match(bad[[1]]$reason, "strike 3.5")

  rec <- kalshi_market_meta(odds_fixture_json("kalshi_markets_recyds_live.json")$markets[[1]], GAME_K, "KXNFLRECYDS")
  expect_equal(c(rec$market_id, rec$line), c("receiving_yards", "74.5"))
  expect_false(kalshi_market_meta(list(ticker = "KXNFLSPREAD-X-BUF"), GAME_K, "KXNFLSPREAD")$ok)
  expect_false(kalshi_market_meta(list(ticker = "KXNFLGAME-X-ZZZ"), GAME_K, "KXNFLGAME")$ok)   # team code matches neither side
})

test_that("candles from both endpoint forms normalize to bid, ask, last and volume", {
  meta <- list(ok = TRUE, market_id = "moneyline", side = "away", line = NA_real_, player_key = NA_character_)
  live <- parse_kalshi_candles(odds_fixture_json("kalshi_candles_game_live.json"), meta, "2026_05_BUF_LA", "e", "kalshi_live")
  expect_equal(nrow(live), 4)
  expect_equal(validate_odds_snapshots(live), character())
  expect_equal(unique(live$snapshot_kind), "candle")
  expect_equal(unique(live$venue_id), "kalshi")
  expect_true(all(live$bid <= live$ask))
  expect_equal(max(live$captured_at), as.POSIXct("2026-10-13 00:00:00", tz = "UTC"))
  hist <- parse_kalshi_candles(odds_fixture_json("kalshi_candles_game_historical.json"), meta, "g", "h", "kalshi_historical")
  expect_equal(nrow(hist), 3)                                        # the historical form says price.close, not price.close_dollars
  expect_false(anyNA(hist$bid) || anyNA(hist$ask) || anyNA(hist$last))
  expect_equal(unique(hist$source), "kalshi_historical")
  # a candle with no trade has no last price, and that stays NA
  untraded <- odds_fixture_json("kalshi_candles_game_live.json")
  untraded$candlesticks[[1]]$price <- NULL
  expect_true(is.na(parse_kalshi_candles(untraded, meta, "g", "e", "kalshi_live")$last[1]))
  expect_equal(nrow(parse_kalshi_candles(list(candlesticks = list()), meta, "g", "e", "kalshi_live")), 0)
})

test_that("kalshi_mid needs a genuine two-sided quote", {
  expect_equal(kalshi_mid(c(.48, 0, .40, .55), c(.50, .5, 1, .50)), c(.49, NA, NA, NA))
})

test_that("game_snapshots tries each spelling, reads live candles and feeds the closing rule", {
  k <- kalshi_provider(game_routes())
  res <- k$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "ok")
  s <- res$snapshots
  expect_equal(nrow(s), 4)
  expect_equal(unique(s$side), "away")                               # BUF is the away team
  expect_equal(unique(s$source), "kalshi_live")
  expect_match(res$source_status$detail, "1 market without candles")
  expect_equal(res$fetches$source[1], "kalshi_cutoff")
  expect_true(all(grepl("^[0-9a-f]{64}$", res$fetches$raw_sha256)))
  close <- select_closing_snapshots(s, data.frame(game_id = "2026_05_BUF_LA", kickoff_utc = KO))
  expect_equal(nrow(close), 1)
  expect_equal(close$close_gap_min, 15)
  expect_true(close$headline_eligible)
})

test_that("a game that kicked off before Kalshi's historical cutoff reads the historical endpoints only", {
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLGAME-26AUG06CARARI", TRUE)]] <- "kalshi_markets_game_historical.json"
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26AUG06CARARI-CAR", TS(PRE_KO) - 48L * 3600L, TS(PRE_KO), TRUE)]] <- "kalshi_candles_game_historical.json"
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26AUG06CARARI-ARI", TS(PRE_KO) - 48L * 3600L, TS(PRE_KO), TRUE)]] <- list(status = 404L)
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26AUG06CARARI-ARI", TS(PRE_KO) - 48L * 3600L, TS(PRE_KO), FALSE)]] <- list(status = 404L)
  k <- kalshi_provider(b)
  res <- k$provider$game_snapshots(GAME_PRE)
  expect_equal(res$source_status$status, "ok")
  expect_equal(unique(res$snapshots$source), "kalshi_historical")
  expect_equal(unique(res$snapshots$side), "away")                   # CAR is the away team
  expect_match(res$source_status$detail, "1 market without candles")
  expect_equal(sum(grepl("/series/", k$fake$state$urls)), 1)        # a live candle request only as the fallback for the 404
})

test_that("props: unsupported strikes are named, markets opened after kickoff have no candles, nothing is invented", {
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLTD-26OCT12BUFLA", FALSE)]] <- empty_markets
  b[[kalshi_event_markets_url("KXNFLTD-26OCT12BUFLAR", FALSE)]] <- "kalshi_markets_td_live.json"
  b[[kalshi_event_markets_url("KXNFLRECYDS-26OCT12BUFLA", FALSE)]] <- empty_markets
  b[[kalshi_event_markets_url("KXNFLRECYDS-26OCT12BUFLAR", FALSE)]] <- "kalshi_markets_recyds_live.json"
  win <- function(series, ticker) kalshi_candles_url(series, ticker, TS(KO) - 48L * 3600L, TS(KO), FALSE)
  b[[win("KXNFLTD", "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-1")]] <- "kalshi_candles_td_live.json"
  b[[win("KXNFLTD", "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-2")]] <- empty_candles
  b[[win("KXNFLRECYDS", "KXNFLRECYDS-26OCT12BUFLAR-BUFTJOHNSON26-75")]] <- "kalshi_candles_recyds_live.json"
  k <- kalshi_provider(b)
  res <- k$provider$prop_snapshots(GAME_K, series = c("KXNFLTD", "KXNFLRECYDS"))
  s <- res$snapshots
  expect_equal(res$source_status$status, "ok")
  expect_equal(nrow(s), 3)                                           # Cook 1+ only: three candles
  expect_equal(unique(s$market_id), "anytime_td")
  expect_equal(unique(s$line), 0.5)
  expect_equal(unique(s$player_key), "kalshi:28cbef9d-f049-419b-89d0-5dbf89d38eef")
  expect_equal(unique(s$side), "yes")
  expect_match(res$source_status$detail, "1 unsupported")
  expect_match(res$source_status$detail, "2 markets without candles")
  expect_false(any(grepl("JCOOK4-4", k$fake$state$urls)))           # no candle request for an unsupported strike
})

test_that("a game with no kickoff is skipped and counted", {
  g <- transform(GAME_K, kickoff_utc = as.POSIXct(NA, tz = "UTC"))
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  res <- kalshi_provider(b)$provider$game_snapshots(g)
  expect_equal(res$source_status$status, "unavailable")
  expect_match(res$source_status$detail, "1 game without a kickoff")
})

test_that("the forward-capture pass stores per-game NFL series only", {
  odds_http_reset()
  fetched <- character()
  fetch <- function(source, key, url) {
    fetched <<- c(fetched, paste(source, key, sep = ":"))
    if (source == "kalshi_series") {
      return('{"series": [{"ticker": "KXNFLTD"}, {"ticker": "KXNFLGAME"}, {"ticker": "KXNFLWINS-NO"}, {"ticker": "KXNBAGAME"}]}')
    }
    '{"markets": [], "cursor": ""}'
  }
  provider_kalshi()$capture(fetch, now = Sys.time(), cfg = list())
  expect_equal(fetched, c("kalshi_series:sports", "kalshi_markets:KXNFLGAME_p1", "kalshi_markets:KXNFLTD_p1"))
})

test_that("the Kalshi provider satisfies the provider interface", {
  p <- provider_kalshi()
  expect_equal(validate_odds_provider(p), character())
  expect_equal(p$venue_ids, "kalshi")
})

# ---- the controller's amendments (R5, R6, R7 and Task 5's block rule) --------------------------

test_that("R5: a market that failed with a server error leaves the result stale, with its rows and its real error", {
  b <- game_routes(lar_candles = "kalshi_candles_game_live.json")
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- list(status = 500L)
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "HTTP 500")
  expect_false(grepl("(NA)", res$source_status$detail, fixed = TRUE))
  expect_equal(nrow(res$snapshots), 8)
})

test_that("R7: an error that escapes the provider is failed, carries no snapshots, and keeps the fetch lineage", {
  b <- game_routes(lar_candles = "kalshi_candles_game_live.json")
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26OCT12BUFLAR-LAR", TS(KO) - 48L * 3600L, TS(KO), FALSE)]] <- NULL
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "failed")
  expect_equal(nrow(res$snapshots), 0)                               # the BUF candles were read; none are returned
  expect_match(res$source_status$detail, "no fixture route")
  expect_gte(nrow(res$fetches), 4)
  expect_true(is.na(res$source_status$last_success_utc))
  # the same rule for props
  pb <- list()
  pb[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  pb[[kalshi_event_markets_url("KXNFLTD-26OCT12BUFLA", FALSE)]] <- empty_markets
  pb[[kalshi_event_markets_url("KXNFLTD-26OCT12BUFLAR", FALSE)]] <- "kalshi_markets_td_live.json"
  pr <- kalshi_provider(pb)$provider$prop_snapshots(GAME_K, series = "KXNFLTD")
  expect_equal(pr$source_status$status, "failed")
  expect_equal(nrow(pr$snapshots), 0)
})

test_that("a 200 response that is not JSON is a block: one request, no retry, named in the detail", {
  # on the very first request
  b <- list()
  b[[kalshi_cutoff_url()]] <- HTML_200
  k <- kalshi_provider(b)
  res <- k$provider$game_snapshots(GAME_K)
  expect_equal(length(k$fake$state$urls), 1)
  expect_equal(res$source_status$status, "unavailable")
  expect_match(res$source_status$detail, "blocked: HTTP 200 body is not JSON (a challenge or geo-fence page)", fixed = TRUE)
  expect_equal(length(k$clock$state$sleeps), 0)                      # nothing retried
  # in the middle of a run: the markets of the first spelling
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- HTML_200
  k <- kalshi_provider(b)
  res <- k$provider$game_snapshots(GAME_K)
  expect_equal(length(k$fake$state$urls), 2)                         # the cutoff and the blocked page, nothing after
  expect_match(res$source_status$detail, "blocked: HTTP 200 body is not JSON (a challenge or geo-fence page)", fixed = TRUE)
  expect_equal(nrow(res$snapshots), 0)
  # after rows were read, a block makes the result stale and keeps them
  b <- game_routes()
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26OCT12BUFLAR-LAR", TS(KO) - 48L * 3600L, TS(KO), FALSE)]] <- HTML_200
  k <- kalshi_provider(b)
  res <- k$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "stale")
  expect_equal(nrow(res$snapshots), 4)
  expect_match(res$source_status$detail, "blocked: HTTP 200 body is not JSON", fixed = TRUE)
  # the same for props
  pb <- list()
  pb[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  pb[[kalshi_event_markets_url("KXNFLTD-26OCT12BUFLA", FALSE)]] <- HTML_200
  pk <- kalshi_provider(pb)
  pr <- pk$provider$prop_snapshots(GAME_K, series = c("KXNFLTD", "KXNFLRECYDS"))
  expect_equal(length(pk$fake$state$urls), 2)
  expect_match(pr$source_status$detail, "blocked: HTTP 200 body is not JSON", fixed = TRUE)
})

test_that("a 403 stops the run at once and is named as a block", {
  b <- list()
  b[[kalshi_cutoff_url()]] <- list(status = 403L)
  k <- kalshi_provider(b)
  res <- k$provider$game_snapshots(GAME_K)
  expect_equal(length(k$fake$state$urls), 1)
  expect_match(res$source_status$detail, "blocked")
  expect_match(res$source_status$detail, "HTTP 403")
})

test_that("a cutoff that cannot be read is a named gap, not a failure", {
  b <- game_routes()
  b[[kalshi_cutoff_url()]] <- list(text = '{"unexpected": true}')
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "historical cutoff unreadable")
  expect_equal(nrow(res$snapshots), 4)
})

test_that("a market list longer than the 20-page cap is read to the cap and named as a stale gap", {
  ev <- "KXNFLGAME-26OCT12BUFLAR"
  one <- list(text = paste0('{"cursor": "next", "markets": [{"ticker": "KXNFLGAME-26OCT12BUFLAR-ZZZ"}]}'))
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- empty_markets
  b[[kalshi_event_markets_url(ev, FALSE)]] <- one
  b[[kalshi_event_markets_url(ev, FALSE, "next")]] <- one
  k <- kalshi_provider(b)
  res <- k$provider$game_snapshots(GAME_K)
  asked <- sum(grepl(paste0("event_ticker=", ev), k$fake$state$urls, fixed = TRUE))
  expect_equal(asked, 20)
  expect_match(res$source_status$detail, "20-page cap")
  expect_match(res$source_status$detail, "20 unsupported markets")   # every page's market is counted, none dropped silently
  expect_equal(res$source_status$status, "unavailable")              # no rows, so unavailable
})

test_that("the capture pass stops at 20 pages", {
  odds_http_reset()
  n <- 0L
  fetch <- function(source, key, url) {
    if (source == "kalshi_series") return('{"series": [{"ticker": "KXNFLGAME"}]}')
    n <<- n + 1L
    '{"markets": [], "cursor": "more"}'
  }
  provider_kalshi()$capture(fetch, now = Sys.time(), cfg = list())
  expect_equal(n, 20L)
})

test_that("the capture pass stops at a body that is not JSON and says so", {
  odds_http_reset()
  seen <- character()
  fetch <- function(source, key, url) {
    seen <<- c(seen, source)
    "<html>challenge</html>"
  }
  msgs <- testthat::capture_messages(out <- provider_kalshi()$capture(fetch, now = Sys.time(), cfg = list()))
  expect_equal(seen, "kalshi_series")                                # no request after the block
  expect_false(isTRUE(out))
  expect_match(paste(msgs, collapse = " "), "blocked: body is not JSON")
})

test_that("candles that cannot be read are counted by class, and an unreadable field makes the result stale", {
  meta <- list(ok = TRUE, market_id = "moneyline", side = "away", line = NA_real_, player_key = NA_character_)
  parsed <- odds_fixture_json("kalshi_candles_game_live.json")
  parsed$candlesticks[[1]]$end_period_ts <- "garbled"                 # no time: cannot be stored
  parsed$candlesticks[[2]]$yes_bid$close_dollars <- "n/a"             # unreadable field
  parsed$candlesticks[[3]]$yes_bid$close_dollars <- "1.5"             # a dollar price outside [0, 1]
  parsed$candlesticks[[4]]$yes_bid <- NULL                            # an absent quote is not drift
  out <- parse_kalshi_candles(parsed, meta, "g", "e", "kalshi_live")
  expect_equal(nrow(out), 3)
  expect_equal(validate_odds_snapshots(out), character())
  expect_equal(attr(out, "no_time"), 1L)
  expect_equal(attr(out, "bad_fields"), 2L)
  # and through the provider
  res <- kalshi_provider(game_routes(buf_candles = kalshi_json_route(parsed)))$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "1 candle without a readable time skipped")
  expect_match(res$source_status$detail, "2 candle\\(s\\) with an unreadable price or crossed quote")
  expect_equal(nrow(res$snapshots), 3)
})

test_that("a candle with no price at all is kept and counted, and is not a gap (R6)", {
  meta <- list(ok = TRUE, market_id = "anytime_td", side = "yes", line = 0.5, player_key = "kalshi:p")
  parsed <- list(candlesticks = list(list(end_period_ts = 1791846000)))
  out <- parse_kalshi_candles(parsed, meta, "g", "e", "kalshi_live")
  expect_equal(nrow(out), 1)
  expect_equal(attr(out, "price_less"), 1L)
  b <- game_routes(buf_candles = kalshi_json_route(parsed))
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "ok")
  expect_match(res$source_status$detail, "1 price-less candle row\\(s\\) kept")
})

test_that("a response without the expected field is schema drift and makes the result stale", {
  b <- game_routes(buf_candles = list(text = '{"unexpected": []}'))
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "unavailable")
  expect_match(res$source_status$detail, "schema drift")
  expect_match(res$source_status$detail, "candlesticks")
  # drift on the market list while another spelling's rows were read
  b <- game_routes()
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- list(text = '{"items": []}')
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "schema drift")
  expect_match(res$source_status$detail, "markets")
})

test_that("a game with no Kalshi event is a named gap", {
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- list(status = 404L)
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLAR", FALSE)]] <- list(status = 404L)
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", TRUE)]] <- list(status = 404L)
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLAR", TRUE)]] <- list(status = 404L)
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "unavailable")
  expect_match(res$source_status$detail, "1 game-series with no Kalshi event")
})

# ---- fix round 1 (task review of feefb95..b55fabd) ---------------------------------------------

test_that("the shared fetch helpers live in provider.R under odds_ names, and neither provider uses the other's", {
  read_src <- function(f) paste(readLines(testthat::test_path("..", "..", "R", "odds", f), warn = FALSE), collapse = "\n")
  expect_false(grepl("espn_", read_src("provider_kalshi.R"), fixed = TRUE))
  expect_false(grepl("kalshi_", read_src("provider_espn_core.R"), fixed = TRUE))
  for (old in c("espn_fetch_problem", "espn_is_html_block", "espn_html_block_note", "espn_one_line")) {
    expect_false(exists(old), info = old)
  }
  expect_match(read_src("provider.R"), "odds_fetch_problem <- function", fixed = TRUE)
  expect_equal(odds_one_line("a\n  b\t c "), "a b c")
  page <- charToRaw("<html><body>challenge</body></html>")
  expect_equal(odds_fetch_problem(list(error = NA_character_, status = 200L, body = page)), "HTTP 200, body is not JSON")
  expect_equal(odds_fetch_problem(list(error = NA_character_, status = 200L)), "HTTP 200, empty body")       # review I-1
  expect_equal(odds_fetch_problem(list(error = NA_character_, status = 200L, body = charToRaw("null"))), "HTTP 200, JSON null")
  expect_equal(odds_fetch_problem(list(error = "HTTP 500", status = 500L)), "HTTP 500")
  expect_true(odds_is_html_block(list(status = 200L, body = page)))
  expect_false(odds_is_html_block(list(status = 200L)))                # an empty body is a gap, not a page (review I-1)
  expect_false(odds_is_html_block(list(status = 500L, body = page)))
  expect_match(odds_html_block_note(list(status = 200L), "X"), "blocked: HTTP 200 body is not JSON")
})

test_that("markets: null is the same as [] (not found, no drift); an absent key is drift", {
  for (body in c('{"markets": null, "cursor": ""}', '{"markets": [], "cursor": ""}')) {
    b <- game_routes()
    b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- list(text = body)
    res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
    expect_equal(res$source_status$status, "ok", info = body)
    expect_false(grepl("schema drift", res$source_status$detail), info = body)
  }
  b <- game_routes()
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- list(text = '{"cursor": ""}')
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "schema drift")
})

test_that("a yards market with no floor_strike is counted drift and stores no row with a NA line", {
  parsed <- odds_fixture_json("kalshi_markets_recyds_live.json")
  parsed$markets[[1]]$floor_strike <- NULL
  meta <- kalshi_market_meta(parsed$markets[[1]], GAME_K, "KXNFLRECYDS")
  expect_false(meta$ok)
  expect_true(isTRUE(meta$drift))
  expect_match(meta$reason, "no floor_strike")
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLRECYDS-26OCT12BUFLA", FALSE)]] <- empty_markets
  b[[kalshi_event_markets_url("KXNFLRECYDS-26OCT12BUFLAR", FALSE)]] <- kalshi_json_route(parsed)
  k <- kalshi_provider(b)
  res <- k$provider$prop_snapshots(GAME_K, series = "KXNFLRECYDS")
  expect_equal(nrow(res$snapshots), 0)
  expect_match(res$source_status$detail, "schema drift")
  expect_match(res$source_status$detail, "no floor_strike")
  expect_false(any(grepl("candlesticks", k$fake$state$urls)))
  # a touchdown market keeps its default strike: still stored, still ok
  b2 <- list()
  b2[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b2[[kalshi_event_markets_url("KXNFLTD-26OCT12BUFLA", FALSE)]] <- empty_markets
  b2[[kalshi_event_markets_url("KXNFLTD-26OCT12BUFLAR", FALSE)]] <- "kalshi_markets_td_live.json"
  b2[[kalshi_candles_url("KXNFLTD", "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-1", TS(KO) - 48L * 3600L, TS(KO), FALSE)]] <- "kalshi_candles_td_live.json"
  b2[[kalshi_candles_url("KXNFLTD", "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-2", TS(KO) - 48L * 3600L, TS(KO), FALSE)]] <- empty_candles
  expect_equal(kalshi_provider(b2)$provider$prop_snapshots(GAME_K, series = "KXNFLTD")$source_status$status, "ok")
})

test_that("M1: a quote that is a bare value instead of an object is counted, not thrown", {
  meta <- list(ok = TRUE, market_id = "moneyline", side = "away", line = NA_real_, player_key = NA_character_)
  parsed <- odds_fixture_json("kalshi_candles_game_live.json")
  parsed$candlesticks[[1]]$yes_bid <- "0.38"
  parsed$candlesticks[[2]]$price <- 0.39
  out <- parse_kalshi_candles(parsed, meta, "g", "e", "kalshi_live")
  expect_equal(nrow(out), 4)
  expect_equal(attr(out, "bad_fields"), 2L)
  res <- kalshi_provider(game_routes(buf_candles = kalshi_json_route(parsed)))$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "stale")
})

test_that("M2: valid JSON that is not an object is drift and stale, never a throw", {
  for (body in c("null", "5", '"text"', "[1, 2]")) {
    b <- game_routes(buf_candles = list(text = body))
    res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
    expect_false(res$source_status$status == "failed", info = body)
    expect_match(res$source_status$detail, "schema drift", info = body)
    expect_false(grepl("blocked", res$source_status$detail), info = body)
  }
  b <- game_routes()
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- list(text = "5")
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "schema drift")
})

test_that("M2/M3: capture treats a non-object body as drift (not a block) and a series list without `series` is named", {
  odds_http_reset()
  msgs <- testthat::capture_messages(provider_kalshi()$capture(function(source, key, url) "null", now = Sys.time(), cfg = list()))
  expect_false(grepl("blocked", paste(msgs, collapse = " ")))
  expect_match(paste(msgs, collapse = " "), "not a JSON object")
  msgs <- testthat::capture_messages(provider_kalshi()$capture(function(source, key, url) '{"other": []}', now = Sys.time(), cfg = list()))
  expect_match(paste(msgs, collapse = " "), "no series field")
  # a page that is not an object stops that series only; the next series is still read
  seen <- character()
  fetch <- function(source, key, url) {
    seen <<- c(seen, paste(source, key, sep = ":"))
    if (source == "kalshi_series") return('{"series": [{"ticker": "KXNFLGAME"}, {"ticker": "KXNFLTD"}]}')
    if (key == "KXNFLGAME_p1") return("5")
    '{"markets": [], "cursor": ""}'
  }
  msgs <- testthat::capture_messages(provider_kalshi()$capture(fetch, now = Sys.time(), cfg = list()))
  expect_equal(seen, c("kalshi_series:sports", "kalshi_markets:KXNFLGAME_p1", "kalshi_markets:KXNFLTD_p1"))
  expect_match(paste(msgs, collapse = " "), "KXNFLGAME_p1 is not a JSON object")
})

test_that("M4: a block says how many games were never attempted", {
  g2 <- transform(GAME_K, game_id = "2026_05_X_Y")
  games <- rbind(GAME_K, g2)
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- HTML_200
  res <- kalshi_provider(b)$provider$game_snapshots(games)
  expect_match(res$source_status$detail, "1 game never attempted")
})

test_that("M5: a non-404 failure on a candle request is named with its real error and leaves the result stale", {
  b <- game_routes(lar_candles = list(status = 500L))
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "KXNFLGAME-26OCT12BUFLAR-LAR (HTTP 500)", fixed = TRUE)
  expect_false(grepl("without candles", res$source_status$detail))
  expect_equal(nrow(res$snapshots), 4)
})

test_that("an empty 200 body is a counted failure, not a block, and a challenge page blocks kalshi.com for the session (review I-1, I-4)", {
  res <- kalshi_provider(game_routes(lar_candles = list(text = "")))$provider$game_snapshots(GAME_K)
  expect_false(grepl("blocked", res$source_status$detail))
  expect_match(res$source_status$detail, "KXNFLGAME-26OCT12BUFLAR-LAR (HTTP 200, empty body)", fixed = TRUE)
  expect_equal(res$source_status$status, "stale")
  expect_equal(nrow(res$snapshots), 4)                               # the other side's candles are kept
  k <- kalshi_provider(game_routes(buf_candles = HTML_200))
  first <- k$provider$game_snapshots(GAME_K)
  expect_match(first$source_status$detail, "blocked")
  n <- length(k$fake$state$urls)
  again <- k$provider$game_snapshots(GAME_K)
  expect_equal(length(k$fake$state$urls), n)                         # refused without a request
  expect_match(again$source_status$detail, "blocked")
})

test_that("a KXNFLTD market without floor_strike, or a prop market without its player, is drift (review I-5)", {
  m <- odds_fixture_json("kalshi_markets_td_live.json")$markets[[1]]
  no_strike <- m
  no_strike$floor_strike <- NULL
  meta <- kalshi_market_meta(no_strike, GAME_K, "KXNFLTD")
  expect_false(meta$ok)
  expect_true(isTRUE(meta$drift))
  expect_match(meta$reason, "no floor_strike")
  no_player <- m
  no_player$custom_strike$football_player <- NULL
  meta2 <- kalshi_market_meta(no_player, GAME_K, "KXNFLTD")
  expect_false(meta2$ok)
  expect_true(isTRUE(meta2$drift))
  expect_match(meta2$reason, "no player")
  three <- m
  three$floor_strike <- 3                                             # 3+ is present but unmapped by design: unsupported, not drift
  expect_false(isTRUE(kalshi_market_meta(three, GAME_K, "KXNFLTD")$drift))
})
