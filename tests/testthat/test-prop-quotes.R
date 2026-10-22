# =============================================================================
# FILE: tests/testthat/test-prop-quotes.R
# PURPOSE: P14 (a historical run never sees a quote captured after its kickoff),
#          P9 (id-only joins) and the M11 rule (no quote -> unpriced, never a number).
# No network. The cache is a table with a game key and a capture time.
# =============================================================================

library(testthat)

source(file.path(.test_project_root, "R", "prop_keys.R"), local = FALSE)
source(file.path(.test_project_root, "R", "prop_odds_api.R"), local = FALSE)
source(file.path(.test_project_root, "R", "correlated_props.R"), local = FALSE)

utc <- function(x) as.POSIXct(x, tz = "UTC")

# 2024 week 16: NE @ BUF, Sunday 2024-12-22 1:00 PM Eastern = 18:00 UTC
KICK_2024_W16 <- prop_kickoff_utc("2024-12-22", "13:00")
NOW_2026 <- utc("2026-10-13 12:00:00")

mk_quote <- function(captured_at, game_id = "2024_16_NE_BUF", player_id = "00-JA", line = 242.5,
                     over = -110, under = -110, book = "draftkings", prop_type = "passing_yards") {
  tibble::tibble(
    player_id = player_id, prop_type = prop_type, game_id = game_id, captured_at = utc(captured_at),
    book = book, line = line, line_over = line, line_under = line,
    over_odds = over, under_odds = under, venue = "book"
  )
}

# lines for the current slate: NE @ BUF is also a 2026 week 4 game (audit P14)
current_slate <- function() {
  rbind(
    mk_quote("2026-10-01 12:00:00", game_id = "2026_04_NE_BUF", line = 240.5, over = -111, under = -113),
    # a quote labelled with the 2024 game but captured two years after its kickoff
    mk_quote("2026-10-01 12:00:00", game_id = "2024_16_NE_BUF", line = 240.5, over = -111, under = -113)
  )
}

quotes_for <- function(cache, kickoff = KICK_2024_W16, now = NOW_2026, game_id = "2024_16_NE_BUF",
                       player_id = "00-JA", prop_type = "passing_yards") {
  get_market_prop_quotes(cache, player_id, prop_type, game_id, kickoff, now)
}

test_that("prop_kickoff_utc converts US Eastern kickoff to UTC and invents nothing", {
  expect_equal(format(KICK_2024_W16, "%Y-%m-%d %H:%M:%S", tz = "UTC"), "2024-12-22 18:00:00")
  expect_equal(format(prop_kickoff_utc("2024-09-08", "13:00"), "%H:%M", tz = "UTC"), "17:00")  # EDT
  expect_true(is.na(prop_kickoff_utc("2024-12-22", NA)))
  expect_true(is.na(prop_kickoff_utc("2024-12-22", "")))
  expect_true(is.na(prop_kickoff_utc(NA, "13:00")))
})

test_that("a 2024 week 16 run never sees a line captured after its kickoff (P14)", {
  r <- quotes_for(current_slate())
  expect_null(r$quotes)
  expect_identical(r$reason, "No line captured before kickoff")

  logged <- character()
  expect_null(get_market_prop_line("00-JA", "passing_yards", current_slate(),
                                   game_id = "2024_16_NE_BUF", kickoff = KICK_2024_W16, now = NOW_2026,
                                   on_unpriced = function(r) logged <<- c(logged, r)))
  expect_identical(logged, "No line captured before kickoff")

  # with one genuine pre-kickoff quote the 2026 lines are still ignored
  cache <- rbind(current_slate(), mk_quote("2024-12-22 17:10:00", line = 242.5, over = -108, under = -112))
  line <- get_market_prop_line("00-JA", "passing_yards", cache, game_id = "2024_16_NE_BUF",
                               kickoff = KICK_2024_W16, now = NOW_2026)
  expect_equal(line$line, 242.5)
  expect_equal(line$over_odds, -108)
  expect_lte(line$captured_at, KICK_2024_W16)
})

test_that("property: every quote returned was captured at or before the kickoff", {
  set.seed(14)
  n <- 200
  # 150 captures between 10:00 and 22:00 UTC on game day (kickoff 18:00) and 50 captured in 2026
  captured <- c(utc("2024-12-22 10:00:00") + runif(150, 0, 43200), utc("2026-01-01 00:00:00") + runif(50, 0, 1e7))
  cache <- do.call(rbind, lapply(seq_len(n), function(i) {
    mk_quote(format(captured[i], "%Y-%m-%d %H:%M:%S"), book = paste0("book", i))
  }))
  r <- quotes_for(cache, now = NOW_2026)
  expect_true(!is.null(r$quotes))
  expect_true(all(r$quotes$captured_at <= KICK_2024_W16))
  expect_true(nrow(r$quotes) > 0 && nrow(r$quotes) < n)
})

test_that("the kickoff instant is included, one second later is not", {
  expect_equal(nrow(quotes_for(mk_quote("2024-12-22 18:00:00"), kickoff = utc("2024-12-22 18:00:00"))$quotes), 1)
  expect_identical(quotes_for(mk_quote("2024-12-22 18:00:01"), kickoff = utc("2024-12-22 18:00:00"))$reason,
                   "No line captured before kickoff")
})

test_that("a stale quote leaves the prop unpriced, the limit is inclusive", {
  at_limit <- mk_quote("2024-12-22 16:00:00")      # exactly 120 minutes before kickoff
  expect_equal(nrow(quotes_for(at_limit)$quotes), 1)
  stale <- mk_quote("2024-12-22 15:59:59")
  r <- quotes_for(stale)
  expect_null(r$quotes)
  expect_match(r$reason, "^Newest line is stale")
  expect_equal(nrow(quotes_for(stale, now = utc("2024-12-22 16:00:30"))$quotes), 1)   # a live run at 16:00:30: 0.02 min old
})

test_that("a live run decides at now, not at kickoff", {
  cache <- mk_quote("2024-12-22 12:30:00")
  r <- quotes_for(cache, now = utc("2024-12-22 12:40:00"))
  expect_equal(nrow(r$quotes), 1)
  expect_null(quotes_for(cache, now = utc("2024-12-22 12:00:00"))$quotes)   # captured after "now"
})

test_that("the latest capture per book wins", {
  cache <- rbind(mk_quote("2024-12-22 16:30:00", line = 241.5),
                 mk_quote("2024-12-22 17:30:00", line = 242.5),
                 mk_quote("2024-12-22 17:00:00", line = 243.5, book = "fanduel"))
  q <- quotes_for(cache)$quotes
  expect_equal(nrow(q), 2)
  expect_equal(q$line[q$book == "draftkings"], 242.5)
})

test_that("unusable inputs give a reason, never a number (M11)", {
  good <- mk_quote("2024-12-22 17:00:00")
  expect_identical(quotes_for(NULL)$reason, "No prop lines loaded")
  expect_identical(quotes_for(good[0, ])$reason, "No prop lines loaded")
  expect_identical(quotes_for(good, kickoff = as.POSIXct(NA))$reason, "Kickoff unknown")
  expect_identical(quotes_for(good, player_id = NA_character_)$reason, "Player id unresolved")
  expect_identical(quotes_for(good, player_id = "")$reason, "Player id unresolved")
  expect_identical(quotes_for(good, game_id = NA_character_)$reason, "Game id missing")
  expect_identical(quotes_for(good, player_id = "00-OTHER")$reason, "No line for this player and game")
  expect_identical(quotes_for(good, prop_type = "rushing_yards")$reason, "No line for this player and game")
  expect_match(quotes_for(good[, setdiff(names(good), "captured_at")])$reason, "captured_at")
  expect_match(quotes_for(good[, setdiff(names(good), "game_id")])$reason, "game_id")
  legacy <- good
  legacy$captured_at <- format(legacy$captured_at)
  expect_identical(quotes_for(legacy)$reason, "captured_at is not a timestamp")
  na_id <- good
  na_id$player_id <- NA_character_
  expect_identical(quotes_for(na_id)$reason, "No line for this player and game")
})

test_that("preferred books narrow the choice; quotes of one player never leak to another", {
  props <- rbind(
    mk_quote("2024-12-22 17:00:00", line = 230.5, over = -113, under = -111, book = "draftkings"),
    mk_quote("2024-12-22 17:00:00", line = 229.5, over = -110, under = -110, book = "fanduel"),
    mk_quote("2024-12-22 17:00:00", line = 99.5, player_id = "00-OTHER", book = "draftkings")
  )
  dk <- get_market_prop_line("00-JA", "passing_yards", props, game_id = "2024_16_NE_BUF",
                             kickoff = KICK_2024_W16, now = NOW_2026, preferred_books = "draftkings")
  expect_equal(dk$book, "draftkings")
  expect_equal(dk$line, 230.5)
  all_books <- get_market_prop_line("00-JA", "passing_yards", props, game_id = "2024_16_NE_BUF",
                                    kickoff = KICK_2024_W16, now = NOW_2026)
  expect_equal(all_books$n_books, 2)
})

test_that("rows without prices are unpriced with a reason", {
  props <- mk_quote("2024-12-22 17:00:00", over = NA_real_, under = NA_real_)
  logged <- character()
  expect_null(get_market_prop_line("00-JA", "passing_yards", props, game_id = "2024_16_NE_BUF",
                                   kickoff = KICK_2024_W16, now = NOW_2026,
                                   on_unpriced = function(r) logged <<- r))
  expect_identical(logged, "Market odds missing")
})

# --- ids are attached once at load, exactly ---

xwalk_fixture <- function() {
  tibble::tibble(player_id = c("00-JA", "00-DM"), name = c("Josh Allen", "Drake Maye"),
                 team = c("BUF", "NEP"), position = "QB")
}

test_that("attach_player_ids fills missing ids exactly and leaves the rest NA", {
  cache <- tibble::tibble(player = c("Josh Allen", "Drake Maye", "J. Allen", "Josh Allen"),
                          team = c("Buffalo Bills", "NE", "BUF", "NE"), prop_type = "passing_yards")
  out <- suppressMessages(attach_player_ids(cache, xwalk_fixture()))
  expect_identical(out$player_id, c("00-JA", "00-DM", NA, NA))
  keep <- tibble::tibble(player = "Josh Allen", team = "BUF", player_id = "PROVIDER-ID")
  expect_identical(suppressMessages(attach_player_ids(keep, xwalk_fixture()))$player_id, "PROVIDER-ID")
})

test_that("a CSV cache keeps its capture times and gets ids", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  utils::write.csv(data.frame(
    player = "Josh Allen", team = "BUF", prop_type = "passing_yards", line = 242.5,
    over_odds = -108, under_odds = -112, book = "draftkings", game_id = "2024_16_NE_BUF",
    captured_at = "2024-12-22T17:10:00Z", stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  cache <- suppressMessages(resolve_prop_odds_cache(source = "csv", csv_path = tmp, xwalk = xwalk_fixture()))
  expect_s3_class(cache$captured_at, "POSIXct")
  expect_equal(format(cache$captured_at, "%H:%M", tz = "UTC"), "17:10")
  expect_identical(cache$player_id, "00-JA")
  expect_identical(attr(cache, "source"), "csv")
  line <- get_market_prop_line(cache$player_id, "passing_yards", cache, game_id = "2024_16_NE_BUF",
                               kickoff = KICK_2024_W16, now = NOW_2026)
  expect_equal(line$line, 242.5)
})

# --- through run_game_props: the audit's observed case, end to end ---

test_that("run_game_props prices 2024 w16 from a pre-kickoff quote and leaves the rest unpriced (P14, M11)", {
  set.seed(16)
  game_sim <- list(home = rpois(2000, 24), away = rpois(2000, 21))
  players <- tibble::tibble(
    player_id = c("00-JA", "00-DM"), player_name = c("Josh Allen", "Drake Maye"), position = "QB",
    recent_team = c("BUF", "NE"), avg_passing_yards = c(300, 220), avg_rushing_yards = c(40, 20),
    avg_receiving_yards = 0, avg_touchdowns = c(0.5, 0.3), is_projection = FALSE, is_baseline = FALSE
  )
  neutral <- tibble::tibble(team = c("BUF", "NE"), pass_def_multiplier = 1, rush_def_multiplier = 1,
                            recv_def_multiplier = 1)
  run <- function(cache) {
    suppressMessages(run_game_props(
      game_sim, home_team = "BUF", away_team = "NE", season = 2024, prop_types = "passing",
      prop_odds_cache = cache, game_id = "2024_16_NE_BUF", kickoff = KICK_2024_W16, week = 16L,
      players = players, defense_ranks = neutral, now = NOW_2026
    ))
  }

  late_only <- run(current_slate())
  allen <- late_only[late_only$player == "Josh Allen", ]
  expect_equal(nrow(allen), 1)
  expect_identical(allen$unpriced_reason, "No line captured before kickoff")
  expect_identical(allen$odds_source, "missing")
  expect_true(is.na(allen$over_odds) && is.na(allen$under_odds))
  expect_true(is.na(allen$ev_over) && is.na(allen$ev_under))
  expect_identical(allen$recommendation, "PASS")
  expect_false(isTRUE(allen$line == 240.5))     # the 2026 line was not used

  priced <- run(rbind(current_slate(), mk_quote("2024-12-22 17:10:00", line = 242.5, over = -108, under = -112)))
  allen <- priced[priced$player == "Josh Allen", ]
  maye <- priced[priced$player == "Drake Maye", ]
  expect_identical(allen$odds_source, "market")
  expect_equal(allen$line, 242.5)
  expect_equal(allen$over_odds, -108)
  expect_identical(allen$unpriced_reason, "")
  expect_identical(maye$odds_source, "missing")
  expect_identical(maye$unpriced_reason, "No line for this player and game")
  expect_true(is.na(maye$ev_over))
})

test_that("run_game_props with no cache says why every prop is unpriced", {
  set.seed(17)
  players <- tibble::tibble(
    player_id = "00-JA", player_name = "Josh Allen", position = "QB", recent_team = "BUF",
    avg_passing_yards = 300, avg_rushing_yards = 40, avg_receiving_yards = 0, avg_touchdowns = 0.5,
    is_projection = FALSE, is_baseline = FALSE
  )
  neutral <- tibble::tibble(team = c("BUF", "NE"), pass_def_multiplier = 1, rush_def_multiplier = 1,
                            recv_def_multiplier = 1)
  old <- get0("USE_REAL_PROP_ODDS", envir = globalenv(), inherits = FALSE)
  assign("USE_REAL_PROP_ODDS", FALSE, envir = globalenv())
  on.exit(assign("USE_REAL_PROP_ODDS", old, envir = globalenv()), add = TRUE)
  res <- suppressMessages(run_game_props(
    list(home = rpois(500, 24), away = rpois(500, 21)), "BUF", "NE", 2024, prop_types = "passing",
    players = players, defense_ranks = neutral
  ))
  expect_identical(res$unpriced_reason, "No prop lines loaded")
  expect_true(is.na(res$ev_over))
})

test_that("a CSV capture time without a time zone is never read as UTC (final review C2)", {
  path <- withr::local_tempfile(fileext = ".csv")
  rows <- data.frame(
    player_id = "00-JA", prop_type = "passing_yards", game_id = "2024_16_NE_BUF", book = "draftkings",
    line = 242.5, line_over = 242.5, line_under = 242.5, over_odds = -110, under_odds = -110,
    captured_at = c("2024-12-22T21:30:00Z", "2024-12-22T16:30:00-05:00", "2024-12-22 16:30:00",
                    "2024-12-22 16:30:00 EST", "2024-12-22T17:10:00Z"),
    stringsAsFactors = FALSE
  )
  utils::write.csv(rows, path, row.names = FALSE)
  expect_message(cache <- load_prop_odds_csv(path), "have a captured_at with no time zone", fixed = TRUE)
  expect_equal(format(cache$captured_at, "%Y-%m-%d %H:%M", tz = "UTC"),
               c("2024-12-22 21:30", "2024-12-22 21:30", NA, NA, "2024-12-22 17:10"))
  q <- quotes_for(cache)$quotes   # kickoff 18:00 UTC: only the 17:10Z capture comes before it
  expect_equal(nrow(q), 1)
  expect_equal(format(q$captured_at, "%H:%M", tz = "UTC"), "17:10")
  expect_identical(quotes_for(cache[3:4, ])$reason, "Line capture time missing or without a time zone")
})

test_that("a book's latest capture keeps every line it offered: a strike ladder, alternate lines (final review I2)", {
  ladder <- rbind(mk_quote("2024-12-22 17:00:00", line = 199.5, book = "kalshi"),
                  mk_quote("2024-12-22 17:00:00", line = 249.5, book = "kalshi"),
                  mk_quote("2024-12-22 17:00:00", line = 299.5, book = "kalshi"))
  expect_setequal(quotes_for(ladder)$quotes$line_over, c(199.5, 249.5, 299.5))
  expect_setequal(quotes_for(ladder[3:1, ])$quotes$line_over, c(199.5, 249.5, 299.5))
  alt <- rbind(mk_quote("2024-12-22 17:00:00", line = 274.5, over = 150, under = -190),
               mk_quote("2024-12-22 17:00:00", line = 242.5))
  expect_setequal(quotes_for(alt)$quotes$line_over, c(274.5, 242.5))
  # a line the book has since moved is superseded by its newer capture
  moved <- rbind(mk_quote("2024-12-22 16:00:00", line = 241.5), mk_quote("2024-12-22 17:00:00", line = 242.5))
  expect_equal(quotes_for(moved)$quotes$line_over, 242.5)
})

test_that("the CSV loader takes P1's own schema: an id for the player, Kalshi bid and ask (final review I7)", {
  by_id <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(data.frame(player_id = "00-JA", prop_type = "passing_yards", game_id = "2024_16_NE_BUF",
                              book = "draftkings", line = 242.5, over_odds = -110, under_odds = -110,
                              captured_at = "2024-12-22T17:10:00Z"), by_id, row.names = FALSE)
  expect_equal(nrow(load_prop_odds_csv(by_id)), 1)
  kalshi <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(data.frame(player_id = "00-JA", prop_type = "passing_yards", game_id = "2024_16_NE_BUF",
                              book = "kalshi", venue = "kalshi", line = 249.5, yes_bid = 0.4, yes_ask = 0.42,
                              captured_at = "2024-12-22T17:10:00Z"), kalshi, row.names = FALSE)
  expect_equal(nrow(load_prop_odds_csv(kalshi)), 1)
  no_price <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(data.frame(player_id = "00-JA", prop_type = "passing_yards", line = 249.5), no_price, row.names = FALSE)
  expect_warning(expect_null(load_prop_odds_csv(no_price)), "price")
})
